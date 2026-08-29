---
name: plan-review-gemini
description: Submits a plan or an analysis document to Gemini CLI as an adversarial reviewer with read access to the repo, then forces a point-by-point response to the critique. Use this skill whenever the user asks for a review, a second opinion, a critique, to "ask Gemini", to "have the plan checked", or says a plan is risky, expensive or important — and use it as the default when the user asks for a review without naming a reviewer. Also use it when the user asks to verify or validate a plan before implementing it, or to check an analysis before making a decision. Requests may come in any language. Do not use it unprompted on trivial plans.
---

# Plan review — Gemini CLI

Gemini reads the repo on its own. Do not prepare context for it: do not extract files, do not summarize, do not attach code. Hand it the document path and then respond to the critique.

This is the default reviewer. Use `plan-review-claude` or `plan-review-antigravity` only when the user names them.

## 1. Locate the document

The current plan is `$CLAUDE_PROJECT_DIR/.claude/plans/latest.md`, written by the `ExitPlanMode` hook. Use the path the user gives instead, if any.

If no file exists, stop and ask. Do not reconstruct the plan from memory of the conversation: you would be critiquing a different version from the one that gets implemented.

For an analysis document, same mechanism with that document's path.

## 2. Run the review

```bash
cd "$CLAUDE_PROJECT_DIR" && timeout 300 gemini \
  --approval-mode plan \
  --output-format json \
  -p "$(cat "${CLAUDE_PLUGIN_ROOT}/reviewers/plan-critic.md")

The document to critique is at @<PLAN_PATH>" \
  | jq -r '.response'
```

Constraints:

- `--approval-mode plan` is read-only mode. Never `--yolo`, never `--approval-mode auto_edit`.
- Always keep `timeout`. Gemini in headless mode can hang.
- Run with cwd at the project root, or the reviewer reads the wrong tree.
- The response lives in `.response` in the JSON output.

## 3. Handle the output

Follow `${CLAUDE_PLUGIN_ROOT}/reviewers/response-protocol.md`. Read it before writing anything.

If `$CLAUDE_PLUGIN_ROOT` is empty in your shell, resolve the plugin root once with:

```bash
find ~/.claude/plugins -type d -name reviewers -path '*plan-review*' 2>/dev/null | head -1
```

and use that path for both shared files.
