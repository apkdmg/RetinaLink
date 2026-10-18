#!/usr/bin/env python3
"""Bounded, two-Mac direct-link runtime validation over an existing SSH master.

Run only after signed Host and Viewer builds are installed. The test sends no
Hello from its diagnostic probes, changes no interface settings, and never
disables SSH. A local Viewer test command simulates an unavailable route without
disconnecting the company's Ethernet or Wi-Fi interfaces. Ordinary Viewer launch
is restored in finally, including when an assertion fails.
"""

import argparse
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import time
import uuid

import test_direct_ethernet as safety


POLICY_KEYS = ('persistentConfigurationSHA256', 'serviceOrderSHA256', 'defaultRoute',
               'primaryService', 'primaryServiceDNSSHA256', 'globalDNSSHA256',
               'bindingSHA256', 'fileVaultStatus')
STATE_KEYS = ('version', 'build', 'pid', 'phase', 'connected', 'streaming', 'fullscreen',
              'transport', 'requiresRemoteLogin', 'connectionID', 'provisionalConnections',
              'startupInstalled', 'networkSettingsChanged', 'time')
PATH_KEYS = ('connection', 'interface', 'interfaceIndex', 'wired', 'automaticAddressing',
             'scopedDiscovery', 'requiredInterfaceVerified', 'addressFamily',
             'localLinkLocal', 'remoteLinkLocal', 'authenticated', 'networkSettingsChanged')
PROBE_KEYS = ('success', 'identityMatched', 'requiredInterfaceVerified', 'selectedInterface',
              'status', 'attempts', 'durationSeconds', 'sentApplicationData',
              'networkSettingsChanged', 'pairingChanged', 'untrustedTest')


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def safe_path(value):
    require(isinstance(value, dict), 'Expected connectionPath metadata is absent')
    return {key: value[key] for key in PATH_KEYS if key in value}


def safe_state(value):
    result = {key: value[key] for key in STATE_KEYS if key in value}
    result['connectionPath'] = safe_path(value.get('connectionPath', {}))
    if isinstance(value.get('lastPreferredRouteProbe'), dict):
        result['lastPreferredRouteProbe'] = safe_probe(value['lastPreferredRouteProbe'])
    return result


def safe_probe(value):
    result = {key: value[key] for key in PROBE_KEYS if key in value}
    result['connectionPath'] = safe_path(value.get('connectionPath', {}))
    return result


class RuntimeTest:
    def __init__(self, args):
        self.args = args
        self.ssh = ['/usr/bin/ssh', '-S', str(args.socket.resolve()), '-o', 'BatchMode=yes',
                    '-o', 'ConnectTimeout=5', '-l', args.user, args.address]
        self.host_state = Path.home() / 'Library/Logs/RetinaLink/Host-ui.json'
        self.home = self.remote('printf %s "$HOME"').stdout
        require(self.home.startswith('/') and '\n' not in self.home, 'Unexpected remote home directory')
        self.viewer_app = self.home + '/Applications/RetinaLink Viewer.app'
        self.viewer_binary = self.viewer_app + '/Contents/MacOS/RetinaLink'
        self.viewer_state = self.home + '/Library/Logs/RetinaLink/Viewer-ui.json'
        self.remote_directory = self.home + '/Library/Logs/RetinaLink/DirectLinkRuntimeTests/' + str(uuid.uuid4())
        self.changed_viewer = False
        self.observations = []

    def remote(self, command, *, timeout=35, check=True):
        return subprocess.run(self.ssh + [command], text=True, capture_output=True,
                              timeout=timeout, check=check)

    def read_remote_json(self, path):
        return json.loads(self.remote('/bin/cat ' + shlex.quote(path)).stdout)

    def states(self):
        host = json.loads(self.host_state.read_text())
        viewer = self.read_remote_json(self.viewer_state)
        now = time.time()
        for role, value in (('Host', host), ('Viewer', viewer)):
            require(value.get('build') == self.args.build, role + ' is not the requested installed build')
            require(now - value.get('time', 0) < 15, role + ' metadata is stale')
        return {'host': host, 'viewer': viewer}

    def record(self, label, states):
        value = {role: safe_state(state) for role, state in states.items()}
        self.observations.append({'label': label, 'elapsed': round(time.monotonic() - self.started, 3), **value})
        return value

    def wait(self, label, predicate, timeout=90):
        deadline = time.monotonic() + timeout
        last_error = None
        while time.monotonic() < deadline:
            try:
                states = self.states()
                if predicate(states):
                    self.record(label, states)
                    print('PASS: ' + label, flush=True)
                    return states
            except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
                last_error = type(error).__name__
            time.sleep(0.75)
        raise RuntimeError(label + ' timed out' + (' (' + last_error + ')' if last_error else ''))

    def streaming(self, states, interface=None):
        host, viewer = states['host'], states['viewer']
        path = viewer.get('connectionPath', {})
        return bool(host.get('streaming') and host.get('connectionID') and viewer.get('phase') == 'streaming'
                    and viewer.get('connectionID') and viewer.get('fullscreen')
                    and viewer.get('transport') == 'direct-tls' and viewer.get('requiresRemoteLogin') is False
                    and path.get('authenticated') is True and path.get('requiredInterfaceVerified') is True
                    and (interface is None or path.get('interface') == interface))

    @staticmethod
    def identity(states):
        return {role: (value['pid'], value['connectionID']) for role, value in states.items()}

    def probe(self, *, untrusted=False):
        label = 'untrusted-probe' if untrusted else 'trusted-probe'
        output = self.remote_directory + '/' + label + '.json'
        # Launch Services supplies the signed-in GUI security session. A raw SSH
        # executable can lack that session even when Viewer itself is authorized.
        # open -W reports launch completion, so the JSON report is the result.
        command = ['/usr/bin/open', '-n', '-W', self.viewer_app, '--args',
                   '--direct-link-probe', '--probe-duration', '8',
                   '--probe-interface', self.args.wired_interface, '--probe-output', output]
        if untrusted:
            command.append('--probe-untrusted')
        before = self.states()
        require(self.streaming(before, self.args.wired_interface), 'Baseline display is not streaming over the preferred interface')
        identity = self.identity(before)
        self.record(label + '-before', before)
        process = subprocess.Popen(self.ssh + [shlex.join(command)], text=True,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        deadline = time.monotonic() + 35
        try:
            while process.poll() is None:
                require(time.monotonic() < deadline, label + ' exceeded its bounded window')
                current = self.states()
                require(self.identity(current) == identity, label + ' replaced or restarted the active stream')
                require(self.streaming(current, self.args.wired_interface), label + ' interrupted the active stream')
                time.sleep(0.5)
            process.communicate(timeout=2)
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.communicate(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.communicate(timeout=3)
        report = self.read_remote_json(output)
        require(process.returncode == 0, label + ' did not complete its Launch Services launch')
        require(report.get('untrustedTest') is untrusted, label + ' did not report the requested credential test')
        require(report.get('sentApplicationData') is False, label + ' sent application data')
        require(report.get('networkSettingsChanged') is False and report.get('pairingChanged') is False,
                label + ' reported an unexpected settings change')
        require(report.get('attempts', 0) > 0, label + ' did not attempt a matching endpoint')
        if untrusted:
            require(report.get('success') is False
                    and report.get('identityMatched') is False and report.get('requiredInterfaceVerified') is False,
                    'An untrusted credential was accepted')
            require(report.get('status') in ('authentication-failed', 'authentication-timeout'),
                    'The untrusted probe did not reach authentication rejection')
        else:
            require(process.returncode == 0 and report.get('success') is True
                    and report.get('identityMatched') is True and report.get('requiredInterfaceVerified') is True,
                    'The trusted Viewer probe did not authenticate')
            require(report.get('selectedInterface') == self.args.wired_interface,
                    'The trusted probe used another interface')
            path = report.get('connectionPath', {})
            require(path.get('wired') is True and path.get('authenticated') is True
                    and path.get('requiredInterfaceVerified') is True, 'The trusted probe did not verify a wired TLS path')
        after = self.states()
        require(self.identity(after) == identity and self.streaming(after, self.args.wired_interface),
                label + ' changed the active stream')
        self.record(label + '-after', after)
        safe = safe_probe(report)
        safety.write(self.args.output / (label + '.json'), safe)
        print('PASS: ' + label + ' leaves both active connection IDs and process IDs unchanged', flush=True)
        return safe

    def stop_viewer(self, pid, *, require_test_control=False):
        # Match the real executable before terminating this exact process.
        script = ('import subprocess,sys\n'
                  'pid=int(sys.argv[1]);binary=sys.argv[2];control=sys.argv[3]\n'
                  'p=subprocess.run(["/bin/ps","-p",str(pid),"-o","comm="],capture_output=True,text=True)\n'
                  'if p.returncode:sys.exit(0)\n'
                  'if p.stdout.strip()!=binary:sys.exit(4)\n'
                  'args=subprocess.run(["/bin/ps","-p",str(pid),"-o","command="],capture_output=True,text=True).stdout\n'
                  'if control and control not in args:sys.exit(5)\n'
                  'subprocess.run(["/bin/kill","-TERM",str(pid)],check=True)\n')
        arguments = ['/usr/bin/python3', '-c', script, str(pid), self.viewer_binary,
                     self.remote_directory if require_test_control else '']
        self.remote(shlex.join(arguments))
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            result = self.remote('/bin/kill -0 ' + str(pid) + ' 2>/dev/null', check=False)
            if result.returncode:
                return
            time.sleep(0.5)
        raise RuntimeError('Viewer did not exit within the bounded restart window')

    def launch_viewer(self, *, controlled):
        command = ['/usr/bin/open', '-n', self.viewer_app, '--args', '--appliance']
        if controlled:
            command.extend(['--direct-link-test-control-directory', self.remote_directory])
        self.remote(shlex.join(command))

    def viewer_process_kind(self, pid):
        script = ('import subprocess,sys\n'
                  'pid=int(sys.argv[1]);binary=sys.argv[2];control=sys.argv[3]\n'
                  'p=subprocess.run(["/bin/ps","-p",str(pid),"-o","comm="],capture_output=True,text=True)\n'
                  'if p.returncode:print("absent");sys.exit(0)\n'
                  'if p.stdout.strip()!=binary:print("other");sys.exit(0)\n'
                  'args=subprocess.run(["/bin/ps","-p",str(pid),"-o","command="],capture_output=True,text=True).stdout\n'
                  'print("test" if control in args else "ordinary")\n')
        return self.remote(shlex.join(['/usr/bin/python3', '-c', script, str(pid),
                                       self.viewer_binary, self.remote_directory])).stdout.strip()

    def fail_active_route(self):
        data = json.dumps({'command': 'fail-active-route'})
        script = ('import os,sys\nfrom pathlib import Path\n'
                  'root=Path(sys.argv[1]);temporary=root/"command.next"\n'
                  'temporary.write_text(sys.argv[2]);os.chmod(temporary,0o600)\n'
                  'temporary.replace(root/"command.json")\n')
        self.remote(shlex.join(['/usr/bin/python3', '-c', script, self.remote_directory, data]))

    def restore_viewer(self):
        if not self.changed_viewer:
            return
        state = self.read_remote_json(self.viewer_state)
        kind = self.viewer_process_kind(int(state['pid']))
        require(kind != 'other', 'Refusing to terminate a different process during Viewer restoration')
        if kind == 'test':
            self.stop_viewer(int(state['pid']), require_test_control=True)
        if kind != 'ordinary':
            self.launch_viewer(controlled=False)
        restored = self.wait('ordinary fullscreen Viewer launch restored',
                             lambda s: self.streaming(s, self.args.wired_interface), timeout=100)
        command = self.remote('/bin/ps -p ' + str(restored['viewer']['pid']) + ' -o command=').stdout
        require('--direct-link-test-control-directory' not in command,
                'Viewer remained in explicit test-control mode')
        self.changed_viewer = False

    def run(self):
        self.started = time.monotonic()
        before = safety.snapshot(self.args, self.ssh)
        safety.write(self.args.output / 'before.json', before)
        self.remote('/bin/mkdir -p ' + shlex.quote(self.remote_directory) + ' && /bin/chmod 700 ' + shlex.quote(self.remote_directory))
        report = {'success': False, 'build': self.args.build, 'physicalDirectCableTested': False,
                  'simulatedUnavailableRoute': True, 'networkInterfacesChanged': False,
                  'systemRemoteLoginDisabledDuringTest': False, 'remoteTestDirectory': self.remote_directory}
        failure = None
        try:
            baseline = self.wait('installed signed apps stream on preferred wired interface',
                                 lambda s: self.streaming(s, self.args.wired_interface), timeout=100)
            routes = baseline['viewer'].get('discoveredRoutes', [])
            require(any(route.get('interface') == self.args.fallback_interface for route in routes),
                    'Fallback interface is not discoverable; no network changes will be made to manufacture one')
            require(baseline['viewer'].get('startupInstalled') is False,
                    'This test requires the existing manual Viewer launch; it will not disable a login agent')
            report['trustedProbe'] = self.probe(untrusted=False)
            report['untrustedProbe'] = self.probe(untrusted=True)
            original_pid = int(self.states()['viewer']['pid'])
            self.changed_viewer = True
            self.stop_viewer(original_pid)
            self.launch_viewer(controlled=True)
            controlled = self.wait('Viewer test-control launch reconnects on preferred wired interface',
                                   lambda s: s['viewer']['pid'] != original_pid and self.streaming(s, self.args.wired_interface), timeout=100)
            controlled_pid = controlled['viewer']['pid']
            host_pid = controlled['host']['pid']
            failed_id = controlled['viewer']['connectionID']
            started = time.monotonic()
            self.fail_active_route()
            fallback = self.wait('simulated route failure recovers over fallback interface',
                                 lambda s: self.streaming(s, self.args.fallback_interface)
                                 and s['viewer']['pid'] == controlled_pid
                                 and s['viewer']['connectionID'] != failed_id, timeout=45)
            report['fallbackSeconds'] = round(time.monotonic() - started, 3)
            fallback_id = fallback['viewer']['connectionID']
            last_healthy_fallback = [time.monotonic()]
            def preferred_returned(states):
                if states['viewer'].get('connectionID') == fallback_id and self.streaming(states, self.args.fallback_interface):
                    last_healthy_fallback[0] = time.monotonic()
                return (self.streaming(states, self.args.wired_interface)
                        and states['viewer']['pid'] == controlled_pid
                        and states['viewer']['connectionID'] != fallback_id
                        and states['viewer'].get('lastPreferredRouteProbe', {}).get('success') is True)
            returned = self.wait('automatic authenticated preferred-route probe returns stream to Ethernet',
                                 preferred_returned,
                                 timeout=110)
            returned_at = time.monotonic()
            require(returned['host']['pid'] == host_pid, 'Host restarted during route recovery')
            preferred_probe = returned['viewer'].get('lastPreferredRouteProbe', {})
            require(preferred_probe.get('identityMatched') is True
                    and preferred_probe.get('requiredInterfaceVerified') is True
                    and preferred_probe.get('selectedInterface') == self.args.wired_interface,
                    'Preferred-route return lacks an authenticated interface-bound probe')
            report['preferredReturnSeconds'] = round(time.monotonic() - started, 3)
            report['preferredReturnProbe'] = safe_probe(preferred_probe)
            report['recoveredFullscreen'] = returned['viewer']['fullscreen']
            # A healthy Wi-Fi stream closed for a preferred-route upgrade must
            # not be put into the failed-route cooldown. Exercise its immediate
            # reuse while that erroneous 30-second cooldown would still apply.
            second_started = time.monotonic()
            self.fail_active_route()
            report['secondFailureAfterPreferredReturnSeconds'] = round(time.monotonic() - returned_at, 3)
            report['secondFailureAfterLastHealthyBackupSeconds'] = round(time.monotonic() - last_healthy_fallback[0], 3)
            require(report['secondFailureAfterLastHealthyBackupSeconds'] < 30,
                    'The second simulated failure missed the healthy-backup cooldown regression window')
            second_fallback = self.wait('healthy fallback is immediately reusable after preferred-route upgrade',
                                        lambda s: self.streaming(s, self.args.fallback_interface)
                                        and s['viewer']['pid'] == controlled_pid and s['host']['pid'] == host_pid
                                        and s['viewer']['connectionID'] != returned['viewer']['connectionID']
                                        and s['host']['connectionID'] != returned['host']['connectionID'],
                                        timeout=max(0.1, 15 - (time.monotonic() - second_started)))
            report['secondFallbackSeconds'] = round(time.monotonic() - second_started, 3)
            require(report['secondFallbackSeconds'] <= 15, 'Healthy fallback took longer than 15 seconds to recover')
            report['healthyBackupImmediatelyReusable'] = True
            report['secondFallbackFullscreen'] = second_fallback['viewer']['fullscreen']
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
            failure = error
        finally:
            try:
                self.restore_viewer()
                report['ordinaryViewerRestored'] = not self.changed_viewer
            except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
                report['ordinaryViewerRestored'] = False
                failure = failure or error
            try:
                after = safety.snapshot(self.args, self.ssh)
                safety.write(self.args.output / 'after.json', after)
                checks = {machine + '.' + key: before[machine][key] == after[machine][key]
                          for machine in ('studio', 'imac') for key in POLICY_KEYS}
                checks['viewerStartupPreferenceUnchanged'] = before['imac']['app'].get('startupInstalled') == after['imac']['app'].get('startupInstalled')
                report['preservationChecks'] = checks
                require(all(checks.values()), 'Company network, pairing binding, FileVault or Viewer startup preference changed')
                report['uiCaptureHelperOff'] = True
                report['appDisplaySSHAbsent'] = True
            except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
                failure = failure or error
            report['observations'] = self.observations
            report['success'] = failure is None
            if failure:
                report['failure'] = type(failure).__name__ + ': ' + str(failure)
            safety.write(self.args.output / 'result.json', report)
        if failure:
            raise failure
        print('PASS: no-Hello trusted probe, untrusted credential rejection, fallback, automatic Ethernet return and immediate healthy-backup reuse; ordinary Viewer restored', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--socket', type=Path, required=True)
    parser.add_argument('--address', required=True)
    parser.add_argument('--user', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--build', default='58')
    parser.add_argument('--wired-interface', default='en0')
    parser.add_argument('--fallback-interface', default='en1')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    os.chmod(args.output, 0o700)
    RuntimeTest(args).run()


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print('FAIL: ' + str(error), file=sys.stderr)
        sys.exit(1)
