---
applyTo: "mod/**/*.lua"
---

# OSPlus Lua — apply these conventions

Source of truth (read both):

- [.cursor/rules/lua-conventions.mdc](../../.cursor/rules/lua-conventions.mdc) — module shape (`local M = {} ... return M`), the `pcall` + ref-drop discipline (the C++ AV trap), `log.log("[CATEGORY] message")` logging, naming, cross-module callback pattern, tick-loop discipline.
- [.cursor/rules/mod-architecture.mdc](../../.cursor/rules/mod-architecture.mdc) — the Lua/BP boundary contract. Three-bucket state model (UI-reactive → BP, domain → Lua, derived display → BP-holds-Lua-pushes). Designing a new feature contract.

Cross-cutting (comment policy, wire-protocol naming, error shape, logging format) lives in [.cursor/rules/code-conventions.mdc](../../.cursor/rules/code-conventions.mdc) — apply alongside the above.
