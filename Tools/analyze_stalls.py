#!/usr/bin/env python3
"""Correlate per-frame traces using sequences and same-host elapsed intervals."""
import argparse
import gzip
import json
from pathlib import Path
import statistics

p=argparse.ArgumentParser();p.add_argument('directory',type=Path);a=p.parse_args();d=a.directory
meta=json.loads((d/'test.json').read_text());start=meta['began']+5;end=meta['finished']-2;duration=end-start
def load(name):
    result=[]
    path=d/name
    contents=path.read_text() if path.exists() else gzip.open(str(path)+'.gz','rt').read()
    for line in contents.splitlines():
        try:result.extend(json.loads(line))
        except json.JSONDecodeError:pass
    return sorted(result,key=lambda x:x['t'])
h=load('host.trace.jsonl');v=load('viewer.trace.jsonl')
sessions=[x for x in v if x['event']=='viewer_session']
if not sessions:raise RuntimeError('No Viewer session in trace')
session=sessions[-1];view=session['view'];link=session['link']
v=[x for x in v if x.get('view')==view or x.get('link')==link]
sequences={x['seq'] for x in h if x['event']=='packed' and start<=x['wall']<=end}
def index(events):
    result={}
    for x in events:
        if x.get('seq') in sequences:result.setdefault(x['seq'],{})[x['event']]=x
    return result
hi=index(h);vi=index(v)
bodies={(x['link'],x['packet']):x for x in v if x['event']=='body_begin'}
frames=[]
for seq in sorted(sequences):
    hs=hi.get(seq,{});vs=vi.get(seq,{})
    if not all(k in hs for k in ['packed','ack_apply']) or not all(k in vs for k in ['body_end','gpu_callback','send_enqueue']):continue
    roundtrip=(hs['ack_apply']['t']-hs['packed']['t'])*1000
    process=(vs['send_enqueue']['t']-vs['body_end']['t'])*1000
    row={'seq':seq,'cycle_ms':roundtrip,'viewer_work_ms':process,'transport_residual_ms':roundtrip-process}
    if 'encode_begin' in hs:row['encode_pack_ms']=(hs['packed']['t']-hs['encode_begin']['t'])*1000
    if 'encode_end' in hs:
        row['pack_ms']=(hs['packed']['t']-hs['encode_end']['t'])*1000
        for key in ['gpu_ms','wait_ms','gather_ms']:row['encoder_'+key]=hs['encode_end'][key]
    cb=vs['gpu_callback'];gpu_end=cb.get('gpu_end',0)
    if gpu_end>0:row['gpu_callback_delay_ms']=(cb['t']-gpu_end)*1000
    row['gpu_ms']=(gpu_end-cb.get('gpu_start',gpu_end))*1000
    body=vs['body_end'];begin=bodies.get((body['link'],body['packet']))
    if begin:row['body_ms']=(body['t']-begin['t'])*1000
    if 'send_begin' in vs:row['ack_send_queue_ms']=(vs['send_begin']['t']-vs['send_enqueue']['t'])*1000
    if 'body_end' in hs:row['host_ack_queue_ms']=(hs['ack_apply']['t']-hs['body_end']['t'])*1000
    if 'send_begin' in hs:row['host_send_queue_ms']=(hs['send_begin']['t']-hs['packed']['t'])*1000
    if 'gpu_commit' in vs:
        commit=vs['gpu_commit'];row['drawable_ms']=(commit['acquired']-commit['uploaded'])*1000
        row['gpu_queue_ms']=(cb.get('gpu_start',commit['t'])-commit['t'])*1000
        if 'present_begin' in vs:row['present_call_ms']=(commit['t']-vs['present_begin']['t'])*1000
        if 'commit_return' in vs:row['commit_call_ms']=(vs['commit_return']['t']-commit['t'])*1000
    if 'drawable_present_begin' in vs and 'drawable_present_end' in vs:
        row['actual_present_ms']=vs['drawable_present_end']['duration_ms']
        if 'gpu_commit' in vs:row['schedule_to_present_ms']=(vs['drawable_present_begin']['t']-vs['gpu_commit']['t'])*1000
    if 'decoded' in vs:
        decode=vs['decoded'];row['decode_ms']=(decode['t']-decode['render_start'])*1000
        row['render_queue_ms']=(decode['render_start']-decode['arrival'])*1000
    row['presented']=vs.get('presented',{}).get('presented_time',0)>0
    frames.append(row)

def summary(values):
    s=sorted(values)
    if not s:return None
    def q(p):return s[min(len(s)-1,int((len(s)-1)*p))]
    return {'mean':statistics.mean(s),'p50':q(.5),'p95':q(.95),'p99':q(.99),'max':max(s)}
capture=[x for x in h if x['event']=='capture' and start<=x['wall']<=end]
complete=[x for x in capture if x['status']==0]
source_times=[x['display'] for x in complete if x.get('display',-1)>=0]
callback_times=[x['t'] for x in complete]
stats={k:summary([x[k] for x in frames if k in x]) for k in sorted({k for x in frames for k in x if k.endswith('_ms')})}
stats['capture_callback_gap_ms']=summary([(b-a)*1000 for a,b in zip(callback_times,callback_times[1:])])
stats['source_display_gap_ms']=summary([(b-a)*1000 for a,b in zip(source_times,source_times[1:]) if b>a])
stats['callback_minus_display_ms']=summary([(x['t']-x['display'])*1000 for x in complete if x.get('display',-1)>=0])
presentations=sorted(x['presented_time'] for x in v if x['event']=='presented' and x.get('seq') in sequences and x.get('presented_time',0)>0)
stats['presentation_gap_ms']=summary([(b-a)*1000 for a,b in zip(presentations,presentations[1:])])
packets=[x for x in h if x['event']=='packed' and x['seq'] in sequences]
report={'seconds':duration,'sent_frames':len(sequences),'matched_frames':len(frames),'capture_fps':len(complete)/duration,'delivered_fps':len(frames)/duration,'presented_fps':sum(x['presented'] for x in frames)/duration,'payload_mbps':sum(x['bytes'] for x in packets)*8/duration/1e6,'idle_callbacks':sum(x['status']==1 for x in capture),'idle_with_image':sum(x['status']==1 and x.get('image',False) for x in capture),'backpressure_skips':sum(x['event']=='capture_backpressure' and start<=x['wall']<=end for x in h),'stats':stats,'slowest_frames':sorted(frames,key=lambda x:x['cycle_ms'],reverse=True)[:12]}
report['tail_counts']={str(ms):sum(x['cycle_ms']>ms for x in frames) for ms in [33.34,50,100,200]}
(d/'stall-analysis.json').write_text(json.dumps(report,indent=2))
print(d.name,'capture',round(report['capture_fps'],2),'delivered',round(report['delivered_fps'],2),'presented',round(report['presented_fps'],2),'matched',len(frames),'of',len(sequences),'idle images',report['idle_with_image'])
for key,x in stats.items():
    if x:print(key,'mean',round(x['mean'],3),'p95',round(x['p95'],3),'p99',round(x['p99'],3),'max',round(x['max'],3))
print('Worst frame:',report['slowest_frames'][0] if frames else None)
