#!/usr/bin/env python3
"""Bounded receiver-side profiling; never changes permissions or uses UI capture."""
import argparse
import json
from pathlib import Path
import shlex
import subprocess
import time

p=argparse.ArgumentParser();p.add_argument('name');p.add_argument('--workspace',required=True,type=Path)
a=p.parse_args()
if not a.name.replace('-','').isalnum():raise RuntimeError('Use an alphanumeric test name')
root=a.workspace.resolve();out=root/'work/perf'/a.name;out.mkdir(parents=True,exist_ok=False)
ssh=['/usr/bin/ssh','-S',str(root/'work/imac-ssh-session/control'),'-o','BatchMode=yes','-o','ConnectTimeout=5','opsounimas@10.28.114.22']
trace='/private/tmp/retinalink-opsounimas-'+a.name+'.trace'
command=['/usr/bin/python3',str(Path(__file__).parent/'run_stall_test.py'),a.name,'--workspace',str(root),'--seconds','40','--source','layer','--scene','scroll']
with open(out/'runner.stdout','w') as log:
    scene=subprocess.Popen(command,stdout=log,stderr=subprocess.STDOUT)
    try:
        time.sleep(8)
        doc=json.loads(subprocess.check_output(ssh+['cat "$HOME/Library/Logs/RetinaLink/Viewer.json"'],timeout=10))
        pid=int(doc['pid'])
        process=subprocess.check_output(ssh+[f'/bin/ps -p {pid} -o command='],timeout=10,text=True).strip()
        if not process.startswith('/Users/opsounimas/Applications/RetinaLink-') or '/RetinaLink Viewer.app/Contents/MacOS/RetinaLink' not in process:
            raise RuntimeError('Unexpected receiver process')
        began=time.time()
        try:
            # Xcode 13's trace writer can exceed SSH's default 256-descriptor
            # soft limit. Raise only this child shell's limit; no system setting.
            result=subprocess.run(ssh+[f'umask 077; ulimit -n 8192 || exit 1; /usr/bin/xcrun xctrace record --no-prompt --template {shlex.quote("Metal System Trace")} --attach {pid} --time-limit 15s --output {shlex.quote(trace)}'],capture_output=True,timeout=45)
        except subprocess.TimeoutExpired as error:
            (out/'instruments.stdout').write_bytes(error.stdout or b'')
            (out/'instruments.stderr').write_bytes(error.stderr or b'')
            (out/'profile.json').write_text(json.dumps({'pid':pid,'began':began,'finished':time.time(),'timeout':True,'secondsRequested':15,'tracePath':trace},indent=2))
            raise
        (out/'instruments.stdout').write_bytes(result.stdout)
        (out/'instruments.stderr').write_bytes(result.stderr)
        (out/'profile.json').write_text(json.dumps({'pid':pid,'began':began,'finished':time.time(),'exitCode':result.returncode,'secondsRequested':15,'template':'Metal System Trace','noPrompt':True,'tracePath':trace},indent=2))
        if result.returncode==0:
            toc=subprocess.run(ssh+[f'ulimit -n 8192 || exit 1; /usr/bin/xcrun xctrace export --input {shlex.quote(trace)} --toc'],capture_output=True,timeout=30)
            (out/'instruments-toc.xml').write_bytes(toc.stdout)
            (out/'toc.stderr').write_bytes(toc.stderr)
        else:
            print('Profiler did not complete; preserved error, no permission changes',flush=True)
    finally:
        scene.wait(timeout=60)
if scene.returncode:raise RuntimeError('Motion test failed')
print('Saved profiled diagnostic run',out,flush=True)
