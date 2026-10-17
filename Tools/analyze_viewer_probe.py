#!/usr/bin/env python3
"""Compare standalone rendering phases without equating renders to presentations."""
import argparse,json,re,statistics
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('directory',type=Path);a=p.parse_args();root=a.directory
doc=json.loads((root/'viewer.json').read_text());phases=[s for s in doc['samples'] if s['kind']=='probe-phase'];result=[]
fields={'rendered_fps':r'([\d.]+) rendered','presented_fps':r'Presentation ([\d.]+) fps','upload_ms':r'upload setup ([\d.]+)','gpu_ms':r'· GPU ([\d.]+)','receiver_ms':r'receiver total ([\d.]+)','gpu_start_ms':r'GPU start delay ([\d.]+)','max_gap_ms':r'max gap ([\d.]+) ms','max_receiver_ms':r'max receiver total ([\d.]+)'}
for i,phase in enumerate(phases):
    start=phase['uptime']+3;end=(phases[i+1]['uptime'] if i+1<len(phases) else doc['samples'][-1]['uptime'])-1
    rows=[s['text'] for s in doc['samples'] if s['kind']=='viewer' and start<=s['uptime']<=end]
    item={'phase':phase['text'],'samples':len(rows),'zero_presentation_samples':sum('Presentation 0.0 fps' in s for s in rows),'not_visible_or_asleep_samples':sum('occlusion visible false' in s or 'active Space false' in s or 'display asleep true' in s for s in rows)}
    for key,pattern in fields.items():
        values=[float(m[1]) for s in rows if (m:=re.search(pattern,s))]
        if values:item[key]={'mean':statistics.mean(values),'min':min(values),'max':max(values)}
    result.append(item)
(root/'analysis.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2))
