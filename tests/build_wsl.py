#!/usr/bin/env python3
"""Exercise the actual offline WSL builder with private-state fixtures."""
import os
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
engine = root / '.bundle_work/download/trusttunnel_client-v1.0.49-windows-x86_64.zip'
with tempfile.TemporaryDirectory(prefix='lwtt-build-') as directory:
    fixture = Path(directory)
    for name in ('app', 'tools', 'docs'):
        shutil.copytree(root / name, fixture / name, ignore=shutil.ignore_patterns('__pycache__'))
    shutil.copyfile(root / 'VERSION', fixture / 'VERSION')
    for name in ('profiles', 'settings', 'log'):
        private = fixture / 'app/lwtt_app' / name
        private.mkdir(exist_ok=True)
        (private / 'private.txt').write_text('TEST ONLY')
    (fixture / 'app/lwtt_app/rogue_credentials.txt').write_text('TEST ONLY')
    env = dict(os.environ, LWTT_TRUSTTUNNEL_ZIP=str(engine))
    result = subprocess.run(['bash', str(fixture / 'tools/build_bundle_wsl.sh')], env=env, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr + result.stdout
    bundle = fixture / 'dist/LWTT_Client_Bundle_windows_x86_64.zip'
    with zipfile.ZipFile(bundle) as archive:
        assert not any('rogue_credentials' in n for n in archive.namelist())
        assert all(not {'profiles', 'settings', 'log'}.intersection(n.split('/')) for n in archive.namelist())
    subprocess.run(['python3', str(root / 'tools/verify_bundle.py'), str(bundle)], check=True)
    invalid = fixture / 'invalid.zip'
    invalid.write_bytes(b'invalid')
    bad_env = dict(env, LWTT_TRUSTTUNNEL_ZIP=str(invalid))
    result = subprocess.run(['bash', str(fixture / 'tools/build_bundle_wsl.sh')], env=bad_env, capture_output=True)
    assert result.returncode != 0 and b'SHA256 mismatch' in result.stderr
    print('PASS: real WSL builder, UTF-8 ZIP names, explicit public manifest, private-state exclusion and refusal of an invalid engine digest.')
