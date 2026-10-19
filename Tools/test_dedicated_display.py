#!/usr/bin/env python3
"""Verify real dedicated login, fullscreen recovery and observed display sleep/wake.

Uses only the temporary forced-command diagnostic SSH key. Run after an actual
owner-authorized reboot; --previous-boot-epoch independently checks that reboot.
The test account must have Tools/dedicated_display_diagnostics.sh installed at
~/.retinalink-test.sh (owned by that user, mode 0700) through an owner-authorized
administrator session. It retains the existing forced-command key restriction.
No passwords, pairing secrets, enrollment contents or screen pixels are read.
Viewer restart and display sleep/wake are the only requested live actions.
"""
import argparse
import json
import pathlib
import re
import subprocess
import time


def fields(text):
    matches = list(re.finditer(r'^RETINALINK_([A-Z_]+)\n', text, re.M))
    return {match[1]: text[match.end():matches[i + 1].start() if i + 1 < len(matches) else len(text)].strip()
            for i, match in enumerate(matches)}


def helper_off():
    names = subprocess.check_output(['/bin/ps', '-axo', 'comm='], text=True).splitlines()
    assert not any(pathlib.Path(s.strip()).name == 'SkyComputerUseService' for s in names), 'Studio UI capture helper is running'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--address', required=True)
    parser.add_argument('--key', type=pathlib.Path, required=True)
    parser.add_argument('--known-hosts', type=pathlib.Path, required=True)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    parser.add_argument('--timeout', type=int, default=180)
    parser.add_argument('--expected-build', default='59')
    parser.add_argument('--previous-boot-epoch', type=int)
    parser.add_argument('--host-ui', type=pathlib.Path,
                        help='Optional fresh Host UI metadata; connection IDs are independently generated on each peer')
    parser.add_argument('--verify-only', action='store_true', help='Only inspect the current login; no restart or sleep request')
    parser.add_argument('--cleanup', action='store_true')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    args.output.chmod(0o700)
    ssh = ['/usr/bin/ssh', '-i', str(args.key), '-o', 'IdentitiesOnly=yes', '-o', 'BatchMode=yes',
           '-o', 'StrictHostKeyChecking=yes', '-o', 'UserKnownHostsFile=' + str(args.known_hosts),
           '-o', 'ConnectTimeout=5', '-o', 'LogLevel=ERROR', 'retinalinkdisplay@' + args.address]

    def save(name, value):
        path = args.output / name
        path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
        path.chmod(0o600)

    def run(action):
        # The installed forced-command script rejects every unlisted action.
        assert action in ('status', 'restart-viewer', 'wake', 'sleep-wake', 'cleanup')
        return subprocess.check_output(ssh + [action], text=True, stderr=subprocess.PIPE, timeout=45)

    def sample(since=0):
        helper_off()
        text = run('status')
        status_path = args.output / 'last-status.txt'
        status_path.write_text(text)
        status_path.chmod(0o600)
        item = fields(text)
        proof = json.loads(item['SETUP'])
        assert proof['configured'] and proof['recoveryCycleVerified'] and proof['fileVaultChanged'] is False, 'Dedicated setup evidence is missing'
        ui = json.loads(item['UI'])
        runtime = json.loads(item['RUNTIME'])
        startup = json.loads(item['STARTUP'])
        lock = json.loads(item['LOCK_POLICY'])
        binding = json.loads(item['BINDING'])
        session = json.loads(item.get('SESSION', '{}'))
        assert session.get('screenIsLocked') is False and session.get('screenLockSource') == 'IOConsoleLocked', 'Dedicated graphical session is locked or its unlocked state is unknown'
        assert item['CONSOLE'] == 'retinalinkdisplay', 'Display account is not the console user'
        assert item['FILEVAULT'] == 'FileVault is Off.', 'FileVault differs from the unchanged off baseline or is unknown'
        assert 'is not a member' in item['ADMIN'], 'Display account is not confirmed standard'
        assert lock['effective'] == 'disabled', 'Effective screen-lock policy is required or unknown'
        assert lock['askForPassword'] in (None, '0', 'false'), 'Explicit idle password preference requires a password'
        assert item['IDLE'] == '0', 'Screensaver is enabled or its policy is unknown'
        assert item['PENDING'] == 'consumed', 'First-login enrollment has not committed'
        assert item['ASSERTIONS'] == 'RetinaLink dedicated display', 'Dedicated idle-sleep assertion is absent'
        assert runtime['uid'] == proof['uid'] and runtime['uid'] >= 501 and runtime['uiCaptureHelperOff'], 'Dedicated UID differs or iMac UI capture helper is running'
        assert runtime['viewerProcessOwnedByAccount'] and runtime['viewerProcessAtInstalledPath'], 'Viewer is not the installed dedicated-account process'
        assert startup['expectedViewerLaunch'] and startup['runAtLoad'] and startup['aquaOnly'] and startup['restartOnFailure'], 'Dedicated startup agent differs'
        assert startup['loaded'] and startup['running'] and startup['pid'] == ui['pid'], 'Startup agent is not running the reported Viewer'
        assert ui['build'] == args.expected_build, 'Viewer build differs'
        assert ui['trusted'] and ui['connected'] and ui['fullscreen'] and ui['startupInstalled'] and ui['systemUIAutoHidden'], 'Viewer is not trusted, connected and fullscreen'
        assert ui['automaticReconnect'] and ui['displayWindows'] == 1 and ui['phase'] == 'streaming', 'Viewer is not streaming as one automatic display'
        assert ui['transport'] == 'direct-tls' and ui['requiresRemoteLogin'] is False and ui['connectionID'], 'Display is not using direct authenticated TLS'
        assert binding['exists'] and binding['nonSecretPreferenceSHA256'], 'Saved non-secret binding metadata is absent'
        assert -2 <= time.time() - ui['time'] < 8 and ui['time'] >= since, 'Viewer UI metadata is stale'
        if args.previous_boot_epoch is not None:
            assert runtime['bootEpoch'] > args.previous_boot_epoch, 'A new kernel boot has not been observed'
        host = None
        if args.host_ui:
            host = json.loads(args.host_ui.read_text())
            assert host['streaming'] and host['trusted'] and not host['paused'] and host['connectionID'], 'Host is not actively streaming'
            assert -2 <= time.time() - host['time'] < 8 and host['time'] >= since, 'Host UI metadata is stale'
        # Render counters are observed metadata, not proof of physical refresh.
        # A static desktop can correctly produce zero new rendered updates.
        return {'ui': ui, 'runtime': runtime, 'startup': startup, 'lock': lock, 'binding': binding,
                'display': json.loads(item['DISPLAY']), 'render': json.loads(item['RENDER']),
                'powerTest': json.loads(item.get('POWER_TEST', '{}')), 'session': session, 'host': host}

    def wait(label, predicate, timeout, since=0):
        deadline = time.monotonic() + timeout
        last_error = 'No sample available'
        while True:
            try:
                current = sample(since)
                if predicate(current):
                    return current
                last_error = 'Condition has not been observed'
            except (AssertionError, ValueError, KeyError, IndexError, OSError, subprocess.SubprocessError) as error:
                last_error = str(error)
            if time.monotonic() >= deadline:
                raise RuntimeError(label + ': ' + last_error)
            time.sleep(2)

    helper_off()
    if args.cleanup:
        run('cleanup')
        print('Temporary forced-command diagnostic key removed.')
        return
    initial = wait('Dedicated sign-in not verified', lambda state: True, args.timeout)
    save('initial.json', initial)
    result = {'success': False, 'initial': initial, 'fileVaultUnchanged': True,
              'uiCaptureHelperOff': True, 'realRebootVerified': args.previous_boot_epoch is not None,
              'requiresSeparateRebootEvidence': args.previous_boot_epoch is None,
              'displaySleepOnly': True, 'physical5K60Proven': False}
    print('PASS: dedicated standard account, effective unlocked policy, consumed enrollment and fresh fullscreen direct-TLS startup', flush=True)
    if args.verify_only:
        result.update(success=True, verificationOnly=True)
        save('result.json', result)
        return
    restarted_at = time.time()
    run('restart-viewer')
    recovered = wait('Viewer launchd recovery not verified', lambda state:
        state['ui']['pid'] != initial['ui']['pid'] and state['ui']['connectionID'] != initial['ui']['connectionID'],
        90, restarted_at)
    assert recovered['binding'] == initial['binding'], 'Saved pairing metadata changed during Viewer restart'
    assert recovered['runtime']['bootEpoch'] == initial['runtime']['bootEpoch'], 'Unexpected reboot during recovery test'
    result['recovered'] = recovered
    save('recovered.json', recovered)
    print('PASS: launchd restarted Viewer and it reconnected fullscreen without user input', flush=True)
    wake_started = time.time()
    display_cycle = json.loads(run('sleep-wake'))
    save('display-sleep-wake.json', display_cycle)
    assert display_cycle['displaySleepOnly'] and display_cycle['sleepRequestSucceeded'] and display_cycle['wakeRequestSucceeded'], 'Display sleep/wake request failed'
    assert display_cycle['before']['awake'] and display_cycle['observedDisplaySleep'] and display_cycle['observedDisplayWake'], 'Actual display power-down and wake were not both observed'
    awake = wait('Fullscreen streaming after display wake not verified', lambda state: state['display']['awake'], 90, display_cycle['after']['time'])
    assert awake['binding'] == initial['binding'], 'Saved pairing metadata changed across display sleep/wake'
    assert awake['runtime']['bootEpoch'] == initial['runtime']['bootEpoch'], 'Unexpected reboot during display-wake test'
    result.update(success=True, awake=awake, displayCycle=display_cycle,
                  automaticReconnectionVerified=True, observedDisplaySleepWake=True)
    save('result.json', result)
    print('PASS: observed display sleep/wake and fresh fullscreen streaming; pairing and FileVault preserved', flush=True)


if __name__ == '__main__':
    main()
