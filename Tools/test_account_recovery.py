#!/usr/bin/env python3
"""Exercise account-change recovery in disposable preference/Keychain profiles.

Runs native AppKit setup and real TCP approval on one logged-in Mac. It does
not create OS accounts, sign anyone out, capture the desktop or access live
pairing. Separate Viewer scopes model the empty state of another user account;
this is not an actual multi-user logout/login hardware test.
"""
import argparse,json,os,subprocess,time,uuid
from pathlib import Path


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apps',type=Path,required=True)
    parser.add_argument('--viewer-app',type=Path,help='Optional older Viewer app for protocol compatibility checks')
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args(); out=args.output.resolve(); out.mkdir(parents=True,exist_ok=False)
    apps=args.apps.resolve(); results=[]
    def run(argv): return subprocess.run([str(x) for x in argv],capture_output=True,text=True,check=True,timeout=20)
    def helper_off():
        assert all(Path(x.strip()).name!='SkyComputerUseService' for x in run(['/bin/ps','-axo','comm=']).stdout.splitlines())
    helper_off()
    for scenario in ['cancel','replace','resume','forget-offline']:
        root=out/scenario;root.mkdir(); hd=root/'host';vd=root/'viewer';hd.mkdir();vd.mkdir()
        host_scope=str(uuid.uuid4()).upper();viewer_scope=str(uuid.uuid4()).upper()
        def state(folder): return json.loads((folder/'state.json').read_text())
        def command(folder,action,**kw):
            p=folder/'next.json';p.write_text(json.dumps(dict(action=action,**kw)));p.replace(folder/'command.json')
        def wait(label,fn,seconds=35):
            end=time.monotonic()+seconds
            while time.monotonic()<end:
                helper_off()
                try:
                    value=fn()
                    if value:return value
                except (OSError,ValueError,KeyError):pass
                time.sleep(.2)
            raise RuntimeError(label+' timed out')
        port=str(58560+['cancel','replace','resume','forget-offline'].index(scenario))
        def launch(role,scope,folder,extra):
            app=args.viewer_app.resolve() if role=='Viewer' and args.viewer_app else apps/f'RetinaLink {role}.app'
            run(['/usr/bin/open','-n',app,'--args','--native-test-harness',
                 '--native-test-scope',scope,'--native-test-directory',folder,'--native-pair-port',port]+extra)
        viewer_started=False
        try:
            launch('Host',host_scope,hd,['--native-test-existing-binding','--native-test-address','127.0.0.1'])
            hs=wait('existing profile controls',lambda:state(hd) if state(hd)['stage']=='existing' else None)
            assert hs['paired'] and hs['continueEnabled'] and hs['boundUsername']=='account_a'
            original_key=hs['testCredentialSHA256']; original_binding=hs['bindingSHA256']
            if scenario=='forget-offline':
                command(hd,'forget-local')
                wait('offline Host forget',lambda:not state(hd)['paired'] and not state(hd)['pending'] and state(hd)['stage']=='choose' and state(hd)['continueEnabled'])
                assert 'testCredentialSHA256' not in state(hd)
                results.append({'scenario':scenario,'noViewerNeeded':True,'credentialRemoved':True,'canStartSetupAgain':True})
                continue
            extra=['--native-test-reject-first-enrollment'] if scenario=='resume' else []
            launch('Viewer',viewer_scope,vd,extra);viewer_started=True
            wait('fresh account ready',lambda:state(vd)['stage']=='waiting' and not state(vd)['paired'])
            command(hd,'begin-account-change')
            wait('new account selection',lambda:state(hd)['stage']=='choose')
            assert state(hd)['testCredentialSHA256']==original_key
            command(hd,'connect')
            hs=wait('Host verification',lambda:state(hd) if state(hd)['stage']=='verify' and state(hd)['code'] else None)
            vs=wait('Viewer verification',lambda:state(vd) if state(vd)['stage']=='verify' and state(vd)['code'] else None)
            assert hs['code']==vs['code']
            command(hd,'approve',code=hs['code'])
            wait('Host approval',lambda:state(hd)['localApproved']);time.sleep(.5)
            assert state(hd)['testCredentialSHA256']==original_key and state(hd)['bindingSHA256']==original_binding
            assert not state(vd)['paired']
            if scenario=='cancel':
                command(vd,'cancel');wait('cancelled replacement',lambda:state(hd)['stage']=='choose')
                assert state(hd)['testCredentialSHA256']==original_key and state(hd)['bindingSHA256']==original_binding
                results.append({'scenario':scenario,'oneApprovalKeepsOldTrust':True,'cancellationKeepsOldTrust':True})
                continue
            command(vd,'approve',code=vs['code'])
            interrupted_key=None
            if scenario=='resume':
                partial=wait('resumable interruption',lambda:state(hd) if state(hd)['stage']=='choose' and state(hd)['pending'] else None)
                assert not state(vd)['paired'];interrupted_key=partial['testCredentialSHA256']
                command(hd,'retry')
                hs=wait('retry Host verification',lambda:state(hd) if state(hd)['stage']=='verify' else None)
                vs=wait('retry Viewer verification',lambda:state(vd) if state(vd)['stage']=='verify' else None)
                assert hs['code']==vs['code']
                command(hd,'approve',code=hs['code']);command(vd,'approve',code=vs['code'])
            hs=wait('Host replacement committed',lambda:state(hd) if state(hd)['stage']=='complete' and not state(hd)['pending'] else None)
            vs=wait('Viewer replacement committed',lambda:state(vd) if state(vd)['stage']=='complete' and state(vd)['paired'] else None)
            assert hs['testCredentialSHA256']==vs['testCredentialSHA256']!=original_key
            assert hs['boundUsername']==os.environ['USER']
            if 'boundUsername' in vs:assert vs['boundUsername']==hs['boundUsername']
            if interrupted_key:assert hs['testCredentialSHA256']==interrupted_key
            results.append({'scenario':scenario,'oldTrustKeptUntilBothApprove':True,'newCredentialSharedOnlyWithApprovedViewer':True,'resumeKeptNewCredential':bool(interrupted_key),'viewerBuild':vs['build']})
        finally:
            command(hd,'cleanup')
            if viewer_started:command(vd,'cleanup')
            time.sleep(.8)
        print('PASS: '+scenario,flush=True)
    helper_off()
    result={'success':True,'cases':results,'uiCaptureHelperOff':True,'realOSAccountSwitchTested':False,'productionPairingAccessed':False}
    (out/'result.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))

if __name__=='__main__':main()
