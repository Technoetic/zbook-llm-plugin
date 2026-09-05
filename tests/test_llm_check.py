"""Black-box checks: no real HTTP calls, processes or BIOS changes."""
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
POWERSHELL = shutil.which("powershell.exe")


@unittest.skipUnless(POWERSHELL, "Windows PowerShell 5.1 required")
class LlmCheckTests(unittest.TestCase):
    def check_scenario(self, scenario, expected):
        result = subprocess.run(
            [POWERSHELL, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
             "-File", str(ROOT / "tests/fixtures/llm-check-fixture.ps1"),
             "-Scenario", scenario, "-ScriptPath",
             str(ROOT / "plugins/zbook-llm/scripts/llm-check.ps1")],
            capture_output=True, encoding="utf-8", errors="replace", timeout=15,
        )
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        self.assertEqual("PASS" in result.stdout, expected == 0, result.stdout)

    def test_correct_complete_answer(self): self.check_scenario("good", 0)
    def test_custom_port(self): self.check_scenario("custom-port", 0)
    def test_discovered_model_is_used(self): self.check_scenario("model-id", 0)
    def test_unicode_model_id_is_sent_as_utf8_bytes(self): self.check_scenario("unicode-model", 0)
    def test_health_unavailable(self): self.check_scenario("offline", 1)
    def test_health_loading(self): self.check_scenario("loading", 1)
    def test_empty_models(self): self.check_scenario("empty-models", 2)
    def test_configured_key_rejected(self): self.check_scenario("bad-key", 2)
    def test_missing_key_accepted(self): self.check_scenario("no-auth", 2)
    def test_any_key_accepted(self): self.check_scenario("any-key", 2)
    def test_probe_network_error_is_not_auth_rejection(self): self.check_scenario("probe-offline", 2)
    def test_probe_503_is_not_auth_rejection(self): self.check_scenario("probe-loading", 2)
    def test_wrong_answer(self): self.check_scenario("wrong-answer", 3)
    def test_truncated_answer_even_if_digit_correct(self): self.check_scenario("truncated", 3)
    def test_thinking_in_content(self): self.check_scenario("thinking", 3)
    def test_empty_answer(self): self.check_scenario("empty-answer", 3)
    def test_missing_finish_reason(self): self.check_scenario("missing-finish", 3)


if __name__ == "__main__":
    unittest.main()
