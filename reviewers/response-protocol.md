# Response protocol

Shared by every `plan-review-*` skill. Applies once the reviewer's output is back.

## Language

Write everything you produce — the point-by-point response, the summary, any question to the user — in the language of the conversation. If that is unclear, use the language the plan is written in. Never switch to English just because these instructions are in English.

The reviewer is told to answer in the language of the document under review. If it comes back in a different language anyway, quote its points in their original wording and write your own verdicts in the conversation language.

## 1. Assess the review before using it

The reviewer decides on its own how deep to dig. A shallow review is indistinguishable from a thorough one unless you check what it actually read.

Look at the closing "Files read" section:

- Missing, or listing only the plan itself → the reviewer verified nothing. Say so and offer to re-run.
- One or two files for a plan touching ten → partial coverage. State this explicitly before reporting the critique.

If the command timed out or returned empty output, say so and stop. Never invent a plausible critique in place of a missing one.

## 2. Respond point by point

This is what gives the skill its value. For each point raised:

**Point raised**: quote it verbatim, not paraphrased into a milder version. Name the reviewer that raised it.

**Verdict**: `ACCEPTED` or `REJECTED`. No third option, no "partially valid".

**Consequence**: if accepted, what concretely changes in the plan — not "I will take this into account". If rejected, why it does not apply, with a `file:line` reference or the constraint that disproves it.

Rules:

- Do not compress the critique into a conciliatory paragraph. The user must be able to read what the reviewer said and what you did with it.
- Rejecting is legitimate and frequent: the reviewer does not know constraints stated verbally in the conversation. But it must be argued, not waved away.
- If you accept something, rewrite the plan and show the diff against the previous version. Never apply changes silently.
- If you accept more than half the points, the plan needs rewriting, not patching. Say so.

## 3. Close

Two lines: how many points accepted, how many rejected, whether the plan changed substantially. Then ask whether to proceed or run another pass.

Do not re-run the review, and do not run a second reviewer, on your own initiative. That is the user's call.
