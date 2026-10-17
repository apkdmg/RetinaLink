#!/usr/bin/env python3
"""Two-Mac native approval integration test, isolated from production pairing.

Uses an existing owner-authenticated SSH socket only for deployment/control.
The apps communicate directly over TCP, with separate test Keychain namespaces.
No real credential is exported; no login, FileVault or sharing setting changes.
"""
import argparse
import json
import os
import plistlib
import math
from pathlib import Path
import shlex
import subprocess
import time
import uuid

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--release', type=Path, required=True)
p.add_argument('--address', required=True)
p.add_argument('--user', required=True)
p.add_argument('--socket', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
a=p.parse_args()
a.output.mkdir(parents=True,exist_ok=False)
ssh=['/usr/bin/ssh','-S',str(a.socket.resolve()),'-o','BatchMode=yes','-o','ConnectTimeout=5','-l',a.user,a.address]
def run(args,**kw): return subprocess.run([str(x) for x in args],check=True,**kw)
def remote(command): return run(ssh+[command],capture_output=True,text=True,timeout=45).stdout
def quote(x): return shlex.quote(str(x))
def wait(label,read,condition,seconds=30):
    end=time.monotonic()+seconds
    while time.monotonic()<end:
        try:
            state=read()
            if condition(state): return state
        except (OSError,ValueError,KeyError,subprocess.SubprocessError): pass
        time.sleep(.4)
    raise RuntimeError(label+' timed out')
def helper_off():
    names=run(['/bin/ps','-axo','comm='],capture_output=True,text=True).stdout.splitlines()
    assert not any(Path(x.strip()).name=='SkyComputerUseService' for x in names)
helper_off()
release=json.loads((a.release/'release-state.json').read_text())
assert release['complete'],'Use the completed notarized release'
home=remote('/usr/bin/printf "%s" "$HOME"').strip()
remote_base=home+'/Library/Logs/RetinaLink/NativePairingTests'
remote_apps=remote_base+'/Apps'
remote('mkdir -p '+quote(remote_apps))
viewer_zip=a.release/'build/apps/RetinaLink Host.app/Contents/Resources/RetinaLink Viewer.zip'
run(ssh+['umask 077; /bin/cat > '+quote(remote_base+'/Viewer.zip')],input=viewer_zip.read_bytes(),capture_output=True)
remote('/usr/bin/ditto -x -k '+quote(remote_base+'/Viewer.zip')+' '+quote(remote_apps))
viewer_app=remote_apps+'/RetinaLink Viewer.app'
remote('/usr/bin/codesign --verify --deep --strict '+quote(viewer_app)+' && /usr/sbin/spctl --assess --type execute '+quote(viewer_app))
host_app=a.release/'build/apps/RetinaLink Host.app'
before=remote('/usr/bin/fdesetup status; /usr/bin/defaults read local.retinalink.Viewer trustedDisplayBinding.v1 2>/dev/null | /usr/bin/shasum -a 256; /usr/bin/shasum -a 256 "$HOME/.ssh/authorized_keys" 2>/dev/null || true')
(a.output/'production-before.txt').write_text(before)
results=[]
for scenario in ('cancel','approve','resume'):
    scope=str(uuid.uuid4()).upper()
    local=a.output/scenario; local.mkdir()
    viewer_dir=remote_base+'/'+scope
    remote('mkdir -m 700 '+quote(viewer_dir))
    viewer_args=['--native-test-harness','--native-test-scope',scope,'--native-test-directory',viewer_dir,'--native-pair-port','58478']
    if scenario=='resume': viewer_args+=['--native-test-reject-first-enrollment']
    host_args=['--native-test-harness','--native-test-scope',scope,'--native-test-directory',str(local.resolve()),'--native-test-address',a.address,'--native-pair-port','58478']
    vstate=lambda:json.loads(remote('cat '+quote(viewer_dir+'/state.json')))
    hstate=lambda:json.loads((local/'state.json').read_text())
    def vcommand(item):
        data=json.dumps(item)
        run(ssh+['umask 077; /bin/cat > '+quote(viewer_dir+'/command.json')],input=data,text=True,capture_output=True)
    def hcommand(item):
        temporary=local/'command.next'; temporary.write_text(json.dumps(item)); temporary.replace(local/'command.json')
    try:
        remote('/usr/bin/open -n '+quote(viewer_app)+' --args '+' '.join(quote(x) for x in viewer_args))
        wait('Viewer starts',vstate,lambda s:s['scope']==scope)
        time.sleep(1)
        run(['/usr/bin/open','-n',host_app,'--args']+host_args)
        hs=wait('Host verification',hstate,lambda s:s['stage']=='verify' and bool(s['code']))
        vs=wait('Viewer verification',vstate,lambda s:s['stage']=='verify' and bool(s['code']))
        assert hs['code']==vs['code'],'Verification numbers differ'
        assert not hs['paired'] and not vs['paired']
        # Invoke the real local Host button action, withhold local Viewer approval.
        hcommand({'action':'approve','code':hs['code']})
        wait('Host local approval',hstate,lambda s:s['localApproved'])
        time.sleep(1)
        assert not hstate()['paired'] and not vstate()['paired'],'One-sided approval enrolled a device'
        if scenario=='cancel':
            vcommand({'action':'cancel'})
            wait('Host cancellation',hstate,lambda s:s['stage']=='choose')
            assert not hstate()['paired'] and not vstate()['paired']
            results.append({'scenario':scenario,'oneSidedApprovalRejected':True,'noPairingCreated':True})
        else:
            hcommand({'action':'export-ui'}); vcommand({'action':'export-ui'}); time.sleep(.5)
            picture=run(ssh+['/bin/cat '+quote(viewer_dir+'/interface.png')],capture_output=True).stdout
            (local/'viewer-interface.png').write_bytes(picture)
            vcommand({'action':'approve','code':vs['code']})
            previous_credential=None
            if scenario=='resume':
                partial=wait('Interrupted Host setup is resumable',hstate,lambda s:s['stage']=='choose' and s['paired'] and s.get('pending'))
                assert not vstate()['paired'],'Injected persistence failure saved Viewer trust'
                previous_credential=partial['testCredentialSHA256']
                hcommand({'action':'retry'})
                hs=wait('Retry Host verification',hstate,lambda s:s['stage']=='verify' and bool(s['code']))
                vs=wait('Retry Viewer verification',vstate,lambda s:s['stage']=='verify' and bool(s['code']))
                assert hs['code']==vs['code']
                hcommand({'action':'approve','code':hs['code']});vcommand({'action':'approve','code':vs['code']})
            hs=wait('Host commits',hstate,lambda s:s['stage']=='complete' and s['paired'])
            vs=wait('Viewer commits',vstate,lambda s:s['stage']=='complete' and s['paired'])
            # Foundation's JSON number formatting differs across macOS 11/27;
            # compare decoded non-secret fixture fields, not encoded JSON bytes.
            hdomain='local.retinalink.Host.NativeTest.'+scope
            vdomain='local.retinalink.Viewer.NativeTest.'+scope
            hp=plistlib.loads(run(['/usr/bin/defaults','export',hdomain,'-'],capture_output=True).stdout)
            vp=plistlib.loads(run(ssh+['/usr/bin/defaults export '+quote(vdomain)+' -'],capture_output=True).stdout)
            hb=json.loads(hp['trustedDisplayBinding.v1']);vb=json.loads(vp['trustedDisplayBinding.v1'])
            ht=hb.pop('enrolledAt');vt=vb.pop('enrolledAt')
            assert hb==vb and math.isclose(ht,vt,rel_tol=0,abs_tol=.000001),'Binding fields differ'
            assert hs['testCredentialSHA256']==vs['testCredentialSHA256'],'Disposable credential differs'
            assert not hs.get('pending'),'Pending state was not cleared after commit'
            if previous_credential is not None: assert hs['testCredentialSHA256']==previous_credential,'Retry regenerated the approved credential'
            results.append({'scenario':scenario,'bothLocalApprovalsRequired':True,'sameTestBindingAndCredential':True,'resumedWithOriginalCredential':previous_credential is not None})
    except Exception:
        hcommand({'action':'export-ui'}); time.sleep(1)
        raise
    finally:
        hcommand({'action':'cleanup'}); vcommand({'action':'cleanup'})
        time.sleep(1)
after=remote('/usr/bin/fdesetup status; /usr/bin/defaults read local.retinalink.Viewer trustedDisplayBinding.v1 2>/dev/null | /usr/bin/shasum -a 256; /usr/bin/shasum -a 256 "$HOME/.ssh/authorized_keys" 2>/dev/null || true')
(a.output/'production-after.txt').write_text(after)
assert before==after,'Production Viewer pairing, FileVault or public SSH keys changed'
helper_off()
(a.output/'result.json').write_text(json.dumps({'success':True,'cases':results,'productionViewerPairingUnchanged':True,'fileVaultUnchanged':True,'authorizedKeysUnchanged':True,'uiCaptureHelperOff':True},indent=2)+'\n')
print('PASS: real two-Mac approval, one-sided denial, cancellation and isolated enrollment; production Viewer pairing and FileVault unchanged')
