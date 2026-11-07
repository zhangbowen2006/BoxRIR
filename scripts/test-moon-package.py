"""Consume the exact local Mooncakes archive without publishing it."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile

root = Path(__file__).resolve().parents[1]
archive = root / '_build/publish/zhangbowen2006-boxrir-0.2.0.zip'
parent = root / 'generated/package-consumer'
parent.mkdir(parents=True, exist_ok=True)
folder = Path(tempfile.mkdtemp(prefix='consumer-', dir=parent))
source, consumer = folder / 'source', folder / 'consumer'
source.mkdir()
consumer.mkdir()
with zipfile.ZipFile(archive) as package:
    names = package.namelist()
    for name in names:
        destination = (source / name).resolve()
        assert destination.is_relative_to(source.resolve()), name
        parts = set(Path(name).parts)
        assert not parts.intersection({'generated', '.git', '.mooncakes', 'node_modules', 'output', 'tests'}), name
    package.extractall(source)
for name in ('LICENSE', 'NOTICE', 'docs/licenses/audiolabs-rir-generator-MIT.txt'):
    assert (source / name).is_file()
(folder / 'moon.work').write_text('members = ["source", "consumer"]\n', encoding='utf-8')
(consumer / 'moon.mod').write_text('name = "boxrir_release/consumer"\nimport { "zhangbowen2006/boxrir@0.2.0" }\n', encoding='utf-8')
(consumer / 'moon.pkg').write_text('import { "zhangbowen2006/boxrir" @boxrir, "zhangbowen2006/boxrir/io" @wav } for "test"\n', encoding='utf-8')
(consumer / 'consumer_test.mbt').write_text('''///|
test "typed reference core from the archive" {
  let rir = @boxrir.audiolabs_rir(
    { x: 6.0, y: 4.0, z: 3.0 }, { x: 1.0, y: 1.0, z: 1.0 },
    [{ x: 2.0, y: 1.0, z: 1.0 }], 16000,
    beta=Some([0.7, 0.6, 0.5, 0.4, 0.3, 0.2]), nsample=Some(512),
    microphone="cardioid", order=2,
  ).unwrap()
  assert_eq(rir.audio.frames(), 512)
  assert_eq(rir.audio.latency_samples, 0)
  assert_eq(rir.audio.convolve([1.0, 0.5]).unwrap().frames(), 513)
}
///|
test "typed convex geometry from the archive" {
  let room = @boxrir.prism_scene(
    [{ x: 0.0, y: 0.0 }, { x: 6.0, y: 0.0 }, { x: 0.0, y: 4.0 }], 3.0,
    { x: 1.0, y: 1.0, z: 1.0 }, [{ x: 2.0, y: 1.0, z: 1.0 }],
    [0.2, 0.3, 0.4, 0.5, 0.6], 16000, 4, 100,
  ).unwrap()
  assert_true(@boxrir.trace_prism(room).length() > 1)
  assert_eq(@boxrir.render(room).channel_count(), 1)
}
///|
test "WAV module preserves amplitudes from the archive" {
  let bytes = @wav.write_float32([[0.5, -2.0, 0.0]], 16000).unwrap()
  assert_eq(@wav.read_mono(bytes).unwrap().samples, [0.5, -2.0, 0.0])
}
''', encoding='utf-8')
checks = []
targets = ['js', 'wasm', 'wasm-gc']
if sys.platform == 'linux':
    targets.append('native')
for target in targets:
    subprocess.run(['moon', 'test', '--target', target, '--deny-warn'], cwd=consumer, check=True)
    checks.append({'target': target, 'consumer_tests': 3, 'passed': True})
result = {'version': '0.2.0', 'source': 'local Mooncakes archive; not a registry publication',
          'packaged_files': len(names), 'private_and_cache_directories_absent': True, 'checks': checks}
(parent / 'verification.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
print(json.dumps(result))
