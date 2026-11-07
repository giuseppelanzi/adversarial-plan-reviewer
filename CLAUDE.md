# CLAUDE.md

Working conventions for this repo. The README and `docs/internals.md` are the source of truth for how the plugin behaves and why: the README for what a user sees and does, `docs/internals.md` for how it works, *Known traps* included. This file only holds what is needed to change it without breaking it. Read *Known traps* in `docs/internals.md` before touching a skill.

## Language

Everything in this repo is English: files, branch names, commit messages, PR titles and bodies, this file. The only non-English strings allowed are deliberate examples of multilingual behaviour, like the Italian request and `## Fonti lette` in the README.

The plugin's *output* follows the language of the conversation or the document. That rule lives in three places — both critics and the response protocol — and must stay in all three.

## Releases

- The user decides when to bump `version` in `.claude-plugin/plugin.json`. Never bump it unasked, not even to test an installed copy — use `claude --plugin-dir .` or uninstall/install instead (see *Verifying a change*).
- Branch: `<english-slug>`; on a release, `vX.Y.Z-<english-slug>`, e.g. `v0.8.0-timeout-signature`.
- Commit title: one sentence on what changed, prefixed `vX.Y.Z: ` on a release. The body is prose: the issue it closes, what was measured and how, and a `Verified:` line listing the checks that actually ran. If the plan was reviewed, say by whom and with what verdict.
- Every change of behaviour updates the docs in the same PR: the README when a user would notice it, `docs/internals.md` for how and why. A finding that cost a run to establish goes into *Known traps*, in `docs/internals.md`. Keep the README short: it is the plugin's front page, and detail belongs in `docs/internals.md`.
- The plugin's `name`, `adversarial-plan-reviewer`, is fixed once the plugin directory lists it: users have it installed under that name. The label shown is `displayName`, which can change. The listing icon, the PNG in `assets/`, is taken at the first submission only; changing it later does not change the listing. Do not name its file in any text file other than `plugin.json` and the README's image tag: the directory holds the plugin for it (*Known traps*).
- Release notes and the GitHub release: `/craft-release`, once the release PR is merged. The tag is `vX.Y.Z` on the commit where main first carries the version; GitHub creates it when the user publishes the draft — never `git tag` or `git push --tags` from a session.

## Things that move together

- **The three skills.** `skills/antigravity/SKILL.md`, `skills/claude/SKILL.md` and `skills/codex/SKILL.md` share their structure: preflight (section 1), document location and critic choice (section 2), the ceiling tiers (section 3). Change one, check the others. What they do **not** share is the boundary: each transport keeps its reviewer read-only with its own mechanism — the agy agent's `tools` list, the Claude allowlist, the Codex sandbox and `--disable` set. Do not carry one transport's mechanism into another: the agy reviewer has no shell because of agy, not because of a plugin rule.
- **`CRITIC` and `FRAMING`.** One unit in every bash block. Swapping the critic without the framing line makes the reviewer invent `file:line` references.
- **The two critics.** `reviewers/plan-critic.md` and `reviewers/doc-critic.md` keep identical severity levels and pass bar (`FAIL` iff at least one `[BLOCKING]`), and the same rule that a path outside the repository is not opened but listed under *What I could not verify* — the only fence on the Codex side, where such reads are not refused. They differ only in what counts as evidence and in what `[BLOCKING]` means.
- **The tier.** On the Claude side the timeout and `--max-turns` are one unit; raising one alone buys nothing. On the Codex side the tier is the external `timeout` alone, and it is required: Codex has no turn cap and no clock of its own.
- **The trace.** The `> **Review**:` stamp is defined in `reviewers/response-protocol.md` section 4, the *not run* lines — trivial plan, user declined — in the `description` of `skills/antigravity`. There is no backstop: the plugin ships no hook (`docs/internals.md`, *Known traps*), so the stamp rests on the skill and the `description` alone. The not-started stamps — `agy` not found, agent missing or outdated; `codex` not found, no `timeout` / `gtimeout` — appear in both section 4 and the section 1 of their skill.
- **The questions.** Two, and each has a question, a header and its options: `Review`, on a ready plan, with four — the three reviewers and `Approve without review`; `Reviewer`, on a request that names no reviewer, with the three reviewers alone. Both are written in the `description` of `skills/antigravity` — without the `Reviewer` wording, for room — and again in full in its section 0, with the one map from answer to skill; so is the rule that proposes plan mode before a non-trivial change made outside it. The `description`s of `skills/claude` and `skills/codex` point back to those questions: a reviewer picked in one is named. The `description` is the copy that counts: it is the only text in context when the skill never loads — and outside plan mode it never does. It is cut at about 1,500 characters (`docs/internals.md`, *Known traps*): keep it under ~1,450, and make room before adding.
- **The reviewer agent.** `reviewers/agy-plan-reviewer.md` and the copy the user installs in `~/.gemini/config/agents/plan-reviewer.md`. The preflight compares them byte for byte, so any edit to the shipped file asks every user to copy it again — say so in the commit.
- **The model pin.** `gemini-4-argon-high` in both bash blocks of `skills/antigravity`, in the README, in `docs/internals.md` and in the stamp examples of the response protocol. On the Codex side, `gpt-6.1-sol` with `model_reasoning_effort="high"` — one setting — in both bash blocks of `skills/codex`, in the README, in `docs/internals.md` and in the response protocol.

## Things this repo does not do

- No `--dangerously-skip-permissions` in the agy command, and never hidden in a wrapper script to get it past the classifier. No `--dangerously-bypass-approvals-and-sandbox` in the codex command, and never a flag of its `--sandbox read-only` / `--disable` set dropped to make a run pass.
- No instructions to the reviewer on which tools to use. Facts about its environment are fine; how to work is not. The agy agent's `tools` list sets the environment — it adds the read tools agy's default agent lacks and leaves out the shell, the same move as `--allowedTools` on the Claude side — and its body states facts only. On the Codex side the sandbox and the `--disable` flags set the environment.
- No installing or editing agy's configuration from a session, the reviewer agent included: the skill hands the user the `cp` command and stops.
- No review started on a plan without the user saying so, unless they asked for one outright. Claude proposes on each point; the user chooses which points to take.
- No context prepared for the reviewer — no summaries, extracted snippets or curated file lists. The document under review travels inline; the reviewer opens the repo itself.
- No automatic retry and no fallback to another reviewer on failure. Report the error, offer the alternative in one line, wait.
- No hook of type `command`: the plugin directory refuses them from organizations that are not Verified. A `prompt` hook is allowed, but none ships.
- Skill `description`s are double-quoted in the front matter. Unquoted, a `: ` in the text makes it invalid YAML, which Claude Code tolerates and the directory refuses.
- Nothing inside `.claude-plugin/` except the two manifests. The icon lives in `assets/`, named by `icon` in `plugin.json`.

## Shell

The Bash tool runs zsh, and the skills' bash runs there too:

- no `${PIPESTATUS[0]}` — redirect to a file and read `$?`;
- `${CLAUDE_PROJECT_DIR:-$PWD}`, never bare `$CLAUDE_PROJECT_DIR`;
- `</dev/null` on every `claude -p`, `agy` and `codex` call — `codex exec` reads stdin even with the prompt as an argument;
- every `agy` flag goes before `-p`;
- `--ask-for-approval never` goes before `exec`: it is a global `codex` option;
- `timeout` may be missing on macOS — the Claude skill already handles `gtimeout` and neither; the Codex skill accepts either name and stops when both are missing.

## Verifying a change

- `claude plugin validate . --profile directory` — the manifests, and anything the plugin directory would refuse a submission for.
- `claude --plugin-dir .` — live loop, no install. `SKILL.md` edits apply at once.
- An installed copy is under `~/.claude/plugins/cache/`. `claude plugin update` compares only the version string, so without a bump it reports `already at the latest version` and reloads nothing; force the copy with `plugin uninstall` + `plugin install`, then restart.
- Judge a reviewer run by its output, never its exit code: an empty agy run exits 0, a failed `claude -p` run sets `.is_error` while exiting 0, and a codex run is the `VERDICT:` in its `--output-last-message` file — after the exit code, since `124` is the ceiling and a failed run whatever the file holds — never its stdout, which is the event stream.
