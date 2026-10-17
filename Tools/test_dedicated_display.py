#!/usr/bin/env python3
"""Read-only dedicated-account verification through a temporary forced-command SSH key.

Host is launched separately with --dedicated-test-public-key pointing at this
key's .pub file. The account installer accepts only that forced diagnostic key.
This script never reads account passwords, pairing secrets, or screen pixels.
"""
import argparse, json, pathlib, subprocess, time
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--address',required=True); p.add_argument('--key',type=pathlib.Path,required=True)
p.add_argument('--known-hosts',type=pathlib.Path,required=True)
p.add_argument('--output',type=pathlib.Path,required=True)
p.add_argument('--timeout',type=int,default=180)
p.add_argument('--cleanup',action='store_true')
a=p.parse_args(); a.output.mkdir(parents=True,exist_ok=True)
ssh=['/usr/bin/ssh','-i',str(a.key),'-o','IdentitiesOnly=yes','-o','BatchMode=yes','-o','StrictHostKeyChecking=yes','-o','UserKnownHostsFile='+str(a.known_hosts),'-o','ConnectTimeout=5','retinalinkdisplay@'+a.address]
def run(command):return subprocess.check_output(ssh+[command],text=True,stderr=subprocess.PIPE,timeout=15)
def helper_off():
    names=subprocess.check_output(['/bin/ps','-axo','comm='],text=True).splitlines()
    assert not any(pathlib.Path(s.strip()).name=='SkyComputerUseService' for s in names)
def sample():
    text=run('status'); (a.output/'last-status.txt').write_text(text)
    def field(label):return text.split('RETINALINK_'+label+'\n',1)[1].split('\nRETINALINK_',1)[0].strip()
    proof=json.loads(field('SETUP')); assert proof['recoveryCycleVerified'] and not proof['fileVaultChanged']
    ui=json.loads(field('UI'))
    assert field('CONSOLE')=='retinalinkdisplay','Display account is not the console user'
    assert 'FileVault is Off' in field('FILEVAULT')
    assert 'is not a member' in field('ADMIN')
    assert field('LOCK').splitlines()[0]=='0','Idle password lock is enabled'
    assert field('IDLE')=='0','Screensaver is enabled'
    assert field('PENDING')=='consumed','First-login enrollment has not committed'
    assert 'RetinaLink dedicated display' in field('ASSERTIONS')
    assert ui['trusted'] and ui['fullscreen'] and ui['startupInstalled'] and ui['systemUIAutoHidden']
    assert ui['phase']=='streaming'
    assert time.time()-ui['time'] < 8,'Viewer state is stale'
    return ui
helper_off()
if a.cleanup:
    run('cleanup'); print('Temporary forced-command diagnostic key removed.'); raise SystemExit
end=time.monotonic()+a.timeout
while True:
    try:initial=sample();break
    except (AssertionError,ValueError,KeyError,IndexError,subprocess.SubprocessError) as e:
        if time.monotonic()>end:raise RuntimeError('Dedicated sign-in not verified: '+str(e)) from e
        time.sleep(2)
(a.output/'initial.json').write_text(json.dumps(initial,indent=2))
print('PASS: dedicated standard account, FileVault unchanged, fullscreen pairing, effective idle policy and sleep assertion',flush=True)
run('restart-viewer'); end=time.monotonic()+60
while True:
    try:
        recovered=sample()
        if recovered['pid']!=initial['pid']:break
    except (AssertionError,ValueError,KeyError,IndexError,subprocess.SubprocessError):pass
    if time.monotonic()>end:raise RuntimeError('Viewer did not recover')
    time.sleep(2)
run('sleep-wake'); awake=sample(); helper_off()
(a.output/'result.json').write_text(json.dumps({'success':True,'initial':initial,'recovered':recovered,'awake':awake,'fileVaultUnchanged':True,'uiCaptureHelperOff':True,'requiresPhysicalRestartEvidence':True},indent=2))
print('PASS: Viewer launchd recovery, paired reconnect and wake activity',flush=True)
