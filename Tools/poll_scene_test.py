import argparse, json, os, pathlib, subprocess, time

p = argparse.ArgumentParser()
p.add_argument('--workspace',required=True,type=pathlib.Path)
p.add_argument('name'); p.add_argument('--scene',default='window'); p.add_argument('--seconds',type=int,default=30); p.add_argument('--source',default='gpu')
p.add_argument('--source-plan');p.add_argument('--source-period',type=int,default=20)
p.add_argument('--prefer-60',action='store_true')
p.add_argument('--measure-display-link',action='store_true')
p.add_argument('--manual-animation',action='store_true')
a = p.parse_args()
root = a.workspace.resolve()
out = root/'work'/'perf'/a.name; out.mkdir(parents=True,exist_ok=True)
ssh = ['/usr/bin/ssh','-S',str(root/'work/imac-ssh-session/control'),'-o','BatchMode=yes','-o','ConnectTimeout=5','-l','opsounimas','10.28.114.22']
host_samples, viewer_samples = {}, {}
endpoints={}
began = time.time()
(out/'test.json').write_text(json.dumps({'began':began,'seconds':a.seconds,'scene':a.scene,'source':a.source},indent=2))
executable=root/({'probe':'work/RetinaLink Source Probe.app/Contents/MacOS/GPUScene','marker':'work/RetinaLink Marker Test.app/Contents/MacOS/GPUScene','layer':'work/RetinaLink Layer Test.app/Contents/MacOS/LayerScene','native':'work/RetinaLink Native Test.app/Contents/MacOS/LayerScene','manual':'work/RetinaLink Manual Test.app/Contents/MacOS/LayerScene','synthetic':'work/RetinaLink Transport Bench.app/Contents/MacOS/Bench'}.get(a.source,'work/RetinaLink GPU Test.app/Contents/MacOS/GPUScene'))
args=[str(executable), '--scene',a.scene,'--seconds',str(a.seconds),'--log',str(out/'source.json')]
if a.source=='probe':args+=['--frame-trace']
if a.source_plan:args+=['--presentation-plan',a.source_plan,'--presentation-period',str(a.source_period)]
if a.prefer_60: args+=['--prefer-60']
if a.measure_display_link: args+=['--measure-display-link']
if a.manual_animation: args+=['--manual-animation']
if a.source=='manual': args+=['--manual-animation','--measure-display-link']
if a.source=='synthetic': args+=['--diagnostics-path',str(root/'work/host-live.json')]
scene = subprocess.Popen(args,stdout=open(out/'source.stdout','w'),stderr=subprocess.STDOUT)
deadline = time.monotonic()+a.seconds+20
while time.monotonic()<deadline:
    try:
        host=json.loads((root/'work/host-live.json').read_text()) if (root/'work/host-live.json').exists() else {'samples':[]}
        viewer=json.loads(subprocess.check_output(ssh+['cat "$HOME/Library/Logs/RetinaLink/Viewer.json"'],timeout=7))
        for role,doc in [('host',host),('viewer',viewer)]:
            endpoints[role]={k:doc.get(k) for k in ['version','build','os','pid']}
        (out/'endpoints.json').write_text(json.dumps(endpoints,indent=2))
        for doc, samples in [(host,host_samples),(viewer,viewer_samples)]:
            for row in doc['samples']:
                if row['time'] >= began-1: samples[row['uptime']] = row
        (out/'host.json').write_text(json.dumps(list(host_samples.values()),indent=2))
        (out/'viewer.json').write_text(json.dumps(list(viewer_samples.values()),indent=2))
    except Exception as e: print('Collection error:',e,flush=True)
    if scene.poll() is not None: break
    time.sleep(2)
if scene.poll() is None: scene.terminate(); scene.wait(timeout=5)
print('Saved',out,'exit',scene.returncode,flush=True)
(out/'test.json').write_text(json.dumps({'began':began,'finished':time.time(),'seconds':a.seconds,'scene':a.scene,'source':a.source},indent=2))
