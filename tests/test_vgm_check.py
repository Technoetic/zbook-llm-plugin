"""Exercise the read-only VGM policy with CIM hardware fixtures."""

from pathlib import Path
import shutil
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "plugins" / "zbook-llm" / "scripts" / "vgm-check.ps1"
FIXTURES = Path(__file__).resolve().parent / "fixtures"
POWERSHELL = shutil.which("powershell.exe")


@unittest.skipUnless(POWERSHELL, "Windows PowerShell 5.1 is required")
class VgmCheckTests(unittest.TestCase):
    def run_scenario(self, name):
        result = subprocess.run(
            [
                POWERSHELL,
                "-NoProfile",
                "-NonInteractive",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(FIXTURES / "vgm-cim-runner.ps1"),
                "-ScriptPath",
                str(SCRIPT),
                "-ScenarioPath",
                str(FIXTURES / f"vgm-{name}.json"),
            ],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=20,
        )
        return result.returncode, result.stdout + result.stderr

    def test_current_16_gb_satisfies_policy_without_mutation(self):
        code, output = self.run_scenario("16gb")
        self.assertEqual(0, code, output)
        self.assertIn("Configured GPU memory (HP BIOS): 16 GB", output)
        self.assertIn("PASS", output)

    def test_current_32_gb_fails_policy_without_changing_it(self):
        code, output = self.run_scenario("32gb")
        self.assertEqual(1, code, output)
        self.assertIn("Configured GPU memory (HP BIOS): 32 GB", output)
        self.assertIn("expected 16 GB", output)
        self.assertNotIn("PASS", output)

    def test_unavailable_bios_namespace_cannot_confirm_policy(self):
        code, output = self.run_scenario("bios-unavailable")
        self.assertEqual(2, code, output)
        self.assertIn("cannot confirm", output)
        self.assertIn("HP BIOS", output)
        self.assertNotIn("PASS", output)

    def test_missing_bios_setting_cannot_confirm_policy(self):
        code, output = self.run_scenario("setting-missing")
        self.assertEqual(2, code, output)
        self.assertIn("cannot confirm", output)
        self.assertIn("Dedicated Graphics Memory", output)
        self.assertNotIn("PASS", output)

    def test_installed_memory_uses_modules_instead_of_os_usable_total(self):
        code, output = self.run_scenario("16gb")
        self.assertEqual(0, code, output)
        self.assertIn("Installed RAM (DIMM capacity sum): 64.00 GiB", output)
        self.assertIn("OS-visible RAM (total, not currently free): 47.78 GiB", output)

    def test_missing_physical_memory_is_not_reported_as_zero_or_success(self):
        code, output = self.run_scenario("ram-missing")
        self.assertEqual(2, code, output)
        self.assertIn("cannot confirm", output)
        self.assertNotIn("PASS", output)


if __name__ == "__main__":
    unittest.main()
