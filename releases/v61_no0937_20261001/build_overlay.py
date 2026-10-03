"""Reproduce Thursday's three-asset patch; align/sign separately with Android tools."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('base_apk', type=Path)
    parser.add_argument('unsigned_apk', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    manifest = json.loads((root / 'manifest.json').read_text())
    if args.base_apk.resolve() == args.unsigned_apk.resolve():
        parser.error('Output must differ from the base APK.')
    if args.unsigned_apk.exists():
        parser.error('Output already exists; choose a new path.')
    if hashlib.sha256(args.base_apk.read_bytes()).hexdigest() != manifest['base_sha256']:
        parser.error('Base APK hash does not match the original Friday v61 build.')
    replacements = {name: (root / Path(name).name).read_bytes()
                    for name in manifest['changed_entries']}
    with zipfile.ZipFile(args.base_apk) as source, zipfile.ZipFile(args.unsigned_apk, 'w') as target:
        for info in source.infolist():
            if not info.filename.startswith('META-INF/') and info.filename not in replacements:
                target.writestr(info, source.read(info.filename))
        for name, data in replacements.items():
            target.writestr(name, data, compress_type=zipfile.ZIP_DEFLATED)
    print(f'Created unsigned overlay: {args.unsigned_apk}. Run zipalign and apksigner next.')


if __name__ == '__main__':
    main()
