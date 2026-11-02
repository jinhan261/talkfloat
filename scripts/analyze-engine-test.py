#!/usr/bin/env python3
"""Summarize engine events against their captured-audio clocks.

These are model-available text timings, not manually annotated acoustic latency
or frame-to-photon measurements. Different engine segmentation is kept explicit.
"""
import collections,json,math,statistics,sys,re
from pathlib import Path

out=Path(sys.argv[1])
events=[json.loads(line) for line in (out/'events.ndjson').read_text().splitlines()]
status=json.loads((out/'status.json').read_text())
record=json.loads(Path(status['archivePath']).with_suffix('.json').read_text())
engine=record.get('engine','doubao')
frames=[e for e in events if e['kind']=='audio-send']
anchors={}
for e in frames:anchors.setdefault(e['session'],[]).append(e['sendUptime']-e['audioEndMS']/1000)
anchors={key:statistics.median(value) for key,value in anchors.items()}
def summary(values):
    values=sorted(values)
    if not values:return None
    return {'n':len(values),'median':round(statistics.median(values),3),
            'p95':round(values[math.ceil(len(values)*.95)-1],3),'max':round(values[-1],3)}

def readable(text):return len(re.findall(r'[\u4e00-\u9fff]',text))>=4
turns=[]
if engine=='local':
    byID=collections.defaultdict(list)
    for e in events:
        if e['kind']=='caption-update':byID[e['id']].append(e)
    for segment in record['segments']:
        rows=byID[segment['id']]
        translated=[r for r in rows if r['text']]
        finals=[r for r in rows if r['translationFinal']]
        if not translated or not finals:continue
        firstReadable=next((r for r in translated if readable(r['text'])),translated[0])
        turns.append(dict(segment,first=translated[0]['uptime'],firstReadable=firstReadable['uptime'],final=finals[-1]['uptime'],firstText=translated[0]['text']))
else:
    pending={}
    for e in events:
        if e['kind']!='event':continue
        key=e['session']
        if e['type']==653:pending[key]={'sessionID':key,'origin':e['origin'],'startMS':e['startMS']}
        if e['type']==654 and e['text'] and key in pending:
            pending[key].setdefault('first',e['receivedUptime']);pending[key].setdefault('firstText',e['text'])
            pending[key]['accumulated']=pending[key].get('accumulated','')+e['text']
            if readable(pending[key]['accumulated']):pending[key].setdefault('firstReadable',e['receivedUptime'])
        if e['type']==655 and e['text'] and key in pending:
            turn=pending.pop(key);turn.update(endMS=e['endMS'],final=e['receivedUptime'],translation=e['text'])
            turn.setdefault('first',e['receivedUptime']);turn.setdefault('firstText',e['text']);turn.setdefault('firstReadable',e['receivedUptime'])
            match=next((s for s in record['segments'] if s['sessionID']==key and s['startMS']==turn['startMS']),None)
            turn['source']=match['source'] if match else ''
            turns.append(turn)
for turn in turns:
    anchor=anchors[turn['sessionID']]
    turn['firstAfterStartSeconds']=turn['first']-anchor-turn['startMS']/1000
    turn['finalAfterEndSeconds']=turn['final']-anchor-turn['endMS']/1000
    turn['readableAfterStartSeconds']=turn['firstReadable']-anchor-turn['startMS']/1000
    turn['segmentSeconds']=(turn['endMS']-turn['startMS'])/1000
report={'engine':engine,'scope':__doc__,'cloudConnections':sum(e['kind']=='cloud-connection' for e in events),
        'errors':[e for e in events if e['kind'] in ('failure','microphone-failure','local-failure')],
        'queueMS':summary([e['queueMS'] for e in frames]),
        'translationComputeMS':summary([e['translateMS'] for e in events if e['kind']=='local-translation']),
        'largestLocalTranslationQueue':max((e['pending'] for e in events if e['kind']=='local-translation'),default=0),
        'turns':turns}
for origin in ('system','microphone'):
    selected=[t for t in turns if t.get('origin','system')==origin]
    report[origin]={'queueMS':summary([e['queueMS'] for e in frames if e.get('origin')==origin]),'firstAfterSegmentStartSeconds':summary([t['firstAfterStartSeconds'] for t in selected]),
                    'finalAfterSegmentEndSeconds':summary([t['finalAfterEndSeconds'] for t in selected]),
                    'segmentSeconds':summary([t['segmentSeconds'] for t in selected]),
                    'twoMinuteFinalLatency':[]}
    for block in range(6):
        blockTurns=[t for t in selected if block*120000<=t['startMS']<(block+1)*120000]
        report[origin]['twoMinuteFinalLatency'].append(summary([t['finalAfterEndSeconds'] for t in blockTurns]))
(out/'engine-analysis.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
print(json.dumps({k:v for k,v in report.items() if k not in ('turns','scope')},ensure_ascii=False,indent=2))
