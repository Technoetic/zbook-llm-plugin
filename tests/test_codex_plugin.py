"""Exercise native skill discovery with an installed Codex CLI, without inference.

Run: python -m unittest discover -s tests -p test_codex_plugin.py -v
The Windows integration test skips when the native Codex executable is absent.
All configuration/cache writes belong to a temporary CODEX_HOME; no auth is copied.
"""
import json
import os
from pathlib import Path
import queue
import re
import shutil
import subprocess
import tempfile
import threading
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]
EXPECTED = {"llm-check", "llm-up", "vgm-check"}
EXPECTED_SCRIPTS = {
    "llm-check": {"llm-check.ps1"},
    "llm-up": {"llm-up.ps1", "llm-check.ps1"},
    "vgm-check": {"vgm-check.ps1"},
}
PLUGIN_ID = "zbook-llm@zbook-tools"
HIDDEN = getattr(subprocess, "CREATE_NO_WINDOW", 0)


def find_codex_executable():
    """Resolve the native executable used by the npm codex.cmd launcher.

    Starting it directly lets timeout cleanup target exactly the owned process,
    without leaving a cmd.exe/node.exe wrapper or its child running.
    """
    direct = shutil.which("codex.exe")
    if direct:
        return Path(direct)
    launcher = shutil.which("codex.cmd")
    if launcher:
        package = Path(launcher).parent / "node_modules" / "@openai" / "codex"
        candidates = list(package.glob("node_modules/@openai/codex-win32-*/vendor/*/bin/codex.exe"))
        candidates += list(package.glob("vendor/*/bin/codex.exe"))
        if len(candidates) == 1:
            return candidates[0]
    return None


class AppServer:
    """Small stdio client for the three local discovery protocol messages."""

    def __init__(self, executable, cwd, environment):
        self.messages = queue.Queue()
        self.stderr = []
        self.process = subprocess.Popen(
            [str(executable), "app-server", "--stdio"], cwd=cwd, env=environment,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, encoding="utf-8", bufsize=1, creationflags=HIDDEN,
        )
        self.threads = [threading.Thread(target=self.read_stdout, daemon=True),
                        threading.Thread(target=self.read_stderr, daemon=True)]
        for thread in self.threads:
            thread.start()

    def read_stdout(self):
        for line in self.process.stdout:
            try:
                self.messages.put(json.loads(line))
            except ValueError:
                self.messages.put({"error": {"invalid_json": line}})
        self.messages.put({"error": "app-server closed stdout"})

    def read_stderr(self):
        self.stderr.extend(self.process.stderr)

    def request(self, method, params=None, request_id=None):
        message = {"method": method}
        if params is not None:
            message["params"] = params
        if request_id is not None:
            message["id"] = request_id
        self.process.stdin.write(json.dumps(message) + "\n")
        self.process.stdin.flush()
        if request_id is None:
            return None
        deadline = time.monotonic() + 45
        while time.monotonic() < deadline:
            response = self.messages.get(timeout=max(0.01, deadline - time.monotonic()))
            if "error" in response:
                raise AssertionError(f"{method}: {response['error']}; stderr={self.stderr}")
            if response.get("id") == request_id:
                return response["result"]
        raise TimeoutError(f"No response to {method}; stderr={self.stderr}")

    def close(self):
        self.process.stdin.close()
        try:
            self.process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.process.terminate()
            self.process.wait(timeout=5)
        for thread in self.threads:
            thread.join(timeout=2)
        self.process.stdout.close()
        self.process.stderr.close()


@unittest.skipUnless(os.name == "nt", "requires Windows and Codex CLI")
class NativeCodexPluginTests(unittest.TestCase):
    def test_relocated_plugin_installs_and_discovers_native_skills(self):
        executable = find_codex_executable()
        if executable is None:
            self.skipTest("native Codex executable not installed (codex.exe or npm codex.cmd)")
        with tempfile.TemporaryDirectory(prefix="zbook-codex-") as temp:
            scratch = Path(temp)
            repo = scratch / "이동 경로" / "marketplace"
            repo.mkdir(parents=True)
            # Copy only distributable plugin/marketplace files, never user config/auth.
            for folder in ("plugins", ".agents", ".claude-plugin"):
                if (ROOT / folder).exists():
                    shutil.copytree(ROOT / folder, repo / folder)
            cwd = scratch / "무관한 작업 폴더"
            cwd.mkdir()
            codex_home = scratch / "격리 Codex Home"
            codex_home.mkdir()
            environment = os.environ.copy()
            environment["CODEX_HOME"] = str(codex_home)

            def run(arguments):
                result = subprocess.run(
                    [str(executable), *arguments], cwd=cwd, env=environment,
                    capture_output=True, text=True, encoding="utf-8",
                    timeout=45, creationflags=HIDDEN,
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                return json.loads(result.stdout)

            marketplace = run(["plugin", "marketplace", "add", str(repo), "--json"])
            self.assertEqual(marketplace["marketplaceName"], "zbook-tools")
            installed = run(["plugin", "add", PLUGIN_ID, "--json"])
            cache_root = Path(installed["installedPath"]).resolve()
            self.assertTrue(cache_root.is_relative_to(codex_home.resolve()))

            server = AppServer(executable, cwd, environment)
            try:
                initialized = server.request("initialize", {
                    "clientInfo": {"name": "zbook-native-skill-test", "version": "1.0"},
                    "capabilities": {"experimentalApi": True},
                }, 1)
                self.assertEqual(Path(initialized["codexHome"]).resolve(), codex_home.resolve())
                server.request("initialized")
                discovered = server.request("skills/list", {
                    "cwds": [str(cwd)], "forceReload": True,
                }, 2)
            finally:
                server.close()
            self.assertEqual(server.process.returncode, 0, "".join(server.stderr))
            self.assertEqual(len(discovered["data"]), 1)
            entry = discovered["data"][0]
            self.assertEqual(entry["errors"], [])
            skills = [skill for skill in entry["skills"] if skill.get("pluginId") == PLUGIN_ID]
            self.assertEqual({skill["name"] for skill in skills},
                             {f"zbook-llm:{name}" for name in EXPECTED})
            self.assertEqual(len(skills), len(EXPECTED))
            self.assertEqual(list(cache_root.rglob("migrated-command-skills")), [])

            for skill in skills:
                name = skill["name"].split(":", 1)[1]
                path = Path(skill["path"]).resolve(strict=True)
                self.assertTrue(skill["enabled"])
                self.assertEqual(path, cache_root / "skills" / name / "SKILL.md")
                source = repo / "plugins" / "zbook-llm" / "skills" / name / "SKILL.md"
                self.assertEqual(path.read_bytes(), source.read_bytes())
                references = set(re.findall(r"(?<![./])(?:\.\./)+scripts/[\w-]+\.ps1",
                                            path.read_text(encoding="utf-8")))
                self.assertEqual(references, {"../../scripts/" + filename
                                              for filename in EXPECTED_SCRIPTS[name]})
                for relative in references:
                    resolved = (path.parent / relative).resolve(strict=True)
                    self.assertEqual(resolved, cache_root / "scripts" / Path(relative).name)
                    # Resolve the path with the consumer shell, without running the script.
                    quoted = str(path.parent / relative).replace("'", "''")
                    result = subprocess.run(
                        ["powershell.exe", "-NoProfile", "-NonInteractive", "-Command",
                         f"[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); "
                         f"(Resolve-Path -LiteralPath '{quoted}' -ErrorAction Stop).Path"],
                        cwd=cwd, env=environment, capture_output=True, text=True,
                        encoding="utf-8", timeout=15, creationflags=HIDDEN,
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(Path(result.stdout.strip()).resolve(), resolved)

            versions = {installed["version"]}
            for plugin_root in (repo / "plugins" / "zbook-llm", cache_root):
                for manifest in (".codex-plugin/plugin.json", ".claude-plugin/plugin.json"):
                    data = json.loads((plugin_root / manifest).read_text(encoding="utf-8"))
                    self.assertEqual(data["name"], "zbook-llm")
                    versions.add(data["version"])
            listed = run(["plugin", "list", "--json"])["installed"]
            matching = [plugin for plugin in listed if plugin["pluginId"] == PLUGIN_ID]
            self.assertEqual(len(matching), 1)
            self.assertTrue(matching[0]["enabled"])
            versions.add(matching[0]["version"])
            self.assertEqual(len(versions), 1, f"installed/source manifest version mismatch: {versions}")


if __name__ == "__main__":
    unittest.main()
