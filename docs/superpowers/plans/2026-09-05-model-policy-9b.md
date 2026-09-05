# 16GB model policy implementation plan

> **For agentic workers:** Apply `superpowers:subagent-driven-development` or `superpowers:executing-plans` with verification at each task boundary.

**Goal:** Publish the measured Qwen3.5 9B Q8 recommendation and make startup follow it when no valid model is pinned.

**Architecture:** Keep the existing offline PowerShell launcher and its explicit `default.txt` override. Change only automatic model fallback and background output handling; document the measured accuracy/speed tradeoff.

**Tech Stack:** Windows PowerShell 5.1, Python unittest, Claude plugin metadata.

**Spec:** User-approved accuracy-first 9B Q8 selection, 4B Q8 fallback, GPU memory fixed at 16GB.

## Global constraints

- Preserve a healthy running server and valid user model selection.
- No automatic downloads, marker writes, BIOS changes or server restarts.
- Keep loopback, API key validation, four slots and total context 32768.
- Preserve PowerShell UTF-8 BOM and CRLF for Windows PowerShell 5.1.
- Publish aggregate synthetic evaluation findings with limitations; no private source documents.

## Task 1: Model selection

Files: `plugins/zbook-llm/scripts/llm-up.ps1`, `tests/test_llm_up.py`.

- [x] Add fixture models with literal expected choices: missing/invalid marker plus installed 9B selects 9B; only 4B selects 4B; explicit 4B remains 4B; projection files are excluded from automatic fallback.
- [x] Run targeted launcher tests; observe failures against the previous smallest-file fallback.
- [x] Add ordered filename lookup for `Qwen3.5-9B-Q8_0.gguf` and `Qwen3.5-4B-Q8_0.gguf`, then the existing size/name fallback excluding `mmproj*.gguf`.
- [x] Re-run launcher tests; all model selection cases pass.

## Task 2: Background output lifetime

Files: the launcher and `tests/fixtures/llm-up-harness.ps1`, `tests/test_llm_up.py`.

- [x] Exercise the real Windows child-process launch with a harmless child waiting for an explicit release file. Capture the launcher output and assert it completes while the child remains alive.
- [x] Observe the inherited-output regression fail before changing production code. An independent reproduction showed that redirecting both streams also keeps the inherited pipe open on Windows PowerShell 5.1.
- [x] Remove stream redirects to use an independent hidden window. Read early failure diagnostics from the existing `--log-file` destination; test that its error reaches the caller.
- [x] Re-run the capture regression and launcher tests. Release only the temporary test child; do not affect a real server.

## Task 3: Publish the policy

Files: README, model policy guide, command instructions and plugin manifest.

- [x] Document explicit selection, verified optional download, temperature 0/nonthinking/schema requests, 1-slot synthetic results and separate 4-slot smoke results.
- [x] Set plugin version 0.3.0; retain direct PowerShell use for Codex.
- [x] Run `python -m unittest discover -s tests -v`, parse manifests and PowerShell files, and inspect `git diff --check` (44 tests pass).
- [x] Obtain an independent review and re-execution of checks (44 tests pass), then smoke-check the existing real server without restarting it (health, authentication, arithmetic, documented schema request and BIOS 16GB pass).

Release procedure after verification: commit, fast-forward master and push the authorized public repository; compare local and remote SHAs. Record the outcome in the session handoff with a local-only commit.
