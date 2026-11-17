"""Version sync must keep Cargo's app lock entry usable with --locked."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class SyncVersionTests(unittest.TestCase):
    def test_syncs_app_lock_version_without_changing_dependencies(self):
        with tempfile.TemporaryDirectory(dir=ROOT) as temp:
            root = Path(temp)
            (root / 'scripts').mkdir()
            (root / 'windows/src-tauri').mkdir(parents=True)
            shutil.copy2(ROOT / 'scripts/sync-version.sh', root / 'scripts/sync-version.sh')
            (root / 'VERSION').write_text('1.2.3\n')
            lock = root / 'windows/src-tauri/Cargo.lock'
            lock.write_text('version = 4\n\n[[package]]\nname = "dependency"\nversion = "8.9.0"\n\n[[package]]\nname = "thoughtvault"\nversion = "1.0.310"\n\n[[package]]\nname = "other"\nversion = "2.0.0"\n')
            before = lock.read_text()
            subprocess.run(['bash', str(root / 'scripts/sync-version.sh')], check=True, capture_output=True)
            self.assertEqual(lock.read_text(), before.replace('version = "1.0.310"', 'version = "1.2.3"'))


if __name__ == '__main__':
    unittest.main()
