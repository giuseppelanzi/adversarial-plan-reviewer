---
name: plan-review-antigravity
description: Submits a plan or an analysis document to Antigravity CLI (agy) as an adversarial reviewer with read-only access to the repo, then forces a point-by-point response to the critique. Use this skill whenever the user asks for a review, a second opinion, a critique, to "ask Antigravity" or "ask agy", to "have the plan checked", or says a plan is risky, expensive or important — and use it as the default when the user asks for a review without naming a reviewer. Also use it when the user asks to verify or validate a plan before implementing it, or to check an analysis before making a decision. Requests may come in any language. Do not use it unprompted on trivial plans.
---

# Plan review — Antigravity CLI (agy)

Antigravity reads the repo on its own. Do not prepare context for it: do not extract files, do not summarize, do not attach code. Hand it the document path and then respond to the critique.

This is the default reviewer. It is a different vendor's model from yours, which is the point — it does not share your blind spots. Use `plan-review-claude` only when the user names it.

## 1. Check the tool exists

Run `agy --version` first. If the command is missing, say so and offer `plan-review-claude` instead — but do not run it yourself.

## 2. Locate the document

The current plan is `.claude/plans/latest.md` under the project root, written by the `ExitPlanMode` hook.

`$CLAUDE_PROJECT_DIR` is set for hook commands but **not** in the shell you run bash in — expect it to be empty and use `${CLAUDE_PROJECT_DIR:-$PWD}` everywhere. Use the path the user gives instead, if any.

If no file exists, stop and ask. Do not reconstruct the plan from memory of the conversation: you would be critiquing a different version from the one that gets implemented.

For an analysis document, same mechanism with that document's path.

## 3. Run the review

```bash
cd "${CLAUDE_PROJECT_DIR:-$PWD}" || exit 1
OUT="${TMPDIR:-/tmp}/plan-review-antigravity.txt"
ERR="${TMPDIR:-/tmp}/plan-review-antigravity.err"

agy \
  --mode plan \
  --print-timeout 300s \
  -p "$(cat "${CLAUDE_PLUGIN_ROOT}/reviewers/plan-critic.md")

The document to critique is at <PLAN_PATH> — read it first." \
  <"/dev/null" >"$OUT" 2>"$ERR"
RC=$?

echo "=== exit $RC ==="
cat "$OUT"
echo "=== stderr ==="
head -c 2000 "$ERR"
```

Constraints:

- **Flag order matters.** `-p` takes the next argument as its prompt, so every other flag goes *before* `-p`, and the prompt stays glued to it. `agy -p --mode plan "..."` makes `--mode` the prompt and silently drops the real one — agy does warn about this, which is why stderr is captured rather than discarded.
- `--mode plan` is agy's read-only execution mode. Never `--dangerously-skip-permissions`.
- `--print-timeout` is agy's own timeout (default 5m), so no `timeout`/`gtimeout` wrapper is needed here.
- Add `--model` if the user wants a stronger adversary than the configured default — `agy models` lists them, and `gemini-3.1-pro-high` is a better critic than the Flash tiers. Note that agy can also run Claude and GPT-OSS models: it is a multi-vendor transport, so a third opinion is a `--model` flag, not another skill.
- `--sandbox` adds terminal restrictions on top, at the cost of a slower start.
- The clean response goes to stdout, diagnostics to stderr — hence no `jq`. If the user wants the JSON envelope, verify the field name with `agy --output-format json ... -p "..."` before parsing it.
- Requires cached credentials from a prior interactive `agy` login on this machine.

## 4. Headless permissions — the prerequisite that bites

In headless mode agy **cannot prompt**, so any tool that needs a permission is auto-denied. The run then produces **zero bytes on stdout while still exiting 0**, with the reason on stderr. This is the normal shape of the failure, and in a repo where the user has never granted agy anything it is what happens on the very first review.

Judge the run by its **output**, never by its exit code — 0 is also what success returns.

You do not inspect, repair, or write agy's configuration, and you do not go looking for where it lives. A permission the consumer grants itself is not a permission. Detect the failure, hand the user the remedy, stop.

The remedy is a one-time interactive grant, per project, made by the user in their own terminal:

```
cd <project root>
agy
```

then, inside that session, a prompt that forces agy to touch the repo — for example:

> List the files in this repository and summarise its structure in three lines.

When agy asks for the read permission, approve it with the **persistent** option (the one that keeps it for this workspace, not the single-use one). A one-shot approval dies with the session and headless will fail again. Then quit and re-run the review.

Say plainly that this is once per repository, not once per review.

If the user wants a stronger guarantee than `--mode plan` gives, offer `--sandbox` or running the review against a throwaway `git worktree`.

## 5. Failure modes

Follow section 0 of the response protocol: report the error, give the remedy, **do not run another reviewer CLI on your own**.

**Tool auto-denied** — stdout is empty and stderr contains `no output produced — a tool required the "<tool>" permission that headless mode cannot prompt for, so it was auto-denied`. Give the interactive grant from section 4, quoting the tool name from the error so the user knows what they are approving. Do **not** reach for `--dangerously-skip-permissions`, which agy itself suggests: it auto-approves writes too, and it would be you granting the permission instead of the user.

**Not logged in** — stderr starts with `Authentication required. Please visit the URL to log in:` followed by a long OAuth URL. Do not print that URL and do not try to complete the flow. Tell the user to log in once, interactively, in another terminal:

```
agy
```

then complete the browser login and quit. Say the review will work from then on, and wait.

**Prompt swallowed by a flag** — stderr contains `took "--…" as its prompt`. That is a bug in the command line, not in the environment: move the flag before `-p` and re-run once.

**Timeout** — agy stops at `--print-timeout` and the output is truncated or empty. Report it and offer a longer timeout; do not silently re-run.

**Empty stdout with exit 0** — treat as a failed run, not as "no critique found". In practice it is almost always the auto-denied case above, so read stderr before saying anything else.

A critique that *did* come back but lists few files read is **not** a failure case. Report the count and move on, as the response protocol says: on a new or nearly empty repo a short list is the correct outcome, and you cannot tell that apart from a permissions problem without knowing the repo better than the user does.

## 6. Handle the output

Follow `${CLAUDE_PLUGIN_ROOT}/reviewers/response-protocol.md`. Read it before writing anything.

If `$CLAUDE_PLUGIN_ROOT` is empty in your shell, resolve the plugin root once with:

```bash
find ~/.claude/plugins -type d -name reviewers -path '*plan-review*' 2>/dev/null | head -1
```

and use that path for both shared files.
