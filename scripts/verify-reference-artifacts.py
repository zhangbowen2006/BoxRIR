"""Independent C++ reference -> exported WAV -> SciPy convolution comparison.

Run with the isolated Python containing rir-generator 0.3.0, NumPy and SciPy.
No alignment, normalization or fitted gains are applied.
"""
import json
import argparse
from pathlib import Path
import numpy as np
import rir_generator as rir
from scipy.io import wavfile
from scipy.signal import fftconvolve

assert rir.__version__ == '0.3.0'
root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--directory', type=Path, default=root / 'generated/reference-workflows')
output = parser.parse_args().directory
records = []
for name in ('reference-omni', 'reference-cardioid', 'reference-2d'):
    scene = json.loads((root / 'examples' / (name + '.json')).read_text())
    folder = output / name
    report = json.loads((folder / 'report.json').read_text())
    parameters = dict(c=scene['speed'], fs=scene['sample_rate'], r=scene['receivers'],
                      s=scene['source'], L=scene['room'], nsample=scene['nsample'],
                      order=scene['max_order'], dim=scene.get('dimension', 3),
                      mtype=getattr(rir.mtype, scene['microphone']),
                      orientation=scene['orientation'], hp_filter=scene['high_pass'])
    for key in ('beta', 'reverberation_time'):
        if key in scene:
            parameters[key] = scene[key]
    expected = rir.generate(**parameters)
    rate, actual = wavfile.read(folder / 'rir.wav')
    dry_rate, dry = wavfile.read(root / 'examples' / 'probe.wav')
    wet_rate, wet = wavfile.read(folder / 'wet.wav')
    assert rate == dry_rate == wet_rate == scene['sample_rate']
    assert actual.dtype == wet.dtype == np.float32
    assert actual.shape == expected.shape
    assert actual.shape[0] == scene['nsample']
    assert report['config']['latency_samples'] == 0
    assert wet.shape == (len(dry) + scene['nsample'] - 1, expected.shape[1])
    rir_error = float(np.max(np.abs(actual - expected)))
    assert np.allclose(actual, expected, atol=1e-8, rtol=1e-6)
    wet_errors = []
    for channel in range(expected.shape[1]):
        independent = fftconvolve(dry.astype(float), expected[:, channel])
        error = float(np.max(np.abs(wet[:, channel] - independent)))
        assert np.allclose(wet[:, channel], independent, atol=1e-8, rtol=1e-6)
        wet_errors.append(error)
    records.append(dict(scene=name, frames=len(actual), channels=actual.shape[1],
                        wet_frames=len(wet), maximum_rir_error=rir_error,
                        maximum_wet_errors=wet_errors, paths_truncated=report['paths_truncated']))
result = dict(reference='unmodified rir-generator 0.3.0 binary', comparison='same sample indices; no normalization, alignment or fitted gain', cases=records)
(output / 'verification.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
print(json.dumps(result))
