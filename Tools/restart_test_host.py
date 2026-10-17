#!/usr/bin/env python3
"""Restart the verified test Host with bounded metadata tracing in this workspace."""
import argparse
import json
from pathlib import Path
import subprocess
import time

p=argparse.ArgumentParser()
p.add_argument('--workspace',type=Path,required=True)
p.add_argument('--app',type=Path,required=True)
p.add_argument('--previous-app',type=Path,help='Explicitly expected currently running Host when changing builds')
p.add_argument('--no-trace',action='store_true')
a=p.parse_args();root=a.workspace.resolve();diagnostics=root/'work/host-live.json'
binary=(a.app/'Contents/MacOS/RetinaLink').resolve()
previous=((a.previous_app or a.app)/'Contents/MacOS/RetinaLink').resolve()
if not binary.is_file() or not str(binary).endswith('/RetinaLink Host.app/Contents/MacOS/RetinaLink'):
    raise RuntimeError('Expected a RetinaLink Host app')
if diagnostics.exists():
    old=int(json.loads(diagnostics.read_text())['pid'])
    result=subprocess.run(['/bin/ps','-p',str(old),'-o','command='],capture_output=True,text=True)
    if result.returncode==0:
        command=result.stdout.strip()
        if not command.startswith(str(previous)+' --'):
            raise RuntimeError('Existing Host differs from selected app; restart stopped')
        subprocess.run(['/bin/kill','-TERM',str(old)],check=True)
        for _ in range(40):
            if subprocess.run(['/bin/ps','-p',str(old),'-o','pid='],stdout=subprocess.DEVNULL).returncode!=0:break
            time.sleep(.1)
        else:raise RuntimeError('Previous Host did not exit normally')
# A relocated workspace can initially point at the old live diagnostic file.
if diagnostics.is_symlink():diagnostics.unlink()
args=[str(binary),'--autostart','--diagnostics-path',str(diagnostics)]
if not a.no_trace:args+=['--trace-path',str(root/'work/host-frame-trace.jsonl')]
with open(root/'work/host-live.stdout','w') as log:
    process=subprocess.Popen(args,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
deadline=time.monotonic()+35
while time.monotonic()<deadline:
    if process.poll() is not None:raise RuntimeError('Host exited before streaming')
    try:
        doc=json.loads(diagnostics.read_text())
        if doc['pid']==process.pid and any(s['kind']=='state' and s['text'].startswith('Streaming') for s in doc['samples']):
            print('Streaming Host',doc.get('version'),doc.get('build'),'PID',process.pid);break
    except (FileNotFoundError,json.JSONDecodeError):pass
    time.sleep(.5)
else:raise RuntimeError('Host did not resume streaming')
