---
name: antigravity
description: Submits a plan, or any document — an analysis, a specification, a proposal, a decision note — to Antigravity CLI (agy) as an adversarial reviewer with read-only access to the repo, then forces a point-by-point response to the critique. On a plan, use it during plan mode, on the plan document, before proposing the plan with ExitPlanMode — not after. Always use it when the user asks for a review, a second opinion, a critique, to "ask Antigravity" or "ask agy", to "have the plan checked", to verify or validate a plan before implementing it, to review or check a document — a specification, a proposal, an analysis, a note — before acting or deciding on it, or when the user asks for a plan and a review in the same breath — and use it as the default when the user asks for a review without naming a reviewer. Unprompted, use it on any non-trivial plan, and treat any plan with architectural consequences as non-trivial. Skip it on trivial ones — a rename, a one-line fix, a mechanical edit to a single file. Whichever way you decide on a plan, declare it in the plan document itself: a `> **Review**: …` line right after the title, saying that the review ran, or that it did not and why. Requests may come in any language.
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

A review is an agy call of up to half an hour in the middle of planning — the ceiling is a tier picked per document, section 3. That cost is why trivial plans are excluded.

**Either way, the plan says so.** A decision nobody can see did not happen: a plan with no review looks exactly like a plan whose review was never mentioned. When the review runs, the trace is section 4 of the response protocol. When you skip it, write the line yourself, right after the document's `#` title, with the reason:

```
> **Review**: not run — mechanical edit to a single file.
```

Keep `**Review**:` in English, and keep the line inside the **first ten lines** of the document: that is what the `ExitPlanMode` hook greps for. Finding nothing, it prepends a notice of its own — a backstop, not a substitute. It can only report that nothing was declared, never why.

## 1. Check the tool exists

Run `agy --version` first. If the command is missing, say so and offer `/plan-review:claude` instead — but do not run it yourself.

## 2. Locate the document, then pick the critic

### The document

Find it in this order:

1. the path the user gave, if any;
2. **the plan document of the current plan mode session** — the path named in your plan mode instructions, typically under `~/.claude/plans/`. This is the authoritative version while you are planning;
3. `${CLAUDE_PROJECT_DIR:-$PWD}/.claude/plans/latest.md`, written by the `ExitPlanMode` hook — for a review asked for *after* leaving plan mode.

`$CLAUDE_PROJECT_DIR` is set for hook commands but **not** in the shell you run bash in — expect it to be empty and use `${CLAUDE_PROJECT_DIR:-$PWD}` everywhere.

If none exists, stop and ask. Do not reconstruct the plan from memory of the conversation: you would be critiquing a different version from the one that gets implemented.

For any other document — an analysis, a specification, a proposal, a note — same mechanism with that document's path.

### The critic

Two critic prompts live in `${CLAUDE_PLUGIN_ROOT}/reviewers/`, and the choice decides what the reviewer is even allowed to count as evidence:

1. **a plan document** — a plan mode session's, or `latest.md` → **always** `plan-critic.md`. No classification, no judgement call;
2. otherwise, ask one question: **are the document's claims verifiable against this repository?** An analysis of this codebase, an ADR about this code, a post-mortem on it → `plan-critic.md`. A specification, a proposal, a note, anything whose subject is not this code → `doc-critic.md`;
3. **if the user names the critic, they win.** Say which one you used either way.

`plan-critic.md` demands a `file:line` on every point and treats a critique without one as an opinion. Aim that at a document that is not about code and it does not degrade — it manufactures references, and the failure modes below then read a correct review as a lazy one. `doc-critic.md` anchors each point to a verbatim quote of the document instead, and keeps the `file:line` requirement only for points that do touch the code.

**The critic does not travel alone.** The framing line that introduces the document in the prompt is part of the choice — section 3 says why.

## 3. Run the review

The document goes **inline in the prompt**, not as a path. The plan document usually lives outside the repo (`~/.claude/plans/…`), agy's workspace is the directory you hand it with `--add-dir`, and in plan mode you cannot copy the document into the repo — the plan file is the only thing you may write. Passing a path is not merely awkward, it does not work.

This does not contradict "do not prepare context for it". That rule is about context **on the repository** — summaries, extracted code, a curated file list — which substitutes your framing for the reviewer's own reading. The document is not context: it is the **object under review**. By value or by reference is transport. What the reviewer is told to do with the repository is the `FRAMING` line, and it follows the critic.

### The ceiling

`--print-timeout` is a **ceiling, not a budget**: a review that needs four minutes finishes in four minutes whatever the ceiling is. Raising it costs nothing on a healthy run — it costs wall clock only on a run that hangs, and it is spent inside plan mode. So the ceiling does not answer *how much compute do I grant*, it answers **how long do I wait before concluding something is broken** — and that is why you err high. A ceiling set too low costs the whole run plus the next one: 5 then 15 makes 20 minutes where starting at 15 makes 15.

Three tiers. agy caps nothing on turns, so here the tier is one number; the Claude skill's table carries two.

| Tier | `--print-timeout` |
|---|---|
| **short** | `300s` |
| **standard** | `900s` |
| **deep** | `1800s` |

Pick one as **a judgement you state, not a threshold you count**:

- **short** — a short, contained document: a plan over a handful of files in one component, a note of two pages. This is the **floor, not the default**.
- **standard** — the ordinary case for anything the skill fires on by itself. A plan with architectural consequences, several modules touched, a document past ~10 KB, a repo of some hundreds of files. **In doubt between two tiers, take the higher one.**
- **deep** — the user asked for a review in depth; or a previous run hit the ceiling; or the plan rewrites something structural across a large repo.

Every signal is free and in hand before the run: the size of the document (you are reading it anyway, to inline it), how many distinct files and modules the plan names, and `git ls-files | wc -l` for the size of the repo. Nothing here is estimated by feel.

**That the floor is not the default follows from section 0, not from taste.** The unprompted review fires *only* on non-trivial plans, and non-trivial is defined there as a plan with architectural consequences — so those runs are born above the floor. Keeping 5 minutes as the default would tune the ceiling for the one case section 0 has just finished excluding.

Say which tier you ran under when it is not the floor: the rule is section 5 of the response protocol.

### The command

```bash
PROJECT="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$PROJECT" || exit 1
PLAN="<PLAN_PATH>"
OUT="${TMPDIR:-/tmp}/plan-review-antigravity.txt"
ERR="${TMPDIR:-/tmp}/plan-review-antigravity.err"
REVIEW_MODEL="${PLAN_REVIEW_MODEL:-gemini-3.1-pro-high}"
# The tier chosen above goes here. Seconds, bare integer, no unit — the "s" is appended below.
REVIEW_TIMEOUT="${PLAN_REVIEW_TIMEOUT:-900}"

# Section 2 chose these two together. They are one unit: see the constraint below.
CRITIC="${CLAUDE_PLUGIN_ROOT}/reviewers/plan-critic.md"
FRAMING="The document to critique follows in full between the markers. It is the object under review, not a description of the code: verify every claim it makes by reading this repository yourself."

PROMPT="$(cat "$CRITIC")

# Output Delivery Constraint
- You MUST output the entire critique verbatim directly as your final response text to stdout.
- Do NOT call \`write_to_file\` or create any artifact file on disk.
- Do NOT save the review to a file: return the complete text directly in the stream.

$FRAMING

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
  --print-timeout "${REVIEW_TIMEOUT}s" \
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
- **`CRITIC` and `FRAMING` are one unit.** The block above carries the plan-critic pair. For a document that is not about this code, both lines change together:

  ```bash
  CRITIC="${CLAUDE_PLUGIN_ROOT}/reviewers/doc-critic.md"
  FRAMING="The document to critique follows in full between the markers. It is the object under review. Where it makes claims about this repository, verify them by reading the code yourself; where it makes none, judge the document on its own terms and say so in the closing section. Do not manufacture code references for a document that is not about code."
  ```

  Swapping the critic and leaving the plan-critic framing in place is the one mistake that costs the whole run: *«verify every claim it makes by reading this repository yourself»* is an order to find code behind a text that has none, and the model obeys it by inventing references. The reverse — doc framing with `plan-critic.md` — quietly drops the verification the plan needed.
- **The Output Delivery Constraint is load-bearing.** Without it, on a long critique agy writes the review to an artefact file and returns a one-line pointer on stdout — plausible, non-empty, and useless. See the failure mode below.
- **The model is pinned to a Pro tier** because agy's own default is a Flash tier: fine for cost, weak as an adversary. Override with `PLAN_REVIEW_MODEL`, and see the failure mode below for when the pin goes stale. `agy models` lists what is available — that list also carries Claude and GPT-OSS models, so agy is a multi-vendor transport and a third opinion is a `--model` flag rather than another skill.
- **`--print-timeout` carries the tier, and the tier is ours.** agy's own default is `0s` — it waits for the turn to complete, with no limit at all — so the ceiling is a choice this skill makes, not a constraint it inherits. This constraint used to say *«agy's own timeout (default 5m)»*, and a limit you believe you inherited is a limit you never reconsider. `PLAN_REVIEW_TIMEOUT` overrides it, in **seconds as a bare integer**: the `s` is appended by the command, so `PLAN_REVIEW_TIMEOUT=900s` builds `900ss` and agy rejects it. Being agy's own flag it needs no `timeout`/`gtimeout` wrapper.
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

**Hit the ceiling** — agy stops at `--print-timeout` and the output comes back truncated or empty; section 0 of the response protocol already counts a run killed by the timeout as a failed one. **Hitting the ceiling means the tier was misjudged, not that the reviewer failed**, so report it as that: name the tier it ran under, name the next one with its number (`300s` → `900s` → `1800s`), and offer it. **Do not re-run on your own** — the ban is the response protocol's, and a second run costs money and answers a question the user did not ask. The way not to arrive here is in section 3: err high on the first tier.

**Empty stdout with exit 0** — treat as a failed run, not as "no critique found". Read stderr first. If stderr does not settle it, re-run once with `--log-file "${TMPDIR:-/tmp}/agy-review.log"` added and grep the log for `permission|grant|project`: that is what distinguishes a lost workspace from a tool that stopped the run, and it is the only diagnostic that turns the one-line error into a cause. Adding the flag for diagnosis is not a retry around the problem — report what it says, then stop.

**A critique that never cites the code** — **under `plan-critic.md` only.** With the document inline, a lazy reviewer can critique the text alone. If nothing in the critique names a `file:line` the document itself does not mention, it did not verify anything. Say so rather than passing off a text review as a code-grounded one.

Do **not** apply this check to a `doc-critic.md` run. There, a review with no `file:line` at all is the expected shape for a document that is not about this code, and reading it as a failure is exactly the misdiagnosis the second critic exists to prevent. Its analogue is **a critique that never quotes the document**: every point under doc-critic is anchored to a verbatim passage, so if none of them quotes anything, the reviewer commented without reading. That one is a real failure — report it.

A critique that *did* come back but lists few files read is **not** a failure case. Report the count and move on, as the response protocol says: on a new or nearly empty repo a short list is the correct outcome, and you cannot tell that apart from a permissions problem without knowing the repo better than the user does. Under `doc-critic.md` the closing section is `Sources read`, and an explicitly empty one — *"the document is not about this repository"* — is a correct outcome, not a shallow review.

## 6. Handle the output

Follow `${CLAUDE_PLUGIN_ROOT}/reviewers/response-protocol.md`. Read it before writing anything.
