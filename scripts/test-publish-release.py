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

    def test_publication_drops_pre_rename_entries(self):
        with tempfile.TemporaryDirectory() as temp:
            root,stage=Path(temp)/"releases",Path(temp)/"stage";stage.mkdir();root.mkdir()
            old={"version":"1.0.242","filename":"TranscriptStudio-1.0.242.dmg"}
            link={"version":"1.0.338","url":"https://testflight.apple.com/join/abc"}
            (root/"releases.json").write_text(json.dumps({"latest_version":"1.0.242","macos":old,"android":dict(old,filename="TranscriptStudio-1.0.242.apk"),"macos_testflight":link}))
            artifact=stage/"ThoughtVault_1.0.338_x64.msi";artifact.write_bytes(b"installer")
            Path(str(artifact)+".sig").write_text(base64.b64encode(b"signed MSI").decode())
            publisher.publish(root,stage,"1.0.338","production")
            manifest=json.loads((root/"releases.json").read_text())
            self.assertNotIn("macos",manifest);self.assertNotIn("android",manifest)
            self.assertEqual(manifest["latest_version"],"1.0.242")
            self.assertEqual(manifest["macos_testflight"],link)
            self.assertEqual(manifest["windows_x64"]["filename"],artifact.name)

    def test_testflight_upload_moves_only_the_testflight_version(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            windows={"version":"1.0.344","filename":"ThoughtVault_1.0.344_x64.msi"}
            (root/"releases.json").write_text(json.dumps({"latest_version":"1.0.242","windows":windows,"macos_testflight":{"version":"1.0.338","url":"https://testflight.apple.com/join/abc"}}))
            publisher.set_testflight(root,"1.0.345")
            manifest=json.loads((root/"releases.json").read_text())
            self.assertEqual(manifest["macos_testflight"],{"version":"1.0.345","url":"https://testflight.apple.com/join/abc"})
            self.assertEqual(manifest["windows"],windows);self.assertEqual(manifest["latest_version"],"1.0.242")
            with self.assertRaises(ValueError): publisher.set_testflight(root,"1.0.344")
            with self.assertRaises(ValueError): publisher.set_testflight(root,"1.0.345; rm")

    def test_unnotarized_mac_cannot_be_published(self):
        with tempfile.TemporaryDirectory() as temp:
            root,stage=Path(temp)/"release",Path(temp)/"stage";stage.mkdir()
            artifact=stage/"ThoughtVault-1.0.256.dmg";artifact.write_bytes(b"dmg")
            Path(str(artifact)+".sparkle.json").write_text(json.dumps({"signature":base64.b64encode(bytes(64)).decode(),"build_number":"256","notarized":False}))
            with self.assertRaises(ValueError):publisher.publish(root,stage,"1.0.256","production")
            self.assertFalse((root/"releases.json").exists())

if __name__ == "__main__": unittest.main()
