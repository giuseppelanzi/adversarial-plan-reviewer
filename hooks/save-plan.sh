#!/usr/bin/env bash
# ExitPlanMode hook: persists the plan, and flags a plan that declares no review.
# Always exits 0 — this hook must never block leaving plan mode.
# It never approves the call and never changes its input: the plan Claude
# proposed is the plan you see and approve. The notice goes only into the saved
# copy, and the warning to you goes out as a systemMessage.

set -uo pipefail

INPUT=$(cat)
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
PLANS_DIR="$PROJECT_DIR/.claude/plans"

PLAN=$(printf '%s' "$INPUT" | jq -r '.tool_input.plan // empty' 2>/dev/null)
[ -z "$PLAN" ] && exit 0

# The marker is only looked for in the head of the document: a plan that merely
# discusses the format further down must not read as one that declares a review.
# No pipeline here — under `pipefail` an early-exiting `head` would poison the
# status with the SIGPIPE of the process feeding it.
HEAD=$(printf '%s\n' "$PLAN" | head -n 10)

NOTICE=""
if ! grep -q '^> \*\*Review\*\*:' <<<"$HEAD"; then
  NOTICE="${PLAN_REVIEW_NOTICE:-> **Review**: no review declared for this plan.
> (adversarial-plan-reviewer hook: the skill left no trace — either the review did not run, or it ran and was not declared.)}"
fi

OUT_PLAN="$PLAN"
[ -n "$NOTICE" ] && OUT_PLAN="$NOTICE

$PLAN"

mkdir -p "$PLANS_DIR" || exit 0

STAMP=$(date +%Y%m%d-%H%M%S)
printf '%s\n' "$OUT_PLAN" > "$PLANS_DIR/$STAMP.md" || exit 0
cp "$PLANS_DIR/$STAMP.md" "$PLANS_DIR/latest.md" 2>/dev/null

# Trace present: the plan speaks for itself, stay silent.
[ -z "$NOTICE" ] && exit 0

# A warning for the user, and nothing else: no permissionDecision, no
# updatedInput. The plugin directory holds any hook that approves a tool call
# or changes its input.
jq -n \
  --arg msg "adversarial-plan-reviewer: this plan declares no review. The copy saved in .claude/plans/$STAMP.md opens with a notice saying so; the plan itself is unchanged." \
  '{ systemMessage: $msg }' 2>/dev/null

exit 0
