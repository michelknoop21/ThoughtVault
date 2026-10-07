#!/usr/bin/env python3
"""Reject releases whose current presentation has no reviewed visual evidence."""
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def check(root):
    proof = json.loads((root / 'docs/design/windows/verification.json').read_text(encoding='utf-8'))
    if proof.get('status') != 'reviewed':
        raise ValueError('Windows visual review is missing; do not publish this release')
    required = {'windows/src/pages/HomePage.tsx', 'windows/src/pages/RecordingPage.tsx',
                'windows/src/styles/globals.css', 'windows/src/styles/thoughtvault.css',
                'macos/Views/HomeView+Studio.swift', 'macos/Views/RecordingView+Studio.swift',
                'logo/thoughtvaultlogo.png', 'windows/src/assets/app-logo.png'}
    for pattern in ('windows/src/pages/**/*.tsx', 'windows/src/components/**/*.tsx',
                    'windows/src/styles/*.css', 'macos/Views/**/*.swift'):
        required.update(str(p.relative_to(root)) for p in root.glob(pattern) if '__tests__' not in p.parts)
    missing = required - proof['sources'].keys()
    if missing:
        raise ValueError('Unreviewed presentation files: ' + ', '.join(sorted(missing)))
    for filename, expected in proof['sources'].items():
        actual = hashlib.sha256((root / filename).read_bytes()).hexdigest()
        if actual != expected:
            raise ValueError(f'Presentation changed after review: {filename}')
    for screen in ('home', 'recording', 'transcripts', 'settings'):
        screenshot = proof['screenshots'][screen]
        data = (root / screenshot['path']).read_bytes()
        if not data.startswith(b'\x89PNG\r\n\x1a\n') or hashlib.sha256(data).hexdigest() != screenshot['sha256']:
            raise ValueError(f'Missing or changed screenshot: {screen}')

if __name__ == '__main__':
    try:
        check(ROOT)
    except (ValueError, KeyError, OSError) as error:
        print(f'Windows design release blocked: {error}', file=sys.stderr)
        sys.exit(1)
    print('Windows presentation matches reviewed sources and screenshots')
