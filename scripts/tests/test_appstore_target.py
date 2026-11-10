"""The TestFlight/App Store macOS build must come from a Sparkle-free target.

App Store validation rejects Sparkle's helper executables (Autoupdate, Updater.app,
Downloader.xpc, Installer.xpc) because they lack the app-sandbox entitlement.
"""
import json
from pathlib import Path
import plistlib
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / "ThoughtVault.xcodeproj/project.pbxproj"
ENTITLEMENTS = ROOT / "macos/ThoughtVault-AppStore.entitlements"
SCHEME = ROOT / "ThoughtVault.xcodeproj/xcshareddata/xcschemes/ThoughtVault AppStore.xcscheme"


class AppStoreTargetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.objects = json.loads(subprocess.check_output(
            ["plutil", "-convert", "json", "-o", "-", str(PROJECT)]))["objects"]
        targets = {o["name"]: o for o in cls.objects.values() if o["isa"] == "PBXNativeTarget"}
        cls.app = targets["ThoughtVault"]
        cls.store = targets["ThoughtVault AppStore"]

    def phase(self, target, isa):
        return next(self.objects[p] for p in target["buildPhases"] if self.objects[p]["isa"] == isa)

    def file_refs(self, target, isa):
        return sorted(self.objects[f]["fileRef"] for f in self.phase(target, isa)["files"])

    def products(self, target):
        refs = set(target.get("packageProductDependencies", []))
        refs |= {self.objects[f]["productRef"]
                 for f in self.phase(target, "PBXFrameworksBuildPhase")["files"]}
        refs |= {self.objects[d]["productRef"] for d in target.get("dependencies", [])
                 if "productRef" in self.objects[d]}
        return {self.objects[r]["productName"] for r in refs}

    def settings(self, target):
        cfgs = self.objects[target["buildConfigurationList"]]["buildConfigurations"]
        return {self.objects[c]["name"]: self.objects[c]["buildSettings"] for c in cfgs}

    def test_store_target_has_no_sparkle(self):
        self.assertEqual(self.products(self.store), {"WhisperKit"})
        self.assertIn("Sparkle", self.products(self.app))

    def test_store_target_builds_the_same_app(self):
        for isa in ("PBXSourcesBuildPhase", "PBXResourcesBuildPhase"):
            self.assertEqual(self.file_refs(self.store, isa), self.file_refs(self.app, isa))
        app = self.settings(self.app)
        for name, cfg in self.settings(self.store).items():
            self.assertEqual(cfg["SUPPORTED_PLATFORMS"], "macosx")
            self.assertEqual(cfg["PRODUCT_NAME"], "ThoughtVault")
            self.assertIn("APP_STORE", cfg["SWIFT_ACTIVE_COMPILATION_CONDITIONS"].split())
            self.assertEqual(cfg["CODE_SIGN_ENTITLEMENTS"], "macos/ThoughtVault-AppStore.entitlements")
            for key in ("PRODUCT_BUNDLE_IDENTIFIER", "MARKETING_VERSION", "CURRENT_PROJECT_VERSION",
                        "INFOPLIST_FILE", "DEVELOPMENT_TEAM", "CODE_SIGN_STYLE"):
                self.assertEqual(cfg[key], app[name][key], key)

    def test_store_entitlements_drop_sparkle_exception_only(self):
        store = plistlib.loads(ENTITLEMENTS.read_bytes())
        app = plistlib.loads((ROOT / "macos/ThoughtVault.entitlements").read_bytes())
        self.assertNotIn("com.apple.security.temporary-exception.mach-lookup.global-name", store)
        self.assertTrue(store["com.apple.security.app-sandbox"])
        app.pop("com.apple.security.temporary-exception.mach-lookup.global-name")
        self.assertEqual(store, app)

    def test_testflight_archives_macos_with_store_scheme(self):
        script = (ROOT / "scripts/testflight.sh").read_text()
        self.assertIn('"macos" "ThoughtVault AppStore"', script)
        self.assertIn('"$BUILD_DIR/ExportOptions-iOS-TestFlight.plist" "" ThoughtVault\n', script)
        self.assertIn(f'BlueprintIdentifier = "{self.store_id()}"', SCHEME.read_text())

    def store_id(self):
        return next(k for k, o in self.objects.items() if o is self.store)


if __name__ == "__main__":
    unittest.main()
