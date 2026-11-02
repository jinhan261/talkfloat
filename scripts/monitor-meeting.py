import json, pathlib, time, subprocess, sys
out=pathlib.Path(sys.argv[1]).resolve() if len(sys.argv)>1 else pathlib.Path(__file__).resolve().parents[1]/'docs/meeting-microphone-2026-11-01/long-run'
pid=int(subprocess.check_output(['pgrep','-x','Saylori']).strip())
start=time.time();(out/'playback-start.json').write_text(json.dumps({'wall':start,'mediaSeconds':0,'url':'https://www.federalreserve.gov/monetarypolicy/fomcpresconf20240612.htm','normalSpeed':True,'pid':pid}))
with (out/'performance.ndjson').open('w') as f:
    for _ in range(620):
        row=subprocess.check_output(['ps','-p',str(pid),'-o','pcpu=,rss=,time=']).decode().split()
        f.write(json.dumps({'wall':time.time(),'elapsed':time.time()-start,'cpu':float(row[0]),'rssKB':int(row[1]),'cpuTime':row[2]})+'\n');f.flush();time.sleep(1)
(out/'ten-minutes-elapsed').touch()
