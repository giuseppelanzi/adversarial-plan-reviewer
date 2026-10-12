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

A review is an agy call of up to half an hour in the middle of planning — the ceiling is a tier picked per document, section 3. That cost is why trivial plans are excluded, and why the first review of a conversation is gated on the fifteen-second preflight of section 1.

**Either way, the plan says so.** A decision nobody can see did not happen: a plan with no review looks exactly like a plan whose review was never mentioned. When the review runs, the trace is section 4 of the response protocol. When you skip it, write the line yourself, right after the document's `#` title, with the reason:

```
> **Review**: not run — mechanical edit to a single file.
```

Keep `**Review**:` in English, and keep the line inside the **first ten lines** of the document: that is what the `ExitPlanMode` hook greps for. Finding nothing, it prepends a notice of its own — a backstop, not a substitute. It can only report that nothing was declared, never why.

## 1. Preflight — the tool exists, and it can read this repo

Two checks before the **first** review of a conversation. Both are cheap, and each of them catches a failure that would otherwise only surface at the end of a long run.

### The tool

Run `agy --version` first. If the command is missing, say so and offer `/plan-review:claude` instead — but do not run it yourself.

### The read probe

**Once per conversation and per working directory, before the first review.** Not before every review: once it has passed, say so and move on.

The probe is a **dress rehearsal of the review**, and the line between what it keeps and what it drops is exactly the line between *being allowed to work* and *costing time*. Identical: the flags, `--add-dir`, the model pin, the event transport. Lowered: the prompt, the ceiling (`120s`), and the effort, which stays at the default because the probe has nothing to reason about (14 seconds measured, against 21 at high effort). Never soften the first group to make the probe pass — a rehearsal under a friendlier command line predicts nothing about the performance.

It asks for **the root listing on purpose**, and that is the point rather than an arbitrary question. Reading a named file works everywhere with no permission; *enumerating a directory* is the operation that reaches for the shell (section 4). Since a review that cannot enumerate cannot explore — and exploring, not reading, is what this skill sells — the probe exercises the capability that actually decides the run, for fifteen seconds instead of the quarter of an hour the review would spend discovering the same thing.

On a machine where the user has already granted the shell commands agy wants, it simply passes and costs those fifteen seconds. Where they have not, it fails **usefully**: the events name the command that was refused, and that is a question to forward, not a dead end.

```bash
PROJECT="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$PROJECT" || exit 1
OUT="${TMPDIR:-/tmp}/plan-review-probe.json"
ERR="${TMPDIR:-/tmp}/plan-review-probe.err"
REVIEW_MODEL="${PLAN_REVIEW_MODEL:-gemini-3.1-pro-high}"
PROBE="List the names of the files and directories at the root of the workspace, one per line, nothing else — no commentary, no code fences, no plan, no subagent."

echo "=== the real root ==="; ls -A
agy --mode plan --sandbox --add-dir "$PROJECT" --model "$REVIEW_MODEL" --print-timeout 120s --output-format stream-json -p "$PROBE" </dev/null >"$OUT" 2>"$ERR"
echo "=== exit $? ==="
jq -r 'select(.event=="result") | "status=\(.result.status)  empty=\(.result.response=="")", .result.response' "$OUT" 2>/dev/null
echo "=== denied, if any ==="
jq -r 'select(.event=="step_update") | .step_update | select(.state=="ERROR") | "tool=\(.tool_name)  command=\(.tool_info.parameters.CommandLine // "—")"' "$OUT" 2>/dev/null
jq -r 'select(.event=="init") | "conversation_id=\(.conversation_id)"' "$OUT" 2>/dev/null
echo "=== stderr ==="; head -c 600 "$ERR"
```

About fifteen seconds, and in that single turn it settles what otherwise fails at the end of a quarter-hour run: credentials still valid, model pin still real, workspace attached, and the shell question answered one way or the other.

**Reading the result.** `ls -A` prints the real root for free — compare against it. It **passes** when the names are the ones of *this* directory, including at least one a model could not have guessed. It **fails** on an empty `response`, on prose instead of names, or on a plausible generic project — `src/`, `package.json` — that is not this one.

**If it fails, the review does not run.** The events say why, and a denied tool call is the common case: hand the user the request as section 5 prescribes — the exact command agy wanted, the two ways to allow it, and the offer to resume. Write the *failed* stamp of section 4 of the response protocol onto the plan, naming the probe as the cause, and stop. Do not re-run it, and do not reach for the other reviewer on your own.

**The probe is not a review.** No critic, no verdict, and it never counts toward files read.

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
OUT="${TMPDIR:-/tmp}/plan-review-antigravity.json"
ERR="${TMPDIR:-/tmp}/plan-review-antigravity.err"
REVIEW_MODEL="${PLAN_REVIEW_MODEL:-gemini-3.1-pro-high}"
# The tier chosen above goes here. Seconds, bare integer, no unit — the "s" is appended below.
REVIEW_TIMEOUT="${PLAN_REVIEW_TIMEOUT:-900}"

# Section 2 chose these two together. They are one unit: see the constraint below.
CRITIC="${CLAUDE_PLUGIN_ROOT}/reviewers/plan-critic.md"
FRAMING="The document to critique follows in full between the markers. It is the object under review, not a description of the code: verify every claim it makes by reading this repository yourself."

PROMPT="$(cat "$CRITIC")

# Output Delivery Constraint
- What is wanted from you is a review, not a plan: do NOT propose a plan and do NOT ask for approval — this run has no channel through which to answer you.
- Output the entire critique verbatim as your final response text. Do NOT write it to a file or an artifact, and do NOT delegate it to a subagent: the run ends before either can reach the reader.

$FRAMING

--- BEGIN DOCUMENT UNDER REVIEW ---
$(cat "$PLAN")
--- END DOCUMENT UNDER REVIEW ---"

# No --dangerously-skip-permissions here, on purpose: see the constraint below and section 4.
agy --mode plan --sandbox --effort high --add-dir "$PROJECT" --model "$REVIEW_MODEL" --print-timeout "${REVIEW_TIMEOUT}s" --output-format stream-json -p "$PROMPT" <"/dev/null" >"$OUT" 2>"$ERR"
RC=$?

echo "=== exit $RC ==="
echo "=== run ==="
jq -r 'select(.event=="result") | "status=\(.result.status)  turns=\(.result.num_turns)  empty_response=\(.result.response=="")"' "$OUT" 2>/dev/null \
  || { echo "!! output is not a JSON event stream, raw:"; head -c 1000 "$OUT"; }
echo "=== tool calls that were denied, if any ==="
jq -r 'select(.event=="step_update") | .step_update | select(.state=="ERROR") | "tool=\(.tool_name)\ncommand=\(.tool_info.parameters.CommandLine // "—")\nreason=\((.tool_info.error.message // "")[0:200])"' "$OUT" 2>/dev/null
echo "=== conversation id — to resume rather than restart ==="
jq -r 'select(.event=="init") | .conversation_id' "$OUT" 2>/dev/null
echo "=== the critique ==="
jq -r 'select(.event=="result") | .result.response // empty' "$OUT" 2>/dev/null
echo "=== stderr ==="
head -c 1000 "$ERR"
```

Constraints:

- **Flag order matters.** `-p` takes the next argument as its prompt, so every other flag goes *before* `-p`, and the prompt stays glued to it. `agy -p --mode plan "..."` makes `--mode` the prompt and silently drops the real one — agy does warn about this, which is why stderr is captured rather than discarded.
- **`--add-dir` is not optional.** `cd` does nothing for agy: it does not take the working directory as its workspace. Asked to list its workspace without the flag, it answers `NO WORKSPACE`. Without a file tree the run dies on an auto-denied tool — and the tool it names is **`read_file`**, measured: with no workspace it is the *reading* that gets denied, which is why the model reaches for the shell rather than the other way round. Quote the path — repositories have spaces in them.
- **Three flags, and they are one unit.** `--mode plan` is agy's read-only execution mode, `--sandbox` adds terminal restrictions, `--effort high` is the quality lever after the model pin. Do not drop one and keep the rest.
- **`--dangerously-skip-permissions` is deliberately absent, and adding it is not yours to decide.** It removes the whole class of failure below — with it agy never has to ask, so it explores freely — and that is exactly why it is tempting. Two measured reasons it is not the default: the host's own permission classifier refuses to launch a command carrying it (`[Create Unsafe Agents]`), which is the most common way this skill fails to start at all; and it auto-approves *every* tool, where the denial below identifies the one command actually wanted. It stays available as the second remedy in section 5, offered to the user, never chosen for them.
- **`--output-format stream-json` is what makes the failure legible**, and it is why this block ends in `jq` rather than `cat`. A denied tool call, an artefact written instead of an answer, a subagent the run never waits for — all three used to arrive as *plausible text or silence* and had to be told apart by reading stderr. As events they are one query each: `result.status` with an empty `result.response` is the silent death, a `step_update` in `state:"ERROR"` carries the tool **and the exact command line** that was refused, and `init.conversation_id` is what lets a granted permission resume the same review instead of paying for it twice. The critique itself lives in `.result.response`.
- **`CRITIC` and `FRAMING` are one unit.** The block above carries the plan-critic pair. For a document that is not about this code, both lines change together:

  ```bash
  CRITIC="${CLAUDE_PLUGIN_ROOT}/reviewers/doc-critic.md"
  FRAMING="The document to critique follows in full between the markers. It is the object under review. Where it makes claims about this repository, verify them by reading the code yourself; where it makes none, judge the document on its own terms and say so in the closing section. Do not manufacture code references for a document that is not about code."
  ```

  Swapping the critic and leaving the plan-critic framing in place is the one mistake that costs the whole run: *«verify every claim it makes by reading this repository yourself»* is an order to find code behind a text that has none, and the model obeys it by inventing references. The reverse — doc framing with `plan-critic.md` — quietly drops the verification the plan needed.
- **The Output Delivery Constraint is load-bearing, and each clause was bought with a failed run.** Without the first, agy answers a review request with a *plan for reviewing* and waits for an approval headless can never give. Without the second, it writes the critique to an artefact file and returns a one-line pointer, or hands the work to a subagent the CLI kills on exit (`terminating 1 background task(s)`) — a promise instead of a review.
- **It states facts about the environment, and it does not dictate method.** That line is the one to hold. *This run has no channel to answer you*, *a background task dies when the turn ends* — true, unknowable to agy, and saying so is not preparing its context. *Use `list_dir` rather than the shell*, or *the shell is unavailable to you*, are the other kind: they tell the reviewer how to work, which is its business and this plugin's central rule. Earlier drafts carried both and they are gone. Measured, they did not even work — agy reached for `run_command` regardless — and worse, they pre-empt the very choice the failure mode below exists to forward to the user.
- **The model is pinned to a Pro tier** because agy's own default is a Flash tier: fine for cost, weak as an adversary. Override with `PLAN_REVIEW_MODEL`, and see the failure mode below for when the pin goes stale. `agy models` lists what is available — that list also carries Claude and GPT-OSS models, so agy is a multi-vendor transport and a third opinion is a `--model` flag rather than another skill.
- **`--print-timeout` carries the tier, and the tier is ours.** agy's own default is `0s` — it waits for the turn to complete, with no limit at all — so the ceiling is a choice this skill makes, not a constraint it inherits. This constraint used to say *«agy's own timeout (default 5m)»*, and a limit you believe you inherited is a limit you never reconsider. `PLAN_REVIEW_TIMEOUT` overrides it, in **seconds as a bare integer**: the `s` is appended by the command, so `PLAN_REVIEW_TIMEOUT=900s` builds `900ss` and agy rejects it. Being agy's own flag it needs no `timeout`/`gtimeout` wrapper.
- **Inlining is safe on size.** A 17 KB plan against a 1 MB `ARG_MAX` is under 2%. A document would have to reach hundreds of KB to matter; past that size the document is the problem.
- **stderr stays captured even though the events carry the diagnosis.** It is where the one-line summary of an auto-denial appears, and where a mistyped flag shows up before any event is emitted.
- Requires cached credentials from a prior interactive `agy` login on this machine. Nothing else: no folder to trust, no permission to pre-grant — section 4.

## 4. What agy can do without asking, and what it cannot

Two facts decide the shape of this skill, and both are measured rather than reasoned.

**The workspace is not the working directory.** Headless agy has no workspace unless you give it one: `cd` is invisible to it, and asked to list its workspace without `--add-dir` it answers `NO WORKSPACE`. In that state even reading is refused — the tool named in the denial is `read_file`, because with no file tree there is nothing to read. `--add-dir` removes this cause entirely.

**With a workspace, reading is free and exploring is not.** Reading a named file needs no permission at all: measured repeatedly, in trusted and untrusted folders alike, in a few seconds. *Enumerating a directory* is what reaches for the shell — agy has `list_dir` and uses `run_command` anyway — and `run_command` cannot be approved in headless, because there is nobody to ask. The run then ends.

That is not a defect to work around; it is a permission agy is entitled to ask for, and section 5 forwards the question to the person who can answer it. Once they have, it stays answered: the grant persists in agy's own settings, so the asking is a one-off per command, per machine — not a toll on every review.

Judge the run by its **output**, never by its exit code, and now not by emptiness alone either: the envelope of a denied run reports `status: SUCCESS` with an empty `response`, and the process exits 0. Success is what this failure looks like from the outside.

### Three remedies that do not work

Each was measured in a folder where the denial reproduces every time. Do not spend a run rediscovering them:

- **Trusting the workspace.** agy does ask interactively and keeps a `trustedWorkspaces` list, so this is the first idea everyone has. It changes nothing here: the same folder, trusted, fails identically — while an untrusted folder elsewhere listed its root without complaint. Trust is an interactive gate, not a headless permission.
- **Naming the tool.** agy's own reasoning has stated there is «no `list_directory` tool» while `list_dir` sat in the tool list it had just been given. Naming the tools it already has does not stop it reaching for `run_command`.
- **Dropping `--mode plan`.** The changelog grants workspace-scoped read *and list* access under the default review mode, which reads like the answer. Measured, the denial is identical with the flag and without it.

And the tool named in a denial is a symptom, not the missing permission in general: it is whichever call tripped first, and agy changes its mind between identical runs — `ls`, then `find`, then `python3 -c "import os; print(os.listdir('.'))"` for the very same task. That matters for what you tell the user, and section 5 says how.

### Why the command carries no skip-permissions flag

`--dangerously-skip-permissions` would remove this whole class: with it agy never has to ask, and it explores freely. It is absent for two measured reasons, not out of caution as a pose.

The first is that it frequently prevents the review from running **at all**: Claude Code's own permission classifier refuses to launch a command that carries it, and the block arrives before agy is ever reached. The second is that it grants everything for the run, where a denial tells you the *one* command that was actually wanted — which is the thing the user can act on.

**What it costs to do without it, said plainly.** A review can still die: on this repo, the same review survived once at 253 seconds with 8 files read and died the next time at 31 seconds with zero bytes. What changed is not the odds but the aftermath. The event stream names the exact command that was refused, and `init.conversation_id` lets a granted permission **resume that same review** instead of paying for it twice. A failure that is precise and resumable is a different animal from a silent one.

The flag remains available as the second remedy in section 5 — offered to the user with its trade, never chosen for them. And you still do not inspect, repair or write agy's configuration, nor go looking for where it lives; the same holds for the host's settings, which Claude Code will refuse to let you edit anyway (`[Auto-Mode Bypass]`), and is right to.

## 5. Failure modes

Follow section 0 of the response protocol: report the error, give the remedy, **do not run another reviewer CLI on your own**.

**A tool was denied — the one you will actually meet.** The signature is `status: SUCCESS` with an empty `response`, exit 0, and at least one `step_update` in `state: "ERROR"` whose message begins `permission check failed for command`. stderr carries the same thing in one line. agy asked for a permission, headless had nobody to ask, and the run ended.

**Forward the request; do not answer it for them.** The events give you what the user needs to decide, so report it in their language and in this shape:

- **what agy wanted to run** — the exact string in `tool_info.parameters.CommandLine`, quoted verbatim. Not "a tool was denied": *`find . -maxdepth 1 -mindepth 1 | sed 's|^./||'`*.
- **what it was trying to do** — from the step, usually: enumerate the workspace. Reading files was never the problem.
- **the two ways forward**, and they are the user's to weigh:
  1. **Grant it to agy**, which is where the permission belongs. Interactively — `agy` in that folder, the same request, and the dialog offers *«always allow for commands that start with `X` (Persist to settings.json)»* — or directly in `~/.gemini/antigravity-cli/settings.json`, where that choice lands as one line:

     ```json
     "permissions": { "allow": ["command(ls)"] }
     ```

     Say the catch honestly: **the grant is per command prefix**, and agy picks a different one between identical runs — `ls`, then `cat`, then `find`, then `python3`. Measured, the set that carried a full review through was `ls`, `cat`, `head`, `tail`, `wc`, `grep`: six read-only commands, granted once, after which a 13 KB plan was reviewed end to end with no denial at all. Worth adding: `find` is the one it still reaches for occasionally, and it is **not** in that set on purpose — `find -exec` runs arbitrary commands, which is a different thing from reading. That is the user's call to make, not a detail to smuggle past them.
  2. **Re-run with `--dangerously-skip-permissions`**, which approves every tool for that one run, bounded by `--mode plan` and `--sandbox`. Say its catch too: in auto mode Claude Code refuses to launch that command outright, and lifting that needs a rule only they can write (below).
- **that the work is not lost.** Quote the `conversation_id` and offer to resume with `--conversation "<id>"` once the permission exists, rather than starting the review again. Measured: the resumed run picks the review up where it stopped, keeps what it had already read, and carries on — *«The permission you needed has been granted. Continue the review now and output the complete critique as your final response text.»* is enough of a prompt, since the critic and the document are already in that conversation.

Then **stop**. Do not grant anything on their behalf, do not re-run, do not switch reviewer. When this fires on the **probe** it costs fifteen seconds instead of a quarter of an hour, which is the whole reason the probe exists — and the probe carries the review's own flags precisely so that it meets this first.

**Blocked by the host's classifier** — only reachable when the user has chosen remedy 2 above. The Bash call never runs: Claude Code refuses it with `Permission for this action was denied by the Claude Code auto mode classifier. Reason: [Create Unsafe Agents]`, because the command line carries `--dangerously-skip-permissions`. Nothing reached agy, so there is no output to judge and no CLI error to quote.

The remedy is one line, once per machine, in `~/.claude/settings.json`:

```json
"permissions": { "allow": ["Bash(agy --mode plan --sandbox --dangerously-skip-permissions:*)"] }
```

In auto mode an allow rule that matches is evaluated *before* the classifier, so the call stops being reviewed. What it grants is exactly that command shape: auto-approval of **agy's own tools** inside agy's plan-and-sandbox mode, nothing about your tools. The rule matches a prefix, so the flags must stay in that order on one line.

**You cannot add it for them.** Writing a permission rule from inside a session is refused in its own right, `Reason: [Auto-Mode Bypass]`, and an agent that grants itself permissions is precisely what that check exists for. Hand them the line.

**Never route around the block by hiding the flag** — building the command through a variable, or moving it into a script so the classifier cannot read the string. It would work, and it defeats the intent of a check the user installed. The remedy is consent, not concealment.

**The critique came back as a pointer, a plan, or a promise** — three shapes of the same thing: a `response` that is short, plausible and not a review. It says the critique is in `review.md` under agy's own working directory; or it offers a *plan* for reviewing and waits for an approval nobody can give; or it announces that a subagent will report back, while stderr says `terminating 1 background task(s) on exit`. All three **pass the empty-output check** in section 0 of the response protocol — they are not empty — and all three are visible in the events: a `write_to_file` or `invoke_subagent` step, or a `response` with no `VERDICT:` line in it.

Never report that sentence as if it were the review, and do not go read the file it names. The fix is the Output Delivery Constraint, whose four lines exist one per shape. If all four are in the prompt and this still happens, say so and stop.

**Unknown model** — stderr names the rejected model. The pin can go stale: the Pro line sits at 3.1 while the Flash tiers are already at 3.7, so a future rename makes the whole skill fail instead of degrading it. Run `agy models`, then either `PLAN_REVIEW_MODEL=<one of them>` or drop the flag. As with `--max-turns` on the Claude side: abandon the flag, not the review.

**Not logged in** — stderr starts with `Authentication required. Please visit the URL to log in:` followed by a long OAuth URL. Do not print that URL and do not try to complete the flow. Tell the user to log in once, interactively, in another terminal:

```
agy
```

then complete the browser login and quit. Say the review will work from then on, and wait.

**Prompt swallowed by a flag** — stderr contains `took "--…" as its prompt`. That is a bug in the command line, not in the environment: move the flag before `-p` and re-run once.

**Hit the ceiling** — agy stops at `--print-timeout`, and in the event stream the signature is precise: `init` and `step_update` events arrive but **no `result` event ever does**. That is what distinguishes it from a denial, which does produce a `result`, with `SUCCESS` and an empty response. Section 0 of the response protocol already counts a run killed by the timeout as a failed one. **Hitting the ceiling means the tier was misjudged, not that the reviewer failed**, so report it as that: name the tier it ran under, name the next one with its number (`300s` → `900s` → `1800s`), and offer it. **Do not re-run on your own** — the ban is the response protocol's, and a second run costs money and answers a question the user did not ask. The way not to arrive here is in section 3: err high on the first tier.

**An empty `response` with exit 0** — treat as a failed run, never as "no critique found". Work through the events before saying anything: a denied `step_update` names the cause outright, a missing `result` event means the ceiling, and neither present means read stderr. Only if all three come up empty is `--log-file "${TMPDIR:-/tmp}/agy-review.log"` worth one re-run, grepping it for `permission|grant|project`. Adding the flag for diagnosis is not a retry around the problem — report what it says, then stop.

**A critique that never cites the code** — **under `plan-critic.md` only.** With the document inline, a lazy reviewer can critique the text alone. If nothing in the critique names a `file:line` the document itself does not mention, it did not verify anything. Say so rather than passing off a text review as a code-grounded one.

Do **not** apply this check to a `doc-critic.md` run. There, a review with no `file:line` at all is the expected shape for a document that is not about this code, and reading it as a failure is exactly the misdiagnosis the second critic exists to prevent. Its analogue is **a critique that never quotes the document**: every point under doc-critic is anchored to a verbatim passage, so if none of them quotes anything, the reviewer commented without reading. That one is a real failure — report it.

A critique that *did* come back but lists few files read is **not** a failure case. Report the count and move on, as the response protocol says: on a new or nearly empty repo a short list is the correct outcome, and you cannot tell that apart from a permissions problem without knowing the repo better than the user does. Under `doc-critic.md` the closing section is `Sources read`, and an explicitly empty one — *"the document is not about this repository"* — is a correct outcome, not a shallow review.

## 6. Handle the output

Follow `${CLAUDE_PLUGIN_ROOT}/reviewers/response-protocol.md`. Read it before writing anything.
