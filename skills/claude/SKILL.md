---
name: claude
description: "Submits a plan, or any document — an analysis, a specification, a proposal, a decision note — to a separate headless Claude Code instance as an adversarial reviewer with read-only access to the repo; you then propose what to do with each point and the user chooses which points to take. Use this skill only when the user names Claude as the reviewer — \"a second Claude\", Claude Code itself — in the request, or by picking it in a question of /adversarial-plan-reviewer:antigravity. With no reviewer named, ask that question first. On a plan, this runs during plan mode, on the plan document, before proposing the plan with ExitPlanMode — not after. Requests may come in any language."
---

# Plan review — headless Claude Code

A second Claude Code process reviews the plan with read-only tools. Do not prepare context: it reads the repo itself.

Note the trade-off, and mention it if the user seems to expect otherwise: the reviewer shares your model family, your `CLAUDE.md` and your conventions. It verifies the plan against the code well, but it is a weaker adversary than a different vendor's model — it tends to share your blind spots. Prefer it when the value is repo-grounded verification rather than genuine disagreement.

## 0. When to run it

Only when the user names Claude as the reviewer — in the request, or by picking `Claude` in one of the two questions of `/adversarial-plan-reviewer:antigravity`. For an unnamed review, ask that skill's `Reviewer` question first: there is no default reviewer.

The trace rule is the same one the other skills carry: whatever the outcome, the plan document ends up with a `> **Review**: …` line right after its title — section 4 of the response protocol.

This reviewer never starts on its own. Picked in a question, it is named: that answer is the request, so run it without asking again. Another pass stays with it, unless the user names a different reviewer. The rest follows the response protocol like the other reviewers: you propose `ACCEPT` / `REJECT` for each point, the user chooses which points to take, and the plan changes on those alone.

The timing is the same as the other reviewers': *inside* plan mode, on the plan document, **before** proposing it with `ExitPlanMode`. Plan mode blocks writes, not reads, and the plan document is the one file you may edit — so the *review → choose → revise → propose* loop closes inside plan mode rather than forcing the user to reject a plan just to get it reviewed.

## 1. Preflight — can the reviewer read this repo?

**Once per conversation and per working directory, before the first review.** Not before every review: once it has passed, say so and move on.

The probe is a **dress rehearsal of the review**: same transport, same permission mode, same tool allowlist — only the prompt is shorter and the turn budget smaller. Keep it that way, or it stops predicting anything about the run it is meant to protect.

```bash
cd "${CLAUDE_PROJECT_DIR:-$PWD}" || exit 1
OUT="${TMPDIR:-/tmp}/plan-review-probe-claude.json"
PROBE="List the names of the files and directories at the root of this repository, one per line, nothing else — no commentary, no code fences."

echo "=== the real root ==="; ls -A
claude -p --permission-mode plan --allowedTools "Read,Grep,Glob" --disallowedTools "Write,Edit,Bash" --max-turns 5 --output-format json "$PROBE" <"/dev/null" >"$OUT" 2>&1
RC=$?
echo "=== exit $RC ==="
jq -r 'if .is_error then "PROBE ERROR: \(.result // .error // "unknown")" else (.result // empty) end' <"$OUT" 2>/dev/null || head -c 500 "$OUT"
```

Half a minute, and it settles in one turn what otherwise fails at the end of a long run: credentials and quota, the allowlist, and whether the reviewer can see this directory at all.

**Reading the result.** `ls -A` prints the real root for free — compare against it. It **passes** when the names are the ones of *this* directory, including at least one a model could not have guessed. It **fails** on an empty or missing `.result`, on `.is_error`, on prose instead of names, or on a plausible generic project — `src/`, `package.json` — that is not this one.

**If it fails, the review does not run.** Report the CLI's own error with the remedy section 4 of this skill gives for it, write the *failed* stamp of section 4 of the response protocol onto the plan naming the probe as the cause, and stop.

**The probe is not a review.** No critic, no verdict, and it never counts toward files read.

**Why this side has nothing to forward.** On the agy transport the tool set is fixed too, by the `plan-reviewer` agent and the command list it runs under, and what can still stop a review there is a refused read outside the workspace, which that skill reports with `--add-dir` as the remedy, or a command outside the list. Here the tool set is decided on the command line — `--allowedTools "Read,Grep,Glob"`, `--disallowedTools "Write,Edit,Bash"` — so the reviewer never asks for anything: it reads, or the run fails for a reason that has nothing to do with permissions. That is also why this probe is cheaper to trust and why a failure here points at credentials, quota or the turn ceiling instead.

## 2. Locate the document, then pick the critic

### The document

Find it in this order:

1. the path the user gave, if any;
2. **the plan document of the current plan mode session** — the path named in your plan mode instructions, typically under `~/.claude/plans/`. This is the authoritative version while you are planning;
3. **the plan document of this conversation's last plan mode session** — for a review asked for *after* leaving plan mode. It is the same path the plan mode instructions named: Claude Code keeps the file under `~/.claude/plans/` after approval. Never take the newest file in that folder instead: it can belong to another session.

If none exists, or the plan mode path is no longer in the conversation — after a compaction, for instance — stop and ask. Do not reconstruct the plan from memory of the conversation.

For any other document — an analysis, a specification, a proposal, a note — same mechanism with that document's path.

### The critic

Same rule as the other skills, and the two critics live in the same `${CLAUDE_PLUGIN_ROOT}/reviewers/`:

1. **a plan document** — a plan mode session's, during or after plan mode → **always** `plan-critic.md`;
2. otherwise, **are the document's claims verifiable against this repository?** An analysis of this codebase, an ADR, a post-mortem on it → `plan-critic.md`. A specification, a proposal, a note, anything whose subject is not this code → `doc-critic.md`;
3. **if the user names the critic, they win.** Say which one you used either way.

`plan-critic.md` requires a `file:line` on every point; pointed at a text that is not about code it invents them. `doc-critic.md` anchors each point to a verbatim quote of the document instead. The framing line in the prompt is chosen with the critic, not separately — section 3 shows both pairs.

## 3. Run the review

The document goes **inline in the prompt**, not as a path: the plan document usually lives outside the repo, and in plan mode you cannot copy it in — the plan file is the only thing you may write.

This does not contradict "do not prepare context". That rule is about context **on the repository** — summaries, extracted code, a curated file list. The document is not context: it is the **object under review**. What the reviewer is told to do with the repository is the `FRAMING` line, and it follows the critic.

### The ceiling

A timeout is a **ceiling, not a budget**: a review that needs four minutes finishes in four minutes whatever the ceiling is. Raising it costs nothing on a healthy run — it costs wall clock only on a run that hangs, inside plan mode. So it answers **how long do you wait before concluding something is broken**, and you err high: too low costs the whole run plus the next one, where 5 then 15 makes 20 minutes against 15 for starting there.

Here the tier is **two numbers, and they are one unit.** `--max-turns` bounds the agent loop independently of the clock, so raising the timeout alone buys no depth — the run still ends at turn 20, with a *partial* critique that presents itself as a whole one. Move both or neither.

| Tier | `timeout` | `--max-turns` |
|---|---|---|
| **short** | `300` | `20` |
| **standard** | `900` | `40` |
| **deep** | `1800` | `60` |

Pick one as **a judgement you state, not a threshold you count**:

- **short** — a short, contained document: a plan over a handful of files in one component, a note of two pages. The **floor, not the default**.
- **standard** — the ordinary case: a plan with architectural consequences, several modules touched, a document past ~10 KB, a repo of some hundreds of files. **In doubt, take the higher tier.**
- **deep** — a review in depth was asked for; or a previous run hit a ceiling; or the plan rewrites something structural across a large repo.

The signals are free and in hand: the size of the document, how many distinct files and modules the plan names, `git ls-files | wc -l` for the repo. The floor is deliberately not the default — this reviewer runs only when the user names or picks it, and trivial plans get no question, so its runs start above the floor. Say which tier you ran under when it is not the floor: section 5 of the response protocol.

### The command

```bash
cd "${CLAUDE_PROJECT_DIR:-$PWD}" || exit 1
PLAN="<PLAN_PATH>"
TO=$(command -v timeout || command -v gtimeout || true)
OUT="${TMPDIR:-/tmp}/plan-review-claude.json"
ERR="${TMPDIR:-/tmp}/plan-review-claude.err"
# The tier chosen above goes here, both of its numbers. Raising one alone is the trap below.
REVIEW_TIMEOUT="${PLAN_REVIEW_TIMEOUT:-900}"
REVIEW_TURNS="${PLAN_REVIEW_MAX_TURNS:-40}"

# Section 2 chose these two together. They are one unit: see the constraint below.
CRITIC="${CLAUDE_PLUGIN_ROOT}/reviewers/plan-critic.md"
FRAMING="The document to critique follows in full between the markers. It is the object under review, not a description of the code: verify every claim it makes by reading this repository yourself."

PROMPT="$(cat "$CRITIC")

$FRAMING

--- BEGIN DOCUMENT UNDER REVIEW ---
$(cat "$PLAN")
--- END DOCUMENT UNDER REVIEW ---"

${TO:+$TO $REVIEW_TIMEOUT} claude -p \
  --permission-mode plan \
  --allowedTools "Read,Grep,Glob" \
  --disallowedTools "Write,Edit,Bash" \
  --max-turns "$REVIEW_TURNS" \
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

- **`CRITIC` and `FRAMING` are one unit.** The block above carries the plan-critic pair. For a document that is not about this code, both lines change together:

  ```bash
  CRITIC="${CLAUDE_PLUGIN_ROOT}/reviewers/doc-critic.md"
  FRAMING="The document to critique follows in full between the markers. It is the object under review. Where it makes claims about this repository, verify them by reading the code yourself; where it makes none, judge the document on its own terms and say so in the closing section. Do not manufacture code references for a document that is not about code."
  ```

  Swapping the critic and leaving the plan-critic framing in place costs the whole run: *«verify every claim it makes by reading this repository yourself»* is an order to find code behind a text that has none, and the model obeys it by inventing references.
- `--permission-mode plan` plus the explicit tool allowlist keeps the run read-only. Never `--dangerously-skip-permissions`.
- The response lives in `.result`. `.is_error` flags a failed run even when the exit code is 0.
- **Redirect to a file, do not pipe into `jq`.** Reading the exit status through a pipe is not portable: `${PIPESTATUS[0]}` is bash-only and expands to nothing under zsh, which is what Claude Code's Bash tool actually runs. Redirecting first keeps `$?` meaningful in either shell.
- `TO` is the portable timeout: GNU `timeout` is absent on a stock macOS, `gtimeout` comes from `brew install coreutils`. If neither exists the command runs unwrapped rather than failing with `command not found` — and then **`--max-turns` is the only ceiling left**, with nothing bounding the clock. At the short tier that was a footnote; at the deep tier it means the half-hour ceiling does not exist on that machine.
- `</dev/null` is not decoration: without it `claude -p` blocks for 3s waiting on stdin and warns `no stdin data received in 3s`. The prompt goes in as an argument, never on stdin.
- **Inlining is safe on size.** A 17 KB document against a 1 MB `ARG_MAX` is under 2%. It would have to reach hundreds of KB to matter.
- **`--max-turns` moves with the timeout, never alone.** It caps the agent loop independently of the clock, so the two numbers *are* the tier and the tier is one unit — the table above. `PLAN_REVIEW_MAX_TURNS` overrides it as `PLAN_REVIEW_TIMEOUT` overrides the clock, and overriding one means deciding about the other. The flag works but is not listed in `claude --help`; if a future version rejects it, drop the flag rather than the review.
- Add `--model` if the user wants a specific one. Default is fine otherwise.
- No `@file` syntax here: the document is in the prompt, and the repo is what the reviewer reads on its own.

## 4. Failure modes

Follow section 0 of the response protocol: report the error, give the remedy, **do not run another reviewer CLI on your own**.

**Authentication or quota** — `.is_error` is true, or stderr mentions login, credit balance, or a 429. Report the message and let the user fix the account. Do not retry in a loop.

**Unknown flag** — stderr contains `unknown option`. Name the flag, drop it, and re-run once. This is the one retry allowed here, because the fix is certain.

**Turn limit** — the result mentions the max turns being reached. The critique is partial: say so before reporting it. It means the tier was too low, so offer the next one with **both** of its numbers — raising the turns under the same clock only changes which ceiling stops the run.

**Hit the clock** — the wrapper kills the process outright, so unlike agy nothing announces it. The signature: `RC` is **`124`** (`timeout` expired) or `143` (`SIGTERM`), the JSON is cut off mid-envelope, `jq` fails on it, and what reaches the screen is the fallback branch of the command block — `!! output is not JSON, raw:` followed by a truncated envelope. Without that signature a timeout is indistinguishable from any other crash that produces invalid JSON. Report it as a misjudged tier, offer the next one, and do not re-run on your own. The complementary case: with `TO` empty there is no wrapper, so there is no `124` to recognise and the only ceiling that can fire is the one on turns.

**Missing CLI or empty `.result` with exit 0** — treat as a failed run, not as "no critique found".

**A critique that never cites the code** — **under `plan-critic.md` only.** With the document inline, a lazy reviewer can critique the text alone. If nothing in the critique names a `file:line` the document itself does not mention, it did not verify anything. Say so rather than passing off a text review as a code-grounded one.

Do **not** apply this check to a `doc-critic.md` run: there, no `file:line` at all is the expected shape for a document that is not about this code. Its analogue is **a critique that never quotes the document** — every doc-critic point is anchored to a verbatim passage, so if none of them quotes anything, the reviewer commented without reading.

## 5. Handle the output

Follow `${CLAUDE_PLUGIN_ROOT}/reviewers/response-protocol.md`. Read it before writing anything: the user, not you, chooses which points to take.
