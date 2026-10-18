#!/usr/bin/env python3
"""Export exactly the reviewed manifest. Never recurse through a private parent project."""
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]

def main():
    files = json.loads((ROOT / 'release-files.json').read_text())
    if not isinstance(files, list) or len(set(files)) != len(files):
        raise SystemExit('Invalid release manifest')
    contents = {}
    for name in files:
        path = PurePosixPath(name)
        if path.is_absolute() or '..' in path.parts or any(x in path.parts for x in ['.git', 'build', 'dist', 'state', 'logs', '.claude', '.codex']):
            raise SystemExit('Unsafe manifest entry')
        source = ROOT / name
        if source.is_symlink() or not source.is_file() or ROOT not in source.resolve().parents:
            raise SystemExit('Manifest entry missing or not a regular package file: ' + name)
        data = source.read_bytes()
        if name.endswith('.png'):
            if not name.startswith('docs/images/') or not data.startswith(b'\x89PNG\r\n\x1a\n') or any(chunk in data for chunk in [b'eXIf', b'tEXt', b'iTXt', b'zTXt']):
                raise SystemExit('Image must be a metadata-free PNG in docs/images: ' + name)
            contents[name] = data
            continue
        text = data.decode('utf-8')
        patterns = [r'/Users/[A-Za-z0-9_.-]+/', r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
                    r'gh[pousr]_[A-Za-z0-9]{20,}', r'sk-[A-Za-z0-9_-]{24,}']
        if any(re.search(pattern, text) for pattern in patterns):
            raise SystemExit('Potential private material in ' + name)
        contents[name] = data
    destination = ROOT / 'dist'
    destination.mkdir(exist_ok=True)
    archive = destination / 'live-ai-usage-widget-1.1.1-source.zip'
    with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED) as output:
        for name, data in sorted(contents.items()):
            info = zipfile.ZipInfo('live-ai-usage-widget/' + name, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            output.writestr(info, data)
    checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
    (destination / 'SHA256SUMS').write_text(checksum + '  ' + archive.name + '\n')
    with zipfile.ZipFile(archive) as check:
        if len(check.namelist()) != len(files) or check.testzip() is not None:
            raise SystemExit('Archive verification failed')
    print(f'Exported {len(files)} reviewed source files: {archive}')
    print('Source archive only. The signed app is a separate artifact; source export does not prove independent-user acceptance.')

if __name__ == '__main__':
    main()
