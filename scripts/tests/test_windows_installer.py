import json
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[2]
NS = {"w": "http://schemas.microsoft.com/wix/2006/wi"}


class WindowsInstallerTests(unittest.TestCase):
    def setUp(self):
        self.config = json.loads((ROOT / "windows/src-tauri/tauri.conf.json").read_text())
        template = self.config["bundle"]["windows"]["wix"]["template"]
        self.template = ET.parse(ROOT / "windows/src-tauri" / template).getroot()

    def test_machine_components_do_not_depend_on_user_registry_keys(self):
        components = self.template.findall(".//w:DirectoryRef[@Id='INSTALLDIR']/w:Component", NS)
        self.assertTrue(components)
        for component in components:
            roots = {node.get("Root") for node in component.iter() if node.get("Root")}
            self.assertNotIn("HKCU", roots, component.get("Id"))
        registry = next(c for c in components if c.get("Id") == "RegistryEntries")
        key = registry.find("w:RegistryKey", NS)
        self.assertEqual(key.get("Root"), "HKLM")
        self.assertEqual(registry.get("Win64"), "$(var.Win64)")
        self.assertIsNone(self.template.find(".//w:ComponentRef[@Id='CMP_UninstallShortcut']", NS))

    def test_only_forward_upgrades_keep_the_existing_application_identity(self):
        windows = self.config["bundle"]["windows"]
        self.assertFalse(windows["allowDowngrades"])
        self.assertEqual(windows["wix"]["upgradeCode"].lower(), "7358330f-1c84-5898-90db-45fe21eb4f31")
        self.assertEqual(self.config["identifier"], "nl.prezent.transcript-studio")
        self.assertTrue(self.config["bundle"]["createUpdaterArtifacts"])
        upgrades = self.template.findall(".//w:MajorUpgrade", NS)
        self.assertEqual(len(upgrades), 1)
        self.assertNotEqual(upgrades[0].get("AllowDowngrades"), "yes")
        self.assertNotEqual(upgrades[0].get("AllowSameVersionUpgrades"), "yes")
        self.assertTrue(upgrades[0].get("DowngradeErrorMessage"))
        self.assertIsNone(self.template.find(".//w:Property[@Id='REINSTALLMODE']", NS))

    def test_machine_install_path_takes_priority_without_losing_legacy_upgrades(self):
        searches = self.template.findall(".//w:Property[@Id='INSTALLDIR']/w:RegistrySearch", NS)
        self.assertEqual([s.get("Root") for s in searches], ["HKCU", "HKCU", "HKLM"])
        self.assertEqual(searches[-1].get("Name"), "InstallDir")
        self.assertEqual(searches[-1].get("Win64"), "$(var.Win64)")


if __name__ == "__main__":
    unittest.main()
