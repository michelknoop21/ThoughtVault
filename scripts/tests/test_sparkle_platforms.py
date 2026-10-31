"""The shared app must build Sparkle only on macOS, and still link it there."""
import json
from pathlib import Path
import subprocess
import unittest

PROJECT = Path(__file__).resolve().parents[2] / "ThoughtVault.xcodeproj/project.pbxproj"


class SparklePlatformsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.objects = json.loads(subprocess.check_output(
            ["plutil", "-convert", "json", "-o", "-", str(PROJECT)]))["objects"]
        cls.app = cls.objects["TT000001"]

    def allowed(self, obj, platform):
        return obj.get("platformFilter", platform) == platform and (
            "platformFilters" not in obj or platform in obj["platformFilters"])

    def products(self, platform):
        products = set(self.app.get("packageProductDependencies", []))
        for ref in self.app.get("dependencies", []):
            dep = self.objects[ref]
            if self.allowed(dep, platform) and "productRef" in dep:
                products.add(dep["productRef"])
        return {self.objects[ref]["productName"] for ref in products}

    def test_ios_has_no_sparkle_build_dependency(self):
        self.assertNotIn("Sparkle", self.products("ios"))
        self.assertIn("WhisperKit", self.products("ios"))

    def test_macos_keeps_sparkle_build_dependency_and_version(self):
        self.assertIn("Sparkle", self.products("macos"))
        self.assertEqual(self.objects["SPUP0001"]["requirement"],
                         {"kind": "exactVersion", "version": "2.10.0"})

    def test_sparkle_link_remains_macos_only(self):
        links = [self.objects[file] for phase in self.app["buildPhases"]
                 if self.objects[phase]["isa"] == "PBXFrameworksBuildPhase"
                 for file in self.objects[phase]["files"]
                 if self.objects[file].get("productRef") == "SDUP0001"]
        self.assertEqual(len(links), 1)
        self.assertTrue(self.allowed(links[0], "macos"))
        self.assertFalse(self.allowed(links[0], "ios"))


if __name__ == "__main__":
    unittest.main()
