---
name: plan-review-antigravity
description: Submits a plan or an analysis document to Antigravity CLI (agy) as an adversarial reviewer with access to the repo, then forces a point-by-point response to the critique. Use this skill only when the user explicitly asks for a review by Antigravity or by agy. For a review with no reviewer named, use plan-review-gemini instead. Requests may come in any language.
---

# Plan review — Antigravity CLI (agy)

Antigravity reads the repo on its own. Do not prepare context for it.

## 1. Check the tool exists

Run `agy --version` first. If the command is missing, say so and offer `plan-review-gemini` instead rather than falling back silently.

## 2. Locate the document

The current plan is `$CLAUDE_PROJECT_DIR/.claude/plans/latest.md`, written by the `ExitPlanMode` hook. Use the path the user gives instead, if any.

If no file exists, stop and ask. Do not reconstruct the plan from memory of the conversation.

## 3. Run the review

```bash
cd "$CLAUDE_PROJECT_DIR" && timeout 300 agy -p \
  "$(cat "${CLAUDE_PLUGIN_ROOT}/reviewers/plan-critic.md")

The document to critique is at <PLAN_PATH> — read it first." \
  2>/dev/null
```

Constraints:

- **Read-only is not guaranteed by a flag here.** In headless mode agy auto-allows reading *and writing* files inside the active workspace; only shell commands default to Ask. The critic prompt forbids edits, but that is an instruction, not a sandbox. If the user cares about the guarantee, add a `permissions.deny` rule for write actions in the agy settings, or run the review against a throwaway `git worktree`.
- Never `--dangerously-skip-permissions`.
- The clean response goes to stdout, diagnostics to stderr — hence the `2>/dev/null` and no `jq`. If the user wants the JSON envelope, verify the field name with `agy -p ... --output-format json` before parsing it.
- Requires cached credentials from a prior interactive `agy` login on this machine.

## 4. Handle the output

Follow `${CLAUDE_PLUGIN_ROOT}/reviewers/response-protocol.md`. Read it before writing anything.

If `$CLAUDE_PLUGIN_ROOT` is empty in your shell, resolve the plugin root once with:

```bash
find ~/.claude/plugins -type d -name reviewers -path '*plan-review*' 2>/dev/null | head -1
```

and use that path for both shared files.
