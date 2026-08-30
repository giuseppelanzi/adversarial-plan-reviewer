---
name: plan-review-claude
description: Submits a plan or an analysis document to a separate headless Claude Code instance as an adversarial reviewer with read-only access to the repo, then forces a point-by-point response to the critique. Use this skill only when the user explicitly asks for a review by Claude, by "a second Claude", or by Claude Code itself. For a review with no reviewer named, use plan-review-antigravity instead. Requests may come in any language.
---

# Plan review — headless Claude Code

A second Claude Code process reviews the plan with read-only tools. Do not prepare context: it reads the repo itself.

Note the trade-off, and mention it if the user seems to expect otherwise: the reviewer shares your model family, your `CLAUDE.md` and your conventions. It verifies the plan against the code well, but it is a weaker adversary than a different vendor's model — it tends to share your blind spots. Prefer it when the value is repo-grounded verification rather than genuine disagreement.

## 1. Locate the document

The current plan is `.claude/plans/latest.md` under the project root, written by the `ExitPlanMode` hook.

`$CLAUDE_PROJECT_DIR` is set for hook commands but **not** in the shell you run bash in — expect it to be empty and use `${CLAUDE_PROJECT_DIR:-$PWD}` everywhere. Use the path the user gives instead, if any.

If no file exists, stop and ask. Do not reconstruct the plan from memory of the conversation.

## 2. Run the review

```bash
cd "${CLAUDE_PROJECT_DIR:-$PWD}" || exit 1
TO=$(command -v timeout || command -v gtimeout || true)
OUT="${TMPDIR:-/tmp}/plan-review-claude.json"
ERR="${TMPDIR:-/tmp}/plan-review-claude.err"

${TO:+$TO 300} claude -p \
  --permission-mode plan \
  --allowedTools "Read,Grep,Glob" \
  --disallowedTools "Write,Edit,Bash" \
  --max-turns 20 \
  --output-format json \
  "$(cat "${CLAUDE_PLUGIN_ROOT}/reviewers/plan-critic.md")

The document to critique is at <PLAN_PATH> — read it first." \
  <"/dev/null" >"$OUT" 2>"$ERR"
RC=$?

echo "=== exit $RC ==="
jq -r 'if .is_error then "REVIEWER ERROR: \(.result // .error // "unknown")" else (.result // empty) end' <"$OUT" 2>/dev/null \
  || { echo "!! output is not JSON, raw:"; head -c 2000 "$OUT"; }
echo "=== stderr ==="
head -c 2000 "$ERR"
```

Constraints:

- `--permission-mode plan` plus the explicit tool allowlist keeps the run read-only. Never `--dangerously-skip-permissions`.
- The response lives in `.result`. `.is_error` flags a failed run even when the exit code is 0.
- **Redirect to a file, do not pipe into `jq`.** Reading the exit status through a pipe is not portable: `${PIPESTATUS[0]}` is bash-only and expands to nothing under zsh, which is what Claude Code's Bash tool actually runs. Redirecting first keeps `$?` meaningful in either shell.
- `TO` is the portable timeout: GNU `timeout` is absent on a stock macOS, `gtimeout` comes from `brew install coreutils`. If neither exists the command runs unwrapped rather than failing with `command not found`.
- `</dev/null` is not decoration: without it `claude -p` blocks for 3s waiting on stdin and warns `no stdin data received in 3s`. The prompt goes in as an argument, never on stdin.
- `--max-turns` caps the agent loop and the cost. It works but is not listed in `claude --help`; if a future version rejects it, drop the flag rather than the review. Raise it only for large plans.
- Add `--model` if the user wants a specific one. Default is fine otherwise.
- No `@file` syntax here: give the path in plain text and let the reviewer read it.

## 3. Failure modes

Follow section 0 of the response protocol: report the error, give the remedy, **do not run another reviewer CLI on your own**.

**Authentication or quota** — `.is_error` is true, or stderr mentions login, credit balance, or a 429. Report the message and let the user fix the account. Do not retry in a loop.

**Unknown flag** — stderr contains `unknown option`. Name the flag, drop it, and re-run once. This is the one retry allowed here, because the fix is certain.

**Turn limit** — the result mentions the max turns being reached. The critique is partial: say so before reporting it, and offer a re-run with a higher `--max-turns`.

**Missing CLI or empty `.result` with exit 0** — treat as a failed run, not as "no critique found".

## 4. Handle the output

Follow `${CLAUDE_PLUGIN_ROOT}/reviewers/response-protocol.md`. Read it before writing anything.

If `$CLAUDE_PLUGIN_ROOT` is empty in your shell, resolve the plugin root once with:

```bash
find ~/.claude/plugins -type d -name reviewers -path '*plan-review*' 2>/dev/null | head -1
```

and use that path for both shared files.
