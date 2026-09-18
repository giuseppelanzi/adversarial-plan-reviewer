# Response protocol

Shared by both reviewer skills of the `plan-review` plugin. Applies once the reviewer's output is back.

## Language

Write everything you produce — the point-by-point response, the summary, any question to the user — in the language of the conversation. If that is unclear, use the language the plan is written in. Never switch to English just because these instructions are in English.

The reviewer is told to answer in the language of the document under review. If it comes back in a different language anyway, quote its points in their original wording and write your own verdicts in the conversation language.

## 0. Check the reviewer actually ran

Before treating the output as a review, check whether the CLI failed. The failure modes are listed in each `SKILL.md`; the shared rules are these.

Treat the run as failed if any of these hold:

- non-zero exit code
- empty output — for `agy`, an empty stdout with exit 0 is the *normal* shape of a failure, so never read it as "no critique found"
- the output or stderr carries an authentication, quota, permission (`auto-denied`), or `command not found` error
- the process was killed by the timeout
- **the output is a pointer rather than a critique** — a short paragraph saying the review was written to a file, naming a path. It is not empty, so nothing above catches it. A review has a `VERDICT:` line and labelled points; anything else is a failed run, whatever it says about itself.

A run **killed by the ceiling** is a failed run too, and it is the only one whose cause you already know: the tier was misjudged, not the reviewer. Report the tier it ran under and offer the next one — the tables in the two skills name them. Offering is not re-running, and point 3 below still holds.

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

## 2. Respond point by point

This is what gives the skill its value. Report the reviewer's `VERDICT` line first, verbatim, then work through the points.

Respond to every `[BLOCKING]` and every `[SHOULD-FIX]`. List the `[NOTE]` points at the end without a verdict of your own — they do not change the plan, and mixing them in dilutes the part that matters.

For each point:

**Point raised**: quote it verbatim, not paraphrased into a milder version. Name the reviewer that raised it.

**Verdict**: `ACCEPTED` or `REJECTED`. No third option, no "partially valid".

**Consequence**: if accepted, what concretely changes in the plan — not "I will take this into account". If rejected, why it does not apply, with a `file:line` reference or the constraint that disproves it.

Rules:

- Do not compress the critique into a conciliatory paragraph. The user must be able to read what the reviewer said and what you did with it.
- Rejecting is legitimate and frequent: the reviewer does not know constraints stated verbally in the conversation. But it must be argued, not waved away.
- If you accept something, rewrite the plan and show the diff against the previous version. Never apply changes silently.
- The reviewer's verdict does not decide yours. A `PASS` does not oblige you to accept a `[SHOULD-FIX]`, and a `FAIL` does not oblige you to accept the `[BLOCKING]` that caused it — but rejecting the point that produced a `FAIL` needs a stronger argument than usual, and you say so explicitly.

## 3. Decide what happens to the plan

State the outcome. Do not hand this decision back to the user as an open question.

- **A `[BLOCKING]` accepted** → the plan is rewritten before any implementation starts, and it needs another review pass. Not negotiable.
- **No blocking, `[SHOULD-FIX]` accepted** → the plan is rewritten to incorporate them, then work proceeds. No second pass. The difference from blocking is that it skips the re-review, not the work: an accepted point that changes nothing is a point you should have rejected.
- **`[NOTE]`** → recorded, not acted on.
- **Everything rejected** → say it in those words: the review changed nothing. This is a legitimate outcome and it must stay visible instead of dissolving into a reassuring summary.

`PASS` never means "proceed unchanged". It means nothing forces a redesign; accepted `[SHOULD-FIX]` points still change the plan.

One escalation, as a judgement you state rather than a threshold you count: if fixing the accepted points turns out to change the plan's *approach* rather than its details — the corrections cascade, each step dragging the next — the plan is rewritten from scratch and re-reviewed, even with no blocking point. Three fixes on a four-step plan is usually this case; three on a twenty-step plan is not.

**When the document under review is not a plan** — a specification, a proposal, an analysis, a note — none of the above applies as written: there is nothing of yours to rewrite and no second pass to schedule. Say which points you accept and, for each, what you would change in the document, concretely enough to act on. Then stop: editing it is the user's call, not yours. Everything else in this protocol still holds — the binary verdict, the ban on paraphrasing a point into something milder, and the rule that "everything rejected" is said out loud rather than dissolved into a summary.

## 4. Stamp the document

The close below lives in the conversation and scrolls away. The plan document does not: it is what the user approves, and what the `ExitPlanMode` hook archives into `.claude/plans/`. So the outcome goes there too.

Write the block immediately after the document's `#` title, before proposing the plan:

```
> **Review**: Antigravity (`gemini-3.1-pro-high`) — VERDICT: PASS — 12 files read
> 4 points accepted (1 BLOCKING, 3 SHOULD-FIX), 2 rejected, 1 note
> Plan rewritten on the accepted points; no second pass needed.
```

One line per line of section 5's close — the same three facts, not a second summary invented for the occasion.

**When the run failed** — section 0's case — the block is still written, in this form:

```
> **Review**: Antigravity produced no output — tool auto-denied or execution failed.
> Plan NOT verified.
```

Quote the reviewer's own error in that first line, trimmed. Do not substitute a cause of your own: naming the wrong one is how a diagnosis nobody re-checks ends up stamped on every plan.

That is the case where it matters most. A plan that was never verified but looks verified is worse than one that says it was not.

Rules:

- `**Review**:` is a **fixed marker**. Keep those two words in English whatever language the document is in, and keep the block inside the **first ten lines**. The hook greps for exactly that: a block written further down, or with the word translated, reads to it as no declaration at all, and it prepends its own notice on top of yours.
- **One block only.** A second pass rewrites it and names itself (`second pass`); it does not stack. If the document already opens with a `> **Review**:` block — typically the hook's own notice, on `latest.md` — replace it.
- **Which document.** The plan document of the current plan mode session, or `.claude/plans/latest.md`. Never a document the user wrote themselves: for `docs/auth-analysis.md` the review is reported in the conversation only. Writing into someone's own file uncalled-for is a surprise.

  **This rule keys on the document, never on the critic.** `docs/auth-analysis.md` is an analysis of this codebase, so it runs under `plan-critic.md` — and it still gets no stamp, because it is the user's file. Read the condition the other way round, as *"plan-critic ran, therefore stamp"*, and you end up writing into documents nobody asked you to touch. Only a plan is stamped, whichever critic reviewed it.
- Everything except the marker and the `PASS`/`FAIL`/`BLOCKING`/`SHOULD-FIX` labels follows the language of the document.

## 5. Close

Three lines, in this order:

1. The reviewer's verdict, which reviewer produced it, **which critic it ran under**, and how many files or sources it read. Name the **ceiling** as well when it mattered: a run above the floor tier, or a run that hit the ceiling.
2. How many points accepted and how many rejected, broken down by label.
3. What section 3 decided about the plan — or, for a document that is not a plan, what you would change in it.

Naming the critic is not bookkeeping: a `plan-critic.md` run and a `doc-critic.md` run answer different questions, and a review reported without saying which one it was reads as more code-grounded than it is.

Then ask whether to proceed.

Do not re-run the review, and do not run a second reviewer, on your own initiative. That is the user's call — including the second pass a `[BLOCKING]` calls for: you say it is needed, they decide when.
