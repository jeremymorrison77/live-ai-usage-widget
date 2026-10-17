#!/usr/bin/env python3
"""Notarize an already reviewed signed app and create a stapled download ZIP.

Only invokes Apple's tools. No credentials in arguments: pass a saved Keychain
profile name. An uncertain submission is recorded and must be resumed by ID.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--notary-profile', required=True)
    parser.add_argument('--submission-id', help='Resume a previously submitted archive; never submit it twice')
    args = parser.parse_args()
    app = ROOT / 'build/Live Usage Widget.app'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    version = info['CFBundleShortVersionString']
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    signature = subprocess.run(['codesign', '-dvv', str(app)], capture_output=True, text=True, check=True).stderr
    if 'Developer ID Application:' not in signature or 'runtime' not in signature:
        raise SystemExit('A hardened Developer ID signed app is required.')
    staging = ROOT / 'build/notary-upload.zip'
    if not args.submission_id:
        subprocess.run(['ditto', '-c', '-k', '--keepParent', str(app), str(staging)], check=True)
        receipt = subprocess.run(['xcrun', 'notarytool', 'submit', str(staging), '--keychain-profile', args.notary_profile, '--output-format', 'json'], capture_output=True, text=True)
        (ROOT / 'build/notary-submit.json').write_text(receipt.stdout)
        if receipt.returncode:
            raise SystemExit('Submission failed or is uncertain. Inspect Apple status before retrying; no automatic resubmission.')
        value = json.loads(receipt.stdout)
        submission = value['id']
    else:
        submission = args.submission_id
    print('Apple submission: ' + submission, flush=True)
    result = subprocess.run(['xcrun', 'notarytool', 'wait', submission, '--keychain-profile', args.notary_profile, '--output-format', 'json'], capture_output=True, text=True)
    (ROOT / 'build/notary-result.json').write_text(result.stdout)
    if result.returncode or json.loads(result.stdout).get('status') != 'Accepted':
        raise SystemExit('Not accepted yet. Resume by submission ID; do not resubmit automatically.')
    subprocess.run(['xcrun', 'stapler', 'staple', str(app)], check=True)
    subprocess.run(['xcrun', 'stapler', 'validate', str(app)], check=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    subprocess.run(['spctl', '--assess', '--type', 'execute', '--verbose=2', str(app)], check=True)
    output = ROOT / 'dist'; output.mkdir(exist_ok=True)
    archive = output / ('Live-Usage-Widget-' + version + '-macOS-arm64.zip')
    subprocess.run(['ditto', '-c', '-k', '--keepParent', str(app), str(archive)], check=True)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    (output / (archive.name + '.sha256')).write_text(digest + '  ' + archive.name + '\n')
    (output / 'notarization.json').write_text(json.dumps({'version': version, 'submission_id': submission, 'status': 'Accepted', 'sha256': digest}, indent=2) + '\n')
    print(archive, flush=True)
    print('Notarization is not a clean-machine installation or account-renewal test.', flush=True)

if __name__ == '__main__':
    main()
