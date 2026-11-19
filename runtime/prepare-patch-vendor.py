import hashlib
import json
from pathlib import Path
import tarfile
import tomllib

root = Path(__file__).resolve().parent
lock = tomllib.loads((root / 'animegamepatch-master' / 'Cargo.lock').read_text())
vendor = root / 'cargo-vendor'
vendor.mkdir(exist_ok=True)
missing = []
for package in lock['package']:
    if not package.get('source'):
        continue
    name = f"{package['name']}-{package['version']}"
    archive = root / 'crate-cache' / f'{name}.crate'
    if not archive.exists():
        missing.append(name)
        continue
    if hashlib.sha256(archive.read_bytes()).hexdigest() != package['checksum']:
        raise RuntimeError(f'Archive checksum mismatch: {name}')
    target = vendor / name
    receipt = target / '.cargo-checksum.json'
    if receipt.exists() and json.loads(receipt.read_text())['package'] == package['checksum']:
        continue
    with tarfile.open(archive) as tar:
        for member in tar.getmembers():
            if not member.name.startswith(name + '/') and member.name != name:
                raise RuntimeError(f'Unexpected archive path: {member.name}')
        tar.extractall(vendor, filter='data')
    files = {p.relative_to(target).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
             for p in target.rglob('*') if p.is_file() and p.name != '.cargo-checksum.json'}
    receipt.write_text(json.dumps({'package': package['checksum'], 'files': files}))
config_dir = root / 'animegamepatch-master' / '.cargo'
config_dir.mkdir(exist_ok=True)
(config_dir / 'config.toml').write_text(
    '[source.crates-io]\nreplace-with = "vendored-sources"\n'
    '[source.vendored-sources]\ndirectory = "' + vendor.as_posix() + '"\n'
    '[net]\noffline = true\n')
print('Missing dependency archives:', missing)
if missing:
    raise SystemExit(2)
print('All locked dependencies verified and ready for offline build.')
