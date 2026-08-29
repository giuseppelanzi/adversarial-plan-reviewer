---
name: plan-review-claude
description: Submits a plan or an analysis document to a separate headless Claude Code instance as an adversarial reviewer with read-only access to the repo, then forces a point-by-point response to the critique. Use this skill only when the user explicitly asks for a review by Claude, by "a second Claude", or by Claude Code itself. For a review with no reviewer named, use plan-review-gemini instead. Requests may come in any language.
---

# Plan review — headless Claude Code

A second Claude Code process reviews the plan with read-only tools. Do not prepare context: it reads the repo itself.

Note the trade-off, and mention it if the user seems to expect otherwise: the reviewer shares your model family, your `CLAUDE.md` and your conventions. It verifies the plan against the code well, but it is a weaker adversary than a different vendor's model — it tends to share your blind spots. Prefer it when the value is repo-grounded verification rather than genuine disagreement.

## 1. Locate the document

The current plan is `$CLAUDE_PROJECT_DIR/.claude/plans/latest.md`, written by the `ExitPlanMode` hook. Use the path the user gives instead, if any.

If no file exists, stop and ask. Do not reconstruct the plan from memory of the conversation.

## 2. Run the review

```bash
cd "$CLAUDE_PROJECT_DIR" && timeout 300 claude -p \
  --permission-mode plan \
  --allowedTools "Read,Grep,Glob" \
  --disallowedTools "Write,Edit,Bash" \
  --max-turns 20 \
  --output-format json \
  "$(cat "${CLAUDE_PLUGIN_ROOT}/reviewers/plan-critic.md")

The document to critique is at <PLAN_PATH> — read it first." \
  | jq -r '.result'
```

Constraints:

- `--permission-mode plan` plus the explicit tool allowlist keeps the run read-only. Never `--dangerously-skip-permissions`.
- The response lives in `.result`, not `.response` — this differs from Gemini CLI.
- `--max-turns` caps the agent loop and the cost. Raise it only for large plans.
- Add `--model` if the user wants a specific one. Default is fine otherwise.
- No `@file` syntax here: give the path in plain text and let the reviewer read it.

## 3. Handle the output

Follow `${CLAUDE_PLUGIN_ROOT}/reviewers/response-protocol.md`. Read it before writing anything.

If `$CLAUDE_PLUGIN_ROOT` is empty in your shell, resolve the plugin root once with:

```bash
find ~/.claude/plugins -type d -name reviewers -path '*plan-review*' 2>/dev/null | head -1
```

and use that path for both shared files.
