"""Exercise publishing boundaries without Xcode, credentials or network access."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'testflight.sh'


class TestFlightTests(unittest.TestCase):
    def run_script(self, *args):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'scripts').mkdir()
            shutil.copy(SCRIPT, root / 'scripts/testflight.sh')
            (root / 'VERSION').write_text('1.0.999')
            config = root / '.appstoreconnect'
            config.mkdir()
            (config / 'config.json').write_text(json.dumps({
                'api_key_id': 'TEST', 'api_issuer_id': 'TEST'}))
            bins = root / 'bin'
            bins.mkdir()
            for name in ('xcodebuild', 'xcrun'):
                tool = bins / name
                tool.write_text('#!/bin/bash\necho "$0 $*" >> "$CALL_LOG"\n'
                    'if [ "$1" = "-exportArchive" ]; then\n'
                    ' while [ "$#" -gt 0 ]; do\n'
                    '  if [ "$1" = "-exportPath" ]; then mkdir -p "$2"; touch "$2/app.pkg"; fi\n'
                    '  shift\n done\nfi\n')
                tool.chmod(0o755)
            log = root / 'calls'
            env = {**os.environ, 'HOME': str(root), 'CALL_LOG': str(log),
                   'PATH': str(bins) + ':' + os.environ['PATH']}
            result = subprocess.run(['bash', str(root / 'scripts/testflight.sh'), *args],
                                    env=env, capture_output=True, text=True)
            plists = {p.name: p.read_text() for p in (root / 'build').glob('*.plist')}
            return result, log.read_text() if log.exists() else '', plists

    def test_local_exports_never_upload(self):
        result, calls, plists = self.run_script('all', '--no-upload')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('altool', calls)
        self.assertEqual(calls.count('-exportArchive'), 2)
        self.assertIn('-scheme ThoughtVault AppStore -configuration Release -destination generic/platform=macOS', calls)
        self.assertIn('-scheme ThoughtVault -configuration Release -destination generic/platform=iOS', calls)
        self.assertTrue(all('<string>upload</string>' not in p for p in plists.values()))
        self.assertIn('nothing uploaded', result.stdout)

    def test_explicit_upload_preserves_both_routes(self):
        result, calls, plists = self.run_script('all')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('altool --upload-app', calls)
        self.assertIn('<string>upload</string>', plists['ExportOptions-iOS-TestFlight.plist'])

    def test_invalid_option_fails_before_build(self):
        result, calls, _ = self.run_script('ipados')
        self.assertEqual(result.returncode, 2)
        self.assertEqual(calls, '')


if __name__ == '__main__':
    unittest.main()
