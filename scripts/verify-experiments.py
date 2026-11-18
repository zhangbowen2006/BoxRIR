"""Execute the standalone CLI and compare output WAV/report data independently."""
import json
import subprocess
import tempfile
from pathlib import Path

import numpy as np
import scipy
from scipy.io import wavfile
from scipy.signal import fftconvolve

ROOT = Path(__file__).resolve().parents[1]
PARENT = ROOT / 'generated' / 'experiment-verification'
PARENT.mkdir(parents=True, exist_ok=True)
WORK = Path(tempfile.mkdtemp(prefix='run-', dir=PARENT))


def cli(backend, *args, succeeds=True):
    result = subprocess.run(
        ['node', 'bin/boxrir.mjs', '--backend', backend, *map(str, args)],
        cwd=ROOT, text=True, capture_output=True, encoding='utf-8',
    )
    if not succeeds:
        assert result.returncode == 2, result.stdout + result.stderr
        return result.stderr
    assert result.returncode == 0, result.stdout + result.stderr
    return json.loads(result.stdout)


def dump(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')
    return path


def report(path):
    return json.loads((path / 'report.json').read_text(encoding='utf-8'))


def matrix(path, expected_rate=16000):
    rate, audio = wavfile.read(path)
    assert rate == expected_rate
    assert np.isfinite(audio).all()
    return audio if audio.ndim == 2 else audio[:, None]


def verify_mix(backend, root):
    specification = json.loads((ROOT / 'examples/mixed-recording.json').read_text(encoding='utf-8'))
    dry_files = []
    expected_tracks = []
    for track in specification['tracks']:
        name = track['id']
        probe = root / ('probe-' + name)
        cli(backend, 'probe', ROOT / 'examples' / ('probe-' + name + '.json'), probe)
        dry_files.append(probe / 'probe.wav')
        scene = dump(root / (name + '.json'), dict(specification['scene'], source=track['source']))
        rendered = root / ('rir-' + name)
        cli(backend, 'rir', scene, rendered)
        impulse = matrix(rendered / 'rir.wav').astype(np.float64)
        dry = matrix(dry_files[-1]).astype(np.float64)
        convolved = np.stack([fftconvolve(dry[:, 0], h) for h in impulse.T], axis=1)
        expected_tracks.append((track['start_frame'], track['gain'] * convolved))
    end_frame = max(start + len(samples) for start, samples in expected_tracks)
    expected = np.zeros((end_frame, 2))
    for start, samples in expected_tracks:
        expected[start:start + len(samples)] += samples
    directory = root / 'mix'
    cli(backend, 'mix', ROOT / 'examples/mixed-recording.json', directory, *dry_files)
    actual = matrix(directory / 'wet.wav')
    assert actual.dtype == np.float32
    assert actual.shape == expected.shape
    error = np.max(np.abs(actual - expected))
    assert error < 1e-7, error
    metadata = report(directory)
    assert metadata['frames'] == end_frame
    assert metadata['latency_samples'] == 16
    assert [t['end_frame'] for t in metadata['tracks']] == [
        start + len(samples) for start, samples in expected_tracks
    ]
    verified = cli(backend, 'verify', directory)
    assert verified['files_verified'] == 5 and verified['recorded_backend'] == backend
    # Change bytes while preserving size to prove verification checks hashes.
    path = directory / 'wet.wav'
    original = path.read_bytes()
    try:
        path.write_bytes(original[:-1] + bytes([original[-1] ^ 1]))
        assert 'checksum' in cli(backend, 'verify', directory, succeeds=False).lower()
    finally:
        path.write_bytes(original)
    return {'frames': end_frame, 'channels': 2, 'maximum_error_vs_scipy': float(error)}


def verify_estimation(backend, root):
    probe = np.array([0.6, -0.2, 0.15, 0.05, 0.03], dtype=np.float32)
    known = np.zeros((1024, 2), dtype=np.float32)
    known[53, 0], known[210, 0], known[936, 0] = 0.6, 0.18, -0.11
    known[60, 1], known[320, 1], known[975, 1] = 0.45, 0.20, 0.10
    recorded = np.stack([fftconvolve(probe.astype(np.float64), h) for h in known.T], axis=1)
    probe_file, recorded_file, reference = [root / name for name in ['pilot.wav', 'observed.wav', 'known.wav']]
    wavfile.write(probe_file, 16000, probe)
    wavfile.write(recorded_file, 16000, recorded.astype(np.float32))
    wavfile.write(reference, 16000, known)
    settings = dump(root / 'estimate.json', {'response_frames': len(known), 'regularization_db': -120})
    estimated = root / 'estimated'
    cli(backend, 'estimate', probe_file, recorded_file, settings, estimated)
    estimate = matrix(estimated / 'estimated-rir.wav')
    error = np.max(np.abs(estimate - known))
    assert estimate.shape == known.shape and error < 1e-7
    assert np.argmax(np.abs(estimate[:, 0])) == 53
    settings = dump(root / 'compare.json', {'frames': 1024})
    comparison = root / 'comparison'
    cli(backend, 'compare', reference, estimated / 'estimated-rir.wav', settings, comparison)
    for channel in report(comparison)['channels']:
        assert channel['observed_lag_frames'] == 0
        assert channel['raw_error_ratio'] < 1e-6
        assert channel['signed_correlation'] > 0.999999
    return {'frames': len(known), 'maximum_error_vs_known_ir': float(error)}


def verify_decay(backend, root):
    rate = 16000
    expected = 0.42
    onset = 24
    signal = np.exp(-np.log(1000.0) * np.arange(24000) / (expected * rate)).astype(np.float32)
    path = root / 'decay.wav'
    wavfile.write(path, rate, np.pad(signal, (onset, 0)))
    options = dump(root / 'decay.json', {'onset_frames': [onset], 'curve_points': 32})
    out = root / 'decay'
    cli(backend, 'analyze', path, out, options)
    stats = report(out)['channels'][0]
    energy = signal.astype(np.float64) ** 2
    sums = np.cumsum(energy[::-1])[::-1]
    decay = 10 * np.log10(sums / sums[0])
    for field, hi, lo in [('edt', 0, -10), ('t20', -5, -25), ('t30', -5, -35)]:
        mask = (decay <= hi) & (decay >= lo)
        slope = np.polyfit(np.arange(len(decay))[mask] / rate, decay[mask], 1)[0]
        assert stats[field]['status'] == 'estimated'
        assert abs(stats[field]['seconds_for_60db'] + 60.0 / slope) < 1e-8
    for point in stats['curve']:
        assert abs(point['energy_db'] - decay[point['frame_from_onset']]) < 1e-8
    return {'analytic_decay_seconds': expected, 't30_reported_seconds': stats['t30']['seconds_for_60db']}


def verify_resample(backend, root):
    rate = 48000
    t = np.arange(4800) / rate
    source = root / '48k.wav'
    samples = np.stack([0.7 * np.sin(2*np.pi*1000*t), 0.7*np.sin(2*np.pi*12000*t)], axis=1)
    wavfile.write(source, rate, samples.astype(np.float32))
    directory = root / '16k'
    cli(backend, 'resample', source, 16000, directory)
    result = matrix(directory / 'resampled.wav')
    assert result.shape == (1600, 2)
    low_error = np.max(np.abs(result[100:1500, 0] - samples[300:4500:3, 0]))
    rejected_peak = np.max(np.abs(result[100:1500, 1]))
    assert low_error < 0.0005 and rejected_peak < 0.0005, (low_error, rejected_peak)
    return {'input_rate': 48000, 'output_rate': 16000, 'passband_maximum_error': float(low_error),
            'out_of_band_peak': float(rejected_peak)}


checks = {}
for backend in ('js', 'wasm-gc'):
    folder = WORK / backend
    folder.mkdir()
    checks[backend] = {
        'multisource': verify_mix(backend, folder),
        'transfer': verify_estimation(backend, folder),
        'decay': verify_decay(backend, folder),
        'resample': verify_resample(backend, folder),
    }
body = {'numpy': np.__version__, 'scipy': scipy.__version__, 'checks': checks,
        'input_scope': 'synthetic inputs with independently generated numerical references'}
dump(PARENT / 'verification.json', body)
print(json.dumps(body, indent=2))
