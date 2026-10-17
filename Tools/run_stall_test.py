#!/usr/bin/env python3
"""Run a scene without SSH polling; fetch bounded stats and metadata traces afterward."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

p=argparse.ArgumentParser()
p.add_argument('name');p.add_argument('--workspace',type=Path)
p.add_argument('--seconds',type=int,default=90);p.add_argument('--source',choices=['layer','native','gpu','marker','probe'],default='layer')
p.add_argument('--scene',default='scroll');p.add_argument('--host-app',type=Path)
p.add_argument('--source-plan');p.add_argument('--source-period',type=int,default=20)
p.add_argument('--prefer-60',action='store_true');p.add_argument('--measure-display-link',action='store_true')
p.add_argument('--no-trace',action='store_true')
p.add_argument('--poll',action='store_true')
argv=sys.argv[1:];split=argv.index('--') if '--' in argv else len(argv)
a=p.parse_args(argv[:split]);a.host_args=argv[split+1:]
root=a.workspace or next((x for x in Path(__file__).resolve().parents if (x/'work/host-live.json').exists()),None)
if root is None:raise RuntimeError('Pass --workspace with the local test workspace')
root=root.resolve();out=root/'work/perf'/a.name;out.mkdir(parents=True,exist_ok=True)
if (out/'test.json').exists():raise RuntimeError('Use a fresh test name')
ssh=['/usr/bin/ssh','-S',str(root/'work/imac-ssh-session/control'),'-o','BatchMode=yes','-o','ConnectTimeout=5','-l','opsounimas','10.28.114.22']
trace=root/'work/host-frame-trace.jsonl'
if a.host_app:
    app=(root/a.host_app).resolve()/'Contents/MacOS/RetinaLink'
    if not app.is_relative_to(root) or not app.is_file():raise RuntimeError('Host app must be inside the workspace')
    if (root/'work/host-live.json').exists():
        old=json.loads((root/'work/host-live.json').read_text())['pid']
        try:
            cmd=subprocess.check_output(['/bin/ps','-p',str(old),'-o','command='],text=True).strip()
            executable=Path(cmd.split(' --',1)[0])
            if not executable.is_relative_to(root) or not str(executable).endswith('/RetinaLink Host.app/Contents/MacOS/RetinaLink'):raise RuntimeError('Unexpected existing Host process')
            subprocess.run(['/bin/kill','-TERM',str(old)],check=True)
        except subprocess.CalledProcessError:pass
        time.sleep(1)
    args=a.host_args[1:] if a.host_args and a.host_args[0]=='--' else a.host_args
    trace_args=[] if a.no_trace else ['--trace-path',str(trace)]
    proc=subprocess.Popen([str(app),'--autostart','--diagnostics-path',str(root/'work/host-live.json')]+trace_args+args,stdout=open(root/'work/host-live.stdout','w'),stderr=subprocess.STDOUT,start_new_session=True)
    deadline=time.monotonic()+30
    while time.monotonic()<deadline:
        if proc.poll() is not None:raise RuntimeError('Host exited')
        try:
            d=json.loads((root/'work/host-live.json').read_text())
            if d['pid']==proc.pid and any(s['kind']=='state' and s['text'].startswith('Streaming') for s in d['samples']):break
        except (FileNotFoundError,json.JSONDecodeError):pass
        time.sleep(.5)
    else:raise RuntimeError('Host did not stream')
    (out/'variant.json').write_text(json.dumps({'app':str(app.relative_to(root)),'arguments':args,'version':d.get('version'),'build':d.get('build'),'pid':proc.pid,'frameTrace':not a.no_trace},indent=2))

began=time.time()
if a.poll:
    flags=(['--prefer-60'] if a.prefer_60 else [])+(['--measure-display-link'] if a.measure_display_link else [])
    if a.source_plan:flags+=['--source-plan',a.source_plan,'--source-period',str(a.source_period)]
    subprocess.run(['/usr/bin/python3',str(Path(__file__).resolve().parent/'poll_scene_test.py'),'--workspace',str(root),a.name,'--source',a.source,'--scene',a.scene,'--seconds',str(a.seconds)]+flags,check=True)
else:
    executable={'layer':'RetinaLink Layer Test.app/Contents/MacOS/LayerScene','native':'RetinaLink Native Test.app/Contents/MacOS/LayerScene','gpu':'RetinaLink GPU Test.app/Contents/MacOS/GPUScene','marker':'RetinaLink Marker Test.app/Contents/MacOS/GPUScene','probe':'RetinaLink Source Probe.app/Contents/MacOS/GPUScene'}[a.source]
    cmd=[str(root/'work'/executable),'--scene',a.scene,'--seconds',str(a.seconds),'--log',str(out/'source.json')]
    if a.source=='probe':cmd.append('--frame-trace')
    if a.source_plan:cmd+=['--presentation-plan',a.source_plan,'--presentation-period',str(a.source_period)]
    if a.prefer_60:cmd.append('--prefer-60')
    if a.measure_display_link:cmd.append('--measure-display-link')
    with open(out/'source.stdout','w') as log:
        scene=subprocess.Popen(cmd,stdout=log,stderr=subprocess.STDOUT)
        try:scene.wait(timeout=a.seconds+20)
        finally:
            if scene.poll() is None:scene.terminate();scene.wait(timeout=5)
    if scene.returncode:raise RuntimeError('Scene exited '+str(scene.returncode))
    finished=time.time()
    (out/'test.json').write_text(json.dumps({'began':began,'finished':finished,'seconds':a.seconds,'source':a.source,'scene':a.scene,'poll':False,'prefer60':a.prefer_60,'measureDisplayLink':a.measure_display_link},indent=2))
    # Let asynchronous GPU callbacks and the once-per-second trace batch settle.
    time.sleep(2)
    endpoints={}
    for role,d in [('host',json.loads((root/'work/host-live.json').read_text())),('viewer',json.loads(subprocess.check_output(ssh+['cat "$HOME/Library/Logs/RetinaLink/Viewer.json"'],text=True)))]:
        endpoints[role]={k:d.get(k) for k in ['version','build','os','pid']}
        rows=[s for s in d['samples'] if began-1<=s['time']<=finished+1]
        (out/(role+'.json')).write_text(json.dumps(rows,indent=2))
    (out/'endpoints.json').write_text(json.dumps(endpoints,indent=2))
if not a.no_trace:
    if trace.exists():shutil.copy2(trace,out/'host.trace.jsonl')
    with open(out/'viewer.trace.jsonl','wb') as log:
        subprocess.run(ssh+['cat "$HOME/Library/Logs/RetinaLink/Viewer-trace.jsonl"'],stdout=log,check=True)
metadata=json.loads((out/'test.json').read_text())
metadata['collectionFinished']=time.time()
(out/'test.json').write_text(json.dumps(metadata,indent=2))
print('Saved',out,flush=True)
