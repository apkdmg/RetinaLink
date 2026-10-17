#!/usr/bin/env python3
"""Collect a bounded standalone Viewer benchmark through the existing SSH master."""
import argparse,json,subprocess,time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('name');p.add_argument('--trace',required=True);p.add_argument('--seconds',type=int,default=110);p.add_argument('--workspace',type=Path)
a=p.parse_args();root=a.workspace or next(x for x in Path(__file__).resolve().parents if (x/'work/host-live.json').exists())
out=root/'work/perf'/a.name;out.mkdir(parents=True,exist_ok=False)
ssh=['/usr/bin/ssh','-S',str(root/'work/imac-ssh-session/control'),'-o','BatchMode=yes','-o','ConnectTimeout=5','-l','opsounimas','10.28.114.22']
pid=None;deadline=time.monotonic()+a.seconds
while time.monotonic()<deadline:
    data=subprocess.check_output(ssh+['cat "$HOME/Library/Logs/RetinaLink/Viewer.json"'],timeout=7);doc=json.loads(data)
    if pid is None:pid=doc['pid']
    if doc['pid'] != pid:raise RuntimeError('Viewer changed during collection')
    (out/'viewer.json').write_bytes(data)
    if any(s['kind'] in ['probe-done','probe-error'] for s in doc['samples']):break
    time.sleep(2)
else:raise RuntimeError('Probe deadline')
if not a.trace.replace('-','').replace('.','').isalnum():raise RuntimeError('Invalid trace basename')
for _ in range(12):
    # Let NSApplication finish its own fullscreen/Space teardown before another
    # installer runs; do not kill a probe in the middle of that transition.
    if subprocess.run(ssh+[f'/bin/ps -p {int(pid)} -o pid='],stdout=subprocess.DEVNULL).returncode != 0:break
    time.sleep(.5)
else:raise RuntimeError('Probe did not exit after completion')
data=subprocess.check_output(ssh+[f'cat "$HOME/Library/Logs/RetinaLink/{a.trace}"'],timeout=15)
(out/'viewer.trace.jsonl').write_bytes(data)
print(doc['samples'][-1]);print('Saved',out)
