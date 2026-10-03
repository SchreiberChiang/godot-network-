#!/usr/bin/env python3
"""Lightweight validation, Python standard library only."""
from pathlib import Path
import array, hashlib, json, math, sys, wave

ROOT = Path(__file__).resolve().parents[1]
LOOPS = ['engine_idle_loop', 'engine_drive_loop', 'tire_skid_loop', 'nitro_loop']

def validate():
    rows = []
    for path in sorted((ROOT/'audio').glob('*.wav')):
        with wave.open(str(path), 'rb') as w:
            params = w.getparams()
            raw = w.readframes(w.getnframes())
        samples = array.array('h', raw)
        if sys.byteorder != 'little': samples.byteswap()
        duration = len(samples)/48000
        isloop = path.stem in LOOPS
        limits = (1,2) if isloop else ((.15,.4) if path.stem=='impact_soft' else (.1,.25))
        peak = max(abs(x) for x in samples)/32768
        steps = [abs(samples[i]-samples[i-1]) for i in range(1,len(samples))]
        seam = abs(samples[0]-samples[-1])/32768
        checks = {'format': params.nchannels==1 and params.sampwidth==2 and params.framerate==48000 and params.comptype=='NONE',
                  'duration':limits[0]<=duration<=limits[1], 'finite':all(math.isfinite(x) for x in samples),
                  'no_clipping':peak<.98, 'non_silent':peak>.01}
        if isloop:
            checks['seam_step'] = seam<=.08 and seam<=max(steps)/32768
            with wave.open(str(ROOT/'audition'/(path.stem+'_3x.wav')), 'rb') as w:
                checks['repeat3_exact'] = w.readframes(w.getnframes())==raw*3
        rows.append({'file':path.name,'bytes':path.stat().st_size,'seconds':duration,'peak':peak,
                     'peak_dbfs':20*math.log10(peak),'dc':sum(samples)/len(samples)/32768,
                     'seam_step':seam if isloop else None,'max_adjacent_step':max(steps)/32768,'checks':checks})
    assert len(rows)==6
    result={'passed':all(all(r['checks'].values()) for r in rows),'files':rows,
            'six_wav_bytes':sum(r['bytes'] for r in rows),'listening':'NOT PERFORMED; signal checks are not listening'}
    assert result['six_wav_bytes']<=2*1024*1024
    print(json.dumps(result,ensure_ascii=False,indent=2))
    return result['passed']

if __name__=='__main__':
    raise SystemExit(0 if validate() else 1)
