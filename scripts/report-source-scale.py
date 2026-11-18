"""Count maintained runtime source separately from references and generated files."""
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
paths = set(subprocess.check_output(
    ['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'],
    cwd=ROOT,
).decode('utf-8').split('\0')) - {''}

PORTS = {'audiolabs.mbt', 'atmosphere.mbt'}
files = {'upstream_port_and_adaptation': {}, 'self_authored_moonbit': {}, 'host_javascript': {}}


def source_lines(text):
    # This repository uses // line comments and conventional standalone /* */
    # blocks in runtime code. Inline comments leave the code line counted.
    block = False
    lines = 0
    for line in text.splitlines():
        code = line.strip()
        while code:
            if block:
                _, boundary, code = code.partition('*/')
                if not boundary:
                    break
                block = False
                code = code.strip()
            elif code.startswith('//'):
                break
            elif code.startswith('/*'):
                block = True
                code = code[2:]
            else:
                lines += 1
                break
    return lines


for name in sorted(paths):
    file = ROOT / name
    if not file.is_file():
        continue
    if name.endswith('.mbt') and not name.endswith(('_test.mbt', '_wbtest.mbt')) and (
        '/' not in name or name.startswith(('api/', 'bridge/', 'io/'))
    ):
        category = 'upstream_port_and_adaptation' if name in PORTS else 'self_authored_moonbit'
    elif name.endswith('.mjs') and name.startswith(('bin/', 'sdk/', 'web/')):
        category = 'host_javascript'
    else:
        continue
    files[category][name] = source_lines(file.read_text(encoding='utf-8'))

totals = {category: sum(entries.values()) for category, entries in files.items()}
result = {
    'method': 'nonblank runtime source lines, excluding pure comments',
    'excludes': ['tests', 'fixtures', 'generated interfaces', 'TypeScript declarations',
                 'docs', 'HTML/CSS', 'build scripts', 'examples', 'dependencies'],
    'counts': totals,
    'self_authored_runtime_total': totals['self_authored_moonbit'] + totals['host_javascript'],
    'files': files,
}
print(json.dumps(result, indent=2))
