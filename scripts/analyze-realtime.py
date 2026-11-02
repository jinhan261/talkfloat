#!/usr/bin/env python3
"""Compare visibly selected previews against cloud segments in the same audio clock.
Matches need the cloud segment's first three words inside an overlapping local
hypothesis. This is a matched-sample latency comparison, not an accuracy score.
"""
import pathlib,json,statistics,re,math,sys
p=pathlib.Path(sys.argv[1]);rows=[json.loads(x) for x in (p/'events.ndjson').read_text().splitlines()]
def norm(t):return ' '.join(re.findall(r'[a-z0-9]+',t.lower()))
def stats(xs):
 xs=sorted(xs)
 return {'n':len(xs),'median':round(statistics.median(xs),3),'p95':round(xs[math.ceil(.95*len(xs))-1],3),'max':round(max(xs),3)} if xs else {}
report={'method':__doc__,'channels':[],'failures':[r for r in rows if 'failure' in r['kind']]}
for sid in dict.fromkeys(r.get('session') for r in rows if r.get('session')):
 rs=[r for r in rows if r.get('session')==sid];sent=[r for r in rs if r['kind']=='audio-send']
 if not sent:continue
 anchor=statistics.median(r['sendUptime']-r['audioEndMS']/1000 for r in sent)
 displays=[r for r in rs if r['kind']=='preview-display']
 local=[r for r in rs if r['kind']=='local-translation']
 first={}
 for r in rs:
  if r['kind']=='event' and r['type'] in [654,655] and r.get('text'):
   first.setdefault(r['startMS'],r['receivedUptime'])
 matches=[]
 for r in rs:
  if r['kind']!='event' or r['type']!=652 or not r['text']:continue
  cloud=first.get(r['startMS']); words=norm(r['text']).split();prefix=' '.join(words[:min(3,len(words))])
  if cloud is None or len(words)<2:continue
  candidates=[d for d in displays if d['endMS']>=r['startMS']+200 and d['startMS']<=r['endMS'] and d['uptime']>=anchor+r['startMS']/1000 and prefix in norm(d['source']) and d['uptime']<=cloud]
  if not candidates:continue
  d=min(candidates,key=lambda x:x['uptime'])
  matches.append({'audioStartSec':r['startMS']/1000,'duration':(r['endMS']-r['startMS'])/1000,'source':r['text'],'previewSource':d['source'],'previewChinese':d['text'],'previewFromStart':d['uptime']-anchor-r['startMS']/1000,'cloudFromStart':cloud-anchor-r['startMS']/1000,'gain':cloud-d['uptime']})
 report['channels'].append({'origin':sent[0]['origin'],'session':sid,'previewUpdates':len(displays),'translateMS':stats([r['translateMS'] for r in local]),'previewAudioEndToDisplayMS':stats([(r['uptime']-anchor)*1000-r['endMS'] for r in displays]),'matchedPreviewStartSec':stats([x['previewFromStart'] for x in matches]),'matchedCloudStartSec':stats([x['cloudFromStart'] for x in matches]),'gainSec':stats([x['gain'] for x in matches]),'queueMS':stats([r['queueMS'] for r in sent]),'byTwoMinutes':{str(k):stats([(r['uptime']-anchor)*1000-r['endMS'] for r in displays if k*120<=r['endMS']/1000<(k+1)*120]) for k in range(6)},'longExamples':sorted(matches,key=lambda x:x['duration'],reverse=True)[:8],'matches':matches})
(p/'realtime-analysis.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
print(json.dumps({**report,'channels':[{k:v for k,v in c.items() if k not in ['matches','longExamples']} for c in report['channels']]},ensure_ascii=False,indent=2))
