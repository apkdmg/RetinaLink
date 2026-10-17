#!/usr/bin/env python3
"""One continuous scene, transparent pulse on/off, automatic SSH collection."""
import argparse,json,subprocess,time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('name');p.add_argument('--source',default='layer');p.add_argument('--scene',default='scroll');p.add_argument('--seconds',type=int,default=150);p.add_argument('--pulse-at',type=int,default=45);p.add_argument('--pulse-seconds',type=int,default=60);p.add_argument('--host-app',type=Path)
a=p.parse_args();root=next(x for x in Path(__file__).resolve().parents if (x/'work/host-live.json').exists());out=root/'work/perf'/a.name
cmd=['/usr/bin/python3',str(Path(__file__).resolve().parent/'run_stall_test.py'),'--seconds',str(a.seconds),'--source',a.source,'--scene',a.scene,'--no-trace','--poll']
if a.host_app:cmd+=['--host-app',str(a.host_app)]
cmd+=[a.name,'--'];runner=subprocess.Popen(cmd)
pulse=None
try:
    deadline=time.monotonic()+a.seconds+45
    while time.monotonic()<deadline:
        if runner.poll() is not None:raise RuntimeError('Scene ended before pulse')
        try:
            s=json.loads((out/'source.json').read_text())['samples']
            if s and s[-1]['elapsed']>=a.pulse_at:break
        except (FileNotFoundError,json.JSONDecodeError):pass
        time.sleep(.2)
    else:raise RuntimeError('Pulse deadline')
    with (out/'pulse.stdout').open('w') as log:
        pulse=subprocess.Popen([str(root/'work/RetinaLink Pulse Test.app/Contents/MacOS/PulseScene'),'--seconds',str(a.pulse_seconds),'--log',str(out/'pulse.json')],stdout=log,stderr=subprocess.STDOUT)
        pulse.wait(timeout=a.pulse_seconds+10)
    if pulse.returncode:raise RuntimeError('Pulse failed')
    runner.wait(timeout=a.seconds+30)
    if runner.returncode:raise RuntimeError('Scene failed')
finally:
    for proc in [pulse,runner]:
        if proc and proc.poll() is None:proc.terminate();proc.wait(timeout=5)
print('Completed',a.name)
