"""Build the Windows installer package from the published source snapshot.

No game files or network access are required at build time. The installer obtains
official REFramework when no verified offline archive was bundled.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
FRAMEWORK_SHA256 = '787c0203dc89087c808a69ec92424ef91ee8f9790fd541a331531050f2bc0bdb'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def check_source():
    version = (ROOT / 'VERSION').read_text().strip()
    required = ['installer/Install.cmd', 'installer/Install-MVP.ps1',
                'installer/Setup.ps1', 'installer/Play.ps1',
                'support/DialogInput.cs', 'support/BeltOverlay.cs',
                'support/openvr_api.cs', 'support/OpenVR-LICENSE.txt',
                'third_party/REFramework-LICENSE.txt', 'runtime/re2ivr_bootstrap.lua']
    for name in required:
        if not (ROOT / name).is_file():
            raise ValueError('Missing source: ' + name)
    if 'local VERSION="' + version + '"' not in (ROOT / 'runtime/re2ivr_bootstrap.lua').read_text(encoding='utf-8'):
        raise ValueError('VERSION and runtime bootstrap disagree')
    if not list((ROOT / 'runtime/re2ivr').glob('*.lua')):
        raise ValueError('Runtime modules missing')
    print('PASS source structure/version (not a Lua parser or headset test)')
    return version

def build(args):
    version = check_source()
    if args.check:
        return
    build_root = (ROOT / 'build').resolve()
    package = (build_root / 'RE2IVR-MVP').resolve()
    if not package.is_relative_to(build_root) or package == build_root:
        raise ValueError('Unsafe package staging path')
    if package.exists():
        shutil.rmtree(package)
    package.mkdir(parents=True)
    for source in (ROOT / 'installer').iterdir():
        if source.is_file():
            shutil.copyfile(source, package / source.name)
    payload = package / 'payload/reframework/autorun'
    shutil.copytree(ROOT / 'runtime', payload)
    helper = package / 'RE2IVR-DialogInput.exe'
    if args.prebuilt_helper:
        provenance = json.loads((ROOT / 'tools/source_provenance.json').read_text())
        if sha(Path(args.prebuilt_helper)) != provenance['helper_sha256']:
            raise ValueError('Prebuilt helper is not the verified 0.6.0 snapshot')
        for name, expected in provenance['helper_sources'].items():
            if sha(ROOT / 'support' / name) != expected:
                raise ValueError('Sources changed; compile the helper instead: ' + name)
        if version != provenance['version']:
            raise ValueError('Prebuilt helper only applies to its original version')
        shutil.copyfile(args.prebuilt_helper, helper)
        print('Reused exact verified Windows helper; self-tests not run on this host')
    else:
        if os.name != 'nt':
            raise RuntimeError('Compile on Windows, or provide the checksum-verified original --prebuilt-helper')
        compiler = Path(os.environ.get('WINDIR', r'C:\Windows')) / 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
        subprocess.run([str(compiler), '/nologo', '/unsafe', '/platform:x64',
                        '/r:System.Web.Extensions.dll', '/r:System.Drawing.dll',
                        '/out:' + str(helper)] + [str(ROOT / 'support' / name) for name in
                        ('DialogInput.cs', 'BeltOverlay.cs', 'openvr_api.cs')], check=True)
        subprocess.run([str(helper), '--self-test'], check=True)
        subprocess.run([str(helper), '--test-belt', str(build_root / 'belt-self-test')], check=True)
    shutil.copytree(ROOT / 'support', package / 'support')
    shutil.copytree(ROOT / 'docs', package / 'docs')
    for name in ('README.md', 'LICENSE', 'CHANGELOG.md', 'THIRD_PARTY_NOTICES.md'):
        shutil.copyfile(ROOT / name, package / name)
    shutil.copyfile(ROOT / 'third_party/REFramework-LICENSE.txt', package / 'REFramework-LICENSE.txt')
    # Preserve filenames referenced by runtime UI and existing launchers.
    for name in ('VR-TROUBLESHOOTING.md', 'DIALOG-INPUT.md'):
        shutil.copyfile(ROOT / 'docs/TROUBLESHOOTING.md', package / name)
    shutil.copyfile(ROOT / 'README.md', package / 'BELT-QUICKSTART.md')
    if args.framework_archive:
        archive = Path(args.framework_archive)
        if sha(archive) != FRAMEWORK_SHA256:
            raise ValueError('Offline RT framework archive does not match pinned upstream hash')
        (package / 'framework').mkdir()
        shutil.copyfile(archive, package / 'framework/RE2.zip')
    manifest = {'schema': 1, 'version': version, 'files': [
        {'path': p.relative_to(package / 'payload').as_posix(), 'sha256': sha(p).upper()}
        for p in sorted((package / 'payload').rglob('*')) if p.is_file()]}
    (package / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    output = Path(args.output_dir or ROOT / 'dist')
    output.mkdir(parents=True, exist_ok=True)
    target = output / ('RE2IVR-' + version + '.zip')
    with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as z:
        for path in sorted(package.rglob('*')):
            if path.is_file():
                z.write(path, 'RE2IVR-MVP/' + path.relative_to(package).as_posix())
    with zipfile.ZipFile(target) as z:
        if z.testzip() is not None:
            raise ValueError('Package integrity check failed')
        for row in manifest['files']:
            actual = hashlib.sha256(z.read('RE2IVR-MVP/payload/' + row['path'])).hexdigest().upper()
            if actual != row['sha256']:
                raise ValueError('Packaged runtime hash mismatch: ' + row['path'])
    print('Built:', target.resolve())
    print('SHA256:', sha(target))

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Check source structure/version only')
    parser.add_argument('--prebuilt-helper', help='Exact helper from original verified snapshot; source hashes must also match')
    parser.add_argument('--framework-archive', help='Optional pinned official RT RE2.zip for offline installation')
    parser.add_argument('--output-dir')
    try:
        build(parser.parse_args())
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print('Build failed:', error, file=sys.stderr)
        sys.exit(1)
