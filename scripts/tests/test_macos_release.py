"""Static checks: macOS release uses the real bundle ID and Developer ID signing, never ad-hoc."""
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
ENV = (ROOT / "scripts/env.sh").read_text()
SCRIPT_PATH = ROOT / "scripts/build-macos-release.sh"
CI = (ROOT / ".gitlab-ci.yml").read_text()


def job(name):
    m = re.search(rf"^{name}:\n(.*?)(?=^\S)", CI + "\nx", re.M | re.S)
    return m.group(1)


class MacosReleaseTests(unittest.TestCase):
    def test_env_bundle_ids(self):
        self.assertIn('BUNDLE_ID_MACOS="com.buildmind.ThoughtVault"', ENV)
        self.assertIn('BUNDLE_ID_MACOS="com.buildmind.ThoughtVault.dev"', ENV)
        self.assertNotIn("nl.prezent.ThoughtVault", ENV)

    def test_release_script(self):
        self.assertTrue(SCRIPT_PATH.is_file())
        self.assertTrue(SCRIPT_PATH.stat().st_mode & 0o111)
        s = SCRIPT_PATH.read_text()
        self.assertEqual(s.count("notarytool submit"), 2)
        self.assertGreaterEqual(s.count("stapler staple"), 2)
        for needle in ("sign_update", '--key "$APPLE_API_KEY_PATH"', "Developer ID Application"):
            self.assertIn(needle, s)
        for bad in ("--keychain-profile", "CODE_SIGNING_ALLOWED=NO"):
            self.assertNotIn(bad, s)

    def test_release_script_syntax(self):
        subprocess.run(["bash", "-n", str(SCRIPT_PATH)], check=True)

    def test_ci(self):
        self.assertIn("scripts/build-macos-release.sh", job("build-macos"))
        self.assertIn("scripts/publish-release.py", job("deploy"))
        self.assertNotIn("nl.prezent.ThoughtVault", CI)
        for name in ("build-macos", "deploy"):
            j = job(name)
            self.assertNotIn("CODE_SIGNING_ALLOWED=NO", j)
            self.assertNotIn("--sign -", j)


if __name__ == "__main__":
    unittest.main()
