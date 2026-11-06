---
name: codex
description: "Submits a plan, or any document — an analysis, a specification, a proposal, a decision note — to OpenAI Codex CLI (`codex exec`) as an adversarial reviewer in a read-only sandbox; you then propose what to do with each point and the user chooses which points to take. Use this skill only when the user names Codex or OpenAI as the reviewer — in the request, or by picking it in a question of /adversarial-plan-reviewer:antigravity. With no reviewer named, ask that question first. On a plan, this runs during plan mode, on the plan document, before proposing the plan with ExitPlanMode — not after. Requests may come in any language."
---

# Plan review — Codex CLI

Codex reads the repo on its own. Do not prepare context for it: do not extract files, do not summarize, do not attach code. Hand it the document and then respond to the critique.

It is a different vendor's model from yours — OpenAI's, as Antigravity's is Google's. Note one limit, and mention it if the user seems to expect otherwise: Codex loads an `AGENTS.md` it finds in the repository as instructions of its own, measured, and it also reads one from its own home directory. A repo with an `AGENTS.md` hands this reviewer the project's conventions the way `CLAUDE.md` reaches the Claude reviewer: a different model, but not an entirely fresh pair of eyes.

## 0. When to run it

Only when the user names Codex — or OpenAI — as the reviewer, in the request, or by picking `Codex` in one of the two questions of `/adversarial-plan-reviewer:antigravity`. For an unnamed review, ask that skill's `Reviewer` question first: there is no default reviewer.

This reviewer never starts on its own. Picked in a question, it is named: that answer is the request, so run it without asking again. Another pass stays with it, unless the user names a different reviewer. The rest follows the response protocol like the other reviewers: you propose `ACCEPT` / `REJECT` for each point, the user chooses which points to take, and the plan changes on those alone.

The trace rule is the one the other skills carry: whatever the outcome, the plan document ends up with a `> **Review**: …` block right after its title — section 4 of the response protocol.

The timing is the other reviewers' too: *inside* plan mode, on the plan document, **before** proposing it with `ExitPlanMode`. Plan mode blocks writes, not reads, and the plan document is the one file you may edit — so the *review → choose → revise → propose* loop closes inside plan mode. Know what plan mode does *not* do: it binds your tools, not an external process you launch. What keeps the reviewer from writing is its own sandbox — section 4.

## 1. Preflight — the tool, the timeout, and a read of this repo

Three checks before the **first** review of a conversation. All are cheap, and each catches a failure that would otherwise only surface at the end of a long run.

### The tool

Run `codex --version` first. If the command is missing, say so and offer `/adversarial-plan-reviewer:antigravity` or `/adversarial-plan-reviewer:claude` in one line — but do not run either yourself. Stamp the plan — no Codex run happened, so there is no Codex error to quote:

```
> **Review**: Codex not run — `codex` not found.
> Plan NOT verified.
```

### The timeout

```bash
command -v timeout || command -v gtimeout || echo "timeout: MISSING"
```

Codex has no wall-clock flag and no turn cap of its own, so an external `timeout` is the only thing that bounds a run — and this skill does not run unbounded. If neither name exists, stop. The remedy is `brew install coreutils` on macOS, where it lands as `gtimeout`. Offer Antigravity or Claude in one line — neither needs it — and stamp:

```
> **Review**: Codex not run — no `timeout` or `gtimeout` on this machine.
> Plan NOT verified.
```

### The read probe

**Once per conversation and per working directory, before the first review.** Not before every review: once it has passed, say so and move on.

The probe is a **dress rehearsal of the review**. Identical: every flag — the sandbox, the approval policy, the model and its effort, the configuration isolation, the `--disable` set, the event transport, the final-message file. Lowered: the prompt, the ceiling (`120`), and the temporary directory, which is the probe's own — every run gets a fresh one — so that no run can read another's leftovers. Never soften the first group to make the probe pass — a rehearsal under a friendlier command line predicts nothing about the performance. If one flag changes, it changes in both blocks.

It asks for **the root listing on purpose**: it is the reviewer's first act of exploration, done with the tools the review will use. About ten seconds settle what a review would otherwise discover at the end of a quarter of an hour: credentials, the model pin, the flags this CLI version accepts, the sandbox starting, and the reviewer reaching this directory.

```bash
PROJECT="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$PROJECT" || exit 1
TO=$(command -v timeout || command -v gtimeout) || { echo "NO TIMEOUT UTILITY"; exit 1; }
# A fresh directory per run: a fixed path would let a concurrent run, or an earlier one, answer for this one.
RUN_DIR=$(mktemp -d "${TMPDIR:-/tmp}/plan-review-probe-codex.XXXXXX") || exit 1
OUT="$RUN_DIR/final.md"
EVENTS="$RUN_DIR/events.jsonl"
ERR="$RUN_DIR/stderr.log"
REVIEW_MODEL="${PLAN_REVIEW_CODEX_MODEL:-gpt-6.1-sol}"
PROBE="List the names of the files and directories at the root of your working directory, one per line, hidden ones included, nothing else — no commentary, no code fences."

echo "=== the real root ==="; ls -A
"$TO" 120 codex --ask-for-approval never exec \
  --sandbox read-only --cd "$PROJECT" --model "$REVIEW_MODEL" \
  -c model_reasoning_effort="high" -c web_search="disabled" \
  --ignore-user-config --ignore-rules \
  --disable apps --disable plugins --disable goals --disable image_generation --disable hooks \
  --json --color never --output-last-message "$OUT" \
  "$PROBE" </dev/null >"$EVENTS" 2>"$ERR"
echo "=== exit $? ===   ($RUN_DIR)"
if [ -s "$OUT" ]; then cat "$OUT"; else echo "!! no final message"; fi
jq -c 'select(.type=="turn.failed" or .type=="error")' "$EVENTS" 2>/dev/null
echo "=== stderr ==="; head -c 600 "$ERR"
```

**Reading the result.** `ls -A` prints the real root for free — compare against it. It **passes** when the names are the ones of *this* directory, including at least one a model could not have guessed. It **fails** on an exit of `124` (the ceiling), on `!! no final message`, on prose instead of names, or on a plausible generic project — `src/`, `package.json` — that is not this one.

**If it fails, the review does not run.** stderr and the events say why — section 5 lists the causes and their remedies. Write the *failed* stamp of section 4 of the response protocol onto the plan, naming the probe as the cause, and stop. Do not re-run it, and do not reach for another reviewer on your own.

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

Same rule as the other skills, and the two critics live in the same `${CLAUDE_PLUGIN_ROOT}/reviewers/`:

1. **a plan document** — a plan mode session's, or `latest.md` → **always** `plan-critic.md`. No classification, no judgement call;
2. otherwise, **are the document's claims verifiable against this repository?** An analysis of this codebase, an ADR about this code, a post-mortem on it → `plan-critic.md`. A specification, a proposal, a note, anything whose subject is not this code → `doc-critic.md`;
3. **if the user names the critic, they win.** Say which one you used either way.

`plan-critic.md` requires a `file:line` on every point; pointed at a text that is not about code it invents them. `doc-critic.md` anchors each point to a verbatim quote of the document instead. The framing line in the prompt is chosen with the critic, not separately — section 3 shows both pairs.

## 3. Run the review

The document goes **inline in the prompt**, not as a path: the plan document usually lives outside the repo, and in plan mode you cannot copy it in — the plan file is the only thing you may write.

This does not contradict "do not prepare context". That rule is about context **on the repository** — summaries, extracted code, a curated file list. The document is not context: it is the **object under review**. What the reviewer is told to do with the repository is the `FRAMING` line, and it follows the critic.

### The ceiling

A timeout is a **ceiling, not a budget**: a review that needs four minutes finishes in four minutes whatever the ceiling is. Raising it costs nothing on a healthy run — it costs wall clock only on a run that hangs, inside plan mode. So it answers **how long do you wait before concluding something is broken**, and you err high: too low costs the whole run plus the next one, where 5 then 15 makes 20 minutes against 15 for starting there.

Codex caps nothing on turns, so here the tier is one number, and the external `timeout` carries it.

| Tier | `timeout` |
|---|---|
| **short** | `300` |
| **standard** | `900` |
| **deep** | `1800` |

Pick one as **a judgement you state, not a threshold you count**:

- **short** — a short, contained document: a plan over a handful of files in one component, a note of two pages. The **floor, not the default**.
- **standard** — the ordinary case: a plan with architectural consequences, several modules touched, a document past ~10 KB, a repo of some hundreds of files. **In doubt, take the higher tier.**
- **deep** — a review in depth was asked for; or a previous run hit a ceiling; or the plan rewrites something structural across a large repo.

The signals are free and in hand: the size of the document, how many distinct files and modules the plan names, `git ls-files | wc -l` for the repo. The floor is deliberately not the default — this reviewer runs only when the user names or picks it, and trivial plans get no question, so its runs start above the floor. Say which tier you ran under when it is not the floor: section 5 of the response protocol.

### The command

```bash
PROJECT="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$PROJECT" || exit 1
PLAN="<PLAN_PATH>"
TO=$(command -v timeout || command -v gtimeout) || { echo "NO TIMEOUT UTILITY"; exit 1; }
RUN_DIR=$(mktemp -d "${TMPDIR:-/tmp}/plan-review-codex.XXXXXX") || exit 1
OUT="$RUN_DIR/final.md"
EVENTS="$RUN_DIR/events.jsonl"
ERR="$RUN_DIR/stderr.log"
REVIEW_MODEL="${PLAN_REVIEW_CODEX_MODEL:-gpt-6.1-sol}"
# The tier chosen above goes here. Seconds, bare integer.
REVIEW_TIMEOUT="${PLAN_REVIEW_TIMEOUT:-900}"

# Section 2 chose these two together. They are one unit: see the constraint below.
CRITIC="${CLAUDE_PLUGIN_ROOT}/reviewers/plan-critic.md"
FRAMING="The document to critique follows in full between the markers. It is the object under review, not a description of the code: verify every claim it makes by reading this repository yourself."

PROMPT="$(cat "$CRITIC")

# Output Delivery Constraint
- What is wanted from you is a review, not a plan: do NOT propose a plan and do NOT ask for input or approval — this run has no channel through which anyone can answer you.
- Output the entire critique verbatim as your final response text. Do NOT write it to a file and do NOT delegate it to another agent: only your final message reaches the reader.

$FRAMING

--- BEGIN DOCUMENT UNDER REVIEW ---
$(cat "$PLAN")
--- END DOCUMENT UNDER REVIEW ---"

# No --dangerously-bypass-approvals-and-sandbox here, on purpose: see the constraints below and section 4.
"$TO" "$REVIEW_TIMEOUT" codex --ask-for-approval never exec \
  --sandbox read-only --cd "$PROJECT" --model "$REVIEW_MODEL" \
  -c model_reasoning_effort="high" -c web_search="disabled" \
  --ignore-user-config --ignore-rules \
  --disable apps --disable plugins --disable goals --disable image_generation --disable hooks \
  --json --color never --output-last-message "$OUT" \
  "$PROMPT" </dev/null >"$EVENTS" 2>"$ERR"
RC=$?

echo "=== exit $RC ===   ($RUN_DIR)"   # 124 or 143: the ceiling — a failed run, whatever $OUT holds
echo "=== run ==="
jq -r 'select(.type=="thread.started") | "thread_id=\(.thread_id)"' "$EVENTS" 2>/dev/null
jq -r 'select(.type=="turn.completed") | "turn completed  output_tokens=\(.usage.output_tokens)"' "$EVENTS" 2>/dev/null
jq -c 'select(.type=="turn.failed" or .type=="error")' "$EVENTS" 2>/dev/null
echo "=== tool calls refused, if any ==="
grep -F 'tools::router: error=' "$ERR" | head -n 10
echo "=== commands that failed, if any — diagnostic only ==="
jq -r 'select(.type=="item.completed" and .item.type=="command_execution" and .item.exit_code != 0) | "exit=\(.item.exit_code)  \(.item.command)"' "$EVENTS" 2>/dev/null
echo "=== the critique ==="
if [ -s "$OUT" ]; then cat "$OUT"; else echo "!! no final message"; fi
echo "=== stderr ==="; head -c 1000 "$ERR"
```

Constraints:

- **`--ask-for-approval never` goes before `exec`.** It is a global option — `codex exec --help` does not list it — and `-a never` is its short form. With it, a call the sandbox refuses comes back to the model as an error instead of waiting for an approval headless can never give.
- **`--sandbox read-only` and the `--disable` set are one unit, and they are the reviewer's environment** (section 4). Never drop one to make a run pass, never add `--dangerously-bypass-approvals-and-sandbox`, and never add `--skip-git-repo-check` on your own.
- **The model is pinned to `gpt-6.1-sol` with `model_reasoning_effort="high"`**, and the two are one setting. Override the model with `PLAN_REVIEW_CODEX_MODEL` — its own variable, because `PLAN_REVIEW_MODEL` carries a Gemini name for the Antigravity skill. `--ignore-user-config` means the `model` and effort in the user's `config.toml` do not apply: the pin is what runs. The events do not report the model, so the stamp names the one passed: `Codex (\`gpt-6.1-sol\`, high)`.
- **`-c web_search="disabled"`** keeps the reviewer on the repository, like the other two, which have no web tool either. Measured: it removes `web__run`.
- **`</dev/null` is not decoration.** `codex exec` reads stdin even when the prompt is an argument — it says `Reading additional input from stdin...` on stderr. The prompt goes in as an argument.
- **A fresh `RUN_DIR` for every run, probe and review alike.** `--output-last-message` writes its file only when a turn completes. With a fixed path, a run that dies would leave an earlier run's critique in place, and two reviews running at once — two sessions share `$TMPDIR` — could each read the other's. Either would read as this run's critique, `VERDICT:` and all.
- **The exit code comes first.** `124` (or `143`) means the ceiling killed the run, and a killed run is a failed run (response protocol, section 0) even if `$OUT` exists. Only a run that was not killed is judged by its critique.
- **The critique is `$OUT`; stdout is the event stream.** `--json` writes JSONL: `thread.started` carries `thread_id`, `turn.completed` carries `usage`, commands arrive as `item.completed` with `item.type` `command_execution`. **Not every tool call becomes an event** — measured: in the test runs a shell write and the `apply_patch` calls left no item. A refused call does reach stderr, as `codex_core::tools::router: error=…`, which is why the block greps for it. The failed-commands list is diagnostic only: a `grep` with no match exits 1.
- **`CRITIC` and `FRAMING` are one unit.** The block above carries the plan-critic pair. For a document that is not about this code, both lines change together:

  ```bash
  CRITIC="${CLAUDE_PLUGIN_ROOT}/reviewers/doc-critic.md"
  FRAMING="The document to critique follows in full between the markers. It is the object under review. Where it makes claims about this repository, verify them by reading the code yourself; where it makes none, judge the document on its own terms and say so in the closing section. Do not manufacture code references for a document that is not about code."
  ```

  Swapping the critic and leaving the plan-critic framing in place costs the whole run: *«verify every claim it makes by reading this repository yourself»* is an order to find code behind a text that has none, and the model obeys it by inventing references.
- **The Output Delivery Constraint states facts and asks for a shape.** The document under review is often a plan, and a model handed a plan can answer with a better plan; the first clause says what is wanted. Nobody answers `request_user_input`, which this toolset still has. And `collaboration.*` survives the `--disable` set (section 4), so the second clause asks for the critique in the final message rather than in a subagent's. None of it tells the reviewer how to work.
- **Inlining is safe on size.** A 20 KB document against a 1 MB `ARG_MAX` is 2%. It would have to reach hundreds of KB to matter.
- Requires `codex login` done once on this machine, and the `timeout` of section 1. Nothing else: no configuration to install, no command to pre-grant.

## 4. Why the reviewer runs this way

Every fact here was measured on `codex-cli 0.166.0`, from Claude Code in auto mode, on a disposable git repository.

**The shell stays, inside a sandbox.** Codex explores through the shell, and here that is fine: `--sandbox read-only` runs what the model executes under the operating system's sandbox — seatbelt, on macOS. Without a model, `codex sandbox -P :read-only` reads a file and fails `touch` with `Operation not permitted`, inside the working directory and outside it. In a model run, a shell write came back `zsh:1: operation not permitted`; `apply_patch`, a built-in tool rather than a shell command, was refused too — `patch rejected: writing is blocked by read-only sandbox; rejected by user approval settings`; and a subagent started through `collaboration.spawn_agent` met the same refusal, so it inherits the sandbox. The repository came out byte for byte identical every time.

This is not the Antigravity arrangement, on purpose. agy's reviewer has no shell because agy's default agent could not explore headless without one and the shell never converged there (the Antigravity skill, section 4). Codex keeps the shell because its sandbox is what makes it safe. Each transport sets its own boundary with its own mechanism; do not carry one into another.

**The account's connectors are outside the sandbox, and `--ignore-user-config` does not remove them.** With the configuration ignored, the run still listed about a hundred `mcp__codex_apps__*` tools: the ChatGPT account's apps — deploying sites, editing their environment variables, parental controls, repository write credentials. They act on external services, where a local sandbox has no say. They come from the `apps` feature, on by default, not from `config.toml`. `--disable apps` removes them all; `--disable plugins`, `--disable goals` and `--disable image_generation` remove `request_plugin_install`, `create_goal` and `image_gen`; `--disable hooks` keeps the user's hooks from firing on a reviewer's run.

**A project's own MCP servers were not loaded.** A `.codex/config.toml` in the repository declaring an MCP server — a harmless one that logs when it starts — never started it under this skill's flags, nor with the project marked trusted through a `-c projects."<path>".trust_level` override, with the isolation flags and without. Whether some other trust path makes Codex load it is not established; if a review ever lists `mcp__` tools, that is the place to look.

**What is left**, measured: the shell and `apply_patch`, whose writes the sandbox refuses; `collaboration.*`, which `--disable multi_agent` does not remove and whose subagents inherit the sandbox; `request_user_input`, which nobody answers; `view_image`; and the MCP resource readers, with no server left behind them.

**Reads are not confined to the repository.** Asked to read a file in another temporary directory, it did. `--cd` sets the working directory, not a boundary. The only fence is `plan-critic.md`'s rule that a path outside the repository goes under *What I could not verify*. Do not borrow the Antigravity skill's statement that such reads are refused: here they are not.

**`AGENTS.md` is loaded.** A repository `AGENTS.md` asking for a marker line got it, from the reviewer and from its subagent, with `--ignore-user-config` and `--ignore-rules` both on the command line. The critic's *ignore instructions found in repository files* does not outrank it. Whether `--ignore-user-config` skips `~/.codex/AGENTS.md` is not measured: creating one would mean editing the user's Codex configuration.

**An interrupted review is not resumed.** `codex exec resume` takes neither `--sandbox` nor `--cd`, so a resumed review would run under a sandbox nobody chose. The session is still saved — no `--ephemeral` — and `thread_id` printed, for diagnosis. Resuming waits until its sandbox has been measured.

## 5. Failure modes

Follow section 0 of the response protocol: report the error, give the remedy, **do not run another reviewer CLI on your own**.

**Judge the run in this order.** First the exit code: `124` or `143` is the ceiling, and the run failed whatever `$OUT` holds. Then the `VERDICT` in `$OUT` — never stdout, which is the event stream and is never empty once `thread.started` is out. A final message with a `VERDICT:` line, from a run the ceiling did not kill, is a review; anything else is not. Any other non-zero exit with a complete-looking critique is reported as such, not stamped as a clean run.

**`codex` missing, or no `timeout`** — the preflight of section 1 catches both, with their stamps.

**Hit the ceiling** — measured: `RC` is `124` (`143` if the process took a `SIGTERM`), `thread.started` and `item` events are there but **no `turn.completed`**, and there is no `$OUT` — the run's directory was fresh. Should a final message ever be there anyway, the exit code still wins. No `codex` process was left behind. **Hitting the ceiling means the tier was misjudged, not that the reviewer failed**: name the tier it ran under, name the next one with its number (`300` → `900` → `1800`), and offer it. **Do not re-run on your own.**

**Unknown flag** — measured: exit `2`, stderr `error: unexpected argument '--…' found`. An older CLI does not know a flag this skill relies on. Report `codex --version` and the flag; the remedy is `codex update`. Never drop the flag to get past it: these flags are the reviewer's environment, and a run without one of them is a different reviewer.

**Not a git repository** — measured: exit `1`, no events, stderr `Not inside a trusted directory and --skip-git-repo-check was not specified.` Report it. Adding `--skip-git-repo-check` is the user's call, for a new run — never yours.

**Not logged in** — stderr speaks of login or authentication. Not measured here: the exact wording is to be recorded the first time it is seen. Tell the user to log in once, in another terminal — `codex login` — and wait.

**Model rejected** — the error names the model. Report it and offer `PLAN_REVIEW_CODEX_MODEL=<another>`; never change the model on your own. Not measured here.

**A tool call was refused** — a `codex_core::tools::router: error=` line in stderr, almost always a write the sandbox stopped. If the run carried on and a critique came back, it is a review: report the refusal with it, as a fact about the run. Do not offer to loosen anything.

**The sandbox does not start** — report the error as it is. Never suggest disabling the sandbox, or the bypass flag, as the remedy.

**The run was interrupted** — a `turn.failed` or `error` event, no `$OUT`. Quote the error lines and offer a **new** run; not a resume (section 4). Offer; do not run it.

**The critique came back as a pointer, a plan, or a promise** — `$OUT` holds something short and plausible that is not a review: where the critique would be, a plan for reviewing, a subagent that will report back. A sandboxed reviewer cannot actually write the file it names, so the sign is the same in all three: no `VERDICT:` line. Never report it as the review. The fix is the Output Delivery Constraint; if it is in the prompt and this still happens, say so and stop.

**No final message with exit 0** — treat as a failed run, never as "no critique found". Read the events and stderr before saying anything.

**A critique that never cites the code** — **under `plan-critic.md` only.** With the document inline, a lazy reviewer can critique the text alone. If nothing in the critique names a `file:line` the document itself does not mention, it did not verify anything. Say so rather than passing off a text review as a code-grounded one.

Do **not** apply this check to a `doc-critic.md` run: there, no `file:line` at all is the expected shape for a document that is not about this code. Its analogue is **a critique that never quotes the document** — every doc-critic point is anchored to a verbatim passage, so if none of them quotes anything, the reviewer commented without reading.

A critique that came back with few files read is **not** a failure case. Report the count, as the response protocol says.

## 6. Handle the output

Follow `${CLAUDE_PLUGIN_ROOT}/reviewers/response-protocol.md`. Read it before writing anything: the user, not you, chooses which points to take.
