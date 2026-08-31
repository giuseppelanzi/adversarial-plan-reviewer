#!/usr/bin/env bash
# ExitPlanMode hook: persists the plan, and flags a plan that declares no review.
# Always exits 0 — this hook must never block leaving plan mode.

set -uo pipefail

INPUT=$(cat)
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
PLANS_DIR="$PROJECT_DIR/.claude/plans"

TOOL_INPUT=$(printf '%s' "$INPUT" | jq -c '.tool_input // empty' 2>/dev/null)
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
> (plan-review hook: the skill left no trace — either the review did not run, or it ran and was not declared.)}"
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

# No permissionDecision: "allow" would skip the user's approval dialog and "deny"
# would block the plan. updatedInput is built from the original tool_input with
# .plan replaced, so any other field ExitPlanMode carries survives.
jq -n \
  --argjson ti "${TOOL_INPUT:-{\}}" \
  --arg plan "$OUT_PLAN" \
  --arg msg 'plan-review: this plan declares no review. A notice was added at the top of it.' \
  '{
     hookSpecificOutput: {
       hookEventName: "PreToolUse",
       updatedInput: ($ti | .plan = $plan)
     },
     systemMessage: $msg
   }' 2>/dev/null

exit 0
