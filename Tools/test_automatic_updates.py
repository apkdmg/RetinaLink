#!/usr/bin/env python3
"""Native Sparkle/SSH integration: opt-out, bad signatures, installation and recovery."""
import argparse, hashlib, http.server, json, os, pathlib, signal, subprocess, threading, time, sys
import xml.etree.ElementTree as ET
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/"Tools"))
from sparkle import CONFIG, fetch
p=argparse.ArgumentParser();p.add_argument('--feed-directory',type=pathlib.Path,required=True);p.add_argument('--output',type=pathlib.Path,required=True);p.add_argument('--socket',type=pathlib.Path,required=True);p.add_argument('--address',required=True);p.add_argument('--user',required=True);p.add_argument('--from-build',required=True);p.add_argument('--to-build',required=True);p.add_argument('--port',type=int,default=58475);a=p.parse_args()
out=a.output.resolve();out.mkdir(parents=True,exist_ok=True); control=out/'control';control.mkdir(mode=0o700,exist_ok=True)
feed=a.feed_directory.resolve(); app=pathlib.Path.home()/'Applications/RetinaLink Host.app';hostlog=pathlib.Path.home()/'Library/Logs/RetinaLink/Host.json';base=f'http://127.0.0.1:{a.port}'; ssh=['/usr/bin/ssh','-S',str(a.socket.resolve()),'-o','BatchMode=yes','-o','ConnectTimeout=5','-l',a.user,a.address]
mode='empty';requests=[]
def run(args,**kw):return subprocess.run([str(x) for x in args],check=True,**kw)
def remote(command):return run(ssh+[command],capture_output=True,text=True,timeout=35).stdout
def load(path):return json.loads(pathlib.Path(path).read_text())
def viewer():return json.loads(remote('/bin/cat "$HOME/Library/Logs/RetinaLink/Viewer-ui.json"'))
def status(role):return load(pathlib.Path.home()/'Library/Logs/RetinaLink/Host-updates.json') if role=='Host' else json.loads(remote('/bin/cat "$HOME/Library/Logs/RetinaLink/Viewer-updates.json"'))
def wait(label,check,timeout=110):
 end=time.monotonic()+timeout
 while time.monotonic()<end:
  try:
   value=check()
   if value:print('PASS: '+label,flush=True);return value
  except (OSError,ValueError,KeyError,subprocess.SubprocessError):pass
  time.sleep(1)
 raise RuntimeError(label+' timed out')
def command(name,**values):
 temp=control/'next.json';temp.write_text(json.dumps(dict(command=name,**values)));temp.chmod(0o600);temp.replace(control/'command.json')
def both_phase(phase):return status('Host')['phase']==phase and status('Viewer')['phase']==phase
def helper_off():assert not any(pathlib.Path(x.strip()).name=='SkyComputerUseService' for x in run(['/bin/ps','-axo','comm='],capture_output=True,text=True).stdout.splitlines())
def snapshot():
 d=json.loads(remote('"$HOME/Applications/RetinaLink Viewer.app/Contents/MacOS/RetinaLink" --device-status'))
 d['authorizedKeysSHA256']=remote('/usr/bin/shasum -a 256 "$HOME/.ssh/authorized_keys"').split()[0]
 d['viewerBindingSHA256']=remote('/usr/bin/defaults read local.retinalink.Viewer trustedDisplayBinding.v1 | /usr/bin/shasum -a 256').split()[0]
 d['hostBindingSHA256']=hashlib.sha256(run(['/usr/bin/defaults','read','local.retinalink.Host','trustedDisplayBinding.v1'],capture_output=True).stdout).hexdigest()
 d['loginSettings']=remote('/usr/bin/fdesetup status; /usr/bin/defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null || true')
 return d
class Handler(http.server.BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_GET(self):
  relative=self.path.split('?',1)[0].lstrip('/'); path=(feed/relative).resolve()
  if not path.is_relative_to(feed) or not path.is_file():self.send_error(404);return
  selected=mode;requests.append({'path':relative,'mode':selected,'time':time.time()})
  if relative.endswith('appcast.xml') and selected=='empty':path=out/'empty'/relative
  data=path.read_bytes()
  if relative.endswith('appcast.xml') and selected=='bad-feed':data=data.replace(b'<title>',b'<title>unsigned change ',1)
  if relative.endswith('.zip') and selected=='bad-archive':
   payload=bytearray(data);payload[len(payload)//2]^=1;data=bytes(payload)
  self.send_response(200);self.send_header('Content-Length',str(len(data)));self.send_header('Content-Type','application/xml' if relative.endswith('.xml') else 'application/octet-stream');self.send_header('Cache-Control','no-store');self.end_headers()
  try:self.wfile.write(data)
  except (BrokenPipeError,ConnectionResetError):pass

# Sign empty feeds with the real update key; never export its private bytes.
sparkle=fetch()
for role in ['host','viewer']:
 empty=out/'empty'/role;empty.mkdir(parents=True,exist_ok=True)
 tree=ET.parse(feed/role/'appcast.xml'); channel=tree.getroot().find('channel')
 for item in list(channel.findall('item')):channel.remove(item)
 target=empty/'appcast.xml';tree.write(target,encoding='utf-8',xml_declaration=True)
 run([sparkle/'bin/sign_update','--account',CONFIG['keychainAccount'],target])
helper_off(); before=snapshot();assert before['build']==a.from_build and viewer()['phase']=='streaming';(out/'before.json').write_text(json.dumps(before,indent=2)+'\n')
server=http.server.ThreadingHTTPServer(('127.0.0.1',a.port),Handler);threading.Thread(target=server.serve_forever,daemon=True).start()
forwarded=False;success=False
try:
 run(['/usr/bin/ssh','-S',str(a.socket.resolve()),'-O','forward','-R',f'127.0.0.1:{a.port}:127.0.0.1:{a.port}','-o','BatchMode=yes','-l',a.user,a.address]);forwarded=True
 # Use the real app, with a local command seam instead of UI/screen capture.
 old=load(hostlog)['pid'];cmd=run(['/bin/ps','-p',str(old),'-o','command='],capture_output=True,text=True).stdout.strip();assert cmd.startswith(str(app/'Contents/MacOS/RetinaLink'))
 subprocess.run(['/bin/launchctl','bootout','gui/'+str(os.getuid())+'/local.retinalink.host.startup'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 if subprocess.run(['/bin/ps','-p',str(old)],stdout=subprocess.DEVNULL).returncode==0:
  try:os.kill(old,signal.SIGTERM)
  except ProcessLookupError:pass
 wait('baseline Host exits',lambda:subprocess.run(['/bin/ps','-p',str(old)],stdout=subprocess.DEVNULL).returncode!=0,20)
 run(['/usr/bin/open','-n',app,'--args','--autostart','--test-control-directory',control,'--test-update-base-url',base,'--export-ui',out/'host-updates-ui.png'])
 wait('baseline test Host streams',lambda:load(hostlog)['pid']!=old and load(hostlog)['build']==a.from_build and viewer()['phase']=='streaming')
 command('updates-automatic',enabled='false');wait('automatic update opt-out reaches Viewer',lambda:not status('Host')['automatic'] and not status('Viewer')['automatic'])
 command('updates-test-feed',url=base);wait('both roles configured with local signed feeds',lambda:status('Host')['configured'] and status('Viewer')['configured'])
 mode='valid';command('updates-check');wait('disabled automatic installation only reports availability',lambda:both_phase('available'))
 time.sleep(2);assert viewer()['build']==a.from_build and load(hostlog)['build']==a.from_build
 assert not any(r['path'].endswith('.zip') for r in requests),'Opt-out still downloaded an installer'
 print('PASS: opt-out leaves both installed apps unchanged',flush=True)
 mode='bad-feed';command('updates-automatic',enabled='true');wait('automatic updates enabled on both roles',lambda:status('Host')['automatic'] and status('Viewer')['automatic']);command('updates-check');wait('both apps reject tampered signed feed',lambda:both_phase('error') and all(any(r['mode']=='bad-feed' and r['path']==role+'/appcast.xml' for r in requests) for role in ['host','viewer']))
 assert viewer()['build']==a.from_build and viewer()['phase']=='streaming';(out/'bad-feed.json').write_text(json.dumps({r:status(r) for r in ['Host','Viewer']},indent=2))
 mode='bad-archive';command('updates-check');wait('both apps reject archive bytes with invalid EdDSA signatures',lambda:both_phase('error') and all(any(r['mode']=='bad-archive' and r['path'].startswith(role+'/') and r['path'].endswith('.zip') for r in requests) for role in ['host','viewer']))
 assert any(r['mode']=='bad-archive' and r['path'].endswith('.zip') for r in requests)
 assert viewer()['build']==a.from_build and load(hostlog)['build']==a.from_build and viewer()['phase']=='streaming';(out/'bad-archive.json').write_text(json.dumps({r:status(r) for r in ['Host','Viewer']},indent=2))
 mode='valid';command('updates-check')
 wait('automatic Host and Viewer download, verify, install and relaunch',lambda:load(hostlog)['build']==a.to_build and viewer()['build']==a.to_build and viewer()['phase']=='streaming' and viewer()['fullscreen'],260)
 after=snapshot();(out/'after.json').write_text(json.dumps(after,indent=2)+'\n')
 for key in ['hostID','namespace','team','startupAtLogin','authorizedKeysSHA256','viewerBindingSHA256','hostBindingSHA256','loginSettings']:assert before[key]==after[key],key+' changed'
 print('PASS: automatic update preserves binding, public SSH keys, startup and login settings',flush=True)
 # Relaunch must return to launchd so future crashes still recover unattended.
 current=load(hostlog)['pid'];agent=run(['/bin/launchctl','print','gui/'+str(os.getuid())+'/local.retinalink.host.startup'],capture_output=True,text=True).stdout;assert f'pid = {current}' in agent
 os.kill(current,signal.SIGKILL)
 wait('updated Host crash recovers through its startup agent',lambda:load(hostlog)['pid']!=current and viewer()['phase']=='streaming')
 old_viewer=viewer()['pid'];remote('command=$(/bin/ps -p '+str(old_viewer)+' -o command=); case "$command" in "$HOME/Applications/RetinaLink Viewer.app/Contents/MacOS/RetinaLink"*) /bin/kill -KILL '+str(old_viewer)+' ;; *) exit 4 ;; esac')
 wait('updated Viewer crash recovers fullscreen',lambda:viewer()['pid']!=old_viewer and viewer()['phase']=='streaming' and viewer()['fullscreen'])
 assert snapshot()==after;helper_off();success=True
finally:
 # No test feed/tunnel/server survives the test. Public hosting stays unconfigured.
 subprocess.run(['/usr/bin/defaults','delete','local.retinalink.Host','RetinaLink.localUpdateTestBaseURL'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 remote('/usr/bin/defaults delete local.retinalink.Viewer RetinaLink.localUpdateTestBaseURL 2>/dev/null || true')
 if forwarded:subprocess.run(['/usr/bin/ssh','-S',str(a.socket.resolve()),'-O','cancel','-R',f'127.0.0.1:{a.port}:127.0.0.1:{a.port}','-o','BatchMode=yes','-l',a.user,a.address],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 server.shutdown();server.server_close();(out/'requests.json').write_text(json.dumps(requests,indent=2)+'\n')
if success:
 run(['/bin/launchctl','kickstart','-k','gui/'+str(os.getuid())+'/local.retinalink.host.startup'])
 remote('/bin/launchctl kickstart -k "gui/$(/usr/bin/id -u)/local.retinalink.viewer.startup"')
 wait('production startup restores fullscreen streaming with no test feed',lambda:viewer()['phase']=='streaming' and viewer()['fullscreen'] and status('Host')['phase']=='not-configured' and status('Viewer')['phase']=='not-configured')
 helper_off();assert snapshot()==after
 (out/'result.json').write_text(json.dumps({'success':True,'fromBuild':a.from_build,'toBuild':a.to_build,'automaticUpdatesInstalledBoth':True,'optOutRespected':True,'badFeedRejectedBoth':True,'badArchiveRejectedBoth':True,'pairingPreserved':True,'sshPublicKeysUnchanged':True,'startupRecoveryBoth':True,'fileVaultAndLoginUnchanged':True,'uiCaptureHelperOff':True,'localTestFeedRemoved':True,'publicHostingConfigured':False},indent=2)+'\n')
 print('PASS: automatic update integration complete; local test feeds removed',flush=True)
