import base64
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("publisher", Path(__file__).with_name("publish-release.py"))
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)

class PublicationTest(unittest.TestCase):
    def test_signed_windows_does_not_announce_a_missing_mac(self):
        with tempfile.TemporaryDirectory() as temp:
            root, stage = Path(temp)/"releases", Path(temp)/"stage"
            stage.mkdir(); root.mkdir()
            (root/"releases.json").write_text(json.dumps({"latest_version":"1.0.255","macos":{"version":"1.0.255"}}))
            artifact=stage/"ThoughtVault_1.0.256_x64.msi"
            artifact.write_bytes(b"installer")
            with self.assertRaises(FileNotFoundError): publisher.publish(root,stage,"1.0.256","production")
            self.assertFalse((root/artifact.name).exists())
            Path(str(artifact)+".sig").write_text(base64.b64encode(b"signed MSI").decode())
            publisher.publish(root,stage,"1.0.256","production")
            manifest=json.loads((root/"releases.json").read_text())
            feed=json.loads((root/"windows/stable.json").read_text())
            self.assertEqual(manifest["latest_version"],"1.0.255")
            self.assertEqual(feed["platforms"]["windows-x86_64"]["url"],publisher.BASE+artifact.name)
            self.assertEqual(manifest["windows_x64"]["url"],publisher.BASE+artifact.name)
            artifact.write_bytes(b"changed")
            with self.assertRaises(ValueError): publisher.publish(root,stage,"1.0.256","production")
            self.assertEqual((root/artifact.name).read_bytes(),b"installer")

    def test_unnotarized_mac_cannot_be_published(self):
        with tempfile.TemporaryDirectory() as temp:
            root,stage=Path(temp)/"release",Path(temp)/"stage";stage.mkdir()
            artifact=stage/"ThoughtVault-1.0.256.dmg";artifact.write_bytes(b"dmg")
            Path(str(artifact)+".sparkle.json").write_text(json.dumps({"signature":base64.b64encode(bytes(64)).decode(),"build_number":"256","notarized":False}))
            with self.assertRaises(ValueError):publisher.publish(root,stage,"1.0.256","production")
            self.assertFalse((root/"releases.json").exists())

if __name__ == "__main__": unittest.main()
