#!/usr/bin/env python3
"""Package only the explicit public LWTT runtime manifest."""
import hashlib
import zipfile
from pathlib import Path
from verify_bundle import verify

root = Path(__file__).resolve().parent.parent
version = (root / 'VERSION').read_text().strip().replace('.', '_')
out = root / 'dist' / f'LWTT_Client_Manager_v{version}_public.zip'
out.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as archive:
    archive.write(root / 'app/lwtt_tray_start.bat', 'lwtt_tray_start.bat')
    archive.write(root / 'docs/QUICK_START_BUNDLE_RU.txt', 'ИНСТРУКЦИЯ БЫСТРОГО СТАРТА.txt')
    for name in (root / 'tools/runtime-files.txt').read_text().splitlines():
        source = root / 'VERSION' if name == 'VERSION' else root / 'app/lwtt_app' / name
        archive.write(source, 'lwtt_app/' + name)
    for name in ('README_LWTT_CLIENT.txt', 'ИЗМЕНЕНИЯ_V4.15.txt'):
        archive.write(root / 'app/lwtt_app' / name, 'lwtt_app/' + name)
Path(str(out) + '.sha256').write_text(hashlib.sha256(out.read_bytes()).hexdigest() + '  ' + out.name + '\n')
verify(out, shell=True)
