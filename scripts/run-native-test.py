#!/usr/bin/env python3
"""Run the app's opt-in integration harness with a fixed, non-private audio fixture."""
import sys,subprocess,time,json,os
from pathlib import Path
root=Path(__file__).resolve().parent.parent
out=Path(sys.argv[1]).resolve()
out.mkdir(parents=True,exist_ok=True)
if '--app' in sys.argv:
 app=Path(sys.argv[sys.argv.index('--app')+1]).expanduser().resolve()
else:
 installed=[p for p in (Path('/Applications/TalkFloat.app'),Path.home()/'Applications/TalkFloat.app') if p.is_dir()]
 if len(installed)!=1:raise RuntimeError('Specify --app PATH when no installation or multiple installations exist')
 app=installed[0]
if not (app/'Contents/MacOS/TalkFloat').is_file():raise RuntimeError('TalkFloat executable not found in --app')
args=['--self-test',str(out)]
args.append('--pin-test-popover')
if '--engine' in sys.argv:args.extend(['--engine',sys.argv[sys.argv.index('--engine')+1]])
if '--dark' in sys.argv:args.append('--dark-appearance')
if '--chrome' in sys.argv:args.append('--chrome-test')
if '--with-microphone' in sys.argv:args.append('--with-microphone')
subprocess.run(['/usr/bin/open','-n','-a',str(app),'--stdout',str(out/'app-console.log'),'--stderr',str(out/'app-console.log'),'--args',*args],check=True)
pid=None
for _ in range(50):
 for line in subprocess.check_output(['/bin/ps','-axo','pid=,command='],text=True).splitlines():
  number,_,command=line.strip().partition(' ')
  if command.startswith(str(app/'Contents/MacOS/TalkFloat')) and str(out) in command:pid=int(number);break
 if pid is not None:break
 time.sleep(.1)
if pid is None:raise RuntimeError('App process not found')
(out/'pid').write_text(str(pid))
last=None;played=set();player=None;marker=None;playbacks=[];metrics=[];completed=False
try:
 for tick in range(3000):
  try:os.kill(pid,0)
  except ProcessLookupError:print('App exited',flush=True);break
  try:state=json.loads((out/'status.json').read_text())
  except (FileNotFoundError,json.JSONDecodeError):time.sleep(.1);continue
  stage=state.get('stage')
  if tick%10==0:
   usage=subprocess.run(['/bin/ps','-p',str(pid),'-o','%cpu=,rss='],capture_output=True,text=True).stdout.split()
   if len(usage)==2:metrics.append({'time':time.time(),'stage':stage,'cpu':float(usage[0]),'rssMiB':int(usage[1])/1024})
  key=(stage,state.get('phase'),state.get('error'))
  if key!=last:print(json.dumps(state,ensure_ascii=False),flush=True);last=key
  if stage in ('listening','resumed') and stage not in played and '--chrome' not in sys.argv:
   playbacks.append({'stage':stage,'started':time.time(),'fixture':'english-meeting-v2.aiff'})
   player=subprocess.Popen(['/usr/bin/afplay',str(root/'native/Tests/Fixtures/english-meeting-v2.aiff')],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
   marker='first-finished' if stage=='listening' else 'second-finished';played.add(stage)
   print('Playing known English fixture:',stage,flush=True)
  if player is not None and player.poll() is not None:
   if player.returncode:raise RuntimeError('Fixture playback failed')
   playbacks[-1]['finished']=time.time()
   (out/marker).touch();player=None
  if stage in ('completed','failed','timeout'):
   completed=stage=='completed';break
  time.sleep(.1)
 else:print('Harness timed out',flush=True)
finally:
 if player is not None and player.poll() is None:player.terminate()
 (out/'playbacks.json').write_text(json.dumps(playbacks,indent=2))
 (out/'performance.json').write_text(json.dumps(metrics,indent=2))
 print('App left running for native UI inspection; PID',pid,flush=True)
if not completed:sys.exit(1)
