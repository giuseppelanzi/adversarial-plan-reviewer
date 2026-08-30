---
name: claude
description: Submits a plan or an analysis document to a separate headless Claude Code instance as an adversarial reviewer with read-only access to the repo, then forces a point-by-point response to the critique. Use this skill only when the user explicitly asks for a review by Claude, by "a second Claude", or by Claude Code itself. For a review with no reviewer named, use /plan-review:antigravity instead. Like it, this runs during plan mode, on the plan document, before proposing the plan with ExitPlanMode — not after. Requests may come in any language.
---

# Plan review — headless Claude Code

A second Claude Code process reviews the plan with read-only tools. Do not prepare context: it reads the repo itself.

Note the trade-off, and mention it if the user seems to expect otherwise: the reviewer shares your model family, your `CLAUDE.md` and your conventions. It verifies the plan against the code well, but it is a weaker adversary than a different vendor's model — it tends to share your blind spots. Prefer it when the value is repo-grounded verification rather than genuine disagreement.

## 0. When to run it

Only when the user names Claude as the reviewer. For an unnamed review, `/plan-review:antigravity` is the default.

The trace rule is the same one the other skill carries: whatever the outcome, the plan document ends up with a `> **Review**: …` line right after its title — section 4 of the response protocol.

The timing is the same as the other reviewer's: *inside* plan mode, on the plan document, **before** proposing it with `ExitPlanMode`. Plan mode blocks writes, not reads, and the plan document is the one file you may edit — so the *review → revise → propose* loop closes inside plan mode rather than forcing the user to reject a plan just to get it reviewed.

## 1. Locate the document

Find the document in this order:

1. the path the user gave, if any;
2. **the plan document of the current plan mode session** — the path named in your plan mode instructions, typically under `~/.claude/plans/`. This is the authoritative version while you are planning;
3. `${CLAUDE_PROJECT_DIR:-$PWD}/.claude/plans/latest.md`, written by the `ExitPlanMode` hook — for a review asked for *after* leaving plan mode.

`$CLAUDE_PROJECT_DIR` is set for hook commands but **not** in the shell you run bash in — expect it to be empty and use `${CLAUDE_PROJECT_DIR:-$PWD}` everywhere.

If none exists, stop and ask. Do not reconstruct the plan from memory of the conversation.

## 2. Run the review

The document goes **inline in the prompt**, not as a path: the plan document usually lives outside the repo, and in plan mode you cannot copy it in — the plan file is the only thing you may write.

This does not contradict "do not prepare context". That rule is about context **on the repository** — summaries, extracted code, a curated file list. The document is not context: it is the **object under review**, and the reviewer still reads the code itself.

```bash
cd "${CLAUDE_PROJECT_DIR:-$PWD}" || exit 1
PLAN="<PLAN_PATH>"
TO=$(command -v timeout || command -v gtimeout || true)
OUT="${TMPDIR:-/tmp}/plan-review-claude.json"
ERR="${TMPDIR:-/tmp}/plan-review-claude.err"

PROMPT="$(cat "${CLAUDE_PLUGIN_ROOT}/reviewers/plan-critic.md")

The document to critique follows in full between the markers. It is the object under review, not a description of the code: verify every claim it makes by reading this repository yourself.

--- BEGIN DOCUMENT UNDER REVIEW ---
$(cat "$PLAN")
--- END DOCUMENT UNDER REVIEW ---"

${TO:+$TO 300} claude -p \
  --permission-mode plan \
  --allowedTools "Read,Grep,Glob" \
  --disallowedTools "Write,Edit,Bash" \
  --max-turns 20 \
  --output-format json \
  "$PROMPT" \
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
- **Inlining is safe on size.** A 17 KB document against a 1 MB `ARG_MAX` is under 2%. It would have to reach hundreds of KB to matter.
- `--max-turns` caps the agent loop and the cost. It works but is not listed in `claude --help`; if a future version rejects it, drop the flag rather than the review. Raise it only for large plans.
- Add `--model` if the user wants a specific one. Default is fine otherwise.
- No `@file` syntax here: the document is in the prompt, and the repo is what the reviewer reads on its own.

## 3. Failure modes

Follow section 0 of the response protocol: report the error, give the remedy, **do not run another reviewer CLI on your own**.

**Authentication or quota** — `.is_error` is true, or stderr mentions login, credit balance, or a 429. Report the message and let the user fix the account. Do not retry in a loop.

**Unknown flag** — stderr contains `unknown option`. Name the flag, drop it, and re-run once. This is the one retry allowed here, because the fix is certain.

**Turn limit** — the result mentions the max turns being reached. The critique is partial: say so before reporting it, and offer a re-run with a higher `--max-turns`.

**Missing CLI or empty `.result` with exit 0** — treat as a failed run, not as "no critique found".

**A critique that never cites the code** — with the document inline, a lazy reviewer can critique the text alone. If nothing in the critique names a `file:line` the document itself does not mention, it did not verify anything. Say so rather than passing off a text review as a code-grounded one.

## 4. Handle the output

Follow `${CLAUDE_PLUGIN_ROOT}/reviewers/response-protocol.md`. Read it before writing anything.
