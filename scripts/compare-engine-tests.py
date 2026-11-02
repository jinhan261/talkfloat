#!/usr/bin/env python3
"""Match identical opening five words across completed real-video engine runs.

Only opening prefixes are compared, not completion of entire sentences. Model
audio starts differ slightly; timings are approximate. Unmatched examples are
excluded, and this is not a quality/accuracy score.
"""
import json,re,statistics,math,sys,collections
from pathlib import Path

local=json.loads((Path(sys.argv[1])/'engine-analysis.json').read_text())
cloud=json.loads((Path(sys.argv[2])/'engine-analysis.json').read_text())
def prefix(text):
    text=text.lower().replace('’',"'")
    for a,b in {"we're":"we are","we've":"we have","we'll":"we will","that's":"that is","it's":"it is"}.items():text=text.replace(a,b)
    words=re.findall(r"[a-z]+|\d+",text)
    return tuple(words[:5]) if len(words)>=5 else None
def index(turns):
    result=collections.defaultdict(list)
    for t in turns:
        if t.get('origin','system')=='system' and prefix(t['source']):result[prefix(t['source'])].append(t)
    return result
def summary(values):
    values=sorted(values)
    if not values:return None
    return {'n':len(values),'median':round(statistics.median(values),3),'p95':round(values[math.ceil(len(values)*.95)-1],3),'max':round(values[-1],3)}
a=index(local['turns']);b=index(cloud['turns']);pairs=[]
for key,values in a.items():
    if len(values)!=1 or len(b.get(key,[]))!=1:continue
    x,y=values[0],b[key][0]
    pairs.append({'prefix':' '.join(key),'localSource':x['source'],'doubaoSource':y['source'],
                  'localSeconds':x['readableAfterStartSeconds'],'doubaoSeconds':y['readableAfterStartSeconds'],
                  'localFirst':x['firstText'],'doubaoFirst':y['firstText'],
                  'localTranslation':x['translation'],'doubaoTranslation':y['translation']})
report={'scope':__doc__,'readableDefinition':'At least four Han characters; shorter complete captions use their available/final event. Not semantic correctness.',
        'localSeconds':summary([x['localSeconds'] for x in pairs]),
        'doubaoSeconds':summary([x['doubaoSeconds'] for x in pairs]),
        'earlierBySeconds':summary([x['doubaoSeconds']-x['localSeconds'] for x in pairs]),'pairs':pairs}
destination=Path(sys.argv[3]) if len(sys.argv)>3 else Path(sys.argv[1]).parent/'comparison.json'
destination.write_text(json.dumps(report,ensure_ascii=False,indent=2))
print(json.dumps({k:v for k,v in report.items() if k!='pairs'},ensure_ascii=False,indent=2))
