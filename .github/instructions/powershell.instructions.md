---
applyTo: "**/*.{ps1,psm1}"
---

# OSPlus PowerShell — apply these conventions

Source of truth: [.cursor/rules/powershell-conventions.mdc](../../.cursor/rules/powershell-conventions.mdc).

The footguns that bite in this repo:

- **`$ErrorActionPreference = "Stop"`** at the top of every non-trivial script. Save+restore around noisy external tools (npm, esbuild, postject).
- **`$LASTEXITCODE` is NOT covered by `Stop`.** Wrap external commands in `Invoke-External` from [tools/_lib.ps1](../../tools/_lib.ps1), or check `$LASTEXITCODE` explicitly with a labeled `throw`.
- **Use `tools/_lib.ps1` helpers** (`Write-Step`, `Write-Ok`, `Write-Warn2`, `Write-Fail`, `Invoke-External`) — don't reinvent. Dot-source from the right relative path.
- **Encoding is explicit, always.** Tool input files: `Out-File -Encoding ascii`. Clean UTF-8 no BOM: `[System.IO.File]::WriteAllText(...)`. Never trust the default.
- **LF line endings** for files consumed on Linux (`*.sh`, `*.service`, `Caddyfile`) — `.gitattributes` enforces, but ship scripts also normalize on the remote with `sed -i 's/\r$//'`.
- **Hardcoded `F:\` paths** are scope debt, acceptable for production scripts; new tooling that any other dev might run should parameterize from the start.

Cross-cutting (comment policy, logging categories) lives in [.cursor/rules/code-conventions.mdc](../../.cursor/rules/code-conventions.mdc).
