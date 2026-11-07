"""Pin complete waveforms from the unmodified upstream binary, not our port.

Requires rir-generator==0.3.0 and NumPy. These are synthetic development tests,
not measured rooms or external user deployments. Output is channel-major f64 LE.
"""
import base64
import hashlib
import json
from pathlib import Path
import numpy as np
import rir_generator as rir

assert rir.__version__ == '0.3.0'
base = dict(model='audiolabs_v030', room=[6, 4, 3], source=[1.37, 1.21, 1.13],
            receivers=[[3.82, 2.31, 1.74], [2.43, 1.57, 1.42]], sample_rate=8000,
            speed=343, nsample=512, beta=[.9, .8, .7, .6, .5, .4], max_order=3)
cases = []

def add(name, **overrides):
    scene = {**base, **overrides}
    if scene.get('beta') is None:
        scene.pop('beta')
    if scene.get('nsample') is None:
        scene.pop('nsample')
    arguments = dict(c=scene['speed'], fs=scene['sample_rate'], r=scene['receivers'],
                     s=scene['source'], L=scene['room'], order=scene['max_order'],
                     dim=scene.get('dimension', 3), hp_filter=scene.get('high_pass', True),
                     mtype=getattr(rir.mtype, scene.get('microphone', 'o')))
    for key in ('beta', 'nsample', 'reverberation_time', 'orientation'):
        if key in scene:
            arguments[key] = scene[key]
    expected = rir.generate(**arguments)
    assert np.isfinite(expected).all()
    raw = np.asarray(expected.T, dtype='<f8').tobytes()
    cases.append(dict(name=name, scene=scene, channels=expected.shape[1], frames=expected.shape[0],
                      float64_le=base64.b64encode(raw).decode('ascii'), sha256=hashlib.sha256(raw).hexdigest()))

for pattern in ('o', 'b', 'c', 's', 'h'):
    for dimension in (2, 3):
        for high_pass in (False, True):
            add(f'{pattern}-dim{dimension}-hp{int(high_pass)}', microphone=pattern,
                dimension=dimension, high_pass=high_pass, orientation=[1.1, .4])
for order in (-1, 0, 1, 2, 4):
    add('order-' + str(order), max_order=order, high_pass=False)
add('negative-pressure', beta=[-.9, .8, -.7, .6, -.5, .4], max_order=-1)
add('zero-walls', beta=[.9, 0, .7, 0, .5, 0], max_order=-1)
add('lossless-explicit-window', beta=[1] * 6, max_order=-1)
add('rt60-explicit-window', beta=None, reverberation_time=.3)
add('rt60-default-window', beta=None, reverberation_time=.2, nsample=None, max_order=2)
add('beta-default-window', nsample=None, max_order=1)
add('fractional-room-default-window', room=[5.7, 4.3, 3.1], beta=[.97, .96, .95, .94, .93, .92], nsample=None, max_order=2, speed=346)
add('anechoic', beta=None, reverberation_time=0, max_order=-1)
add('nonstandard-rate', sample_rate=11025, speed=340, orientation=[-.7], microphone='h')
add('48k-kernel', sample_rate=48000, nsample=768, max_order=1)
add('96k-kernel', sample_rate=96000, nsample=1024, max_order=1)
add('small-window-clipped-kernel', room=[4, 4, 3], source=[1, 1, 1], receivers=[[1.02, 1, 1]],
    beta=[0] * 6, nsample=32, high_pass=False, max_order=-1)
add('outside-short-window', nsample=1, max_order=0)
add('wall-pairs', beta=[[.9, .8], [.7, .6], [.5, .4]], max_order=2)

report = dict(reference='audiolabs/rir-generator', version=rir.__version__,
              upstream_tag='v0.3.0', upstream_commit='052790faade19074c6921e007fb8972c60e8f0a6',
              numpy=np.__version__, comparison='all samples, no alignment, normalization or correlation fit', cases=cases)
target = Path(__file__).with_name('audiolabs-0.3.0.json')
target.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8', newline='\n')
embedded = Path(__file__).resolve().parents[2] / 'cmd' / 'reference-parity' / 'fixtures.mbt'
embedded.write_text('// GENERATED test data, not implementation code. Regenerate with tests/reference/generate_audiolabs.py.\n///|\nlet reference_fixture_text : String =\n' + '\n'.join('  #|' + line for line in json.dumps(report, indent=2).splitlines()) + '\n', encoding='utf-8', newline='\n')
print(json.dumps({'cases': len(cases), 'samples': sum(c['frames'] * c['channels'] for c in cases),
                  'fixture_sha256': hashlib.sha256(target.read_bytes()).hexdigest()}))
