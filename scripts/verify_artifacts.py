"""Independent SciPy file/convolution checks for the three documented workflows."""
import argparse,json
from pathlib import Path
from importlib.metadata import version
import numpy as np
from scipy.io import wavfile
from scipy.signal import fftconvolve
import xml.etree.ElementTree as ET

root=Path(__file__).resolve().parent.parent
parser=argparse.ArgumentParser();parser.add_argument('--directory',type=Path,default=root/'outputs');args=parser.parse_args()
records=[]
for name in ['stereo','wall-before','wall-after','array']:
    folder=args.directory/name
    report=json.loads((folder/'report.json').read_text(encoding='utf-8'))
    config=report['config'];rate,samples=wavfile.read(folder/'rir.wav')
    assert samples.dtype==np.float32
    if samples.ndim==1:samples=samples[:,None]
    assert rate==config['sample_rate'] and samples.shape==(config['output_frames'],len(config['receivers']))
    assert np.isfinite(samples).all()
    image_count=report['geometric_images']
    for ch,position in enumerate(config['receivers']):
        assert report['contributing_paths'][ch]+report['omitted_late_paths'][ch]+report['zero_gain_paths'][ch]==image_count
        direct=next(p for p in report['paths'] if p['receiver']==ch and p['order']==0)
        d=float(np.linalg.norm(np.array(config['source'])-np.array(position)))
        assert np.isclose(d,direct['distance'],rtol=1e-12)
        assert np.isclose(d/config['speed']*rate,direct['delay_samples'],rtol=1e-12)
        assert np.isclose(1/(4*np.pi*d),direct['gain'],rtol=1e-12)
        gain=sum(p['gain'] for p in report['paths'] if p['receiver']==ch and p['delay_samples']<config['physical_frames'])
        assert np.isclose(samples[:,ch].sum(dtype=np.float64),gain,atol=1e-7,rtol=2e-6)
    ET.parse(folder/'response.svg')
    entry={'case':name,'channels':samples.shape[1],'rir_frames':len(samples),'gain_sum_verified':True}
    if name=='array':
        dry_rate,dry=wavfile.read(root/'examples/probe.wav');wet_rate,wet=wavfile.read(folder/'wet.wav')
        assert dry_rate==wet_rate==rate
        assert wet.shape==(len(dry)+len(samples)-1,samples.shape[1])
        errors=[]
        for ch in range(samples.shape[1]):
            expected=fftconvolve(dry.astype(np.float64),samples[:,ch].astype(np.float64))
            errors.append(float(np.max(np.abs(expected-wet[:,ch]))))
            assert np.allclose(expected,wet[:,ch],atol=1e-7,rtol=1e-5)
        entry.update(wet_frames=len(wet),scipy_max_absolute_errors=errors)
    records.append(entry)
before=json.loads((args.directory/'wall-before/report.json').read_text())
after=json.loads((args.directory/'wall-after/report.json').read_text())
for wall in range(6):
    bounces=[int(i==wall) for i in range(6)]
    a=next(p for p in before['paths'] if p['bounces']==bounces)
    b=next(p for p in after['paths'] if p['bounces']==bounces)
    assert a['delay_samples']==b['delay_samples']
    assert np.isclose(b['gain']/a['gain'],1/3 if wall==0 else 1,atol=1e-12)
result={'numpy':version('numpy'),'scipy':version('scipy'),'cases':records,'changed_wall_first_reflection_gain_ratio':1/3,'physical_measurements':False}
print(json.dumps(result,indent=2))
