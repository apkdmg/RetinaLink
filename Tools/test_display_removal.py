#!/usr/bin/env python3
"""Exercise Host-only remove/re-add with disposable approval and real TLS.

Optionally uses a bounded SSH bridge to launch Viewer in an already signed-in
dedicated login. No production pairing, login, FileVault or startup is modified.
"""
import argparse,json,shlex,subprocess,time,uuid
from pathlib import Path


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--apps',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--ssh-socket',type=Path);p.add_argument('--ssh-peer');p.add_argument('--bridge-root')
    p.add_argument('--viewer-address',default='127.0.0.1');p.add_argument('--port-base',type=int,default=58831)
    a=p.parse_args();out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
    assert 58500 <= a.port_base <= 65000
    remote=all([a.ssh_socket,a.ssh_peer,a.bridge_root]);assert remote or not any([a.ssh_socket,a.ssh_peer,a.bridge_root])
    scopes={x:str(uuid.uuid4()).upper() for x in ['host','viewer']}
    folders={x:out/x for x in scopes}
    for f in folders.values():f.mkdir()
    live=set();results=[]
    def run(args,**kw):return subprocess.run([str(x) for x in args],capture_output=True,check=True,timeout=25,**kw)
    def ssh(cmd,**kw):return run(['/usr/bin/ssh','-S',a.ssh_socket.resolve(),'-o','BatchMode=yes',a.ssh_peer,cmd],**kw)
    def bridge():return json.loads(ssh('/bin/cat '+shlex.quote(a.bridge_root+'/bridge-state.json')).stdout)
    def helper_off():
        names=run(['/bin/ps','-axo','comm='],text=True).stdout.splitlines()
        assert not any(Path(x.strip()).name=='SkyComputerUseService' for x in names)
    def state(name):
        if remote and name=='viewer':
            b=bridge()
            if b.get('error') or b.get('launchError'):raise RuntimeError(b.get('error') or b['launchError'])
            return b['viewers']['viewer']
        return json.loads((folders[name]/'state.json').read_text())
    def wait(label,fn,seconds=45):
        end=time.monotonic()+seconds
        while time.monotonic()<end:
            helper_off()
            try:
                v=fn()
                if v:return v
            except (OSError,ValueError,KeyError,subprocess.SubprocessError):pass
            time.sleep(.25)
        raise RuntimeError(label+' timed out')
    def rcommand(action,**values):
        data=json.dumps(dict(action=action,**values)).encode()
        temp=a.bridge_root+'/bridge-command.next';dest=a.bridge_root+'/bridge-command.json'
        ssh('/bin/cat > '+shlex.quote(temp),input=data)
        ssh('/bin/mv '+shlex.quote(temp)+' '+shlex.quote(dest))
        wait('Bridge consumes command',lambda:ssh('/bin/test ! -e '+shlex.quote(dest)).returncode==0)
    def command(name,action,**kw):
        if remote and name=='viewer':rcommand('send',name='viewer',command=action,**kw);return
        f=folders[name]/'next.json';f.write_text(json.dumps(dict(action=action,**kw)));f.replace(folders[name]/'command.json')
    def launch(name):
        if remote and name=='viewer':
            previous=bridge().get('viewers',{}).get('viewer',{}).get('pid')
            rcommand('launch',name='viewer');live.add(name)
            wait('Fresh SSH Viewer starts',lambda:state(name) if state(name).get('pid')!=previous else None)
            return
        role='Host' if name=='host' else 'Viewer'
        (folders[name]/'state.json').unlink(missing_ok=True)
        args=['--native-test-harness','--native-test-scope',scopes[name],'--native-test-directory',folders[name],
              '--native-pair-port',str(a.port_base),'--native-test-stream-port',str(a.port_base+1)]
        if name=='host':args+=['--native-test-address',a.viewer_address]
        run(['/usr/bin/open','-n',a.apps.resolve()/f'RetinaLink {role}.app','--args']+args)
        live.add(name);wait(name+' starts',lambda:state(name))
    def probe(expected):
        previous=state('viewer')['desktopProbeCompleted'];command('viewer','probe-state')
        wait('TLS desktop state '+expected,lambda:state('viewer')['desktopProbeCompleted']>previous and state('viewer')['desktopState']==expected)
    success=False
    try:
        helper_off()
        if remote:
            ready=wait('SSH bridge ready',lambda:bridge() if bridge()['phase']=='ready' else None,seconds=240)
            assert ready['uid']==502;(out/'before.json').write_text(json.dumps(ready,indent=2)+'\n')
        launch('viewer');launch('host')
        hs=wait('Host verification',lambda:state('host') if state('host')['stage']=='verify' else None)
        vs=wait('Viewer verification',lambda:state('viewer') if state('viewer')['stage']=='verify' else None)
        assert hs['code'] and hs['code']==vs['code']
        command('host','approve',code=hs['code']);wait('Host approval',lambda:state('host')['localApproved'])
        assert not state('viewer')['paired'];command('viewer','approve',code=vs['code'])
        wait('Pair committed',lambda:state('host')['stage']=='complete' and not state('host')['pending'])
        wait('Viewer authenticates',lambda:state('viewer')['probe']=='passed');probe('sharing')
        for dedicated in [False,True]:
            if dedicated:
                command('host','dedicated-fixture')
                wait('Dedicated fixture',lambda:state('host')['boundUsername']=='retinalinkdisplay')
            before=state('host');viewer=state('viewer')
            command('host','remove-display')
            wait('Display removed',lambda:state('host')['displayRemoved'] and not state('host')['paired'] and state('host')['stage']=='approved')
            assert state('host')['retainedBindingSHA256']==before['bindingSHA256']
            assert state('host')['testCredentialSHA256']==before['testCredentialSHA256']
            assert not state('host')['mayShareDesktop'];probe('removed')
            # Reopening Host must not implicitly re-add or enable sharing.
            command('host','exit');time.sleep(1);live.remove('host');launch('host')
            assert state('host')['displayRemoved'] and not state('host')['mayShareDesktop'];probe('removed')
            # Viewer is deliberately unavailable when Add Display is clicked.
            command('viewer','exit');time.sleep(1);live.remove('viewer')
            command('host','restore-display');wait('Host-only re-add',lambda:state('host')['paired'] and not state('host')['displayRemoved'])
            assert state('host')['bindingSHA256']==before['bindingSHA256']
            assert state('host')['testCredentialSHA256']==before['testCredentialSHA256']
            launch('viewer');wait('Viewer reconnects without approval',lambda:state('viewer')['probe']=='passed');probe('sharing')
            assert state('viewer')['bindingSHA256']==viewer['bindingSHA256']
            assert state('viewer')['testCredentialSHA256']==viewer['testCredentialSHA256']
            results.append({'dedicatedDisplay':dedicated,'hostRestartWhileRemovedDoesNotShare':True,
                'hostOnlyReaddWhileViewerOffline':True,'viewerReconnectsWithoutApproval':True,
                'sameOriginalBindingAndKey':True,'startupAndLoginMetadataPreserved':True})
            print('PASS: '+('Dedicated Display' if dedicated else 'ordinary display')+' removal, restart, offline re-add and fresh Viewer TLS reconnection',flush=True)
        success=True
        (out/'result.json').write_text(json.dumps({'success':True,'cases':results,'sshTested':remote,
            'uiCaptureHelperOff':True,'productionPairingAccessed':False,'screenCaptureUsed':False},indent=2)+'\n')
        print(json.dumps(results,indent=2))
    finally:
        for name in scopes:
            if name not in live:
                if remote and name=='viewer':continue  # bounded bridge owns its cleanup
                if not (folders[name]/'state.json').exists():continue
                try:launch(name)
                except Exception:continue
            try:command(name,'cleanup')
            except Exception:pass
        if remote and success:
            rcommand('finish')
            final=wait('Protected login preserved',lambda:bridge() if bridge()['phase']=='complete' else None)
            (out/'after.json').write_text(json.dumps(final,indent=2)+'\n')
            assert final['preserved'] and final['helperOff'] and not final.get('cleanupErrors'),final
        time.sleep(1)

if __name__=='__main__':main()
