"""Behavioral startup regressions using isolated Windows PowerShell fixtures."""

import base64
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest


REPO = Path(__file__).resolve().parents[1]
SCRIPT = REPO / "plugins" / "zbook-llm" / "scripts" / "llm-up.ps1"
HARNESS = Path(__file__).resolve().parent / "fixtures" / "llm-up-harness.ps1"
POWERSHELL = shutil.which("powershell.exe")


@unittest.skipUnless(os.name == "nt" and POWERSHELL, "Windows PowerShell 5.1 required")
class LlmUpTests(unittest.TestCase):
    def run_up(self, *, default="small model.gguf", installed=True, extra_models=None,
               generic_models=True, **overrides):
        with tempfile.TemporaryDirectory(prefix="llm up regression ") as name:
            root = Path(name)
            models = root / "LLM" / "models"
            if installed:
                models.mkdir(parents=True)
                if generic_models:
                    (models / "small model.gguf").write_bytes(b"GGUF")
                    (models / "large model.gguf").write_bytes(b"GGUF" * 8)
                for filename, size in (extra_models or {}).items():
                    (models / filename).write_bytes(b"G" * size)
                (models / "pretend.gguf").mkdir()
                (models / "not-a-model.txt").write_text("ignore", encoding="utf-8")
                if default is not None:
                    (models / "default.txt").write_text(default, encoding="utf-8-sig")
                binary = root / "LLM" / "bin" / "b5678" / "llama-server.exe"
                binary.parent.mkdir(parents=True)
                binary.write_bytes(b"fixture only: never execute")
            scenario = {
                "temp": str(root), "port": 18080, "busy": False,
                "processName": "llama-server", "healthStatus": 200,
                "healthBody": {"status": "ok"}, "modelsStatus": 200,
                "modelsBody": {"object": "list", "data": [
                    {"id": "small model.gguf", "object": "model", "owned_by": "llamacpp"}
                ]},
                "missingStatus": 401, "wrongStatus": 403,
                "startFault": "", "nativeArguments": False, "processExited": False,
            }
            scenario.update(overrides)
            config = root / "scenario.json"
            config.write_text(json.dumps(scenario), encoding="utf-8")
            command = [POWERSHELL, "-NoLogo", "-NoProfile", "-NonInteractive",
                       "-ExecutionPolicy", "Bypass", "-File", str(HARNESS),
                       "-TargetScript", str(SCRIPT), "-ScenarioFile", str(config)]
            with subprocess.Popen(command, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  encoding="utf-8", errors="replace") as process:
                captured_before_release = False
                try:
                    stdout, stderr = process.communicate(timeout=8 if scenario.get("captureChild") else 30)
                    captured_before_release = ((root / "child-started").exists()
                                               and not (root / "child-exited").exists())
                except subprocess.TimeoutExpired:
                    if not scenario.get("captureChild"):
                        process.kill()
                        process.communicate()
                        raise
                    (root / "release-child").touch()
                    stdout, stderr = process.communicate(timeout=10)
                finally:
                    (root / "release-child").touch()
                    if (root / "child-started").exists():
                        deadline = time.monotonic() + 5
                        while not (root / "child-exited").exists() and time.monotonic() < deadline:
                            time.sleep(0.05)
                result = subprocess.CompletedProcess(command, process.returncode, stdout, stderr)
                result.captured_before_release = captured_before_release
            event_file = root / "events.jsonl"
            events = ([json.loads(line) for line in event_file.read_text(encoding="utf-8-sig").splitlines()]
                      if event_file.exists() else [])
            argv_file = root / "argv.txt"
            argv = ([base64.b64decode(line).decode("utf-8") for line in argv_file.read_text().splitlines()]
                    if argv_file.exists() else [])
            return result, events, argv, models

    def assert_failed_without_start(self, result, events):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(any(event["kind"] == "start" for event in events), events)

    def test_healthy_existing_server_works_without_installation(self):
        result, events, _, _ = self.run_up(busy=True, installed=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(any(event["kind"] == "scan-installation" for event in events), events)
        self.assertFalse(any(event["kind"] == "start" for event in events), events)

    def test_existing_server_requires_health_ok(self):
        for status in (401, 503, 0):
            with self.subTest(status=status):
                result, events, _, _ = self.run_up(busy=True, healthStatus=status)
                self.assert_failed_without_start(result, events)

    def test_existing_server_rejects_unhealthy_response(self):
        result, events, _, _ = self.run_up(busy=True, healthBody={"status": "loading model"})
        self.assert_failed_without_start(result, events)

    def test_existing_server_requires_authenticated_models(self):
        for status in (401, 503):
            with self.subTest(status=status):
                result, events, _, _ = self.run_up(busy=True, modelsStatus=status)
                self.assert_failed_without_start(result, events)

    def test_existing_server_rejects_malformed_model_lists(self):
        for body in ({}, {"data": []}, {"data": [{"id": " "}]}, {"data": [{"id": 42}]}):
            with self.subTest(body=body):
                result, events, _, _ = self.run_up(busy=True, modelsBody=body)
                self.assert_failed_without_start(result, events)

    def test_existing_server_requires_missing_and_wrong_keys_rejected(self):
        for change in ({"missingStatus": 200}, {"wrongStatus": 200},
                       {"missingStatus": 503}, {"wrongStatus": 0}):
            with self.subTest(change=change):
                result, events, _, _ = self.run_up(busy=True, **change)
                self.assert_failed_without_start(result, events)

    def test_healthy_existing_server_checks_three_auth_cases(self):
        result, events, _, _ = self.run_up(busy=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        http = [event["details"] for event in events if event["kind"] == "http"]
        self.assertEqual({event["key"] for event in http if event["path"] == "/v1/models"},
                         {"correct", "missing", "wrong"})
        self.assertTrue(all(0 < event["timeout"] <= 3 for event in http), http)

    def test_unrelated_listener_is_never_replaced(self):
        result, events, _, _ = self.run_up(busy=True, processName="other-server")
        self.assert_failed_without_start(result, events)

    def test_default_model_fallback_always_selects_gguf_file(self):
        for default in (None, "", " \r\n ", "missing.gguf", "pretend.gguf", "not-a-model.txt"):
            with self.subTest(default=default):
                result, events, argv, models = self.run_up(default=default, nativeArguments=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(argv[argv.index("-m") + 1], str(models / "small model.gguf"))

    def test_valid_default_model_takes_precedence(self):
        result, _, argv, models = self.run_up(default="large model.gguf", nativeArguments=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(argv[argv.index("-m") + 1], str(models / "large model.gguf"))

    def test_unpinned_model_prefers_installed_9b_even_when_smaller_models_exist(self):
        for default in (None, "missing.gguf"):
            with self.subTest(default=default):
                result, _, argv, models = self.run_up(
                    default=default, nativeArguments=True, extra_models={
                        "Qwen3.5-9B-Q8_0.gguf": 90, "Qwen3.5-4B-Q8_0.gguf": 40})
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(argv[argv.index("-m") + 1], str(models / "Qwen3.5-9B-Q8_0.gguf"))

    def test_unpinned_model_prefers_installed_4b_when_9b_is_absent(self):
        result, _, argv, models = self.run_up(
            default=None, nativeArguments=True, extra_models={"Qwen3.5-4B-Q8_0.gguf": 40})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(argv[argv.index("-m") + 1], str(models / "Qwen3.5-4B-Q8_0.gguf"))

    def test_explicit_4b_selection_is_preserved_when_9b_is_installed(self):
        result, _, argv, models = self.run_up(
            default="Qwen3.5-4B-Q8_0.gguf", nativeArguments=True, extra_models={
                "Qwen3.5-9B-Q8_0.gguf": 90, "Qwen3.5-4B-Q8_0.gguf": 40})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(argv[argv.index("-m") + 1], str(models / "Qwen3.5-4B-Q8_0.gguf"))

    def test_automatic_fallback_does_not_launch_a_projection_file(self):
        result, _, argv, models = self.run_up(
            default=None, nativeArguments=True, extra_models={"mmproj-Qwen3.5-9B-F16.gguf": 1})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(argv[argv.index("-m") + 1], str(models / "small model.gguf"))

    def test_projection_only_installation_fails_without_starting(self):
        result, events, _, _ = self.run_up(default=None, generic_models=False,
                                           extra_models={"mmproj-Qwen3.5-9B-F16.gguf": 1})
        self.assert_failed_without_start(result, events)

    def test_captured_launcher_returns_while_background_child_is_alive(self):
        result, _, _, _ = self.run_up(captureChild=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(result.captured_before_release,
                        "captured launcher output waited for the long-lived child to exit")
        self.assertNotIn("background stdout", result.stdout)

    def test_native_arguments_preserve_paths_spaces_and_loopback(self):
        result, events, argv, models = self.run_up(nativeArguments=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(argv[argv.index("-m") + 1], str(models / "small model.gguf"))
        self.assertEqual(argv[argv.index("--log-file") + 1], str(models.parent / "logs" / "server.log"))
        self.assertEqual(argv[argv.index("--host") + 1], "127.0.0.1")
        self.assertEqual(argv[argv.index("--port") + 1], "18080")
        self.assertEqual(argv[argv.index("--api-key") + 1], "ns-local")
        self.assertEqual(next(event["details"]["windowStyle"] for event in events
                              if event["kind"] == "start"), "Hidden")

    def test_launch_throw_or_null_fails_without_polling(self):
        for fault in ("throw", "null"):
            with self.subTest(fault=fault):
                result, events, _, _ = self.run_up(startFault=fault)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertFalse(any(event["kind"] == "sleep" for event in events), events)
                self.assertIn("[중단]", result.stdout)

    def test_new_server_requires_models_and_auth_before_success(self):
        for change in ({"modelsStatus": 401}, {"modelsBody": {"data": []}},
                       {"missingStatus": 200}, {"wrongStatus": 200}):
            with self.subTest(change=change):
                result, _, _, _ = self.run_up(**change)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_new_server_exit_is_reported(self):
        result, _, _, _ = self.run_up(processExited=True, startupLog="fixture model loading failed")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("17", result.stdout)
        self.assertIn("fixture model loading failed", result.stdout)

    def test_invalid_ports_are_rejected_before_any_side_effect(self):
        for port in (0, -1, 65536):
            with self.subTest(port=port):
                result, events, _, _ = self.run_up(port=port)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(events, [])


if __name__ == "__main__":
    unittest.main()
