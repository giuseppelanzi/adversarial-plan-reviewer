---
name: antigravity
description: "Submits a plan or any document — analysis, specification, proposal, note — to Antigravity CLI (agy), an adversarial read-only reviewer; you propose on each point, the user picks which to take. Use it when the user names agy or Antigravity, or picks it in a question below. The user picks the reviewer each time, and you run the skill picked: asked to review, check or critique a plan or document, or for a second opinion, with no reviewer named, ask with AskUserQuestion, header \"Reviewer\", options \"Antigravity\" / \"Codex\" / \"Claude\". Never start a review of a plan on your own: discuss it first. When a non-trivial plan is ready — any plan with architectural consequences — ask: \"The plan is ready. Send it to a reviewer before approving it?\", header \"Review\", options \"Antigravity\" / \"Codex\" / \"Claude\" / \"Approve without review\"; a free answer means keep discussing. A trivial plan — a rename, a one-line fix, a mechanical edit to a single file — gets no question. Either way, right after the plan's title: `> **Review**: not run — <reason>` when trivial, exactly `> **Review**: not run — the user chose to skip the review.` on \"Approve without review\". It runs in plan mode, before ExitPlanMode. Outside plan mode, before a non-trivial change by the same line, propose plan mode with EnterPlanMode, unless the user said to proceed without one; declined, proceed with no review and no stamp. Requests may come in any language."
---

# Plan review — Antigravity CLI (agy)

Antigravity reads the repo on its own. Do not prepare context for it: do not extract files, do not summarize, do not attach code. Hand it the document and then respond to the critique.

There is no default reviewer: the user picks one each time, and this skill also holds the two questions that ask them. Antigravity is a different vendor's model from yours, which is its point — it does not share your blind spots. So is Codex; headless Claude is not.

## 0. When to run it

Two rules, in order of precedence.

**Asked for → always.** If the user asks for a review, or for a plan *and* a review, a review runs. Do not weigh whether the plan deserves one: they asked. Which reviewer:

- **named** — in the request, by picking it in one of the questions below, or by invoking its skill directly → that one. A reviewer picked in a question is named: run its skill and do not ask again;
- **not named** → ask with `AskUserQuestion`:
  - question: `Which reviewer should review it?`
  - header: `Reviewer`
  - options, single choice: `Antigravity` / `Codex` / `Claude`

  The answer is the request.

**Not asked for → never on your own: the user decides.** Plan mode is where the plan is made *with* the user, so discuss it first. When you consider a non-trivial plan ready — after the discussion, not instead of it — ask with `AskUserQuestion`:

- question: `The plan is ready. Send it to a reviewer before approving it?`
- header: `Review`
- options, single choice: `Antigravity` / `Codex` / `Claude` / `Approve without review`

Their answer is the confirmation. "Keep discussing" has no option of its own — the tool takes four at most — so a free-text answer under *Other* means keep discussing: do that, and ask again when the plan is ready again.

**One map for both questions:**

| Answer | What runs |
|---|---|
| `Antigravity` | this skill |
| `Codex` | `/adversarial-plan-reviewer:codex` |
| `Claude` | `/adversarial-plan-reviewer:claude` |
| `Approve without review` — `Review` only | no review: write the *skipped* line below and call `ExitPlanMode` |

**Another pass** — the final question of the response protocol — goes to the reviewer of the first pass, with no `Reviewer` question: it checks that its own points were resolved. Another reviewer only if the user names one.

A plan with architectural consequences is non-trivial by definition. Trivial ones get no question: a rename, a one-line fix, a mechanical edit to a single file. Declare them and propose.

**When, in the plan's life:** *inside* plan mode, on the plan document, **before** proposing it with `ExitPlanMode`. Not after.

Plan mode blocks writes, not reads — bash runs fine there, and the plan document is the one file you may edit. So the whole *review → choose → revise → propose* loop closes inside plan mode, and the user sees the plan and the critique together instead of having to reject a plan just to get it reviewed.

A review is an agy call of up to half an hour in the middle of planning — the ceiling is a tier picked per document, section 3. That cost is why the user decides, why trivial plans get no question, and why the first review of a conversation is gated on the preflight of section 1.

**Either way, the plan says so.** A decision nobody can see did not happen: a plan with no review looks exactly like a plan whose review was never mentioned. When the review runs, the trace is section 4 of the response protocol. When it does not, write the line yourself, right after the document's `#` title — with the reason for a trivial plan, and in exactly this form when the user picked `Approve without review`:

```
> **Review**: not run — mechanical edit to a single file.
> **Review**: not run — the user chose to skip the review.
```

Keep `**Review**:` and `not run` in English. Nothing else checks for the line: a plan without it simply looks unreviewed, with no reason given.

**Outside plan mode, propose it.** In auto mode or the default mode there is no plan document and no `ExitPlanMode`: the question never comes, and a non-trivial change goes straight to code. So before implementing a change that is non-trivial by the line above, propose plan mode with `EnterPlanMode` — the tool asks the user to consent. Accepted, the plan is made with the user and everything above applies. Declined, proceed as asked: there is no review and no stamp, because there is no plan to carry one. Do not propose it for a trivial change, or when the user has already said to proceed without a plan. The `description` carries the same rule, and it is the copy that counts: outside plan mode this section is never loaded.

## 1. Preflight — the tool, the reviewer agent, and a read of this repo

Three checks before the **first** review of a conversation. All are cheap, and each catches a failure that would otherwise only surface at the end of a long run.

### The tool

Run `agy --version` first. If the command is missing, say so and offer `/adversarial-plan-reviewer:claude` or `/adversarial-plan-reviewer:codex` instead — but do not run either yourself. Stamp the plan — no agy run happened, so there is no agy error to quote:

```
> **Review**: Antigravity not run — `agy` not found.
> Plan NOT verified.
```

### The reviewer agent

The reviewer runs as the agy agent `plan-reviewer`, whose tools are `read_file` and `run_command`, the latter held to the command list of section 3 — section 4 says why. It lives in agy's own configuration, and it must be the one this plugin ships:

```bash
AGENT="$HOME/.gemini/config/agents/plan-reviewer.md"
SHIPPED="${CLAUDE_PLUGIN_ROOT}/reviewers/agy-plan-reviewer.md"
if [ ! -f "$AGENT" ]; then echo "agent: MISSING"
elif ! cmp -s "$AGENT" "$SHIPPED"; then echo "agent: OUTDATED"
else echo "agent: ok"; fi
```

Always `$HOME`, never `~` inside quotes, where the shell does not expand it.

**Missing or outdated → stop.** Do not install it yourself: agy's configuration is the user's. Hand them the command, already resolved:

```bash
mkdir -p "$HOME/.gemini/config/agents" && cp "${CLAUDE_PLUGIN_ROOT}/reviewers/agy-plan-reviewer.md" "$HOME/.gemini/config/agents/plan-reviewer.md"
```

and stamp the plan — no agy run happened, so there is no agy error to quote:

```
> **Review**: Antigravity not run — reviewer agent missing or outdated (~/.gemini/config/agents/plan-reviewer.md).
> Plan NOT verified.
```

### The read probe

**Once per conversation and per working directory, before the first review.** Not before every review: once it has passed, say so and move on.

The probe is a **dress rehearsal of the review**. Identical: the flags (`--mode plan --sandbox --agent plan-reviewer`), `--add-dir`, the command list in `--settings`, the model pin, the event transport. Lowered: the prompt and the ceiling (`120s`). Never soften the first group to make the probe pass — a rehearsal under a friendlier command line predicts nothing about the performance.

It asks for **the root listing on purpose**: it is the reviewer's first act of exploration, done with the same tools the review will use. In about half a minute — 25 to 30 seconds measured with `gemini-4-argon-high` — it settles what a review would otherwise discover at the end of a quarter of an hour: credentials still valid, model pin still real, workspace attached, and the agent able to list the root.

```bash
PROJECT="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$PROJECT" || exit 1
OUT="${TMPDIR:-/tmp}/plan-review-probe.json"
ERR="${TMPDIR:-/tmp}/plan-review-probe.err"
REVIEW_MODEL="${PLAN_REVIEW_MODEL:-gemini-4-argon-high}"
# The reviewer's command list, for this run only: it replaces the user's own permissions.allow (section 3).
AGY_SETTINGS='{"permissions":{"allow":["command(ls)","command(grep)","command(cat)","command(head)","command(tail)","command(wc)"]}}'
PROBE="List the names of the files and directories at the root of the workspace, one per line, nothing else — no commentary, no code fences, no plan, no subagent."

echo "=== the real root ==="; ls -A
agy --mode plan --sandbox --agent plan-reviewer --add-dir "$PROJECT" --settings "$AGY_SETTINGS" --model "$REVIEW_MODEL" --print-timeout 120s --output-format stream-json -p "$PROBE" </dev/null >"$OUT" 2>"$ERR"
echo "=== exit $? ==="
jq -r 'select(.event=="result") | "status=\(.result.status)  empty=\(.result.response=="")", .result.response' "$OUT" 2>/dev/null
echo "=== commands that ran ==="
jq -r 'select(.event=="step_update") | .step_update | select(.tool_name=="run_command" and .state=="DONE") | "cmd=\(.tool_info.parameters.CommandLine)\n\(.tool_info.output // "" | .[0:600])"' "$OUT" 2>/dev/null
echo "=== refused, if any ==="
jq -r 'select(.event=="step_update") | .step_update | select(.state=="ERROR") | "tool=\(.tool_name)  target=\(.tool_info.parameters | (.CommandLine // .AbsolutePath // .Path // "—"))  reason=\((.tool_info.error.message // "")[0:200])"' "$OUT" 2>/dev/null
jq -r 'select(.event=="init") | "conversation_id=\(.conversation_id)"' "$OUT" 2>/dev/null
echo "=== stderr ==="; head -c 600 "$ERR"
```

**Reading the result.** `ls -A` prints the real root for free — compare against it. It **passes** on two conditions, both required:

- the names in the response are the ones of *this* directory;
- *commands that ran* shows an `ls` of the workspace root — no path, `.`, or the workspace's own path — whose output says `Command exited with code 0.` and carries those names.

It **fails** on an empty `response`, on prose instead of names, on a plausible generic project — `src/`, `package.json` — that is not this one, and on a correct listing with no such `ls` behind it. That last case is not hypothetical. From 4 to 6 November 2026, agy 1.5 had already taken the listing tools away from the agent, and the probe kept passing on this repo: the reviewer rebuilt the root from `README.md`, the repo layout in `docs/internals.md`, `.DS_Store` and `.git/logs/HEAD`, names a model could not have guessed included. Some other command that succeeded, such as `wc README.md`, does not count either: the listing is what is being proven.

**If it fails, the review does not run.** The events and stderr say why — section 5 lists the causes and their remedies. Write the *failed* stamp of section 4 of the response protocol onto the plan, naming the probe as the cause, and stop. Do not re-run it, and do not reach for another reviewer on your own.

**The probe is not a review.** No critic, no verdict, and it never counts toward files read.

## 2. Locate the document, then pick the critic

### The document

Find it in this order:

1. the path the user gave, if any;
2. **the plan document of the current plan mode session** — the path named in your plan mode instructions, typically under `~/.claude/plans/`. This is the authoritative version while you are planning;
3. **the plan document of this conversation's last plan mode session** — for a review asked for *after* leaving plan mode. It is the same path the plan mode instructions named: Claude Code keeps the file under `~/.claude/plans/` after approval. Never take the newest file in that folder instead: it can belong to another session.

If none exists, or the plan mode path is no longer in the conversation — after a compaction, for instance — stop and ask. Do not reconstruct the plan from memory of the conversation: you would be critiquing a different version from the one that gets implemented.

For any other document — an analysis, a specification, a proposal, a note — same mechanism with that document's path.

### The critic

Two critic prompts live in `${CLAUDE_PLUGIN_ROOT}/reviewers/`, and the choice decides what the reviewer is even allowed to count as evidence:

1. **a plan document** — a plan mode session's, during or after plan mode → **always** `plan-critic.md`. No classification, no judgement call;
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
- **standard** — the ordinary case for a plan the user sends to review. A plan with architectural consequences, several modules touched, a document past ~10 KB, a repo of some hundreds of files. **In doubt between two tiers, take the higher one.**
- **deep** — the user asked for a review in depth; or a previous run hit the ceiling; or the plan rewrites something structural across a large repo.

Every signal is free and in hand before the run: the size of the document (you are reading it anyway, to inline it), how many distinct files and modules the plan names, and `git ls-files | wc -l` for the size of the repo. Nothing here is estimated by feel.

**That the floor is not the default follows from section 0, not from taste.** The review runs only on non-trivial plans — trivial ones skip the question — and non-trivial is defined there as a plan with architectural consequences, so those runs are born above the floor. Keeping 5 minutes as the default would tune the ceiling for the one case section 0 has just finished excluding.

Say which tier you ran under when it is not the floor: the rule is section 5 of the response protocol.

### The command

```bash
PROJECT="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$PROJECT" || exit 1
PLAN="<PLAN_PATH>"
OUT="${TMPDIR:-/tmp}/plan-review-antigravity.json"
ERR="${TMPDIR:-/tmp}/plan-review-antigravity.err"
REVIEW_MODEL="${PLAN_REVIEW_MODEL:-gemini-4-argon-high}"
# The reviewer's command list, for this run only — identical to the probe's. See the constraint below.
AGY_SETTINGS='{"permissions":{"allow":["command(ls)","command(grep)","command(cat)","command(head)","command(tail)","command(wc)"]}}'
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

# No --dangerously-skip-permissions here, on purpose: see the constraints below and section 4.
agy --mode plan --sandbox --agent plan-reviewer --add-dir "$PROJECT" --settings "$AGY_SETTINGS" --model "$REVIEW_MODEL" --print-timeout "${REVIEW_TIMEOUT}s" --output-format stream-json -p "$PROMPT" <"/dev/null" >"$OUT" 2>"$ERR"
RC=$?

echo "=== exit $RC ==="
echo "=== run ==="
jq -r 'select(.event=="result") | "status=\(.result.status)  turns=\(.result.num_turns)  empty_response=\(.result.response=="")"' "$OUT" 2>/dev/null \
  || { echo "!! output is not a JSON event stream, raw:"; head -c 1000 "$OUT"; }
echo "=== tool calls that were refused, if any ==="
jq -r 'select(.event=="step_update") | .step_update | select(.state=="ERROR") | "tool=\(.tool_name)\ntarget=\(.tool_info.parameters | (.CommandLine // .AbsolutePath // .Path // "—"))\nreason=\((.tool_info.error.message // "")[0:200])"' "$OUT" 2>/dev/null
echo "=== conversation id — to resume an interrupted review ==="
jq -r 'select(.event=="init") | .conversation_id' "$OUT" 2>/dev/null
echo "=== the critique ==="
jq -r 'select(.event=="result") | .result.response // empty' "$OUT" 2>/dev/null
echo "=== stderr ==="
head -c 1000 "$ERR"
```

Constraints:

- **Flag order matters.** `-p` takes the next argument as its prompt, so every other flag goes *before* `-p`, and the prompt stays glued to it. `agy -p --mode plan "..."` makes `--mode` the prompt and silently drops the real one — agy does warn about this, which is why stderr is captured rather than discarded.
- **`--add-dir` is not optional.** `cd` does nothing for agy: it does not take the working directory as its workspace. Asked to list its workspace without the flag, it answers `NO WORKSPACE`. Without a file tree even reading is refused — the tool it names is **`read_file`**, measured. Quote the path — repositories have spaces in them.
- **Four flags, and they are one unit.** `--mode plan` is agy's read-only execution mode, `--sandbox` runs commands under the operating system's sandbox, `--agent plan-reviewer` is the reviewer with `read_file` and `run_command` alone, and `--settings "$AGY_SETTINGS"` is the list of commands that run (section 4). Do not drop one and keep the rest.
- **`--settings` carries the command list, and it replaces the user's own.** Measured with `agy -p "/permissions"`, which answers without starting a turn: a `permissions.allow` passed in `--settings` **replaces** the `allow` list of `~/.gemini/antigravity-cli/settings.json` for that run, and leaves the file untouched; a `deny` passed alone is added to the user's list instead. Relying on the user's list would hand the reviewer every command they ever allowed for their own sessions. On the machine where this was measured that meant `python3` and `git`, and both can write. The repository under review cannot widen the list either: six candidate project files granting `command(touch)` added nothing, in a workspace marked trusted. `AGY_SETTINGS` is the same string in both blocks. `rg` is not on it, because `rg --pre <program>` runs a program on every file it searches.
- **No `--effort`.** The reasoning level is in the model's name (`-high`), and since agy 1.3.4 a name that carries it rejects the flag: `--effort is not supported for model …`.
- **`--dangerously-skip-permissions` stays out.** It would approve every command, not only the six of the list, writes included, for a run that is meant to read. Claude Code's own classifier refuses to launch a command that carries it anyway (README, *Known traps*).
- **`--output-format stream-json` is what makes the failure legible**, and it is why this block ends in `jq` rather than `cat`. A refused read, an artefact written instead of an answer, a subagent the run never waits for — all three used to arrive as *plausible text or silence* and had to be told apart by reading stderr. As events they are one query each: an empty `result.response` is a failed run, a `step_update` in `state:"ERROR"` carries the tool **and its target** — `CommandLine` for `run_command`, `Path` for `read_file` — a `run_command` in `state:"DONE"` carries its output in `tool_info.output`, and `init.conversation_id` is what lets an interrupted review resume instead of paying for it twice. The critique itself lives in `.result.response`.
- **`CRITIC` and `FRAMING` are one unit.** The block above carries the plan-critic pair. For a document that is not about this code, both lines change together:

  ```bash
  CRITIC="${CLAUDE_PLUGIN_ROOT}/reviewers/doc-critic.md"
  FRAMING="The document to critique follows in full between the markers. It is the object under review. Where it makes claims about this repository, verify them by reading the code yourself; where it makes none, judge the document on its own terms and say so in the closing section. Do not manufacture code references for a document that is not about code."
  ```

  Swapping the critic and leaving the plan-critic framing in place is the one mistake that costs the whole run: *«verify every claim it makes by reading this repository yourself»* is an order to find code behind a text that has none, and the model obeys it by inventing references. The reverse — doc framing with `plan-critic.md` — quietly drops the verification the plan needed.
- **The Output Delivery Constraint is load-bearing, and each clause was bought with a failed run.** Without the first, agy answers a review request with a *plan for reviewing* and waits for an approval headless can never give. Without the second, it writes the critique to an artefact file and returns a one-line pointer, or hands the work to a subagent the CLI kills on exit (`terminating 1 background task(s)`) — a promise instead of a review. `plan-reviewer` has neither `write_to_file` nor `invoke_subagent`, so the second clause no longer guards an action. Keep it anyway: it is what asks for the critique verbatim in the response, rather than a summary or a sentence about where the critique would be.
- **It states facts about the environment, and it does not dictate method.** That line is the one to hold. *This run has no channel to answer you*, *a background task dies when the turn ends* — true, unknowable to agy, and saying so is not preparing its context. The agent's tool list, and the sentences of its body — which commands run, which forms are refused — are of the same kind: they describe the room, not how to work in it. *Use simple commands*, *mark your commands as safe to auto-run*, or *read these files first*, are the other kind: they tell the reviewer how to work, which is its business and this plugin's central rule.
- **The model is pinned to `gemini-4-argon-high`.** It is the newest Gemini tier `agy models` lists (seen on agy 1.4.0), after the Pro tier left the list in 1.3.4 and `gemini-3.8-flash-high` stood in for it. It is a different vendor's model from yours, which is the point. Override with `PLAN_REVIEW_MODEL` — `gemini-3.8-flash-high`, the previous pin, is the fallback — and see the failure mode below for when the pin goes stale. `agy models` lists what is available — that list also carries Claude models and `gpt-oss-120b`, an open-weights model, but none of OpenAI's frontier ones. For those there is `/adversarial-plan-reviewer:codex`.
- **`--print-timeout` carries the tier, and the tier is ours.** agy's own default is `0s` — it waits for the turn to complete, with no limit at all — so the ceiling is a choice this skill makes, not a constraint it inherits. `PLAN_REVIEW_TIMEOUT` overrides it, in **seconds as a bare integer**: the `s` is appended by the command, so `PLAN_REVIEW_TIMEOUT=900s` builds `900ss` and agy rejects it. Being agy's own flag it needs no `timeout`/`gtimeout` wrapper.
- **Inlining is safe on size.** A 17 KB plan against a 1 MB `ARG_MAX` is under 2%. A document would have to reach hundreds of KB to matter; past that size the document is the problem.
- **stderr stays captured even though the events carry the diagnosis.** It is where the one-line summary of a refusal appears, and where a mistyped flag shows up before any event is emitted.
- Requires cached credentials from a prior interactive `agy` login on this machine, and the `plan-reviewer` agent of section 1. Nothing else: no folder to trust, no command to pre-grant — the command list travels with each run, in `--settings`.

## 4. Why the reviewer runs as `plan-reviewer`

Every fact here was measured — on this repo, or on a disposable git repository with agy 1.5.2 and 1.5.3 — except what is cited from agy's own changelog.

**The workspace is not the working directory.** Headless agy has no workspace unless you give it one: `cd` is invisible to it, and asked to list its workspace without `--add-dir` it answers `NO WORKSPACE`. In that state even reading is refused. `--add-dir` removes this cause entirely.

**agy 1.5 left the shell as the only way to explore.** From 1.5.0 on, agy logs `Tool "list_dir" is deprecated and has no effect` at every start, and the same for `grep_search` and `find_by_name`; `view_file` is mapped to `read_file`. The changelog does not mention it. The agent that used to list those four tools got `read_file` and `manage_task` alone, and the default agent has `run_command`, `read_file`, `write_file`, `edit_file` and others, but nothing that lists or searches. `read_file` opens a path it already knows and answers `path is a directory, not a file` on a directory. A reviewer with it alone still reads a good deal — on 6 November 2026 one read 32 files of a JavaScript repo by following imports and the README — but it cannot search for who else calls a function, and it never finds a file that nothing names.

**So the agent has the shell, and what runs is set on the command line.** `plan-reviewer` has `read_file` and `run_command`, and every run passes `--settings` with six commands allowed: `ls`, `grep`, `cat`, `head`, `tail`, `wc` (section 3 says why it replaces the user's own list). Headless, any other command needs a permission nobody can give, and it is refused. Measured by asking the reviewer outright, with `--mode plan` dropped so that the attempts reached the runtime — under plan mode the model declines a write on its own, which is a second layer, not a measurement:

- refused, with `permission check failed for command`: `touch`, `grep … > f`, `ls; touch f`, `cat $(touch f; …)`, `rg --pre`, `python3 -c "open(…,'w')"`, `git commit`, and the harmless-looking `find` and `cp`. The repository and its `git log` came out unchanged;
- run: `ls` and `grep -r`, with nobody to approve them, and a pipeline of listed commands, `grep -rn … | head`. The search found a marker string in a nested file that no other file names.

On agy 1.4, granting command prefixes one at a time never converged: the default agent reached for `python3 -c "…os.listdir('.')…"`, `git status && git branch`, `ps aux`, because nothing told it what was allowed. The agent's body now states the list as a fact of its environment, and in every measured run the reviewer stayed on it.

**`commandExecutionPolicy: off`.** With the list in `--settings`, `off`, `auto` and no policy at all behaved the same in every case above. `off` is kept because its name rules out running a command on the model's own judgement: the list is the only way a command runs.

**The sandbox fences the home directory, not every path.** `read_file` refuses any path outside the workspace. Commands run under the operating system's sandbox: a file in the user's home outside the workspace fails with `Operation not permitted`, but `/tmp`, `$TMPDIR` and `/etc` are readable — and `$TMPDIR` holds the files of earlier reviews. `plan-critic.md` limits *open it* to the repository and sends outside paths to *What I could not verify*, which is all the Codex side has, where reads are not fenced at all. The agent's body states the two refusals as facts of its environment.

**It is the same move as `--allowedTools "Read,Grep,Glob"` on the Claude side.** The environment is set — the tools by the agent, the commands by the list — and the reviewer is told nothing about how to work.

**Do not set `excludeDefaultComponents: true` on the agent.** It also drops the prompt section that tells the agent where its workspace is: the agent guessed `/workspace`, and the read was refused.

### Three remedies that did not work on agy 1.4

Measured against the shell refusals of agy 1.4's default agent, before `plan-reviewer` existed. Do not spend a run rediscovering them:

- **Trusting the workspace.** agy keeps a `trustedWorkspaces` list; the same folder, trusted, failed identically. Trust is an interactive gate, not a headless permission.
- **Naming the tool.** Telling agy to use `list_dir` did not stop it reaching for `run_command` — it could not: the default agent had no `list_dir`. Naming it in the agent's `tools` did, until agy 1.5 retired the tool.
- **Dropping `--mode plan`.** The refusal was identical with the flag and without it.

## 5. Failure modes

Follow section 0 of the response protocol: report the error, give the remedy, **do not run another reviewer CLI on your own**.

**Judge the run by its `VERDICT`, not by its exit code or its `status`.** A run that ends empty with exit 0 and `status: SUCCESS` has failed; a resumed run has closed with `status: ERROR` and a whole critique in its response. A response with a `VERDICT:` line is a review; anything else is not.

**The reviewer agent is missing or outdated.** The preflight of section 1 catches it before any run. If a run gets there anyway, agy 1.3.4 exits 1 on an unknown `--agent` and lists the agents it has. Hand the user the `cp` command of section 1, stamp the plan in that section's form, and stop.

**A read was refused.** The signature is a `step_update` in `state: "ERROR"` whose message begins `permission check failed for read_file`, and `result.denied_actions` listing `read_file`; the filter above prints the target. If the run carried on and a critique came back, it is a review: report the refused path with it. If the run ended empty, it failed. Report in the user's language:

- **what was refused** — the target, verbatim, and the reason line;
- **the way forward**, which is the user's: **re-run with one more `--add-dir`** for that directory — measured to work. It is a **new run**, not a resume: the workspace is fixed when the run starts, so `--conversation` cannot widen it.

  Do not offer a `read_file(<path>)` rule in the user's `permissions.allow`: `--settings` replaces that list for the run (section 3), so the rule would never reach it. Never offer to open `~/.gemini` whole: it holds agy's settings and credentials, and agy refuses reads of its own settings anyway, measured.

Then **stop**. Do not grant anything on their behalf, do not re-run, do not switch reviewer.

**A command was refused** — `target` is a command line. Two signatures, both measured:

- a `step_update` in `state: "ERROR"` whose message begins `permission check failed for command`, with `command` in `result.denied_actions`;
- a `run_command` step in `state: "DONE"` with an empty `tool_info.output`, and on stderr `jetski: no output produced — a tool required the "command" permission that headless mode cannot prompt for, so it was auto-denied`. Do not read `DONE` as success here: the command never ran.

The reviewer tried a command outside the list, or a form the list does not cover — a redirection, a `;` chain, a `$(…)`. If a critique came back anyway, it is a review: report the refused command with it, as a fact about the run. If the run ended empty, it failed. Either way the list is the reviewer's environment: never offer to add a command to it, and never offer `--dangerously-skip-permissions`. One exception is a bug in the command line, not a refusal: an ordinary `ls`, `grep` or `cat` refused means `--settings "$AGY_SETTINGS"` is missing, and the user's own list applied instead. Fix the command line.

**The run was interrupted** — stderr says `There was a network issue connecting to the server`, with an `AGY_ERROR` line marked `retryable`, and the process exits 3. Report it and offer to **resume** the same review with `--conversation "<id>"` and the same flags, rather than start again. Measured: a review cut by a network error resumed, kept what it had read, and finished. *«The run was interrupted by a network error. Continue the review now and output the complete critique as your final response text.»* is enough of a prompt, since the critic and the document are already in that conversation. Offer; do not resume on your own.

**The critique came back as a pointer, a plan, or a promise** — three shapes of the same thing: a `response` that is short, plausible and not a review. It says the critique is in `review.md` under agy's own working directory; or it offers a *plan* for reviewing and waits for an approval nobody can give; or it announces that a subagent will report back. All three **pass the empty-output check** in section 0 of the response protocol — they are not empty. Before the agent, the first and the third were real actions — a `write_to_file` or `invoke_subagent` step in the events, and `terminating 1 background task(s) on exit` on stderr for the subagent. `plan-reviewer` has neither tool, so now they can only be claimed, and no step shows them: the sign left is a `response` with no `VERDICT:` line in it.

Never report that sentence as if it were the review, and do not go read the file it names. The fix is the Output Delivery Constraint. If it is in the prompt and this still happens, say so and stop.

**Unknown model** — stderr names the rejected model. The pin goes stale: agy 1.3.4 dropped `gemini-3.1-pro-high` from `agy models`, and the same release rejects `--effort` with a model name that carries the level (`invalid model selection (--model "…-high" --effort "high")`). Run `agy models`, then either `PLAN_REVIEW_MODEL=<one of them>` or drop the flag. As with `--max-turns` on the Claude side: abandon the flag, not the review.

**Not logged in** — stderr starts with `Authentication required. Please visit the URL to log in:` followed by a long OAuth URL. Do not print that URL and do not try to complete the flow. Tell the user to log in once, interactively, in another terminal:

```
agy
```

then complete the browser login and quit. Say the review will work from then on, and wait.

**Prompt swallowed by a flag** — stderr contains `took "--…" as its prompt`. That is a bug in the command line, not in the environment: move the flag before `-p` and re-run once.

**Hit the ceiling** — agy stops at `--print-timeout`, and in the event stream the signature is precise: `init` and `step_update` events arrive but **no `result` event ever does**. That is what distinguishes it from a refusal, which does produce a `result`. Section 0 of the response protocol already counts a run killed by the timeout as a failed one. **Hitting the ceiling means the tier was misjudged, not that the reviewer failed**, so report it as that: name the tier it ran under, name the next one with its number (`300s` → `900s` → `1800s`), and offer it. **Do not re-run on your own** — the ban is the response protocol's, and a second run costs money and answers a question the user did not ask. The way not to arrive here is in section 3: err high on the first tier.

**An empty `response` with exit 0** — treat as a failed run, never as "no critique found". Work through the events before saying anything: a refused step names its target, a missing `result` event means the ceiling, and neither present means read stderr. Only if all three come up empty is `--log-file "${TMPDIR:-/tmp}/agy-review.log"` worth one re-run, grepping it for `permission|grant|project`. Adding the flag for diagnosis is not a retry around the problem — report what it says, then stop.

**A critique that never cites the code** — **under `plan-critic.md` only.** With the document inline, a lazy reviewer can critique the text alone. If nothing in the critique names a `file:line` the document itself does not mention, it did not verify anything. Say so rather than passing off a text review as a code-grounded one.

Do **not** apply this check to a `doc-critic.md` run. There, a review with no `file:line` at all is the expected shape for a document that is not about this code, and reading it as a failure is exactly the misdiagnosis the second critic exists to prevent. Its analogue is **a critique that never quotes the document**: every point under doc-critic is anchored to a verbatim passage, so if none of them quotes anything, the reviewer commented without reading. That one is a real failure — report it.

A critique that *did* come back but lists few files read is **not** a failure case. Report the count and move on, as the response protocol says: on a new or nearly empty repo a short list is the correct outcome, and you cannot tell that apart from a permissions problem without knowing the repo better than the user does. Under `doc-critic.md` the closing section is `Sources read`, and an explicitly empty one — *"the document is not about this repository"* — is a correct outcome, not a shallow review.

## 6. Handle the output

Follow `${CLAUDE_PLUGIN_ROOT}/reviewers/response-protocol.md`. Read it before writing anything: the user, not you, chooses which points to take.
