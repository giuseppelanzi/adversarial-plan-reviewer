#!/usr/bin/env bash
# ExitPlanMode hook: persists the plan, nothing else.
# Always exits 0 — this hook must never block leaving plan mode.

set -uo pipefail

INPUT=$(cat)
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
PLANS_DIR="$PROJECT_DIR/.claude/plans"

PLAN=$(printf '%s' "$INPUT" | jq -r '.tool_input.plan // empty' 2>/dev/null)
[ -z "$PLAN" ] && exit 0

mkdir -p "$PLANS_DIR" || exit 0

STAMP=$(date +%Y%m%d-%H%M%S)
printf '%s\n' "$PLAN" > "$PLANS_DIR/$STAMP.md" || exit 0
cp "$PLANS_DIR/$STAMP.md" "$PLANS_DIR/latest.md" 2>/dev/null

exit 0
