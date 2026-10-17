#!/usr/bin/env python3
"""Exercise actual Host setup and iMac launchd recovery without a UI capture bridge.

Needs a previously authorized SSH ControlMaster. Never reboots, changes FileVault,
automatic login, lock policy, or system sharing settings. Kills only verified
RetinaLink test processes and the app-owned display tunnel.
"""
import argparse,json,os,pathlib,plistlib,re,shutil,signal,subprocess,time
p=argparse.ArgumentParser();p.add_argument('--host-app',type=pathlib.Path,required=True);p.add_argument('--address',required=True);p.add_argument('--user',required=True);p.add_argument('--socket',type=pathlib.Path,required=True);p.add_argument('--workspace',type=pathlib.Path,required=True);p.add_argument('--dedicated-display',action='store_true');a=p.parse_args()
if a.dedicated_display:
 p.error('Dedicated mode now configures privileged account/login policy. Use Host’s guided setup and Tools/test_dedicated_display.py; this harness tests ordinary after-sign-in setup only.')
root=a.workspace.resolve();out=root/'work/setup-030';out.mkdir(mode=0o700,parents=True,exist_ok=True);control=out/'control';control.mkdir(mode=0o700,exist_ok=True)
ssh=['/usr/bin/ssh','-S',str(a.socket.resolve()),'-o','BatchMode=yes','-o','ConnectTimeout=5','-l',a.user,a.address]
def remote(cmd):return subprocess.check_output(ssh+[cmd],text=True,stderr=subprocess.PIPE,timeout=30)
def wait_for(label,check,timeout=65):
 end=time.monotonic()+timeout;last=None
 while time.monotonic()<end:
  try:
   last=check()
   if last:print('PASS:',label,flush=True);return last
  except (OSError,ValueError,subprocess.SubprocessError,KeyError) as e:last=str(e)
  time.sleep(.7)
 raise RuntimeError(label+' timed out: '+str(last)[:250])
def viewer():return json.loads(remote('/bin/cat "$HOME/Library/Logs/RetinaLink/Viewer-ui.json"'))
def host():return json.loads((root/'work/host-live.json').read_text())
def command(name):
 temp=control/'next.json';temp.write_text(json.dumps({'command':name}));temp.chmod(0o600);temp.replace(control/'command.json')
class NativeProcess:
 def __init__(self,pid):self.pid=pid
 def poll(self):
  return None if subprocess.run(['/bin/ps','-p',str(self.pid),'-o','pid='],stdout=subprocess.DEVNULL).returncode==0 else 0
 def wait(self,timeout=10):
  end=time.monotonic()+timeout
  while self.poll() is None and time.monotonic()<end:time.sleep(.1)
  if self.poll() is None:raise RuntimeError('Host did not exit')
def own_host_kill(pid,sig):
 text=subprocess.check_output(['/bin/ps','-p',str(pid),'-o','command='],text=True).strip()
 if not text.startswith(str(a.host_app.resolve()/'Contents/MacOS/RetinaLink')):raise RuntimeError('Unexpected Host process')
 os.kill(pid,sig)
def settings():return remote('/usr/bin/fdesetup status; /usr/bin/defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null || true')
def assert_helper_off():
 names=subprocess.check_output(['/bin/ps','-axo','comm='],text=True).splitlines()
 assert not any(pathlib.Path(n.strip()).name=='SkyComputerUseService' for n in names),'UI capture helper must remain off'
assert_helper_off();before=settings();(out/'settings-before.txt').write_text(before)
subprocess.run(['/bin/launchctl','bootout','gui/'+str(os.getuid())+'/local.retinalink.host.startup'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
old=host();pid=old['pid'];check=subprocess.run(['/bin/ps','-p',str(pid),'-o','command='],capture_output=True,text=True);cmd=check.stdout.strip()
shutil.copy2(root/'work/host-live.json',out/'previous-host.json')
if check.returncode==0:
 assert '/RetinaLink Host.app/Contents/MacOS/RetinaLink' in cmd and (str(root) in cmd or '/Users/opsohebat/Applications/' in cmd)
 os.kill(pid,signal.SIGTERM);time.sleep(1)
live=root/'work/host-live.json'
if live.exists() or live.is_symlink():live.unlink()
live.symlink_to(pathlib.Path.home()/'Library/Logs/RetinaLink/Host.json')
report=out/'enrollment.json'
if report.exists():report.unlink()
args=[str(a.host_app.resolve()/'Contents/MacOS/RetinaLink'),'--setup-viewer','--viewer-address',a.address,'--viewer-user',a.user,'--ssh-control-path',str(a.socket.resolve()),'--setup-report',str(report),'--test-control-directory',str(control),'--ui-state-path',str(out/'host-ui.json')]
if a.dedicated_display:args.append('--dedicated-display')
ui=out/'host-ui.json'
if ui.exists():ui.unlink()
with (out/'host.stdout').open('w') as log:subprocess.run(['/usr/bin/open','-n',str(a.host_app.resolve()),'--args']+args[1:],stdout=log,stderr=subprocess.STDOUT,check=True)
wait_for('Host launched through native Launch Services',lambda:ui.exists(),25)
process=NativeProcess(json.loads(ui.read_text())['pid'])
wait_for('Host-side enrollment completed',lambda:report.exists(),150)
result=json.loads(report.read_text());assert result.get('success'),result
assert result['fileVaultChanged'] is False and result['automaticLoginChanged'] is False
state=wait_for('Viewer automatically streams fullscreen',lambda:(s if (s:=viewer()).get('phase')=='streaming' else None),80)
assert state['trusted'] and state['fullscreen'] and state['systemUIAutoHidden'] and state['automaticReconnect'] and state['startupInstalled'] and state['displayWindows']==1
(out/'viewer-initial.json').write_text(json.dumps(state,indent=2))
agent=plistlib.loads(remote('/bin/cat "$HOME/Library/LaunchAgents/local.retinalink.viewer.startup.plist"').encode());assert agent['ProgramArguments'][1:]==['--appliance'] and agent['LimitLoadToSessionType']=='Aqua'
assert '--frames-in-flight' not in agent['ProgramArguments'];(out/'viewer-agent.json').write_text(json.dumps(agent,indent=2))
for image in ['host-ui.png','setup-ui.png']:
 path=control/image
 if path.exists():path.unlink()
command('snapshot');wait_for('Host UI rendered without screen capture',lambda:(control/'host-ui.png').exists())
command('snapshot-setup');wait_for('Setup UI rendered without screen capture',lambda:(control/'setup-ui.png').exists())
command('pause');s=wait_for('Host Disconnect produces fullscreen standby',lambda:(s if (s:=viewer())['phase']=='paused' else None));assert s['standbyVisible'] and s['fullscreen'] and s['trusted'];(out/'viewer-paused.json').write_text(json.dumps(s,indent=2))
command('resume');wait_for('Host Connect resumes without Viewer input',lambda:viewer()['phase']=='streaming')
command('close-home');time.sleep(2);assert process.poll() is None and viewer()['phase']=='streaming';print('PASS: closing Host window keeps display running',flush=True)
old_pid=viewer()['pid'];remote('command=$(/bin/ps -p '+str(old_pid)+' -o command=); case "$command" in "$HOME/Applications/RetinaLink Viewer.app/Contents/MacOS/RetinaLink"*) /bin/kill -KILL '+str(old_pid)+' ;; *) exit 4 ;; esac')
new=wait_for('launchd restarts crashed Viewer and reconnects fullscreen',lambda:(s if (s:=viewer())['pid']!=old_pid and s['phase']=='streaming' else None));assert new['fullscreen'];(out/'viewer-recovered.json').write_text(json.dumps(new,indent=2))
command('open-home');time.sleep(1)
command('forget')
wait_for('Host removes pairing and Viewer returns to fullscreen readiness',lambda:(s if (s:=viewer())['phase']=='ready' and not s['trusted'] else None),70)
assert not viewer()['startupInstalled']
if report.exists():report.unlink()
command('reenroll')
wait_for('Host re-enrolls without Viewer interaction',lambda:report.exists(),150)
assert json.loads(report.read_text()).get('success')
wait_for('Re-enrolled display streams fullscreen',lambda:viewer()['phase']=='streaming',70)
# The GUI login domain is kept alive; this checks login-agent configuration and
# restart behavior without logging out, locking the iMac, or requiring a password.
own_host_kill(process.pid,signal.SIGTERM);process.wait(timeout=10)
subprocess.run(['/bin/launchctl','enable','gui/'+str(os.getuid())+'/local.retinalink.host.startup'],check=True)
subprocess.run(['/bin/launchctl','bootstrap','gui/'+str(os.getuid()),str(pathlib.Path.home()/'Library/LaunchAgents/local.retinalink.host.startup.plist')],check=True)
new_host=wait_for('Host starts from its login agent and restores pairing',lambda:(d if (d:=host())['pid']!=process.pid and any(s['kind']=='state' and s['text'].startswith('Streaming') for s in d['samples']) and viewer()['phase']=='streaming' else None));(out/'host-agent-recovery.json').write_text(json.dumps({k:v for k,v in new_host.items() if k!='samples'},indent=2))
owned_socket=pathlib.Path.home()/'Library/Application Support/RetinaLink/display-tunnel'
check=subprocess.run(['/usr/bin/ssh','-S',str(owned_socket),'-O','check','-o','BatchMode=yes','-l',a.user,a.address],capture_output=True,text=True,check=True);match=re.search(r'pid=(\d+)',check.stderr);assert match,check.stderr
tunnel_pid=int(match[1])
subprocess.run(['/usr/bin/ssh','-S',str(owned_socket),'-O','exit','-o','BatchMode=yes','-l',a.user,a.address],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
wait_for('Viewer observes tunnel interruption and stays fullscreen',lambda:(s if (s:=viewer())['phase'] in ('reconnecting','connecting') else None),30)
wait_for('Host repairs its tunnel using saved identity without passwords',lambda:viewer()['phase']=='streaming',75)
after=settings();(out/'settings-after.txt').write_text(after);assert after==before,'FileVault or automatic-login status changed'
assert_helper_off();final=viewer();(out/'viewer-final.json').write_text(json.dumps(final,indent=2))
(out/'result.json').write_text(json.dumps({'success':True,'version':final['version'],'build':final['build'],'dedicatedDisplay':a.dedicated_display,'fileVaultUnchanged':True,'automaticLoginUnchanged':True,'uiCaptureHelperOff':True,'viewerCrashRecovery':True,'hostLoginAgentRecovery':True,'tunnelRecovery':True,'physicalRebootTested':False},indent=2))
print('PASS: FileVault and automatic-login settings unchanged; UI capture helper remains off',flush=True)
