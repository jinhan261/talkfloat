#!/usr/bin/env python3
"""Audit received event-to-archive equality, then locate reference differences.
The reference comparison is an aid for manual review, not a translation score.
"""
import json,pathlib,re,sys,difflib,collections
out=pathlib.Path(sys.argv[1]);status=json.loads((out/'status.json').read_text())
record=json.loads(pathlib.Path(status['archivePath']).with_suffix('.json').read_text())
rows=[json.loads(x) for x in (out/'events.ndjson').read_text().splitlines()]
audit={}
for origin in ['system','microphone']:
 segments=[s for s in record['segments'] if s.get('origin','system')==origin and (s['source'] or s['translation'])]
 source=[s['source'] for s in segments if s['sourceFinal']]
 target=[s['translation'] for s in segments if s['translationFinal']]
 sourceEvents=[e['text'] for e in rows if e.get('origin')==origin and e.get('type')==652 and e['text']]
 targetEvents=[e['text'] for e in rows if e.get('origin')==origin and e.get('type')==655 and e['text']]
 audit[origin]={'segments':len(segments),'sourceFinals':len(source),'targetFinals':len(target),'sourceEventsEqualArchive':source==sourceEvents,'translationEventsEqualArchive':target==targetEvents,'missingSource':sum(not s['source'] for s in segments),'missingTranslation':sum(not s['translation'] for s in segments),'partial':sum(not s['sourceFinal'] or not s['translationFinal'] for s in segments)}
md=pathlib.Path(status['archivePath']).read_text()
audit['emptyProtocolSegments']=sum(not s['source'] and not s['translation'] for s in record['segments'])
normalize=lambda text: re.sub(r'\s+', ' ', text).strip()
audit['mdHasEverySourceAndTranslation']=all(normalize(s['source']) in normalize(md) and normalize(s['translation']) in normalize(md) for s in record['segments'])
audit['ended']=record.get('endedAt') is not None;audit['interruptions']=record.get('interruptions',[])
reference=(out.parent/'reference.txt').read_text()
reference=' '.join(l.strip() for l in reference.splitlines() if not re.search(r'June 12, 2024|Page \d+ of|Transcript of Chair',l))
reference=reference.replace('CHAIR POWELL.','')
sourceText=' '.join(s['source'] for s in record['segments'] if s.get('origin','system')=='system')
contractions={"i'll":"i will","we'll":"we will","we're":"we are","we've":"we have","that's":"that is","it's":"it is","isn't":"is not","doesn't":"does not","don't":"do not","can't":"cannot","won't":"will not","haven't":"have not","there's":"there is","you're":"you are","didn't":"did not"}
def tokens(t):
 t=t.lower().replace('’',"'")
 for a,b in contractions.items():t=t.replace(a,b)
 t=t.replace('%',' percent')
 return [re.sub(r'\.0$','',x.replace(',','')) if x[0].isdigit() else x for x in re.findall(r"[a-z]+(?:'[a-z]+)?|\d+(?:[.,]\d+)*",t)]
a=tokens(reference);b=tokens(sourceText)
matcher=difflib.SequenceMatcher(None,a,b,autojunk=False)
blocks=[m for m in matcher.get_matching_blocks() if m.size>=4]
if blocks:
 start=blocks[0].a;end=blocks[-1].a+blocks[-1].size
 a=a[start:end]
 matcher=difflib.SequenceMatcher(None,a,b,autojunk=False)
 diffs=[]
 for op,i,j,k,l in matcher.get_opcodes():
  if op!='equal':diffs.append({'type':op,'refTokens':j-i,'reference':' '.join(a[i:j]),'recognized':' '.join(b[k:l]),'before':' '.join(a[max(0,i-8):i])})
 audit['reference']={'referenceTokens':len(a),'recognizedTokens':len(b),'differences':diffs,'note':'Normalized lexical comparison only; punctuation, numerals, speaker labels and spoken corrections differ from the edited PDF. No accuracy percentage inferred.'}
(out/'archive-audit.json').write_text(json.dumps(audit,ensure_ascii=False,indent=2))
print(json.dumps({k:v for k,v in audit.items() if k!='reference'},ensure_ascii=False,indent=2))
print('Reference differences:')
for d in audit.get('reference',{}).get('differences',[]):print(d)
