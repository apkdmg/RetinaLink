#!/usr/bin/env python3
import argparse,json,re,statistics
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('directory',type=Path);a=p.parse_args();root=a.directory
host=json.loads((root/'host.json').read_text());source=json.loads((root/'source.json').read_text())['samples'];meta=json.loads((root/'test.json').read_text())
phases=[x for x in host if x['kind']=='probe-phase'];results=[]
for i,phase in enumerate(phases):
    start=phase['uptime']+5;end=phases[i+1]['uptime']-2 if i+1<len(phases) else source[-1]['uptime']-2
    rows=[x for x in host if x['kind']=='host' and start<x['uptime']<end]
    fields={'capture_fps':r'Capture ([\d.]+)','processed':r'processed (\d+)','work_ms':r'work ([\d.]+) ms','gpu_ms':r'GPU ([\d.]+) ms · pack','pack_ms':r'pack ([\d.]+) ms · bytes','coalesced':r'coalesced (\d+)'}
    record={'phase':phase['text'],'samples':len(rows),'start':start,'end':end}
    for key,pattern in fields.items():
        vals=[float(m.group(1)) for x in rows if (m:=re.search(pattern,x['text']))]
        if vals:record[key]={'mean':statistics.mean(vals),'min':min(vals),'max':max(vals)}
    ss=[x for x in source if start<x['uptime']<end]
    for key in ['drawnFPS','presentedFPS']:
        values=[x[key] for x in ss if key in x]
        if values:record['source_'+key]=statistics.mean(values)
    results.append(record)
    print(phase['text'].split(' · elapsed')[0],{k:round(v['mean'],3) if isinstance(v,dict) else round(v,3) for k,v in record.items() if k not in ['phase','samples','start','end']})
(root/'probe-analysis.json').write_text(json.dumps(results,indent=2))
