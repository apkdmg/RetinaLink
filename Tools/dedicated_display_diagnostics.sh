#!/bin/sh
# Temporary forced-command diagnostics for the dedicated display account.
# No shell command passthrough, screen pixels, credentials or secret files.
set -eu
[ "$(/usr/bin/id -un)" = retinalinkdisplay ] || exit 77
case "${SSH_ORIGINAL_COMMAND:-status}" in
  status|sleep-wake|wake)
    exec /usr/bin/python3 - "${SSH_ORIGINAL_COMMAND:-status}" <<'PY'
import ctypes, hashlib, json, os, pathlib, plistlib, re, subprocess, sys, time
HOME = pathlib.Path('/Users/retinalinkdisplay')
APP = HOME / 'Applications/RetinaLink Viewer.app'
LOG = HOME / 'Library/Logs/RetinaLink'

def command(args, timeout=15):
    try:
        value = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        return {'returncode': value.returncode, 'stdout': value.stdout.strip(), 'stderr': value.stderr.strip()}
    except (OSError, subprocess.TimeoutExpired):
        return {'returncode': -1, 'stdout': '', 'stderr': ''}

def emit(label, value):
    print('RETINALINK_' + label)
    print(value if isinstance(value, str) else json.dumps(value, sort_keys=True))

def read_json(path):
    try:
        if path.is_symlink() or path.stat().st_size > 1024 * 1024:
            return {}
        value = json.loads(path.read_text())
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}

def preference(args):
    result = command(['/usr/bin/defaults', '-currentHost', 'read'] + args[1:] if args[:1] == ['-currentHost'] else ['/usr/bin/defaults', 'read'] + args)
    return result['stdout'] if result['returncode'] == 0 else None

def lock_policy(text, returncode, preference):
    # These are sysadminctl's known status report formats. A zero-second or
    # immediate delay requires a password; missing/failed reports prove nothing.
    off = bool(re.search(r'(?m)\bscreen\s*lock is off\s*$', text, re.I))
    required = bool(re.search(r'(?m)\bscreen\s*lock delay is (?:immediate|\d+ seconds)\s*$', text, re.I))
    effective = 'unknown'
    if returncode == 0 and off and not required:
        effective = 'disabled'
    elif returncode == 0 and required and not off:
        effective = 'password-required'
    return {'askForPassword': preference, 'effective': effective,
            'sysadminctlSucceeded': returncode == 0,
            'effectivePolicyReportedDisabled': off,
            'effectivePolicyReportedRequired': required}


def console_session(roots, uid):
    result = {'screenIsLocked': None, 'screenLockSource': 'unknown',
              'onConsole': None, 'loginDone': None, 'uid': None}
    for root in roots:
        if isinstance(root.get('IOConsoleLocked'), bool):
            result['screenIsLocked'] = root['IOConsoleLocked']
            result['screenLockSource'] = 'IOConsoleLocked'
        for entry in root.get('IOConsoleUsers', []):
            user_id = entry.get('kCGSSessionUserIDKey', entry.get('CGSSessionUserIDKey'))
            name = entry.get('kCGSSessionUserNameKey', entry.get('CGSSessionUserNameKey'))
            if str(user_id) != str(uid) and name != 'retinalinkdisplay':
                continue
            result['uid'] = uid
            for out, keys in {'onConsole': ('kCGSSessionOnConsoleKey', 'CGSSessionOnConsoleKey'),
                              'loginDone': ('kCGSessionLoginDoneKey', 'kCGSSessionLoginDoneKey', 'CGSSessionLoginDoneKey')}.items():
                for key in keys:
                    if isinstance(entry.get(key), bool):
                        result[out] = entry[key]
                        break
    return result


def power():
    result = command(['/usr/sbin/ioreg', '-r', '-n', 'IODisplayWrangler', '-d', '1', '-a'], timeout=2)
    state = None
    try:
        entries = plistlib.loads(result['stdout'].encode())
        for entry in entries:
            state = entry.get('IOPowerManagement', {}).get('CurrentPowerState')
            if isinstance(state, int):
                break
    except (ValueError, TypeError, AttributeError, plistlib.InvalidFileException):
        pass
    return {'time': time.time(), 'currentPowerState': state,
            'asleep': isinstance(state, int) and state <= 1,
            'awake': isinstance(state, int) and state >= 3}

class LocalUserActivity:
    """Public IOKit activity assertion, scoped to this bounded wake request."""
    def __init__(self):
        self.cf = ctypes.CDLL('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation')
        self.io = ctypes.CDLL('/System/Library/Frameworks/IOKit.framework/IOKit')
        self.cf.CFStringCreateWithCString.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_uint32]
        self.cf.CFStringCreateWithCString.restype = ctypes.c_void_p
        self.cf.CFRelease.argtypes = [ctypes.c_void_p]
        self.cf.CFRelease.restype = None
        self.io.IOPMAssertionDeclareUserActivity.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(ctypes.c_uint32)]
        self.io.IOPMAssertionDeclareUserActivity.restype = ctypes.c_uint32
        self.io.IOPMAssertionRelease.argtypes = [ctypes.c_uint32]
        self.io.IOPMAssertionRelease.restype = ctypes.c_uint32
        # SDK: kCFStringEncodingUTF8=0x08000100; IOPMAssertionID=uint32_t.
        self.name = self.cf.CFStringCreateWithCString(None, b'RetinaLink authorized display wake test', 0x08000100)
        if not self.name:
            raise OSError('Could not create wake assertion name')
        self.assertion = ctypes.c_uint32(0)
        self.released = False

    def declare(self):
        # SDK: kIOPMUserActiveLocal is the first enum member, value zero.
        # Reuse the returned assertion ID for each continuous activity report.
        return int(self.io.IOPMAssertionDeclareUserActivity(self.name, 0, ctypes.byref(self.assertion)))

    def release(self):
        if self.released:
            return None
        self.released = True
        status = int(self.io.IOPMAssertionRelease(self.assertion.value)) if self.assertion.value else None
        self.cf.CFRelease(self.name)
        self.name = None
        return status


def wake_display(power_reader=None, activity_factory=None, clock=None, sleeper=None, timeout=20):
    read_power = power_reader or power
    factory = activity_factory or LocalUserActivity
    now = clock or time.monotonic
    pause = sleeper or time.sleep
    started = now()
    maximum = min(max(timeout, 0), 20)
    deadline = started + maximum
    result = {'method': 'IOPMAssertionDeclareUserActivity', 'userActiveLocal': 0,
              'maximumRetrySeconds': maximum, 'attempts': [], 'powerSamples': [],
              'requestSucceeded': False, 'observedDisplayWake': False,
              'assertionReleased': False}
    activity = None
    try:
        activity = factory()
        while True:
            code = activity.declare()
            result['attempts'].append({'elapsedSeconds': now() - started, 'returncode': code})
            result['requestSucceeded'] = result['requestSucceeded'] or code == 0
            state = read_power()
            result['powerSamples'].append(state)
            result['after'] = state
            if state['awake']:
                result['observedDisplayWake'] = True
                break
            remaining = deadline - now()
            if remaining <= 0:
                break
            pause(min(1, remaining))
    except (OSError, ValueError, AttributeError):
        # Report only the error category, never arbitrary library output.
        result['error'] = 'Local user activity API unavailable'
    finally:
        if activity is not None:
            release = activity.release()
            result['assertionReleased'] = release in (None, 0)
            result['assertionReleaseReturncode'] = release
        result['elapsedSeconds'] = now() - started
    return result


if sys.argv[1] == 'wake':
    result = wake_display()
    print(json.dumps(result, sort_keys=True))
    raise SystemExit(0 if result['requestSucceeded'] and result['observedDisplayWake'] else 1)

if sys.argv[1] == 'sleep-wake':
    before = power()
    request = command(['/usr/bin/pmset', 'displaysleepnow'])
    samples = []
    end = time.monotonic() + 8
    while time.monotonic() < end:
        samples.append(power())
        if samples[-1]['asleep']:
            break
        time.sleep(0.3)
    wake = wake_display()
    print(json.dumps({'displaySleepOnly': True, 'before': before,
                      'sleepRequestSucceeded': request['returncode'] == 0,
                      'sleepSamples': samples, 'wakeRequestSucceeded': wake['requestSucceeded'],
                      'wake': wake, 'after': wake['after'] if 'after' in wake else power(),
                      'observedDisplaySleep': any(s['asleep'] for s in samples),
                      'observedDisplayWake': wake['observedDisplayWake']}, sort_keys=True))
    raise SystemExit(0)

proof = read_json(LOG / 'dedicated-setup.json')
emit('SETUP', {k: proof[k] for k in ('configured', 'account', 'uid', 'administrator',
    'automaticLogin', 'lockPasswordRequired', 'viewerStartsAtLogin', 'restartRequired',
    'fileVaultChanged', 'recoveryCycleVerified') if k in proof})
ui = read_json(LOG / 'Viewer-ui.json')
emit('UI', {k: ui[k] for k in ('version', 'build', 'pid', 'phase', 'connected', 'trusted',
    'fullscreen', 'systemUIAutoHidden', 'standbyVisible', 'automaticReconnect', 'displayWindows',
    'startupInstalled', 'transport', 'requiresRemoteLogin', 'connectionID', 'time', 'windowFrame') if k in ui})
emit('CONSOLE', command(['/usr/bin/stat', '-f', '%Su', '/dev/console'])['stdout'])
emit('FILEVAULT', command(['/usr/bin/fdesetup', 'status'])['stdout'])
lock = preference(['com.apple.screensaver', 'askForPassword'])
idle = preference(['-currentHost', 'com.apple.screensaver', 'idleTime'])
screenlock = command(['/usr/sbin/sysadminctl', '-screenLock', 'status'])
effective_text = '\n'.join(filter(None, [screenlock['stdout'], screenlock['stderr']]))
# The effective result is queried in this forced SSH user's context.
# Actual unlocked-session evidence is independently read from IOConsoleLocked.
emit('LOCK', lock if lock is not None else 'unknown')
emit('LOCK_POLICY', lock_policy(effective_text, screenlock['returncode'], lock))
emit('IDLE', idle if idle is not None else 'unknown')
admin = command(['/usr/bin/dsmemberutil', 'checkmembership', '-U', 'retinalinkdisplay', '-G', 'admin'])
emit('ADMIN', admin['stdout'])
pending = HOME / 'Library/Application Support/RetinaLink/dedicated-enrollment.json'
try:
    pending.lstat()
    exists = True
except FileNotFoundError:
    exists = False
emit('PENDING', 'pending' if exists else 'consumed')
assertions = command(['/usr/bin/pmset', '-g', 'assertions'])['stdout']
matching = [line for line in assertions.splitlines() if 'RetinaLink dedicated display' in line]
emit('ASSERTIONS', 'RetinaLink dedicated display' if matching else 'absent')
agent = HOME / 'Library/LaunchAgents/local.retinalink.viewer.startup.plist'
startup = {'exists': agent.exists(), 'expectedViewerLaunch': False}
try:
    if not agent.is_symlink():
        item = plistlib.loads(agent.read_bytes())
        permitted = {'Label', 'ProgramArguments', 'RunAtLoad', 'KeepAlive', 'ThrottleInterval', 'LimitLoadToSessionType', 'ProcessType', 'AssociatedBundleIdentifiers'}
        if isinstance(item, dict) and set(item).issubset(permitted):
            startup['nonSecretDocumentSHA256'] = hashlib.sha256(agent.read_bytes()).hexdigest()
        startup.update(expectedViewerLaunch=item.get('Label') == 'local.retinalink.viewer.startup' and item.get('ProgramArguments') == [str(APP / 'Contents/MacOS/RetinaLink'), '--appliance'],
            runAtLoad=item.get('RunAtLoad') is True, aquaOnly=item.get('LimitLoadToSessionType') == 'Aqua',
            restartOnFailure=item.get('KeepAlive') == {'SuccessfulExit': False})
except (OSError, ValueError):
    pass
launch = command(['/bin/launchctl', 'print', 'gui/' + str(os.getuid()) + '/local.retinalink.viewer.startup'])
match = re.search(r'(?m)^\s*pid = (\d+)\s*$', launch['stdout'])
startup.update(loaded=launch['returncode'] == 0, pid=int(match[1]) if match else None,
               running=bool(re.search(r'(?m)^\s*state = running\s*$', launch['stdout'])))
emit('STARTUP', startup)
processes = command(['/bin/ps', '-axo', 'comm='])['stdout'].splitlines()
boot = command(['/usr/sbin/sysctl', '-n', 'kern.boottime'])['stdout']
match = re.search(r'\bsec\s*=\s*(\d+)', boot)
pid = ui.get('pid')
process = command(['/bin/ps', '-ww', '-p', str(pid), '-o', 'uid=,comm='])['stdout'] if isinstance(pid, int) else ''
parts = process.split(None, 1)
emit('RUNTIME', {'uid': os.getuid(), 'bootEpoch': int(match[1]) if match else None,
    'uiCaptureHelperOff': not any(pathlib.Path(p.strip()).name == 'SkyComputerUseService' for p in processes),
    'viewerProcessOwnedByAccount': len(parts) == 2 and parts[0] == str(os.getuid()),
    'viewerProcessAtInstalledPath': len(parts) == 2 and parts[1] == str(APP / 'Contents/MacOS/RetinaLink')})
binding = command(['/usr/bin/defaults', 'read', 'local.retinalink.Viewer', 'trustedDisplayBinding.v1'])
emit('BINDING', {'exists': binding['returncode'] == 0, 'nonSecretPreferenceSHA256': hashlib.sha256(binding['stdout'].encode()).hexdigest() if binding['returncode'] == 0 else None})
session = console_session([], os.getuid())
console = command(['/usr/sbin/ioreg', '-r', '-n', 'Root', '-d', '1', '-a'])
try:
    session = console_session(plistlib.loads(console['stdout'].encode()), os.getuid())
except (ValueError, TypeError, AttributeError, plistlib.InvalidFileException):
    pass
emit('SESSION', session)
emit('DISPLAY', power())
metrics = read_json(LOG / 'Viewer.json')
rendered = []
for sample in metrics.get('samples', [])[-120:]:
    if not isinstance(sample, dict) or sample.get('kind') != 'viewer':
        continue
    match = re.search(r'(\d+) × (\d+) · ([0-9.]+) rendered updates/s · ([0-9.]+) Mbps', sample.get('text', ''))
    if match:
        rendered.append({'time': sample.get('time'), 'width': int(match[1]), 'height': int(match[2]),
                         'renderedUpdatesPerSecond': float(match[3]), 'Mbps': float(match[4])})
emit('RENDER', {'pid': metrics.get('pid'), 'build': metrics.get('build'), 'samples': rendered[-8:]})
power_test = read_json(LOG / 'dedicated-power-test.json')
emit('POWER_TEST', {k: power_test[k] for k in ('bootBefore', 'sleepSchedule', 'time', 'sleepScheduledAt', 'sleepRequestedAt', 'wakeScheduledAt', 'events', 'sleepWakeEvents', 'rebootRequested', 'rebootRequestedAt', 'sleepVerified', 'wakeVerified', 'success', 'error', 'fileVaultBefore', 'fileVaultAfterSleep', 'fileVaultUnchanged', 'powerPolicyBeforeSHA256', 'powerPolicyAfterSHA256', 'powerPolicyUnchanged', 'systemSleepCommandSucceeded', 'waitingForAuthorizedTestTrigger', 'testWakeScheduleRemoved', 'consoleUnlockedBefore', 'guiLockPolicyBefore', 'guiLockPolicyAfter', 'guiWakeRequestSucceeded', 'wakeFullscreenRecoveryVerified') if k in power_test})
PY
    ;;
  restart-viewer)
    exec /bin/launchctl kickstart -k "gui/$(/usr/bin/id -u)/local.retinalink.viewer.startup"
    ;;
  cleanup)
    keyfile="$HOME/.ssh/authorized_keys"
    /usr/bin/sed '/ RetinaLink-dedicated-test$/d' "$keyfile" > "$keyfile.next"
    /bin/chmod 600 "$keyfile.next"
    /bin/mv "$keyfile.next" "$keyfile"
    /bin/rm -f "$HOME/.retinalink-test.sh"
    ;;
  *) exit 64 ;;
esac
