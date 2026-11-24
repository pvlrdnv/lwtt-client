#!/usr/bin/env python3
"""Check public source text, local documentation links and tooling invariants."""
import ast
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parent.parent
paths = []
for directory in ('app', 'tools', 'tests', 'docs', 'examples'):
    paths.extend(p for p in (ROOT / directory).rglob('*') if p.is_file() and '__pycache__' not in p.parts)
paths.extend(p for p in ROOT.iterdir() if p.is_file() and p.suffix in {'.md', '.txt', '.sh'})
errors = []
for path in paths:
    if path.suffix not in {'.md', '.txt', '.ps1', '.bat', '.sh', '.py'}:
        continue
    text = path.read_text(encoding='utf-8-sig')
    if '\u2014' in text:
        errors.append(f'{path.relative_to(ROOT)}: forbidden punctuation U+2014')
    if any(ord(c) < 32 and c not in '\t\n\r' for c in text):
        errors.append(f'{path.relative_to(ROOT)}: invisible control character')
    if path.suffix in {'.md', '.txt'} and '\t' in text:
        errors.append(f'{path.relative_to(ROOT)}: tab in public documentation')
    if path.suffix == '.ps1' and not path.read_bytes().startswith(b'\xef\xbb\xbf'):
        errors.append(f'{path.relative_to(ROOT)}: missing UTF-8 BOM for PowerShell 5.1')
    if path.suffix == '.py':
        ast.parse(text, filename=str(path))
    if path.suffix == '.sh':
        subprocess.run(['bash', '-n', str(path)], check=True)
    if path.suffix == '.md':
        prose = re.sub(r'```.*?```', '', text, flags=re.S)
        for target in re.findall(r'\]\(([^)]+)\)', prose):
            target = target.strip().strip('<>')
            if re.match(r'^[a-zA-Z][a-zA-Z0-9+.-]*:', target) or target.startswith('#'):
                continue
            local = unquote(target.split('#')[0])
            if local and not (path.parent / local).exists():
                errors.append(f'{path.relative_to(ROOT)}: missing link target {target}')
manifest = (ROOT / 'MANIFEST.txt').read_text().splitlines()
for name in manifest:
    if not (ROOT / name).is_file():
        errors.append(f'MANIFEST.txt: missing {name}')
for directory in ('app', 'docs', 'tools', 'tests', 'examples'):
    for path in (ROOT / directory).rglob('*'):
        if path.is_file() and '__pycache__' not in path.parts and path.relative_to(ROOT).as_posix() not in manifest:
            errors.append(f'MANIFEST.txt: unlisted {path.relative_to(ROOT)}')
for path in (ROOT / 'app').rglob('*.bat'):
    if 'net session' in path.read_text(encoding='utf-8-sig').lower():
        errors.append(f'{path.relative_to(ROOT)}: elevation depends on Server service')
with tempfile.TemporaryDirectory(prefix='lwtt-static-') as directory:
    temporary = Path(directory)
    archive = temporary / 'invalid.zip'
    with zipfile.ZipFile(archive, 'w') as output:
        output.writestr('unexpected.txt', 'test')
    result = subprocess.run([sys.executable, '-O', str(ROOT / 'tools/verify_bundle.py'), str(archive)], capture_output=True, text=True)
    if result.returncode == 0 or 'ValueError' not in result.stderr:
        errors.append('Archive verification was skipped under Python optimization')
    fixture = temporary / 'legacy'
    (fixture / 'tools').mkdir(parents=True)
    (fixture / 'VERSION').write_text((ROOT / 'VERSION').read_text())
    shutil.copyfile(ROOT / 'tools/restructure_project_v4_16.sh', fixture / 'tools/restructure_project_v4_16.sh')
    result = subprocess.run(['bash', str(fixture / 'tools/restructure_project_v4_16.sh')], capture_output=True, text=True)
    if result.returncode == 0 or (fixture / 'app').exists() or (fixture / 'VERSION').read_text() != (ROOT / 'VERSION').read_text():
        errors.append('Legacy migration mutated an unsupported current project')
if errors:
    raise SystemExit('\n'.join(errors))
print('PASS: Python/Bash syntax, public text, documentation links, manifest, elevation scripts, optimized archive verification and legacy migration guard.')
