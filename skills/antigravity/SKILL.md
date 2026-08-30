---
name: antigravity
description: Submits a plan or an analysis document to Antigravity CLI (agy) as an adversarial reviewer with read-only access to the repo, then forces a point-by-point response to the critique. Use it during plan mode, on the plan document, before proposing the plan with ExitPlanMode — not after. Always use it when the user asks for a review, a second opinion, a critique, to "ask Antigravity" or "ask agy", to "have the plan checked", to verify or validate a plan before implementing it, to check an analysis document before making a decision, or when the user asks for a plan and a review in the same breath — and use it as the default when the user asks for a review without naming a reviewer. Unprompted, use it on any non-trivial plan, and treat any plan with architectural consequences as non-trivial. Skip it on trivial ones — a rename, a one-line fix, a mechanical edit to a single file. Whichever way you decide, declare it in the plan document itself: a `> **Review**: …` line right after the title, saying that the review ran, or that it did not and why. Requests may come in any language.
---

# Plan review — Antigravity CLI (agy)

Antigravity reads the repo on its own. Do not prepare context for it: do not extract files, do not summarize, do not attach code. Hand it the document and then respond to the critique.

This is the default reviewer. It is a different vendor's model from yours, which is the point — it does not share your blind spots. Use `/plan-review:claude` only when the user names it.

## 0. When to run it

Two rules, in order of precedence.

**Asked for → always.** If the user asks for a review, names a reviewer, or asks for a plan *and* a review, run it. Do not weigh whether the plan deserves one: they asked.

**Not asked for → on any non-trivial plan.** A plan with architectural consequences is non-trivial by definition. Trivial ones stay out: a rename, a one-line fix, a mechanical edit to a single file.

**When, in the plan's life:** *inside* plan mode, on the plan document, **before** proposing it with `ExitPlanMode`. Not after.

Plan mode blocks writes, not reads — bash runs fine there, and the plan document is the one file you may edit. So the whole *review → revise → propose* loop closes inside plan mode, and the user sees the plan and the critique together instead of having to reject a plan just to get it reviewed.

A review is an agy call of up to `--print-timeout 300s` in the middle of planning. That cost is why trivial plans are excluded.

**Either way, the plan says so.** A decision nobody can see did not happen: a plan with no review looks exactly like a plan whose review was never mentioned. When the review runs, the trace is section 4 of the response protocol. When you skip it, write the line yourself, right after the document's `#` title, with the reason:

```
> **Review**: not run — mechanical edit to a single file.
```

Keep `**Review**:` in English, and keep the line inside the **first ten lines** of the document: that is what the `ExitPlanMode` hook greps for. Finding nothing, it prepends a notice of its own — a backstop, not a substitute. It can only report that nothing was declared, never why.

## 1. Check the tool exists

Run `agy --version` first. If the command is missing, say so and offer `/plan-review:claude` instead — but do not run it yourself.

## 2. Locate the document

Find the document in this order:

1. the path the user gave, if any;
2. **the plan document of the current plan mode session** — the path named in your plan mode instructions, typically under `~/.claude/plans/`. This is the authoritative version while you are planning;
3. `${CLAUDE_PROJECT_DIR:-$PWD}/.claude/plans/latest.md`, written by the `ExitPlanMode` hook — for a review asked for *after* leaving plan mode.

`$CLAUDE_PROJECT_DIR` is set for hook commands but **not** in the shell you run bash in — expect it to be empty and use `${CLAUDE_PROJECT_DIR:-$PWD}` everywhere.

If none exists, stop and ask. Do not reconstruct the plan from memory of the conversation: you would be critiquing a different version from the one that gets implemented.

For an analysis document, same mechanism with that document's path.

## 3. Run the review

The document goes **inline in the prompt**, not as a path. The plan document usually lives outside the repo (`~/.claude/plans/…`), agy's workspace is the directory you hand it with `--add-dir`, and in plan mode you cannot copy the document into the repo — the plan file is the only thing you may write. Passing a path is not merely awkward, it does not work.

This does not contradict "do not prepare context for it". That rule is about context **on the repository** — summaries, extracted code, a curated file list — which substitutes your framing for the reviewer's own reading. The document is not context: it is the **object under review**. By value or by reference is transport. The reviewer still reads the code itself, which is why the prompt says so explicitly.

```bash
PROJECT="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$PROJECT" || exit 1
PLAN="<PLAN_PATH>"
OUT="${TMPDIR:-/tmp}/plan-review-antigravity.txt"
ERR="${TMPDIR:-/tmp}/plan-review-antigravity.err"
REVIEW_MODEL="${PLAN_REVIEW_MODEL:-gemini-3.1-pro-high}"

PROMPT="$(cat "${CLAUDE_PLUGIN_ROOT}/reviewers/plan-critic.md")

# Output Delivery Constraint
- You MUST output the entire critique verbatim directly as your final response text to stdout.
- Do NOT call \`write_to_file\` or create any artifact file on disk.
- Do NOT save the review to a file: return the complete text directly in the stream.

The document to critique follows in full between the markers. It is the object under review, not a description of the code: verify every claim it makes by reading this repository yourself.

--- BEGIN DOCUMENT UNDER REVIEW ---
$(cat "$PLAN")
--- END DOCUMENT UNDER REVIEW ---"

agy \
  --mode plan \
  --sandbox \
  --dangerously-skip-permissions \
  --effort high \
  --add-dir "$PROJECT" \
  --model "$REVIEW_MODEL" \
  --print-timeout 300s \
  -p "$PROMPT" \
  <"/dev/null" >"$OUT" 2>"$ERR"
RC=$?

echo "=== exit $RC ==="
cat "$OUT"
echo "=== stderr ==="
head -c 2000 "$ERR"
```

Constraints:

- **Flag order matters.** `-p` takes the next argument as its prompt, so every other flag goes *before* `-p`, and the prompt stays glued to it. `agy -p --mode plan "..."` makes `--mode` the prompt and silently drops the real one — agy does warn about this, which is why stderr is captured rather than discarded.
- **`--add-dir` is not optional.** `cd` does nothing for agy: it does not take the working directory as its workspace. Asked to list its workspace without the flag, it answers `NO WORKSPACE`. With no file tree the model falls back on the shell to explore, and headless denies it. Quote the path — repositories have spaces in them.
- **The four flags are one unit**, and section 4 explains why. `--mode plan` is agy's read-only execution mode and `--sandbox` adds terminal restrictions; those two are what makes `--dangerously-skip-permissions` acceptable, and it is what keeps a long exploration from dying on an auto-denied tool. `--effort high` is the quality lever. Do not drop one and keep the rest: without skip-permissions, `--effort high` makes the run reach for the shell and die.
- **The Output Delivery Constraint is load-bearing.** Without it, on a long critique agy writes the review to an artefact file and returns a one-line pointer on stdout — plausible, non-empty, and useless. See the failure mode below.
- **The model is pinned to a Pro tier** because agy's own default is a Flash tier: fine for cost, weak as an adversary. Override with `PLAN_REVIEW_MODEL`, and see the failure mode below for when the pin goes stale. `agy models` lists what is available — that list also carries Claude and GPT-OSS models, so agy is a multi-vendor transport and a third opinion is a `--model` flag rather than another skill.
- `--print-timeout` is agy's own timeout (default 5m), so no `timeout`/`gtimeout` wrapper is needed here.
- **Inlining is safe on size.** A 17 KB plan against a 1 MB `ARG_MAX` is under 2%. A document would have to reach hundreds of KB to matter; past that size the document is the problem.
- The clean response goes to stdout, diagnostics to stderr — hence no `jq`. If the user wants the JSON envelope, verify the field name with `agy --output-format json ... -p "..."` before parsing it.
- Requires cached credentials from a prior interactive `agy` login on this machine.

## 4. The workspace and the shell — the prerequisite that bites

Headless agy has **no workspace** unless you give it one. `cd` is invisible to it. With no file tree the model explores through the shell instead, and headless **cannot prompt**, so the shell call is auto-denied: **zero bytes on stdout while still exiting 0**, with the reason on stderr.

Judge the run by its **output**, never by its exit code — 0 is also what success returns.

The tool named in that error — `command`, `read_file`, whatever — is **not** the permission that is missing. It is whichever call happened to trip first in a long exploration, and it changes between identical runs. Chasing it leads nowhere; earlier versions of this skill chased it into a per-repository permission ritual that fixed nothing.

The command in section 3 removes both causes at once: `--add-dir` gives the model a workspace, and `--dangerously-skip-permissions` stops a mid-exploration tool call from killing the whole run.

**On auto-approving.** This skill does reach for the flag agy itself suggests, which is a deliberate reversal of an earlier position, and it is only defensible because of what stands around it: `--mode plan` is agy's read-only execution mode and `--sandbox` adds terminal restrictions on top. Measured on a throwaway copy of a repo, a full review under those flags left all 18 files byte-identical. What it does **not** promise is the rest of the filesystem: agy still writes inside its own working directory. If the user wants a harder guarantee than that, offer to run the review against a throwaway `git worktree`, or with the flag dropped and the shell declared unavailable in the prompt instead — that combination also produces a review, from file-reading tools alone.

You still do not inspect, repair, or write agy's configuration, and you do not go looking for where it lives.

## 5. Failure modes

Follow section 0 of the response protocol: report the error, give the remedy, **do not run another reviewer CLI on your own**.

**Tool auto-denied** — stdout is empty and stderr contains `no output produced — a tool required the "<tool>" permission that headless mode cannot prompt for, so it was auto-denied`. With the command in section 3 this should not happen; when it does, the cause is a flag that went missing, not a permission the user has to grant. Do not quote the tool name to the user as the thing to approve: it does not identify the missing permission (section 4). Report the error and stop.

**The critique came back as a pointer** — stdout is short (a few hundred bytes), reads like `Ho completato l'analisi. Puoi trovare la revisione nel documento review.md`, and names a path under agy's own working directory. The review exists, but it went to an artefact file instead of the stream, and **this failure passes the empty-output check** in section 0 of the response protocol: it is not empty, so nothing catches it but you. Never report that sentence as if it were the review, and do not go read the file it names — the fix is the Output Delivery Constraint in the prompt. If it is present and this still happens, say so and stop.

**Unknown model** — stderr names the rejected model. The pin can go stale: the Pro line sits at 3.1 while the Flash tiers are already at 3.7, so a future rename makes the whole skill fail instead of degrading it. Run `agy models`, then either `PLAN_REVIEW_MODEL=<one of them>` or drop the flag. As with `--max-turns` on the Claude side: abandon the flag, not the review.

**Not logged in** — stderr starts with `Authentication required. Please visit the URL to log in:` followed by a long OAuth URL. Do not print that URL and do not try to complete the flow. Tell the user to log in once, interactively, in another terminal:

```
agy
```

then complete the browser login and quit. Say the review will work from then on, and wait.

**Prompt swallowed by a flag** — stderr contains `took "--…" as its prompt`. That is a bug in the command line, not in the environment: move the flag before `-p` and re-run once.

**Timeout** — agy stops at `--print-timeout` and the output is truncated or empty. Report it and offer a longer timeout; do not silently re-run.

**Empty stdout with exit 0** — treat as a failed run, not as "no critique found". Read stderr first. If stderr does not settle it, re-run once with `--log-file "${TMPDIR:-/tmp}/agy-review.log"` added and grep the log for `permission|grant|project`: that is what distinguishes a lost workspace from a tool that stopped the run, and it is the only diagnostic that turns the one-line error into a cause. Adding the flag for diagnosis is not a retry around the problem — report what it says, then stop.

**A critique that never cites the code** — with the document inline, a lazy reviewer can critique the text alone. If nothing in the critique names a `file:line` the document itself does not mention, it did not verify anything. Say so rather than passing off a text review as a code-grounded one.

A critique that *did* come back but lists few files read is **not** a failure case. Report the count and move on, as the response protocol says: on a new or nearly empty repo a short list is the correct outcome, and you cannot tell that apart from a permissions problem without knowing the repo better than the user does.

## 6. Handle the output

Follow `${CLAUDE_PLUGIN_ROOT}/reviewers/response-protocol.md`. Read it before writing anything.
