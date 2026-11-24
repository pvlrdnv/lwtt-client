#!/usr/bin/env python3
"""Validate local LWTT ZIP contents, scripts, version and SHA256."""
import argparse
import hashlib
import zipfile
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parent.parent


def require(condition: bool, message: object) -> None:
    # Production validation must remain active under python -O/PYTHONOPTIMIZE.
    if not condition:
        raise ValueError(str(message))


def verify(path: Path, shell: bool = False) -> None:
    with zipfile.ZipFile(path) as archive:
        require(archive.testzip() is None, f"Corrupt archive: {path}")
        names = archive.namelist()
        require(len(names) == len({n.replace('\\', '/').casefold() for n in names}), 'Duplicate Windows ZIP paths')
        roots = {name.split('/')[0] for name in names}
        require(roots == {'lwtt_app', 'lwtt_tray_start.bat', 'ИНСТРУКЦИЯ БЫСТРОГО СТАРТА.txt'}, roots)
        for name in names:
            parts = name.lower().replace('\\', '/').split('/')
            require(not PurePosixPath(name).is_absolute() and '..' not in parts and ':' not in name and '\\' not in name, f'Unsafe ZIP path: {name}')
            require(not {'profiles', 'settings', 'log', '.git', '__pycache__'}.intersection(parts), name)
            require(not name.lower().endswith(('.pem', '.pid', '.log', '.tmp', '.bak')), name)
            require(not name.lower().endswith(('lwtt_client.toml', 'bypass.json')), name)
        for required in (ROOT / 'tools/runtime-files.txt').read_text().splitlines():
            require('lwtt_app/' + required in names, f"Missing dependency: {required}")
        for source in (ROOT / 'app').rglob('*'):
            if source.is_file():
                relative = source.relative_to(ROOT / 'app').as_posix()
                if any(p in {'settings', 'profiles', 'log'} for p in source.parts):
                    continue
                if source.suffix in {'.ps1', '.bat', '.ico', '.txt'}:
                    require(archive.read(relative) == source.read_bytes(), f"Stale file: {relative}")
        require(archive.read('ИНСТРУКЦИЯ БЫСТРОГО СТАРТА.txt') == (ROOT / 'docs/QUICK_START_BUNDLE_RU.txt').read_bytes(), 'Stale quick start guide')
        require(archive.read('lwtt_app/VERSION').decode().strip() == (ROOT / 'VERSION').read_text().strip(), 'Incorrect application version')
        if not shell:
            require({'lwtt_app/trusttunnel_client.exe', 'lwtt_app/wintun.dll'}.issubset(names), 'Missing engine or Wintun')
        else:
            require(not any(name.endswith(('.exe', '.dll')) for name in names), 'Unexpected binary in shell archive')
    digest = Path(str(path) + '.sha256')
    require(digest.exists(), f"Missing checksum: {path}")
    require(digest.read_text().split()[0].lower() == hashlib.sha256(path.read_bytes()).hexdigest(), 'SHA256 mismatch')
    print(f"PASS: {path.name}: contents, current scripts, version, integrity and SHA256")


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('archive', type=Path)
    parser.add_argument('--shell', action='store_true')
    args = parser.parse_args()
    verify(args.archive, args.shell)
