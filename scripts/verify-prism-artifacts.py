"""Read actual CLI-produced WAV/CSV files and check convolution using SciPy."""
import csv
import argparse
import json
from pathlib import Path
import numpy as np
from scipy.io import wavfile
from scipy.signal import fftconvolve

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--directory', type=Path, default=root / 'generated/prism-workflows')
output = parser.parse_args().directory
records = []
for name in ('triangle', 'trapezoid', 'pentagon'):
    folder = output / name
    report = json.loads((folder / 'report.json').read_text())
    rate, rir = wavfile.read(folder / 'rir.wav')
    wet_rate, wet = wavfile.read(folder / 'wet.wav')
    dry_rate, dry = wavfile.read(root / 'examples' / 'probe.wav')
    assert rate == wet_rate == dry_rate == report['config']['sample_rate']
    assert rir.dtype == wet.dtype == np.float32
    assert rir.shape == (report['config']['output_frames'], len(report['config']['receivers']))
    assert wet.shape == (len(dry) + len(rir) - 1, rir.shape[1])
    errors = []
    for channel in range(rir.shape[1]):
        expected = fftconvolve(dry.astype(float), rir[:, channel].astype(float))
        error = float(np.max(np.abs(expected - wet[:, channel])))
        assert np.allclose(expected, wet[:, channel], atol=1e-7, rtol=1e-5)
        errors.append(error)
    with (folder / 'paths.csv').open(newline='') as f:
        rows = list(csv.DictReader(f))
    assert len(rows) == len(report['paths'])
    assert list(rows[0]) == ['receiver', 'order', 'distance_m', 'arrival_sample', 'gain'] + [f'edge_{i}' for i in range(len(report['config']['footprint']))] + ['floor', 'ceiling']
    assert all(None not in row for row in rows)
    records.append({'scene': name, 'paths': len(rows), 'rir_frames': len(rir), 'wet_frames': len(wet), 'channels': rir.shape[1], 'maximum_convolution_errors': errors})
result = {'scope': 'synthetic local workflows, not field measurements', 'cases': records}
target = output / 'verification.json'
target.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
print(json.dumps(result))
