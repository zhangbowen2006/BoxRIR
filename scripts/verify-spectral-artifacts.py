"""File-level spectral check using separately validated geometry reports.

Unlike the independent first-order golden, this reconstruction reads path
geometry from the report. It independently checks per-band loss/FIR/WAV/SciPy
convolution and does not claim independent high-order geometry validation.
"""
import argparse, importlib.util, json, math
from pathlib import Path
import numpy as np
from scipy.io import wavfile
from scipy.signal import firwin, fftconvolve
root=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser();parser.add_argument('--directory',type=Path,default=root/'generated/spectral-workflows');folder=parser.parse_args().directory
spec=importlib.util.spec_from_file_location('independent_spectral',root/'tests/reference/generate_spectral.py');reference=importlib.util.module_from_spec(spec);spec.loader.exec_module(reference)
records=[]
for name in ('spectral-before','spectral-after','spectral-prism'):
    scene=json.loads((root/'examples'/(name+'.json')).read_text(encoding='utf-8'))
    report=json.loads((folder/name/'report.json').read_text(encoding='utf-8'));config=report['config']
    assert not report['paths_truncated']
    fs,actual=wavfile.read(folder/name/'rir.wav');wet_rate,wet=wavfile.read(folder/name/'wet.wav');dry_rate,dry=wavfile.read(root/'examples/probe.wav')
    assert fs==wet_rate==dry_rate==scene['sample_rate']
    half=scene.get('half_width',16);bank_half=math.ceil(256*fs/16000)
    frames=math.ceil(fs*scene['duration_ms']/1000);raw=np.zeros((6,len(scene['receivers']),frames+2*half))
    air=reference.air_loss(scene['atmosphere']) if 'atmosphere' in scene else np.asarray(scene.get('air_db_per_m',[0]*6))
    materials=np.asarray(scene['band_absorption'])
    for row in report['band_paths']:
        path=row['path'];distance=path['distance']
        gains=np.prod(np.sqrt(1-materials)**np.asarray(path['bounces'])[:,None],axis=0)*np.exp(-math.log(10)*air*distance/20)/(4*math.pi*distance)
        assert np.allclose(gains,row['band_gains'],atol=1e-12,rtol=1e-10)
        arrival=path['delay_samples']
        if arrival>=frames:continue
        base=math.floor(arrival);t=np.arange(-half,half+1)-(arrival-base)
        taps=np.sinc(t)*.5*(1+np.cos(np.pi*t/half));taps[np.abs(t)>half]=0;taps/=taps.sum()
        raw[:,path['receiver'],base:base+len(taps)]+=gains[:,None]*taps
    low=[firwin(2*bank_half+1,f,fs=fs,window='hamming') for f in np.sqrt(reference.CENTERS[:-1]*reference.CENTERS[1:])]
    delta=np.zeros(2*bank_half+1);delta[bank_half]=1
    filters=[low[0]]+[low[b]-low[b-1] for b in range(1,5)]+[delta-low[-1]]
    expected=np.stack([sum(fftconvolve(raw[b,ch],filters[b]) for b in range(6)) for ch in range(len(scene['receivers']))],axis=1)
    assert actual.shape==expected.shape and actual.dtype==np.float32
    assert np.allclose(actual,expected,atol=1e-8,rtol=1e-6)
    independent=np.stack([fftconvolve(dry.astype(float),expected[:,ch]) for ch in range(expected.shape[1])],axis=1)
    assert wet.shape==independent.shape and np.allclose(wet,independent,atol=1e-8,rtol=1e-6)
    assert config['latency_samples']==half+bank_half
    records.append({'scene':name,'channels':actual.shape[1],'rir_frames':len(actual),'wet_frames':len(wet),'maximum_rir_error':float(np.max(np.abs(actual-expected))),'maximum_wet_error':float(np.max(np.abs(wet-independent)))})
result={'scope':'report-driven spectral synthesis and actual WAV/convolution; geometry independently checked by other tests','cases':records}
(folder/'verification.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
print(json.dumps(result))
