#!/usr/bin/env python3
"""Upgrade installed apps through signed local feeds, test retained direct trust.

The existing SSH socket is for test management and a loopback update-feed forward,
never for display streaming. No encryption, login or sharing settings change.
"""
import argparse
import functools
import hashlib
import http.server
import json
import os
from pathlib import Path
import shlex
import signal
import subprocess
import threading
import time

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--feed',type=Path,required=True);p.add_argument('--socket',type=Path,required=True)
p.add_argument('--address',required=True);p.add_argument('--user',required=True)
p.add_argument('--output',type=Path,required=True);p.add_argument('--build',default='55')
p.add_argument('--restart-baseline-viewer',action='store_true',help='Relaunch the older Viewer once before upgrading; recovery after the update is still tested without intervention')
a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
control=a.output/'control';control.mkdir(mode=0o700)
app=Path.home()/'Applications/RetinaLink Host.app'
log=Path.home()/'Library/Logs/RetinaLink/Host.json'
ssh=['/usr/bin/ssh','-S',str(a.socket.resolve()),'-o','BatchMode=yes','-o','ConnectTimeout=5','-l',a.user,a.address]
port=58475;base='http://127.0.0.1:'+str(port)
def run(args,**kw):return subprocess.run([str(x) for x in args],check=True,**kw)
def remote(command):return run(ssh+[command],capture_output=True,text=True,timeout=40).stdout
def viewer():return json.loads(remote('cat "$HOME/Library/Logs/RetinaLink/Viewer-ui.json"'))
def host():return json.loads(log.read_text())
def wait(label,check,timeout=90):
 end=time.monotonic()+timeout
 while time.monotonic()<end:
  try:
   value=check()
   if value:print('PASS: '+label,flush=True);return value
  except (OSError,ValueError,KeyError,subprocess.SubprocessError):pass
  time.sleep(1)
 raise RuntimeError(label+' timed out')
def command(name,**values):
 temp=control/'command.next';temp.write_text(json.dumps(dict(command=name,**values)));temp.replace(control/'command.json')
def helper_off():
 names=run(['/bin/ps','-axo','comm='],capture_output=True,text=True).stdout.splitlines()
 assert not any(Path(x.strip()).name=='SkyComputerUseService' for x in names)
def snapshot():
 binding=run(['/usr/bin/defaults','read','local.retinalink.Host','trustedDisplayBinding.v1'],capture_output=True).stdout
 return {'hostBindingSHA256':hashlib.sha256(binding).hexdigest(),
  'viewerMetadata':remote('/usr/bin/defaults read local.retinalink.Viewer trustedDisplayBinding.v1 | /usr/bin/shasum -a 256; /usr/bin/shasum -a 256 "$HOME/.ssh/authorized_keys"; /usr/bin/fdesetup status; /usr/bin/defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null || true; /usr/bin/pmset -g custom'),
  'viewerStartup':viewer()['startupInstalled']}
def display_ssh_absent():
 output=run(['/bin/ps','-axo','command='],capture_output=True,text=True).stdout
 return not any(x.startswith('/usr/bin/ssh ') and 'Application Support/RetinaLink/display-tunnel' in x for x in output.splitlines())
def is_native():
 value=viewer();hd=host()
 capture_active=any(x['kind']=='host' for x in hd.get('samples',[]))
 return value if capture_active and value['build']==a.build and value['phase']=='streaming' and value['fullscreen'] and value.get('transport')=='direct-tls' and value.get('requiresRemoteLogin') is False and hd['build']==a.build and display_ssh_absent() else None
helper_off();before=snapshot();(a.output/'before.json').write_text(json.dumps(before,indent=2)+'\n')
class Handler(http.server.SimpleHTTPRequestHandler):
 def log_message(self,*args):pass
server=http.server.ThreadingHTTPServer(('127.0.0.1',port),functools.partial(Handler,directory=str(a.feed.resolve())))
threading.Thread(target=server.serve_forever,daemon=True).start()
forwarded=False
try:
 run(['/usr/bin/ssh','-S',str(a.socket.resolve()),'-O','forward','-R',f'127.0.0.1:{port}:127.0.0.1:{port}','-l',a.user,a.address]);forwarded=True
 old=int(host()['pid']);name=run(['/bin/ps','-p',old,'-o','command='],capture_output=True,text=True).stdout.strip()
 assert name.startswith(str(app/'Contents/MacOS/RetinaLink'))
 subprocess.run(['/bin/launchctl','bootout','gui/'+str(os.getuid())+'/local.retinalink.host.startup'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 if subprocess.run(['/bin/ps','-p',str(old)],stdout=subprocess.DEVNULL).returncode==0:
  try:os.kill(old,signal.SIGTERM)
  except ProcessLookupError:pass
 wait('old Host exits',lambda:subprocess.run(['/bin/ps','-p',str(old)],stdout=subprocess.DEVNULL).returncode!=0,20)
 baseline_time=time.time()
 host_ui=control/'host-state.json'
 run(['/usr/bin/open','-n',app,'--args','--autostart','--test-control-directory',control.resolve(),'--test-update-base-url',base,'--ui-state-path',host_ui.resolve()])
 def baseline_connected():
  hs=json.loads(host_ui.read_text());vs=viewer()
  return hs['pid']!=old and hs['streaming'] and hs['time']>=baseline_time and vs['phase']=='streaming' and vs['time']>=baseline_time
 if a.restart_baseline_viewer:
  previous=viewer()['pid']
  remote('command=$(/bin/ps -p '+str(previous)+' -o command=); case "$command" in "$HOME/Applications/RetinaLink Viewer.app/Contents/MacOS/RetinaLink"*) /bin/kill -TERM '+str(previous)+' ;; *) exit 4 ;; esac')
  time.sleep(1);remote('/usr/bin/open "$HOME/Applications/RetinaLink Viewer.app" --args --appliance')
 wait('baseline Viewer completes fresh authenticated handshake',baseline_connected)
 command('updates-test-feed',url=base)
 wait('Viewer configured with local signed feed',lambda:(u if (u:=json.loads(remote('cat "$HOME/Library/Logs/RetinaLink/Viewer-updates.json"')))['configured'] and u['message']=='Update service is ready.' else None))
 command('updates-install')
 migrated=wait('both updated apps stream directly without an app SSH tunnel',is_native,260)
 (a.output/'migrated-viewer.json').write_text(json.dumps(migrated,indent=2)+'\n')
 after=snapshot();assert before==after,'Pairing, public SSH keys, FileVault, login or power/startup policy changed'
 (a.output/'after.json').write_text(json.dumps(after,indent=2)+'\n')
 # The real Host login agent has ordinary arguments, never a test grant/helper.
 agent=Path.home()/'Library/LaunchAgents/local.retinalink.host.startup.plist'
 import plistlib
 assert plistlib.loads(agent.read_bytes())['ProgramArguments']==[str(app/'Contents/MacOS/RetinaLink'),'--autostart']
 previous=host()['pid'];recovery_start=time.monotonic()
 run(['/bin/launchctl','kickstart','-k','gui/'+str(os.getuid())+'/local.retinalink.host.startup'])
 wait('normal Host agent restart reconnects directly',lambda:host()['pid']!=previous and is_native())
 recovery_seconds=time.monotonic()-recovery_start
 # Existing original-account Viewer startup is intentionally disabled by the
 # dedicated-account setup. Test relaunch without altering that preference.
 previous=viewer()['pid']
 remote('command=$(/bin/ps -p '+str(previous)+' -o command=); case "$command" in "$HOME/Applications/RetinaLink Viewer.app/Contents/MacOS/RetinaLink"*) /bin/kill -TERM '+str(previous)+' ;; *) exit 4 ;; esac')
 time.sleep(2)
 remote('/usr/bin/open "$HOME/Applications/RetinaLink Viewer.app" --args --appliance')
 recovered=wait('Viewer relaunch retains pairing and direct fullscreen reconnection',lambda:(v if (v:=is_native()) and v['pid']!=previous else None))
 assert snapshot()==after;helper_off()
 (a.output/'result.json').write_text(json.dumps({'success':True,'baselineViewerRelaunched':a.restart_baseline_viewer,'hostRecoverySeconds':round(recovery_seconds,2),'retainedPairing':True,'fileVaultUnchanged':True,'appDisplaySSHAbsent':True,'viewer':recovered,'hostAgentRecovery':True,'viewerRelaunchRecovery':True,'viewerStartupPreferenceUnchanged':True,'uiCaptureHelperOff':True,'systemRemoteLoginDisabledDuringTest':False},indent=2)+'\n')
finally:
 subprocess.run(['/usr/bin/defaults','delete','local.retinalink.Host','RetinaLink.localUpdateTestBaseURL'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 remote('/usr/bin/defaults delete local.retinalink.Viewer RetinaLink.localUpdateTestBaseURL 2>/dev/null || true')
 if forwarded:subprocess.run(['/usr/bin/ssh','-S',str(a.socket.resolve()),'-O','cancel','-R',f'127.0.0.1:{port}:127.0.0.1:{port}','-l',a.user,a.address],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 server.shutdown()
 # A failed check must not leave the production Host in test mode or its
 # existing startup agent unloaded. Stop only this run's explicit test process.
 try:
  pid=host()['pid'];args=run(['/bin/ps','-p',pid,'-o','command='],capture_output=True,text=True).stdout
  if str(control.resolve()) in args and args.startswith(str(app/'Contents/MacOS/RetinaLink')): os.kill(pid,signal.SIGTERM)
 except (OSError,ValueError,KeyError,subprocess.SubprocessError):pass
 agent=Path.home()/'Library/LaunchAgents/local.retinalink.host.startup.plist'
 subprocess.run(['/bin/launchctl','bootstrap','gui/'+str(os.getuid()),str(agent)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 subprocess.run(['/bin/launchctl','kickstart','gui/'+str(os.getuid())+'/local.retinalink.host.startup'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
print('PASS: native installed update, direct streaming, retained trust, normal Host recovery and Viewer relaunch; FileVault unchanged')
