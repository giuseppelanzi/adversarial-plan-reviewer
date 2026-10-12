# CLAUDE.md

Working conventions for this repo. The README is the source of truth for how the plugin behaves and why; this file only holds what is needed to change it without breaking it. Read the README's *Known traps* before touching a skill.

## Language

Everything in this repo is English: files, branch names, commit messages, PR titles and bodies, this file. The only non-English strings allowed are deliberate examples of multilingual behaviour, like the Italian request and `## Fonti lette` in the README.

The plugin's *output* follows the language of the conversation or the document. That rule lives in three places — both critics and the response protocol — and must stay in all three.

## Releases

- The user decides when to bump `version` in `.claude-plugin/plugin.json`. Never bump it unasked, not even to test an installed copy — use `claude --plugin-dir .` or uninstall/install instead (see *Verifying a change*).
- Branch: `<english-slug>`; on a release, `vX.Y.Z-<english-slug>`, e.g. `v0.8.0-timeout-signature`.
- Commit title: one sentence on what changed, prefixed `vX.Y.Z: ` on a release. The body is prose: the issue it closes, what was measured and how, and a `Verified:` line listing the checks that actually ran. If the plan was reviewed, say by whom and with what verdict.
- Every change of behaviour updates the README in the same PR. A finding that cost a run to establish goes into *Known traps*.

## Things that move together

- **The two skills.** `skills/antigravity/SKILL.md` and `skills/claude/SKILL.md` share their structure: preflight (section 1), document location and critic choice (section 2), the ceiling tiers (section 3). Change one, check the other.
- **`CRITIC` and `FRAMING`.** One unit in both bash blocks. Swapping the critic without the framing line makes the reviewer invent `file:line` references.
- **The two critics.** `reviewers/plan-critic.md` and `reviewers/doc-critic.md` keep identical severity levels and pass bar (`FAIL` iff at least one `[BLOCKING]`). They differ only in what counts as evidence and in what `[BLOCKING]` means.
- **The tier.** On the Claude side the timeout and `--max-turns` are one unit; raising one alone buys nothing.
- **The trace.** The `> **Review**:` stamp is defined in `reviewers/response-protocol.md` section 4, the skip rule in the `description` of `skills/antigravity`, the backstop in `hooks/save-plan.sh`.

## Things this repo does not do

- No `--dangerously-skip-permissions` in the agy command, and never hidden in a wrapper script to get it past the classifier.
- No instructions to the reviewer on which tools to use. Facts about its environment are fine; how to work is not.
- No context prepared for the reviewer — no summaries, extracted snippets or curated file lists. The document under review travels inline; the reviewer opens the repo itself.
- No automatic retry and no fallback to the other reviewer on failure. Report the error, offer the alternative in one line, wait.
- Nothing inside `.claude-plugin/` except the two manifests.

## Shell

The Bash tool runs zsh, and the skills' bash runs there too:

- no `${PIPESTATUS[0]}` — redirect to a file and read `$?`;
- `${CLAUDE_PROJECT_DIR:-$PWD}`, never bare `$CLAUDE_PROJECT_DIR`;
- `</dev/null` on every `claude -p` and `agy` call;
- every `agy` flag goes before `-p`;
- `timeout` may be missing on macOS — the Claude skill already handles `gtimeout` and neither.

## Verifying a change

- `claude plugin validate .` — the manifests.
- `claude --plugin-dir .` — live loop, no install. `SKILL.md` edits apply at once; `hooks/` edits need `/reload-plugins`.
- An installed copy is under `~/.claude/plugins/cache/`. `claude plugin update` compares only the version string, so without a bump it reports `already at the latest version` and reloads nothing; force the copy with `plugin uninstall` + `plugin install`, then restart.
- Judge a reviewer run by its output, never its exit code: an empty agy run exits 0, and a failed `claude -p` run sets `.is_error` while exiting 0.
