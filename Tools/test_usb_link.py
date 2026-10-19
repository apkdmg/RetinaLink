#!/usr/bin/env python3
"""Read-only USB-link and company-network checks over an existing SSH master.

No app, interface, account or security setting is changed. Both supplied binaries
must implement --usb-link-status; an old binary is a preflight error, not a
reason to launch its GUI. Protected account evidence remains explicitly unknown.
"""

import argparse
import json
from pathlib import Path
import re
import shlex
import stat
import subprocess
import sys
import time


USB_SOURCES = frozenset(('deviceNCM', 'hostMacNCM'))
INTERFACE = re.compile(r'en[0-9]{1,12}\Z')
USERNAME = re.compile(r'[A-Za-z_][A-Za-z0-9_.-]{0,63}\Z')

# Derived from test_direct_ethernet.COLLECTOR. Raw addresses, settings and pairing
# values are consumed inside the collector and emitted only as SHA-256 digests.
# Never use sudo to read the console user's protected home or login Keychain.
COLLECTOR = r'''
import copy,hashlib,json,os,plistlib,pwd,re,subprocess,sys,time
from pathlib import Path
role=sys.argv[1];requested=sys.argv[2]
def run(args,input=None,required=True):
    p=subprocess.run(args,input=input,text=True,capture_output=True,timeout=12)
    if required and p.returncode:raise RuntimeError("Read-only command failed: "+args[0])
    return p.stdout
def digest(value):
    return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(",",":"),default=str).encode()).hexdigest()
def sc(key):return run(["/usr/sbin/scutil"],input="show "+key+"\nquit\n")
preferences=plistlib.loads(Path("/Library/Preferences/SystemConfiguration/preferences.plist").read_bytes())
services={sid:{"deviceName":service.get("Interface",{}).get("DeviceName"),"configurationSHA256":digest(service)}
    for sid,service in preferences.get("NetworkServices",{}).items()}
sets={}
for sid,value in preferences.get("Sets",{}).items():
    global_settings=copy.deepcopy(value.get("Network",{}).get("Global",{}))
    order=global_settings.get("IPv4",{}).pop("ServiceOrder",[])
    sets[sid]={"serviceOrder":order,"otherGlobalSHA256":digest(global_settings)}
global_v4=sc("State:/Network/Global/IPv4")
match=re.search(r"(?m)^\s*PrimaryService\s*:\s*(\S+)",global_v4)
primary=match.group(1) if match else None
def route(family):
    text=run(["/sbin/route","-n","get","-"+family,"default"],required=False)
    return {m.group(1):(digest(m.group(2)) if m.group(1)=="gateway" else m.group(2))
        for m in re.finditer(r"(?m)^\s+(gateway|interface): (\S+)",text)}
console_stat=os.stat("/dev/console");console_uid=console_stat.st_uid
try:console=pwd.getpwuid(console_uid)
except KeyError:console=None
try:target=pwd.getpwnam(requested) if requested else pwd.getpwuid(os.getuid())
except KeyError:raise RuntimeError("The requested Viewer account does not exist")
def binding(user):
    if user is None:return {"available":False,"reason":"consoleAccountUnavailable","uid":console_uid}
    path=Path(user.pw_dir)/"Library/Preferences"/("local.retinalink."+role+".plist")
    try:
        value=plistlib.loads(path.read_bytes()).get("trustedDisplayBinding.v1")
        if value is None:return {"available":False,"reason":"bindingAbsent","uid":user.pw_uid}
        return {"available":True,"uid":user.pw_uid,"sha256":digest(value)}
    except PermissionError:return {"available":False,"reason":"protectedAccount","uid":user.pw_uid}
    except (OSError,ValueError,plistlib.InvalidFileException):return {"available":False,"reason":"bindingUnreadable","uid":user.pw_uid}
def app_state(user):
    if user is None:return {"available":False,"reason":"consoleAccountUnavailable"}
    path=Path(user.pw_dir)/"Library/Logs/RetinaLink"/(role+"-ui.json")
    try:
        value=json.loads(path.read_text())
        result={"available":True,"uid":user.pw_uid}
        for key in ("version","build","time","connected","streaming","phase","fullscreen","transport","requiresRemoteLogin"):
            if key in value and isinstance(value[key],(str,int,float,bool,type(None))):result[key]=value[key]
        source=value.get("connectionPath",{})
        allowed=("interface","interfaceIndex","transportKind","usbEvidence","wired","authenticated","requiredInterfaceVerified","networkSettingsChanged")
        result["connectionPath"]={key:source[key] for key in allowed if key in source and isinstance(source[key],(str,int,float,bool,type(None)))}
        return result
    except PermissionError:return {"available":False,"reason":"protectedAccount","uid":user.pw_uid}
    except (OSError,ValueError,TypeError):return {"available":False,"reason":"stateUnreadable","uid":user.pw_uid}
names=run(["/bin/ps","-axo","comm="])
commands=run(["/bin/ps","-axo","command="])
helper_off=not any(Path(name.strip()).name=="SkyComputerUseService" for name in names.splitlines())
display_ssh_absent=not any((line.lstrip().startswith("/usr/bin/ssh ") or line.lstrip().startswith("ssh ")) and
    "Application Support/RetinaLink/display-tunnel" in line for line in commands.splitlines())
active=console if role=="Viewer" else target
result={"capturedAt":time.time(),"services":services,"sets":sets,"currentSet":preferences.get("CurrentSet"),
    "persistentConfigurationSHA256":digest(preferences),"defaultRouteIPv4":route("inet"),"defaultRouteIPv6":route("inet6"),
    "primaryService":primary,"primaryServiceDNSSHA256":digest(sc("State:/Network/Service/"+primary+"/DNS") if primary else ""),
    "globalDNSSHA256":digest(sc("State:/Network/Global/DNS")),"fileVaultStatus":run(["/usr/bin/fdesetup","status"]).strip(),
    "uiCaptureHelperOff":helper_off,"appDisplaySSHAbsent":display_ssh_absent,"consoleUID":console_uid,
    "requestedBinding":binding(target),"activeBinding":binding(active),"appState":app_state(active)}
print(json.dumps(result,sort_keys=True))
'''


def require(condition, message):
    if not condition:
        raise ValueError(message)


def parse_usb_status(value):
    """Strictly accept the public read-only diagnostic; export no extra fields."""
    require(isinstance(value, dict) and type(value.get('schema')) is int and value['schema'] == 1,
            'USB diagnostic schema is unavailable')
    for key, expected in (('readOnly', True), ('networkSettingsChanged', False),
                          ('pairingAccessed', False), ('peerAuthenticated', False)):
        require(value.get(key) is expected, 'USB diagnostic does not guarantee ' + key)
    require(isinstance(value.get('interfaces'), list) and len(value['interfaces']) <= 128,
            'USB diagnostic interface list is invalid')
    result = {'schema': 1, 'readOnly': True, 'networkSettingsChanged': False,
              'pairingAccessed': False, 'peerAuthenticated': False, 'interfaces': []}
    for key in ('version', 'build'):
        require(isinstance(value.get(key), str) and 0 < len(value[key]) <= 64,
                'USB diagnostic does not identify its ' + key)
        result[key] = value[key]
    seen = set()
    for item in value['interfaces']:
        require(isinstance(item, dict), 'USB diagnostic entry is invalid')
        name, source = item.get('interface'), item.get('usbEvidence')
        require(isinstance(name, str) and INTERFACE.fullmatch(name) and name not in seen,
                'USB diagnostic interface is invalid or repeated')
        require(isinstance(source, str) and source in USB_SOURCES,
                'USB diagnostic has unrecognized evidence; an ordinary USB NIC is insufficient')
        seen.add(name)
        record = {'interface': name, 'usbEvidence': source}
        for key in ('interfaceUp', 'hasLinkLocalAddress', 'automaticAddressing'):
            require(type(item.get(key)) is bool, 'USB diagnostic is missing ' + key)
            record[key] = item[key]
        if 'linkActive' in item:
            require(type(item['linkActive']) is bool, 'USB link activity is invalid')
            record['linkActive'] = item['linkActive']
        if 'nominalLinkSpeed' in item:
            require(type(item['nominalLinkSpeed']) is int and 0 < item['nominalLinkSpeed'] < 2**64,
                    'USB link speed is invalid')
            record['nominalLinkSpeed'] = item['nominalLinkSpeed']
        result['interfaces'].append(record)
    return result


def identified_usb_interfaces(machine, *, active=False):
    records = parse_usb_status(machine['usbStatus'])['interfaces']
    return {item['interface'] for item in records
            if not active or (item.get('linkActive') is True and item['interfaceUp'])}


def pairing_check(before, current):
    if not before.get('available') or not current.get('available'):
        return None
    if any(type(item.get('uid')) is not int or not isinstance(item.get('sha256'), str)
           or re.fullmatch(r'[0-9a-f]{64}', item['sha256']) is None for item in (before, current)):
        return None
    return before.get('uid') == current.get('uid') and before.get('sha256') == current.get('sha256')


def usb_stream_check(machine, *, role, now):
    interfaces = identified_usb_interfaces(machine, active=True)
    if not interfaces:
        return False
    state = machine.get('appState', {})
    if not state.get('available'):
        return None
    stamp = state.get('time')
    if type(stamp) not in (int, float) or not 0 <= now - stamp < 15:
        return False
    path = state.get('connectionPath', {})
    streaming = state.get('streaming') is True if role == 'Host' else state.get('phase') == 'streaming'
    return bool(streaming and state.get('transport') == 'direct-tls'
                and state.get('requiresRemoteLogin') is False
                and path.get('transportKind') == 'usb' and path.get('usbEvidence') in USB_SOURCES
                and path.get('interface') in interfaces and path.get('authenticated') is True
                and path.get('networkSettingsChanged') is False
                and (role == 'Host' or (state.get('fullscreen') is True
                                       and path.get('requiredInterfaceVerified') is True)))


def compare_machine(before, current, *, require_usb=False, role='Viewer', now=None):
    """Allow only OS-created USB service additions, never edits to old services."""
    checks = {}
    old_services, services = before['services'], current['services']
    checks['existingServicesUnchanged'] = all(services.get(key) == value for key, value in old_services.items())
    additions = set(services) - set(old_services)
    usb_names = identified_usb_interfaces(current)
    checks['addedServicesAreIdentifiedUSB'] = all(services[key].get('deviceName') in usb_names for key in additions)
    old_sets, sets = before['sets'], current['sets']
    checks['networkSetsUnchanged'] = set(old_sets) == set(sets) and before['currentSet'] == current['currentSet']
    checks['companyServiceOrderUnchanged'] = all(
        key in sets and old.get('otherGlobalSHA256') == sets[key].get('otherGlobalSHA256')
        and old.get('serviceOrder') == [item for item in sets[key].get('serviceOrder', []) if item not in additions]
        for key, old in old_sets.items())
    for key in ('defaultRouteIPv4', 'defaultRouteIPv6', 'primaryService', 'primaryServiceDNSSHA256',
                'globalDNSSHA256', 'fileVaultStatus'):
        checks[key] = before.get(key) == current.get(key)
    checks['requestedAccountPairingUnchanged'] = pairing_check(before['requestedBinding'], current['requestedBinding'])
    checks['activeAccountPairingUnchanged'] = pairing_check(before['activeBinding'], current['activeBinding'])
    checks['uiCaptureHelperOff'] = before.get('uiCaptureHelperOff') is True and current.get('uiCaptureHelperOff') is True
    checks['appDisplaySSHAbsent'] = before.get('appDisplaySSHAbsent') is True and current.get('appDisplaySSHAbsent') is True
    if require_usb:
        checks['authenticatedUSBStream'] = usb_stream_check(current, role=role, now=now or time.time())
    return checks


def result_status(checks):
    if any(value is False for value in checks.values()):
        return 'failed'
    if any(value is None for value in checks.values()):
        return 'notVerified'
    return 'passed'


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    action = result.add_mutually_exclusive_group(required=True)
    action.add_argument('--snapshot', action='store_true')
    action.add_argument('--compare', type=Path, metavar='BASELINE')
    result.add_argument('--socket', type=Path, required=True, help='Existing authenticated SSH control socket')
    result.add_argument('--address', required=True)
    result.add_argument('--user', required=True, help='SSH account; no sudo is used')
    result.add_argument('--viewer-user', help='Viewer preference account; active console evidence is checked separately')
    result.add_argument('--host-binary', type=Path, required=True)
    result.add_argument('--viewer-binary', required=True, help='Absolute remote test binary with --usb-link-status')
    result.add_argument('--output', type=Path, required=True)
    result.add_argument('--require-usb', action='store_true', help='Require an active, authenticated USB display stream on both Macs')
    result.add_argument('--hardware-connected', action='store_true', help='Record an owner assertion; not proof of a USB link')
    return result


def run(command, *, input=None, timeout=30):
    value = subprocess.run([str(part) for part in command], input=input, text=True,
                           capture_output=True, timeout=timeout)
    if value.returncode:
        raise RuntimeError('Read-only preflight failed: ' + str(command[0]) + ' (exit ' + str(value.returncode) + ')')
    return value.stdout


def require_usb_cli(path):
    # Executing an unknown CLI option on an older RetinaLink binary would enter
    # its normal GUI. Refuse that binary before launch, rather than relying on a
    # timeout to stop an accidentally opened Viewer or Host.
    needle = b'--usb-link-status'
    with path.open('rb') as source:
        tail = b''
        while True:
            chunk = source.read(1024 * 1024)
            if not chunk:
                break
            if needle in tail + chunk:
                return
            tail = chunk[-len(needle):]
    raise ValueError('The supplied local binary does not implement --usb-link-status; no app was launched')


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + '.next')
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
    temporary.chmod(0o600)
    temporary.replace(path)


def snapshot(args):
    require(args.socket.exists() and stat.S_ISSOCK(args.socket.stat().st_mode), 'An existing SSH control socket is required')
    require(args.host_binary.is_file(), 'The local USB test binary does not exist')
    require(args.viewer_binary.startswith('/') and '\0' not in args.viewer_binary,
            'The remote USB test binary must be an absolute path')
    require(USERNAME.fullmatch(args.user) and (args.viewer_user is None or USERNAME.fullmatch(args.viewer_user)),
            'SSH and Viewer account names must be local macOS account names')
    require_usb_cli(args.host_binary)
    ssh = ['/usr/bin/ssh', '-S', str(args.socket.resolve()), '-o', 'BatchMode=yes',
           '-o', 'ConnectTimeout=5', '-l', args.user, args.address]
    run(ssh[:-1] + ['-O', 'check', args.address], timeout=10)
    # Strict short CLI checks happen before collecting any account evidence.
    remote_capability = shlex.join(['/usr/bin/grep', '-a', '-F', '-q', '--', '--usb-link-status', args.viewer_binary])
    run(ssh + [remote_capability], timeout=12)
    local_usb = parse_usb_status(json.loads(run([args.host_binary.resolve(), '--usb-link-status'], timeout=12)))
    remote_usb = parse_usb_status(json.loads(run(ssh + [shlex.join([args.viewer_binary, '--usb-link-status'])], timeout=15)))
    local = json.loads(run(['/usr/bin/python3', '-', 'Host', ''], input=COLLECTOR, timeout=55))
    remote_command = shlex.join(['/usr/bin/python3', '-', 'Viewer', args.viewer_user or ''])
    remote = json.loads(run(ssh + [remote_command], input=COLLECTOR, timeout=55))
    for name, machine, usb in (('studio', local, local_usb), ('imac', remote, remote_usb)):
        require(machine.get('uiCaptureHelperOff') is True, 'UI capture helper is running on ' + name + '; stopped without changing it')
        require(machine.get('appDisplaySSHAbsent') is True, 'An application SSH display tunnel is active on ' + name)
        machine['usbStatus'] = usb
    return {'schema': 1, 'capturedAt': time.time(), 'readOnly': True,
            'hardwareConnectedOwnerAssertion': args.hardware_connected,
            'unplugReplugTested': False, 'studio': local, 'imac': remote}


def main(argv=None):
    args = parser().parse_args(argv)
    require(not args.output.exists(), 'Choose a new output path to preserve existing evidence')
    current = snapshot(args)
    if args.snapshot:
        if args.require_usb:
            current['requirementChecks'] = {name + '.authenticatedUSBStream': usb_stream_check(
                current[name], role=role, now=current['capturedAt'])
                for name, role in (('studio', 'Host'), ('imac', 'Viewer'))}
            current['requirementStatus'] = result_status(current['requirementChecks'])
        write(args.output, current)
        print('Read-only baseline saved. Hardware connection is not established by the owner assertion.')
        unavailable = [name for name in ('studio', 'imac')
                       if not current[name]['activeBinding'].get('available')]
        if unavailable:
            print('Active-account pairing not verified: ' + ', '.join(unavailable))
        if args.require_usb:
            status = current['requirementStatus']
            print('Required authenticated USB stream: ' + status)
            return 0 if status == 'passed' else (2 if status == 'notVerified' else 1)
        return 0
    before = json.loads(args.compare.read_text())
    require(before.get('schema') == current['schema'] and before.get('readOnly') is True,
            'Baseline does not match this read-only collector')
    checks = {}
    for name, role in (('studio', 'Host'), ('imac', 'Viewer')):
        checks.update({name + '.' + key: value for key, value in compare_machine(
            before[name], current[name], require_usb=args.require_usb, role=role, now=current['capturedAt']).items()})
    status = result_status(checks)
    report = {'schema': 1, 'status': status, 'success': status == 'passed', 'checks': checks,
              'snapshot': current, 'readOnly': True, 'physicalUSBValidated': args.require_usb and status == 'passed',
              'unplugReplugTested': False}
    write(args.output, report)
    print('USB/network validation: ' + status)
    for value, label in ((False, 'Failed'), (None, 'Not verified')):
        names = [key for key, check in checks.items() if check is value]
        if names:
            print(label + ': ' + ', '.join(names))
    return 0 if status == 'passed' else (2 if status == 'notVerified' else 1)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print('USB preflight stopped: ' + str(error), file=sys.stderr)
        sys.exit(1)
