#!/usr/bin/env python3
"""Analyze opt-in diagnostic timing; never reads credentials or private recordings."""
import json,sys,statistics,math
from pathlib import Path
out=Path(sys.argv[1]);events=json.loads((out/'events.json').read_text())
def summary(a):
 a=sorted(a)
 return {'n':len(a),'median':round(statistics.median(a),3),'p95':round(a[min(len(a)-1,math.ceil(len(a)*.95)-1)],3),'max':round(max(a),3)} if a else None
runs=[];run=None
for e in events:
 if e['kind']=='connection-ready':
  run={'frames':[],'translations':[],'active':None};runs.append(run)
 if not run:continue
 if e['kind']=='audio-send':run['frames'].append(e)
 if e['kind']=='event':
  if e['type']==653:run['active']={'startMS':e['startMS']}
  if e['type']==654 and e['text'] and run['active'] is not None:run['active'].setdefault('first',e['receivedUptime'])
  if e['type']==655 and run['active'] is not None:
   run['active'].update(endMS=e['endMS'],final=e['receivedUptime'],text=e['text']);run['translations'].append(run['active']);run['active']=None
latencies=[]
for r in runs:
 if not r['frames']:continue
 # Approximate audio clock from paced captured samples; send timestamps include normal scheduling jitter.
 anchor=statistics.median(f['sendUptime']-f['audioEndMS']/1000 for f in r['frames'])
 for t in r['translations']:
  if t['endMS']>0 and 'first' in t:
   t['firstAfterServerAudioEndMS']=round(1000*(t['first']-anchor)-t['endMS'],2)
   t['finalAfterServerAudioEndMS']=round(1000*(t['final']-anchor)-t['endMS'],2)
   latencies.append(t['firstAfterServerAudioEndMS'])
frames=[e for e in events if e['kind']=='audio-send'];messages=[e for e in events if e['kind']=='event']
report={'queueAgeMS':summary([e['queueMS'] for e in frames]),'websocketSendMS':summary([e['sendMS'] for e in frames]),'decodedEventToMainActorMS':summary([e['displayLagMS'] for e in messages]),'firstChineseAfterServerAudioEndMS':summary(latencies),'translations':[t for r in runs for t in r['translations']],'timingScope':'Service-provided audio end timestamp and paced upload clock; not manually annotated phrase end or frame-to-photon latency. Small synthetic sample, not a meeting SLA.'}
(out/'latency.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps(report,ensure_ascii=False,indent=2))
