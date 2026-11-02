#!/usr/bin/env python3
"""Trace clocks measure service segment latency, not human speech-boundary delay."""
import json,sys,pathlib,statistics,math,collections
root=pathlib.Path(sys.argv[1]);rows=[json.loads(x) for x in (root/'events.ndjson').read_text().splitlines()]
def stats(a):
 a=sorted(a)
 return {'n':len(a),'median':round(statistics.median(a),3),'p95':round(a[math.ceil(.95*len(a))-1],3),'max':round(max(a),3)} if a else {}
report={'sessions':[],'errors':[r for r in rows if 'failure' in r['kind']]}
for sid in dict.fromkeys(r.get('session') for r in rows if r.get('session')):
 rs=[r for r in rows if r.get('session')==sid];sends=[r for r in rs if r['kind']=='audio-send'];ev=[r for r in rs if r['kind']=='event']
 if not sends:continue
 anchor=statistics.median(r['sendUptime']-r['audioEndMS']/1000 for r in sends)
 groups=[];current=None
 for r in ev:
  if r['type']==653:current={'first':None,'start':r['startMS'],'end':0};groups.append(current)
  if r['type']==654 and current and current['first'] is None:current['first']=r['receivedUptime']
  if r['type']==655 and current:current['end']=r['endMS'];current['first']=current['first'] or r['receivedUptime']
 lat=[{'audioSec':g['end']/1000,'ms':1000*(g['first']-anchor)-g['end'],'fromStartMS':1000*(g['first']-anchor)-g['start']} for g in groups if g['end'] and g['first']]
 report['sessions'].append({'id':sid,'origin':sends[0]['origin'],'audioSec':sends[-1]['audioEndMS']/1000,'sourceFinals':sum(r['type']==652 for r in ev),'translationFinals':sum(r['type']==655 for r in ev),'queueMS':stats([r['queueMS'] for r in sends]),'sendMS':stats([r['sendMS'] for r in sends]),'mainActorMS':stats([r['displayLagMS'] for r in ev]),'semanticEndToFirstChineseMS':stats([x['ms'] for x in lat]),'semanticStartToFirstChineseMS':stats([x['fromStartMS'] for x in lat]),'byTwoMinutes':{str(k):stats([x['ms'] for x in lat if k*120<=x['audioSec']<(k+1)*120]) for k in range(6)},'measurements':lat})
(root/'analysis.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps({**report,'sessions':[{k:v for k,v in s.items() if k!='measurements'} for s in report['sessions']]},ensure_ascii=False,indent=2))
