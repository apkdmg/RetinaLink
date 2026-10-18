#!/usr/bin/env python3
"""Read-only SSH validation for automatic Ethernet transport.

This never configures an interface or starts/stops an app. A link-local socket
over the existing company LAN validates scoped transport, not a physical direct
cable. Keep that distinction when recording results without the USB hub.
"""

import argparse
import json
from pathlib import Path
import shlex
import subprocess
import sys
import time


# The same collector runs locally and over the already authenticated SSH master.
# Addresses and process command lines are used internally only. In particular,
# IPv6 link-local addresses can encode a hardware address and are never exported.
COLLECTOR = r'''
import hashlib,ipaddress,json,os,plistlib,re,socket,subprocess
from pathlib import Path

def run(args,input=None,required=True):
    p=subprocess.run(args,input=input,text=True,capture_output=True,timeout=20)
    if required and p.returncode:
        raise RuntimeError("Read-only command failed: "+args[0])
    return p.stdout

def digest(value):
    return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(",",":"),default=str).encode()).hexdigest()

def sc(key):
    return run(["/usr/sbin/scutil"],input="show "+key+"\nquit\n")

preferences=plistlib.loads(Path("/Library/Preferences/SystemConfiguration/preferences.plist").read_bytes())
services=[]
for sid,service in sorted(preferences.get("NetworkServices",{}).items()):
    interface=service.get("Interface",{})
    policy={k:service[k] for k in ("IPv4","IPv6","DNS","Proxies","SMB","__INACTIVE__") if k in service}
    services.append({"id":sid,"name":service.get("UserDefinedName"),
        "interface":{k:interface[k] for k in ("DeviceName","Hardware","Type","SubType","SCNetworkInterfaceType") if k in interface},
        "configurationSHA256":digest(policy),
        "ipv4Method":service.get("IPv4",{}).get("ConfigMethod"),
        "ipv6Method":service.get("IPv6",{}).get("ConfigMethod")})
sets={sid:value.get("Network",{}).get("Global",{}) for sid,value in preferences.get("Sets",{}).items()}
policy={"services":services,"sets":sets,"currentSet":preferences.get("CurrentSet")}
global_v4=sc("State:/Network/Global/IPv4")
match=re.search(r"(?m)^\s*PrimaryService\s*:\s*(\S+)",global_v4)
primary_service=match.group(1) if match else None
primary_dns=sc("State:/Network/Service/"+primary_service+"/DNS") if primary_service else ""
route_text=run(["/sbin/route","-n","get","default"],required=False)
route={m.group(1):m.group(2) for m in re.finditer(r"(?m)^\s+(gateway|interface): (\S+)",route_text)}

interfaces=[]
address_interfaces={}
for block in re.split(r"(?m)(?=^\w[^ ]*: flags=)",run(["/sbin/ifconfig","-a"])):
    if ": flags=" not in block:continue
    name=block.split(":",1)[0]
    ipv4=re.findall(r"(?m)^\s+inet (\S+) netmask (\S+)",block)
    ipv6=re.findall(r"(?m)^\s+inet6 (\S+)",block)
    for address in [a for a,_ in ipv4]+ipv6:
        try:address_interfaces[str(ipaddress.ip_address(address.split("%",1)[0]))]=name
        except ValueError:pass
    media=re.search(r"(?m)^\s+media: (.*)",block)
    status=re.search(r"(?m)^\s+status: (.*)",block)
    try:index=socket.if_nametoindex(name)
    except OSError:index=None
    interfaces.append({"name":name,"index":index,"ipv4Count":len(ipv4),
        "hasIPv4LinkLocal":any(a.startswith("169.254.") for a,_ in ipv4),
        "hasIPv6LinkLocal":any(a.startswith("fe80:") for a in ipv6),
        "media":media.group(1) if media else None,"status":status.group(1) if status else None})

def endpoint(text):
    match=re.match(r"^\[([^\]]+)\]:(\d+)$",text) or re.match(r"^(.+):(\d+)$",text)
    if not match:return {"recognized":False}
    raw,port=match.groups();parts=raw.split("%",1);zone=parts[1] if len(parts)>1 else None
    try:address=ipaddress.ip_address(parts[0])
    except ValueError:return {"recognized":False}
    interface=zone or address_interfaces.get(str(address))
    if address.version==6 and address.is_link_local and not interface:
        # Darwin lsof can embed the scope in the second 16-bit word.
        words=list(address.packed);scope=(words[2]<<8)|words[3]
        if scope:
            try:interface=socket.if_indextoname(scope)
            except OSError:pass
            words[2:4]=[0,0]
            interface=interface or address_interfaces.get(str(ipaddress.IPv6Address(bytes(words))))
    return {"recognized":True,"family":"IPv"+str(address.version),"linkLocal":address.is_link_local,
        "loopback":address.is_loopback,"interface":interface,"port":int(port)}

connections=[]
for line in run(["/usr/sbin/lsof","-nP","-iTCP:58473","-sTCP:ESTABLISHED","-F","n"],required=False).splitlines():
    if not line.startswith("n") or "->" not in line:continue
    local,remote=line[1:].split("->",1)
    connections.append({"local":endpoint(local),"remote":endpoint(remote)})
if not connections:
    # Newer macOS can hide another application's descriptors from lsof even
    # within the same login. The system TCP table is still a read-only source.
    for line in run(["/usr/sbin/netstat","-anvl","-p","tcp"],required=False).splitlines():
        fields=line.split()
        if len(fields)<6 or fields[5]!="ESTABLISHED":continue
        pairs=[]
        for raw in fields[3:5]:
            address,separator,port=raw.rpartition(".")
            if not separator or not port.isdigit():break
            pairs.append(endpoint(("["+address+"]" if ":" in address else address)+":"+port))
        if len(pairs)==2 and any(v.get("port")==58473 for v in pairs):
            connections.append({"local":pairs[0],"remote":pairs[1]})
commands=run(["/bin/ps","-axo","command="])
names=run(["/bin/ps","-axo","comm="])
helper_off=not any(Path(name.strip()).name=="SkyComputerUseService" for name in names.splitlines())
display_ssh_absent=not any((line.lstrip().startswith("/usr/bin/ssh ") or line.lstrip().startswith("ssh ")) and
    "Application Support/RetinaLink/display-tunnel" in line for line in commands.splitlines())
role="Host" if (Path.home()/"Applications/RetinaLink Host.app").exists() else "Viewer"
binding=run(["/usr/bin/defaults","read","local.retinalink."+role,"trustedDisplayBinding.v1"],required=False)
if not binding.strip():raise RuntimeError("Expected existing production pairing binding is unavailable")
info_path=Path.home()/("Applications/RetinaLink "+role+".app/Contents/Info.plist")
info=plistlib.loads(info_path.read_bytes())
app={"role":role,"version":info.get("CFBundleShortVersionString"),"build":info.get("CFBundleVersion")}
ui_path=Path.home()/"Library/Logs/RetinaLink/Viewer-ui.json"
if role=="Viewer" and ui_path.exists():
    value=json.loads(ui_path.read_text())
    app.update({key:value[key] for key in ("phase","fullscreen","transport","requiresRemoteLogin","startupInstalled") if key in value})
print(json.dumps({"persistentConfigurationSHA256":digest(policy),"services":services,"serviceOrderSHA256":digest(sets),
    "defaultRoute":route,"primaryService":primary_service,"primaryServiceDNSSHA256":digest(primary_dns),
    "globalDNSSHA256":digest(sc("State:/Network/Global/DNS")),"interfaces":interfaces,
    "bindingSHA256":digest(binding),"fileVaultStatus":run(["/usr/bin/fdesetup","status"]).strip(),
    "uiCaptureHelperOff":helper_off,"appDisplaySSHAbsent":display_ssh_absent,"connections":connections,"app":app},sort_keys=True))
'''


def run(args, **kwargs):
    return subprocess.run([str(value) for value in args], check=True, text=True,
                          capture_output=True, timeout=65, **kwargs)


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument('action', choices=('snapshot', 'check'))
    result.add_argument('--socket', type=Path, required=True, help='Existing authenticated SSH control socket')
    result.add_argument('--address', required=True)
    result.add_argument('--user', required=True)
    result.add_argument('--output', type=Path, required=True)
    result.add_argument('--baseline', type=Path, help='A snapshot made by this tool; required for check')
    result.add_argument('--host-diagnostics', type=Path, help='Optional local direct-link JSON report')
    result.add_argument('--viewer-diagnostics', help='Optional absolute path of remote direct-link JSON report')
    result.add_argument('--probe-result', type=Path, help='JSON produced by the signed Viewer --direct-link-probe')
    result.add_argument('--require-link-local', action='store_true', help='Require an established scoped local-link display socket on both Macs')
    result.add_argument('--expected-interface', help='Expected local wired interface; remote scopes can have different names')
    result.add_argument('--physical-direct-cable', action='store_true', help='Record an owner-confirmed isolated physical cable test, rather than the existing LAN')
    return result


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    # Evidence may be replaced explicitly but never leave a partial JSON report.
    temporary = path.with_name(path.name + '.next')
    temporary.write_text(json.dumps(data, indent=2, sort_keys=True) + '\n')
    temporary.replace(path)


def snapshot(args, ssh):
    run(['/usr/bin/ssh', '-S', args.socket.resolve(), '-O', 'check', '-o', 'BatchMode=yes',
         '-o', 'ConnectTimeout=5', '-l', args.user, args.address])
    local = json.loads(run(['/usr/bin/python3', '-'], input=COLLECTOR).stdout)
    remote = json.loads(run(ssh + ['/usr/bin/python3 -'], input=COLLECTOR).stdout)
    for name, value in [('studio', local), ('imac', remote)]:
        if not value['uiCaptureHelperOff']:
            raise RuntimeError('UI capture helper is running on ' + name + '; test stopped without changing it')
        if not value['appDisplaySSHAbsent']:
            raise RuntimeError('An application-owned SSH display tunnel exists on ' + name)
    return {'schema': 1, 'capturedAt': time.time(), 'readOnly': True, 'studio': local, 'imac': remote}


def link_local_connection(value):
    return any(connection['local'].get('linkLocal') and connection['remote'].get('linkLocal')
               and connection['local'].get('interface') for connection in value['connections'])


def safe_diagnostics(value):
    """Export only transport classifications, never raw addresses or pairing data."""
    allowed = ('state', 'kind', 'transport', 'interface', 'interfaceName', 'interfaceType',
               'family', 'linkLocal', 'wired', 'isWired', 'requiresRemoteLogin',
               'authenticated', 'ready', 'success', 'networkConfigurationChanged',
               'identityMatched', 'requiredInterfaceVerified', 'selectedInterface',
               'localLinkLocal', 'remoteLinkLocal', 'addressFamily')
    if not isinstance(value, dict):
        raise ValueError('Direct-link diagnostics must be a JSON object')
    source = value.get('connectionPath', value.get('directLink', value))
    if not isinstance(source, dict):
        raise ValueError('directLink must be a JSON object')
    return {key: source[key] for key in allowed if key in source and isinstance(source[key], (str, int, float, bool, type(None)))}


def main():
    args = parser().parse_args()
    if args.action == 'check' and args.baseline is None:
        raise ValueError('--baseline is required for check')
    if args.output.exists():
        raise ValueError('Choose a new --output path so existing evidence is preserved')
    ssh = ['/usr/bin/ssh', '-S', str(args.socket.resolve()), '-o', 'BatchMode=yes',
           '-o', 'ConnectTimeout=5', '-l', args.user, args.address]
    current = snapshot(args, ssh)
    if args.action == 'snapshot':
        write(args.output, current)
        print('PASS: read-only baseline saved; UI capture helpers off; no application SSH display tunnel')
        return
    before = json.loads(args.baseline.read_text())
    if before.get('schema') != current['schema']:
        raise ValueError('Baseline schema does not match this collector')
    checks = {}
    for machine in ('studio', 'imac'):
        for key in ('persistentConfigurationSHA256', 'serviceOrderSHA256', 'defaultRoute',
                    'primaryService', 'primaryServiceDNSSHA256', 'globalDNSSHA256', 'bindingSHA256', 'fileVaultStatus'):
            checks[machine + '.' + key] = before[machine][key] == current[machine][key]
        checks[machine + '.uiCaptureHelperOff'] = current[machine]['uiCaptureHelperOff']
        checks[machine + '.appDisplaySSHAbsent'] = current[machine]['appDisplaySSHAbsent']
        if args.require_link_local:
            checks[machine + '.scopedLinkLocalDisplaySocket'] = link_local_connection(current[machine])
    if args.expected_interface:
        checks['studio.expectedInterface'] = any(c['local'].get('interface') == args.expected_interface
                                                   for c in current['studio']['connections'])
    diagnostics = {}
    if args.host_diagnostics:
        diagnostics['host'] = safe_diagnostics(json.loads(args.host_diagnostics.read_text()))
    if args.viewer_diagnostics:
        if not args.viewer_diagnostics.startswith('/') or '\x00' in args.viewer_diagnostics:
            raise ValueError('--viewer-diagnostics must be an absolute remote path')
        diagnostics['viewer'] = safe_diagnostics(json.loads(run(ssh + ['cat ' + shlex.quote(args.viewer_diagnostics)]).stdout))
    if args.probe_result:
        probe = json.loads(args.probe_result.read_text())
        if not isinstance(probe, dict):
            raise ValueError('Probe result must be a JSON object')
        for key in ('success', 'identityMatched', 'requiredInterfaceVerified'):
            checks['probe.' + key] = probe.get(key) is True
        if args.expected_interface:
            checks['probe.selectedInterface'] = probe.get('selectedInterface') == args.expected_interface
        diagnostics['probe'] = safe_diagnostics(probe)
        for key in ('connectionPath', 'path'):
            if isinstance(probe.get(key), dict):
                diagnostics['probePath'] = safe_diagnostics(probe[key])
    result = {'schema': 1, 'success': all(checks.values()), 'checks': checks, 'snapshot': current,
              'diagnostics': diagnostics, 'readOnly': True, 'physicalDirectCableConfirmed': args.physical_direct_cable,
              'physicalDirectCableBypassProven': False,
              'validationScope': 'Owner-confirmed physical cable; review endpoint interface evidence' if args.physical_direct_cable else
                  'Existing network only; link-local operation does not establish physical direct-cable bypass'}
    write(args.output, result)
    failed = [key for key, value in checks.items() if not value]
    if failed:
        raise RuntimeError('Read-only validation failed: ' + ', '.join(failed))
    print('PASS: company network configuration, routes, DNS, pairing binding and FileVault unchanged; UI capture helpers off')
    if args.require_link_local:
        print('PASS: both Macs have a scoped link-local display socket; this does not prove a dedicated physical cable')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print('FAIL: ' + str(error), file=sys.stderr)
        sys.exit(1)
