#!/usr/bin/env python3
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('gate', Path(__file__).with_name('check-windows-design.py'))
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)

class DesignGateTests(unittest.TestCase):
    def test_missing_review_or_unreviewed_sources_block_release(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            proof = root / 'docs/design/windows/verification.json'
            proof.parent.mkdir(parents=True)
            proof.write_text(json.dumps({'status': 'pending', 'sources': {}, 'screenshots': {}}))
            with self.assertRaisesRegex(ValueError, 'visual review is missing'):
                gate.check(root)
            proof.write_text(json.dumps({'status': 'reviewed', 'sources': {}, 'screenshots': {}}))
            with self.assertRaisesRegex(ValueError, 'Unreviewed presentation files'):
                gate.check(root)

if __name__ == '__main__':
    unittest.main()
