import json, pathlib, re, statistics, sys
for name in sys.argv[1:]:
    d=pathlib.Path('work/perf')/name
    source=json.loads((d/'source.json').read_text())['samples']
    host=json.loads((d/'host.json').read_text())
    metadata=json.loads((d/'test.json').read_text()) if (d/'test.json').exists() else None
    start=metadata['began'] if metadata else (host or json.loads((d/'viewer.json').read_text()))[0]['time']
    end=metadata.get('finished',start+len(source)) if metadata else start+len(source)
    print('\n'+name)
    drawn=[s['drawnFPS'] for s in source if s['elapsed']>5 and 'drawnFPS' in s]
    print('Source drawn fps:',round(statistics.mean(drawn),2) if drawn else 'Source presentation rate not independently measured; see issued-update counters in source.json')
    for role in ['host','viewer']:
        rows=[s for s in json.loads((d/(role+'.json')).read_text()) if s['kind']==role and s['time']>start+5 and s['time']<end-2]
        fields={'delivered':r'([\d.]+) delivered','capture':r'Capture ([\d.]+)', 'encode_ms':r'encode \+ pack ([\d.]+)', 'ack_ms':r'acknowledgement ([\d.]+)', 'rendered':r'([\d.]+) rendered', 'presented':r'Presentation ([\d.]+)', 'gpu_ms':r'GPU ([\d.]+)', 'unpack_ms':r'unpack ([\d.]+)', 'upload_ms':r'upload setup ([\d.]+)', 'queue_ms':r'queue ([\d.]+)', 'body_ms':r'body assembly ([\d.]+)','drawable_ms':r'Drawable wait ([\d.]+)', 'mbps':r'([\d.]+) Mbps','skips':r'backpressure skips (\d+)'}
        print(role,'samples',len(rows))
        for field,pattern in fields.items():
            vals=[float(m.group(1)) for s in rows if (m:=re.search(pattern,s['text']))]
            if vals: print(field, 'mean',round(statistics.mean(vals),2),'min',min(vals),'max',max(vals))
        if role=='host':
            for field,pattern in {'encoder_gpu_ms':r'Encoder GPU ([\d.]+)', 'gpu_submit_wait_ms':r'GPU submit/wait ([\d.]+)', 'tile_gather_ms':r'tile gather ([\d.]+)', 'packet_pack_ms':r'packet pack ([\d.]+)', 'source_gap_ms':r'Source display gap ([\d.]+)', 'callback_lag_ms':r'callback (?:age|lag) ([\d.]+)'}.items():
                vals=[float(m.group(1)) for s in rows if (m:=re.search(pattern,s['text']))]
                if vals: print(field,'mean',round(statistics.mean(vals),2),'min',min(vals),'max',max(vals))
