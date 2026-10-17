#!/usr/bin/env python3
"""Test an installed, paired Developer ID update using native launch and SSH.

Run only after notarizing both builds and completing baseline Display Setup.
Never exports Keychain contents or changes FileVault, login or TCC settings.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import time

from signing import select_identity, verify_app

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--release', type=Path, required=True)
p.add_argument('--host-app', type=Path, required=True)
p.add_argument('--address', required=True)
p.add_argument('--user', required=True)
p.add_argument('--socket', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
out = a.output.resolve(); out.mkdir(parents=True, exist_ok=True)
host_app = a.host_app.resolve()
ssh = ['/usr/bin/ssh', '-S', str(a.socket.resolve()), '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=5', '-l', a.user, a.address]


def run(args, **kw):
    return subprocess.run([str(x) for x in args], check=True, **kw)


def remote(command):
    return run(ssh+[command], capture_output=True, text=True, timeout=45).stdout


def load(path):
    return json.loads(Path(path).read_text())


def viewer():
    return json.loads(remote('/bin/cat "$HOME/Library/Logs/RetinaLink/Viewer-ui.json"'))


def wait(label, condition, seconds=90):
    end = time.monotonic()+seconds
    while time.monotonic() < end:
        try:
            value = condition()
            if value:
                print('PASS: '+label, flush=True)
                return value
        except (OSError, ValueError, KeyError, subprocess.SubprocessError):
            pass
        time.sleep(1)
    raise RuntimeError(label+' timed out; inspect metadata logs. No security settings were changed.')


def helper_off():
    names = run(['/bin/ps', '-axo', 'comm='], capture_output=True, text=True).stdout.splitlines()
    assert not any(Path(n.strip()).name == 'SkyComputerUseService' for n in names)


def snapshot():
    status = json.loads(remote('"$HOME/Applications/RetinaLink Viewer.app/Contents/MacOS/RetinaLink" --device-status'))
    # Only hashes of the public authorized_keys file and non-secret binding.
    status['authorizedKeysSHA256'] = remote('/usr/bin/shasum -a 256 "$HOME/.ssh/authorized_keys"').split()[0]
    status['viewerBindingSHA256'] = remote('/usr/bin/defaults read local.retinalink.Viewer trustedDisplayBinding.v1 | /usr/bin/shasum -a 256').split()[0]
    binding = run(['/usr/bin/defaults', 'read', 'local.retinalink.Host', 'trustedDisplayBinding.v1'], capture_output=True).stdout
    status['hostBindingSHA256'] = hashlib.sha256(binding).hexdigest()
    status['loginSettings'] = remote('/usr/bin/fdesetup status; /usr/bin/defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null || true')
    return status


def stop_host():
    pid = int(load(Path.home()/'Library/Logs/RetinaLink/Host.json')['pid'])
    command = run(['/bin/ps', '-p', str(pid), '-o', 'command='], capture_output=True, text=True).stdout.strip()
    assert command.startswith(str(host_app/'Contents/MacOS/RetinaLink'))
    subprocess.run(['/bin/launchctl', 'bootout', 'gui/'+str(os.getuid())+'/local.retinalink.host.startup'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if subprocess.run(['/bin/ps', '-p', str(pid)], stdout=subprocess.DEVNULL).returncode == 0:
        try: os.kill(pid, signal.SIGTERM)
        except ProcessLookupError: pass
    wait('old Host exits', lambda: subprocess.run(['/bin/ps', '-p', str(pid)], stdout=subprocess.DEVNULL).returncode != 0, 20)
    return pid


helper_off()
state = load(a.release/'release-state.json')
assert state['complete'], 'Notarize and staple the release first'
identity = select_identity(state['identity']['identity'])
incoming = a.release/'build/apps/RetinaLink Host.app'
assert verify_app(incoming, identity, 'Host') == state['apps']['Host']
baseline = verify_app(host_app, identity, 'Host')
assert baseline['build'] != state['apps']['Host']['build']
assert viewer()['phase'] == 'streaming', 'Complete baseline capture approval first'
before = snapshot(); (out/'before.json').write_text(json.dumps(before, indent=2)+'\n')
backup = out/'previous/RetinaLink Host.app'; assert not backup.exists(), 'Use a fresh output directory'
backup.parent.mkdir()
run(['/usr/bin/ditto', host_app, backup])
stop_host()
shutil.rmtree(host_app)
run(['/usr/bin/ditto', incoming, host_app])
assert verify_app(host_app, identity, 'Host') == state['apps']['Host']
run(['/usr/sbin/spctl', '--assess', '--type', 'execute', host_app])
run(['/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister', '-f', host_app])
report = out/'update.json'; assert not report.exists()
run(['/usr/bin/open', '-n', host_app, '--args', '--autostart', '--update-viewer', '--ssh-control-path', a.socket.resolve(), '--update-report', report])
result = wait('Host-side Viewer update finishes', lambda: load(report) if report.exists() else None, 150)
assert result.get('success') and result.get('pairingPreserved'), result
new_build = state['apps']['Viewer']['build']
wait('new signed Viewer reconnects fullscreen', lambda: (s if (s := viewer())['build'] == new_build and s['phase'] == 'streaming' and s['fullscreen'] else None))
after = snapshot(); (out/'after.json').write_text(json.dumps(after, indent=2)+'\n')
for key in ['hostID', 'namespace', 'team', 'startupAtLogin', 'authorizedKeysSHA256', 'viewerBindingSHA256', 'hostBindingSHA256', 'loginSettings']:
    assert before[key] == after[key], key+' changed during update'
print('PASS: binding, public authorized keys, startup and login settings unchanged', flush=True)

# Relaunch from the real startup agent, with no test flags or inherited tool grant.
previous_host_pid = stop_host()
agent = Path.home()/'Library/LaunchAgents/local.retinalink.host.startup.plist'
assert plistlib.loads(agent.read_bytes())['ProgramArguments'] == [str(host_app/'Contents/MacOS/RetinaLink'), '--autostart']
run(['/bin/launchctl', 'bootstrap', 'gui/'+str(os.getuid()), agent])
def agent_streaming():
    current = load(Path.home()/'Library/Logs/RetinaLink/Host.json')
    return current.get('build') == new_build and current['pid'] != previous_host_pid and any(s['kind'] == 'state' and s['text'].startswith('Streaming') for s in current['samples']) and viewer()['phase'] == 'streaming'
wait('signed Host startup agent restores streaming', agent_streaming)
old_viewer = viewer()['pid']
remote('command=$(/bin/ps -p '+str(old_viewer)+' -o command=); case "$command" in "$HOME/Applications/RetinaLink Viewer.app/Contents/MacOS/RetinaLink"*) /bin/kill -KILL '+str(old_viewer)+' ;; *) exit 4 ;; esac')
wait('new Viewer crash recovery retains fullscreen pairing', lambda: (s if (s := viewer())['pid'] != old_viewer and s['phase'] == 'streaming' and s['fullscreen'] else None))
assert snapshot() == after
helper_off()
(out/'result.json').write_text(json.dumps({'success': True, 'beforeBuild': baseline['build'], 'afterBuild': new_build, 'pairingPreserved': True, 'authorizedKeysUnchanged': True, 'hostLoginAgentRecovery': True, 'viewerCrashRecovery': True, 'loginSettingsUnchanged': True, 'uiCaptureHelperOff': True}, indent=2)+'\n')
print('PASS: installed signed update validation complete', flush=True)
