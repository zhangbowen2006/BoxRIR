"""Consume the exact local Mooncakes archive without publishing it."""
import json
import re
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile

root = Path(__file__).resolve().parents[1]
manifest = (root / 'moon.mod').read_text(encoding='utf-8')
module = re.search(r'^name\s*=\s*"([^"]+)"', manifest, re.M)[1]
version = re.search(r'^version\s*=\s*"([^"]+)"', manifest, re.M)[1]
archive = root / '_build/publish' / (module.replace('/', '-') + '-' + version + '.zip')
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
(consumer / 'moon.mod').write_text('name = "boxrir_release/consumer"\nimport { "' + module + '@' + version + '" }\n', encoding='utf-8')
(consumer / 'moon.pkg').write_text('import { "' + module + '" @boxrir, "' + module + '/io" @wav } for "test"\n', encoding='utf-8')
(consumer / 'consumer_test.mbt').write_text((root / 'scripts/consumer-tests.mbt.txt').read_text(encoding='utf-8'), encoding='utf-8')
guide = (source / 'docs/MOONBIT-QUICKSTART.md').read_text(encoding='utf-8')
assert guide == (root / 'docs/MOONBIT-QUICKSTART.md').read_text(encoding='utf-8')
quickstart = re.findall(r'```moonbit\r?\n(.*?)\r?\n```', guide, re.S)
assert len(quickstart) == 3, 'expected module, package and runnable example in the guide'
(consumer / 'quickstart_test.mbt').write_text(quickstart[2] + '\n', encoding='utf-8')
checks = []
targets = ['js', 'wasm', 'wasm-gc']
if sys.platform == 'linux':
    targets.append('native')
for target in targets:
    run = subprocess.run(['moon', 'test', '--target', target, '--deny-warn', '-p', 'boxrir_release/consumer'],
                         cwd=consumer, check=True, capture_output=True, text=True, encoding='utf-8')
    print(run.stdout, end='')
    passed = int(re.search(r'Total tests: \d+, passed: (\d+), failed: 0\.', run.stdout + run.stderr)[1])
    assert passed > 0, 'the standalone consumer tests must execute'
    checks.append({'target': target, 'consumer_tests': passed, 'passed': True})
result = {'version': version, 'source': 'local Mooncakes archive; not a registry publication',
          'packaged_files': len(names), 'private_and_cache_directories_absent': True,
          'quickstart_example_executed': True, 'checks': checks}
(parent / 'verification.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
print(json.dumps(result))
