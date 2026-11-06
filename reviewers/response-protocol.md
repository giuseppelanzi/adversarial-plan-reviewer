# Response protocol

Shared by the reviewer skills of the `adversarial-plan-reviewer` plugin. Applies once the reviewer's output is back.

The reviewer critiques, you propose, **the user decides**. You say what you would do with each point and why; the user chooses which points to take; you act on those and nothing else. That takes two turns, because you cannot know their choice until it arrives: **phase A** (sections 2 and 3, up to the question) right after the review, **phase B** (the rest of section 3, then sections 4 and 5) after their answer.

## Language

Write everything you produce — the proposals, the summary, any question to the user — in the language of the conversation. If that is unclear, use the language the plan is written in. Never switch to English just because these instructions are in English.

The reviewer is told to answer in the language of the document under review. If it comes back in a different language anyway, quote its points in their original wording and write your own proposals in the conversation language.

## 0. Check the reviewer actually ran

Before treating the output as a review, check whether the CLI failed. The failure modes are listed in each `SKILL.md`; the shared rules are these.

Treat the run as failed if any of these hold:

- non-zero exit code with no critique
- empty output — for `agy`, an empty stdout with exit 0 is the *normal* shape of a failure, so never read it as "no critique found"; for `codex`, the critique is the `--output-last-message` file, not stdout — stdout is the event stream and is never empty — so a missing or empty file is the failure
- the output or stderr carries an authentication, quota, permission (`auto-denied`), or `command not found` error, and no critique came back
- the process was killed by the timeout
- **the output is a pointer rather than a critique** — a short paragraph saying the review was written to a file, naming a path. It is not empty, so nothing above catches it. A review has a `VERDICT:` line and labelled points; anything else is a failed run, whatever it says about itself.

The `VERDICT:` line decides, not the exit code and not a `status` field: a run can report success and be empty, and a resumed run has reported an error with a whole critique in it.

A run **killed by the ceiling** is a failed run too, and it is the only one whose cause you already know: the tier was misjudged, not the reviewer. Report the tier it ran under and offer the next one — each skill's table names them. Offering is not re-running, and point 3 below still holds.

When the run failed:

1. **Say so.** Report which reviewer failed and quote the CLI's own error message, trimmed to the useful lines. Do not paraphrase it into "something went wrong".
2. **Give the concrete remedy** — the one the skill lists for that error. It is normally a command the user runs themselves in another terminal.
3. **Stop there.** Do not retry the command, do not silently work around the error, and above all **do not run a different reviewer CLI instead**. Picking the fallback is the user's call, not yours: another reviewer costs money and answers a question they did not ask. Offer it in one line, then wait.
4. **Never invent a critique.** A missing review is reported as missing.
5. **Stamp the failure on the document**, in the failed form of section 4. A failed review that leaves no trace in the plan is indistinguishable from a review that was never attempted.

## 1. Report how deep the review went

The reviewer decides on its own how much to read, and a shallow review looks exactly like a thorough one unless the reader is told what it opened.

Count the entries in the closing section — `Files read` under `plan-critic.md`, `Sources read` under `doc-critic.md`, possibly translated into the document's language — and carry that number into your summary. Report it as a **fact, not a verdict**.

Resist the temptation to judge it. A short list is often the right answer: a first plan in a new repo, a greenfield project, a plan that genuinely touches two files. You do not know the repo better than the user does — give them the count and let them decide whether it is enough. If the section is missing entirely, say that instead of the number.

Under `doc-critic.md` an **explicitly empty** list — *"the document is not about this repository"* — is a correct outcome and reports as such. It is not a shallow review, and it is not a broken run.

The one case that *is* a failure is section 0's: no output at all. That is a broken run, not a shallow one, and it never gets reported as a review.

## 2. Phase A — propose, point by point

Report the reviewer's `VERDICT` line first, verbatim, then work through **every** point — `[BLOCKING]`, `[SHOULD-FIX]` and `[NOTE]` alike. A note is offered like the others: the reviewer thinks it does not change the plan, and the user may still take it.

For each point:

**Point raised**: quote it verbatim, not paraphrased into a milder version. Name the reviewer that raised it.

**Proposal**: `ACCEPT` or `REJECT`. No third option, no "partially valid".

**Consequence**: if you propose to accept, what concretely would change in the plan — not "I will take this into account". If you propose to reject, why it does not apply, with a `file:line` reference or the constraint that disproves it.

Rules:

- Do not compress the critique into a conciliatory paragraph. The user must be able to read what the reviewer said and what you propose to do with it.
- Proposing to reject is legitimate and frequent: the reviewer does not know constraints stated verbally in the conversation. But it must be argued, not waved away.
- The reviewer's verdict does not decide your proposals. A `PASS` does not oblige you to accept a `[SHOULD-FIX]`, and a `FAIL` does not oblige you to accept the `[BLOCKING]` that caused it — but proposing to reject the point that produced a `FAIL` needs a stronger argument than usual, and you say so explicitly.
- **Do not touch the plan's body in this phase.** The one thing you write into the document is the provisional block of section 4, at its head.

## 3. The user chooses, then the plan changes

### The question (phase A)

After the proposals, ask the user **which points to take**, with `AskUserQuestion` and **`multiSelect: true` written out** — the default is single choice, under which nobody can take more than one point. The tool takes **2 to 4 options per question** and at most 4 questions per call:

- **one point**: a single-choice question with two options, *take point 1* / *set point 1 aside*;
- **2 to 4 points**: one question, the label in each option's text (`[BLOCKING] 1 — …`);
- **more**: one question per label while 4 questions are enough; when they are not — even under 16 points: 5 BLOCKING, 5 SHOULD-FIX and 1 NOTE make 5 questions — lay the points out in order in **balanced** blocks, never a question with a single option (5 points → 3 + 2, not 4 + 1); a label with a single point joins another;
- **more than 16**: ask for a free answer with the numbers.

Say which points you propose to take. "None of these" takes no option of its own: the user writes it under *Other*, which the tool always offers.

**With no points raised the two phases collapse into one turn**: no question about points, the final stamp at once (`No points raised` / `Plan unchanged: no points raised.`), and a final question offering only approval or more discussion — a second pass on a review with nothing in it makes no sense.

### What happens to the plan (phase B)

Rewrite the plan on **the points the user took, and only those**, and show the diff against the previous version. Never apply changes silently, and never act on a point they set aside — not even a little, not even when you proposed to accept it.

If, while applying a point they took, you find it is wrong after all, say so and why, instead of skipping it in silence.

Then state the outcome and ask the final question — **another pass**, **approve** (`ExitPlanMode`), or **keep discussing**. Another pass goes to the reviewer of the first, with no question about which: it checks that its own points were resolved. A different reviewer only if the user names one.

- **a `[BLOCKING]` taken** → the plan changed where it would have broken: another pass is **recommended**. Recommend it; the user decides.
- **only `[SHOULD-FIX]` or `[NOTE]` taken** → the plan is rewritten and no further pass is needed.
- **everything set aside** → say it in those words: the review changed nothing. This is a legitimate outcome and it must stay visible instead of dissolving into a reassuring summary.

`PASS` never means "proceed unchanged": points the user takes still change the plan.

One escalation, as a judgement you state rather than a threshold you count: if the points taken change the plan's *approach* rather than its details — the corrections cascade, each step dragging the next — say that the plan should be rewritten from scratch and re-reviewed, and recommend it strongly, even with no blocking point. Three fixes on a four-step plan is usually this case; three on a twenty-step plan is not. The decision is still the user's.

**When the document under review is not a plan** — a specification, a proposal, an analysis, a note — the same two phases apply, but phase B differs: there is nothing of yours to rewrite and no pass to schedule. Say, for each point taken, what you would change in the document, concretely enough to act on. Then stop: editing it is the user's call, not yours. Everything else in this protocol still holds — the binary proposal, the ban on paraphrasing a point into something milder, and the rule that "everything set aside" is said out loud rather than dissolved into a summary.

## 4. Stamp the document

The close below lives in the conversation and scrolls away. The plan document does not: it is what the user approves, and what the `ExitPlanMode` hook archives into `.claude/plans/`. So the outcome goes there too, immediately after the document's `#` title.

**In phase A** the block is provisional, so that the plan never looks unreviewed while the user chooses. It is the one change to the document in that phase:

```
> **Review**: Antigravity (`gemini-4-argon-high`) — VERDICT: FAIL — 11 files read
> 8 points proposed (4 BLOCKING, 3 SHOULD-FIX, 1 NOTE) — awaiting the user's choice.
```

The same form for the other reviewers, with `Claude Code (<model>)` or ``Codex (`gpt-6.1-sol`, high)`` in the first line.

**In phase B** it becomes final — one line per line of section 5's close, the same three facts, not a second summary invented for the occasion:

```
> **Review**: Antigravity (`gemini-4-argon-high`) — VERDICT: FAIL — 11 files read
> 7 points taken (3 BLOCKING, 3 SHOULD-FIX, 1 NOTE), 1 set aside (1 BLOCKING)
> Plan rewritten on the points taken; another pass recommended (BLOCKING taken).
```

The second line takes one of four forms:

- some taken, some set aside: `7 points taken (3 BLOCKING, 3 SHOULD-FIX, 1 NOTE), 1 set aside (1 BLOCKING)`
- all taken: `8 points taken (4 BLOCKING, 3 SHOULD-FIX, 1 NOTE), none set aside`
- none taken: `No points taken, 5 set aside (2 BLOCKING, 3 SHOULD-FIX)`
- none raised: `No points raised`

The third line, one of four:

- `Plan rewritten on the points taken; another pass recommended (BLOCKING taken).`
- `Plan rewritten on the points taken; no further pass needed.`
- `Plan unchanged: every point set aside.`
- `Plan unchanged: no points raised.`

**When the run failed** — section 0's case — the block is still written, in this form:

```
> **Review**: Antigravity produced no output — tool auto-denied or execution failed.
> Plan NOT verified.
```

Quote the reviewer's own error in that first line, trimmed. Do not substitute a cause of your own: naming the wrong one is how a diagnosis nobody re-checks ends up stamped on every plan.

**When the review never started** because the preflight stopped before any run — `agy` not found, or the reviewer agent missing or outdated; `codex` not found, or no `timeout` / `gtimeout` for it — there is no reviewer error to quote, so the block says what stopped it:

```
> **Review**: Antigravity not run — `agy` not found.
> Plan NOT verified.
```

```
> **Review**: Antigravity not run — reviewer agent missing or outdated (~/.gemini/config/agents/plan-reviewer.md).
> Plan NOT verified.
```

```
> **Review**: Codex not run — `codex` not found.
> Plan NOT verified.
```

```
> **Review**: Codex not run — no `timeout` or `gtimeout` on this machine.
> Plan NOT verified.
```

That is the case where it matters most. A plan that was never verified but looks verified is worse than one that says it was not.

Rules:

- `**Review**:` is a **fixed marker**. Keep those two words in English whatever language the document is in, and keep the block inside the **first ten lines**. The hook greps for exactly that: a block written further down, or with the word translated, reads to it as no declaration at all: it warns the user and puts its own notice on top of yours in the copy it saves.
- **One block only.** A later pass rewrites it and names itself (`second pass`); it does not stack. If the document already opens with a `> **Review**:` block — the provisional one of phase A, or the hook's own notice on `latest.md` — replace it.
- **Which document.** The plan document of the current plan mode session, or `.claude/plans/latest.md`. Never a document the user wrote themselves: for `docs/auth-analysis.md` the review is reported in the conversation only. Writing into someone's own file uncalled-for is a surprise.

  **This rule keys on the document, never on the critic.** `docs/auth-analysis.md` is an analysis of this codebase, so it runs under `plan-critic.md` — and it still gets no stamp, because it is the user's file. Read the condition the other way round, as *"plan-critic ran, therefore stamp"*, and you end up writing into documents nobody asked you to touch. Only a plan is stamped, whichever critic reviewed it.
- Everything except the marker and the `PASS`/`FAIL`/`BLOCKING`/`SHOULD-FIX`/`NOTE` labels follows the language of the document.

## 5. Close

Three lines, at the end of phase B, in this order:

1. The reviewer's verdict, which reviewer produced it, **which critic it ran under**, and how many files or sources it read. Name the **ceiling** as well when it mattered: a run above the floor tier, or a run that hit the ceiling.
2. How many points taken and how many set aside, broken down by label.
3. What section 3 decided about the plan — or, for a document that is not a plan, what you would change in it.

Naming the critic is not bookkeeping: a `plan-critic.md` run and a `doc-critic.md` run answer different questions, and a review reported without saying which one it was reads as more code-grounded than it is.

Then the final question of section 3: another pass, approve, or keep discussing.

Do not re-run the review, and do not run a second reviewer, on your own initiative. That is the user's call — including the pass a `[BLOCKING]` recommends: you say it is recommended, they decide.
