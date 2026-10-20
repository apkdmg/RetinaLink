#!/usr/bin/env python3
"""One saved iMac across isolated logins, native approval and automatic TLS reconnect.

Uses disposable preferences and real login-Keychain items, not OS logout/login.
No desktop capture, production pairing, FileVault or network settings are touched.
"""
import argparse,json,subprocess,time,uuid
from pathlib import Path


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--apps',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
    physical=str(uuid.uuid4()).upper(); scopes={x:str(uuid.uuid4()).upper() for x in ['host','a','b']}
    folders={x:out/x for x in scopes}
    for f in folders.values():f.mkdir()
    live=set(); evidence=[]
    def run(argv):return subprocess.run([str(x) for x in argv],capture_output=True,text=True,check=True,timeout=20)
    def helper_off():
        assert all(Path(x.strip()).name!='SkyComputerUseService' for x in run(['/bin/ps','-axo','comm=']).stdout.splitlines())
    def state(x):return json.loads((folders[x]/'state.json').read_text())
    def command(x,action,**kw):
        f=folders[x]/'next.json';f.write_text(json.dumps(dict(action=action,**kw)));f.replace(folders[x]/'command.json')
    def wait(label,fn):
        end=time.monotonic()+40
        while time.monotonic()<end:
            helper_off()
            try:
                v=fn()
                if v:return v
            except (OSError,ValueError,KeyError):pass
            time.sleep(.2)
        raise RuntimeError(label+' timed out')
    def launch(x):
        role='Host' if x=='host' else 'Viewer';folder=folders[x]
        args=['--native-test-harness','--native-test-scope',scopes[x],'--native-test-directory',folder,
              '--native-pair-port','58581','--native-test-stream-port','58582']
        if x=='host':args+=['--native-test-address','127.0.0.1']
        else:args+=['--native-test-username','login_'+x,'--native-test-device-id',physical]
        (folder/'state.json').unlink(missing_ok=True)
        run(['/usr/bin/open','-n',a.apps.resolve()/f'RetinaLink {role}.app','--args']+args);live.add(x)
        wait(x+' starts',lambda:state(x))
    def approve(x):
        hs=wait('Host verification',lambda:state('host') if state('host')['stage']=='verify' else None)
        vs=wait('Viewer verification',lambda:state(x) if state(x)['stage']=='verify' else None)
        assert hs['code']==vs['code'] and hs['code']
        command('host','approve',code=hs['code'])
        wait('Host local approval',lambda:state('host')['localApproved']);time.sleep(.4)
        assert not state(x)['paired'],'A hint or one approval released trust'
        command(x,'approve',code=vs['code'])
        wait('Host commit',lambda:state('host')['stage']=='complete' and not state('host')['pending'])
        wait('Viewer auto reconnect',lambda:state(x)['probe']=='passed')
    try:
        helper_off();launch('a');launch('host');approve('a')
        first=state('host');key=first['testCredentialSHA256'];profile=(first['savedDisplayName'],first['savedDisplayDate'])
        assert key==state('a')['testCredentialSHA256']
        command('a','exit');time.sleep(1);live.remove('a')
        launch('b');command('b','probe')
        wait('New login has no key',lambda:state('b')['probe']=='not-approved')
        assert state('b')['physicalDisplayID']==physical and not state('b')['paired']
        command('host','reopen');wait('Saved display controls',lambda:state('host')['stage']=='existing')
        assert state('host')['primaryTitle']=='Reconnect Display…'
        command('host','begin-reconnect');wait('Reconnect choice',lambda:state('host')['stage']=='choose')
        command('host','connect');approve('b')
        assert state('host')['testCredentialSHA256']==state('b')['testCredentialSHA256']==key
        assert (state('host')['savedDisplayName'],state('host')['savedDisplayDate'])==profile,'Reconnection changed the saved display profile'
        assert state('b')['boundUsername']=='login_b'
        evidence.append({'newLoginNeedsBothApprovals':True,'sameSavedDisplay':True,'sameApprovedKey':True,'automaticTLSReconnect':True})
        launch('a');wait('Original login reconnects without approval',lambda:state('a')['probe']=='passed')
        assert state('a')['testCredentialSHA256']==key and (state('host')['savedDisplayName'],state('host')['savedDisplayDate'])==profile
        evidence.append({'originalLoginReopened':True,'noNewApproval':True,'automaticTLSReconnect':True})
        # Dropped connection: the exact saved key authenticates a fresh TCP/TLS session.
        command('b','probe');wait('Second login reconnects again',lambda:state('b')['probe']=='passed')
        evidence.append({'secondLoginStillApproved':True,'freshEncryptedConnection':True})
        result={'success':True,'cases':evidence,'uiCaptureHelperOff':True,'realOSAccountSwitchTested':False,'productionPairingAccessed':False}
        (out/'result.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
    finally:
        # A deliberately exits with trust intact to exercise returning later.
        # Reopen it for cleanup even if a subsequent assertion failed.
        for x in scopes:
            if x not in live and (folders[x]/'state.json').exists():
                try:launch(x)
                except Exception:pass
        for x in live:command(x,'cleanup')
        time.sleep(1)

if __name__=='__main__':main()
