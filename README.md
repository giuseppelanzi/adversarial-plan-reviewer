# plan-review

Adversarial review of Claude Code plans by an external model, with a forced point-by-point response.

It runs on its own on any non-trivial plan, and always when you ask for it. But it is not a gate: it never blocks you, it hands you a critique and a revised plan, and approving or rejecting stays your call.

---

## How it works

1. Write a plan in plan mode.
2. **Before the plan is proposed to you**, the review fires on it. The skill hands the plan document to the external reviewer, which reads the repo read-only and comes back with a `PASS` / `FAIL` verdict, labelling every point `[BLOCKING]`, `[SHOULD-FIX]` or `[NOTE]`.
3. Claude answers each point `ACCEPTED` / `REJECTED` with its concrete consequence, rewrites the plan for what it accepted, and states what that means: a blocking point needs another pass, a should-fix changes the plan and moves on.
4. You get the plan and the critique together, and approve or reject once.

Plan mode blocks writes, not reads, so the reviewer runs from inside it — and the plan document is the one file Claude may edit there. That is what lets the *review → revise → propose* loop close before you ever see the plan. Without it the only way to get a plan reviewed is to propose it, **reject** it to get the turn back, and then ask for the review.

You can still ask for one at any other moment — *"review the plan"*, *"review docs/auth-analysis.md"*. That path is what the hook serves: it writes every proposed plan to `.claude/plans/latest.md` **in the current repo**, on the proposal and *before* you approve it. It costs milliseconds, blocks nothing, and calls no model.

### The trace it leaves in the plan

As far as the plan is concerned, a review you cannot see did not happen. So the review status travels **in the document**, right under the title:

```
> **Review**: Antigravity (`gemini-3.1-pro-high`) — VERDICT: PASS — 12 files read
> 4 points accepted (1 BLOCKING, 3 SHOULD-FIX), 2 rejected, 1 note
> Plan rewritten on the accepted points; no second pass needed.
```

Three shapes, and one of them is always there: the review **ran** (verdict, files read, counts, what changed in the plan), it **failed** (which reviewer, which error, `Plan NOT verified`), or it was **not run** (with the reason — *"mechanical edit to a single file"*). Unlike the summary in the chat, the block survives into `.claude/plans/` and into the plan you approve.

Two things write it, and it takes both:

- **The skill**, the only one that knows what actually happened. Its rules live in `reviewers/response-protocol.md` (review ran, or failed) and in the `description` of `skills/antigravity` (review skipped — that `description` is the plugin's only text that stays in context even when the skill never loads).
- **The hook**, as a backstop. On `ExitPlanMode` it greps the first ten lines for `> **Review**:`; if the line is missing it prepends a notice of its own and tells you it did. It never blocks and never approves — it sets no `permissionDecision`, so the approval dialog is exactly the one you know. What it cannot do is say *why* there was no review: it only reports that nothing was declared. Its wording is overridable with `PLAN_REVIEW_NOTICE`.

The second layer exists because the first is a rule addressed to a model, and this repo has already watched one of those get skipped.

### When it fires on its own

- **You asked** — a review, a second opinion, a named reviewer, or a plan *and* a review in one breath: it always runs, with no judgement about whether the plan deserves it.
- **You didn't ask** — it runs on any **non-trivial** plan, and any plan with architectural consequences counts as non-trivial. It stays out of trivial ones: a rename, a one-line fix, a mechanical edit to a single file.

The cost is why that line exists: a review is an external model call of up to five minutes, in the middle of planning. On an architectural plan that is time well spent.

The hook is deliberately on `PreToolUse`, not `PostToolUse`. Saving on approval would only give you the document once the plan is already starting — which is the wrong moment, since the whole point is to review before committing to it. On `PreToolUse` the file exists as soon as the plan is on the table, so the after-the-fact path works too: reject the plan, ask for the review, iterate. The cost is that `latest.md` also holds plans you turned down; the next proposal overwrites it, so it tracks the most recent plan rather than the last approved one.

Two reviewers are available. Antigravity is the default; Claude only fires if you name it.

| Skill | Command | Read-only | Output |
|---|---|---|---|
| `/plan-review:antigravity` | `agy --mode plan --sandbox` | plan mode + sandbox, with `--add-dir` as the workspace | stdout |
| `/plan-review:claude` | `claude -p --permission-mode plan` | flag + tool allowlist | `.result` |

Antigravity is the default because it is a *different vendor's* model: it does not share your blind spots. Headless Claude verifies a plan against the code well, but it shares your model family, your `CLAUDE.md` and your conventions, which makes it the weaker adversary. Use it when you want repo-grounded verification rather than genuine disagreement.

Gemini CLI used to be the default and has been removed: Google is folding Gemini Code Assist for individuals into Antigravity, and the standalone CLI now answers `IneligibleTierError` on that tier. Nothing was lost in the swap — both are Google, so the cross-vendor axis that makes the review worth running is intact. It is in the git history if you ever want it back.

If a reviewer's CLI fails — not logged in, tools auto-denied, missing binary — the skill reports the CLI's own error and stops. It never retries around the problem and never falls back to a different reviewer on its own: that costs money and answers a question you did not ask. It offers the alternative in one line and waits.

---

## Repo layout

```
claude-ai-reviewer-plugin/
├── .claude-plugin/
│   ├── plugin.json          plugin manifest — manifests only in here, never content
│   └── marketplace.json     catalog, so the repo can be installed from itself
├── skills/
│   ├── antigravity/SKILL.md
│   └── claude/SKILL.md
├── reviewers/
│   ├── plan-critic.md        critic prompt for a plan, or a document about this code
│   ├── doc-critic.md         critic prompt for a document that is not about this code
│   └── response-protocol.md  how to answer the critique — shared
├── hooks/
│   ├── hooks.json            registers the hook on ExitPlanMode
│   └── save-plan.sh          saves the plan, flags one that declares no review
├── .gitignore
└── README.md
```

What is Claude Code convention and what is not:

- **Standard**: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `skills/`, `hooks/hooks.json`. These are discovered on their own.
- **Non-standard**: `reviewers/`. It is my own folder, read only because the SKILL.md files reference its path. Inside a plugin this is legitimate: the files travel with the bundle and resolve through `${CLAUDE_PLUGIN_ROOT}`.

The most common mistake is putting `skills/` or `hooks/` **inside** `.claude-plugin/`. That directory holds **manifests, and only manifests** — the content lives beside it, at the repo root.

Two manifests is normal here, not a mistake: `marketplace.json` is *required* to sit at `.claude-plugin/marketplace.json` in a marketplace repo, and this repo is a marketplace of itself, so both files share the directory legitimately. What never joins them is a skill, a hook, or a command.

---

## Installation

### Option A — as a plugin (recommended)

Push this repo to GitHub, then in Claude Code:

```
/plugin marketplace add giuseppelanzi/claude-ai-reviewer-plugin
/plugin install plan-review@plan-review-marketplace
```

You can check the manifests at any time with:

```bash
claude plugin validate .
```

### From disk, and how to reload it

The repo is a marketplace of itself — `marketplace.json` sits next to the manifest — so it installs from its own directory, with no GitHub in the loop:

```bash
claude plugin marketplace add "/local/path/to/claude-ai-reviewer-plugin"
claude plugin install plan-review@plan-review-marketplace
```

Installing does not link that directory, it **copies** it to `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`. So editing the repo changes nothing in a running Claude Code, and reloading takes two commands — the first refreshes the catalog from the directory, the second reinstalls the plugin from it:

```bash
claude plugin marketplace update plan-review-marketplace
claude plugin update plan-review@plan-review-marketplace
```

Then restart Claude Code; `plugin update` says so itself.

**`plugin update` compares the `version` in `.claude-plugin/plugin.json`, and nothing else.** Leave it untouched and you get `already at the latest version` however much the code changed — the most convincing way to believe you have reloaded when you have not. Bump the version on each local iteration, or force the copy through:

```bash
claude plugin uninstall plan-review@plan-review-marketplace
claude plugin install plan-review@plan-review-marketplace
```

What it does *not* need is a commit: a directory marketplace copies the working tree as it stands, untracked files included. `installed_plugins.json` does record a `gitCommitSha`, but that only describes where HEAD was at install time — it is not what the update compares.

Every version keeps its own folder in the cache and nothing prunes the old ones, so `ls ~/.claude/plugins/cache/plan-review-marketplace/plan-review/` reads as a history of what you installed.

For a tight edit-and-test loop, skip installation entirely. This reads the directory live — no version bumps, no cache, no reload:

```bash
claude --plugin-dir "/local/path/to/claude-ai-reviewer-plugin"
```

### Option B — no plugin, user level

If a marketplace feels like too much machinery for personal use:

```bash
mkdir -p ~/.claude/skills ~/.claude/reviewers ~/.claude/hooks
cp -r skills/* ~/.claude/skills/
cp reviewers/*.md ~/.claude/reviewers/
cp hooks/save-plan.sh ~/.claude/hooks/ && chmod +x ~/.claude/hooks/save-plan.sh
```

Outside a plugin nothing substitutes `${CLAUDE_PLUGIN_ROOT}` for you, so replace it with `$HOME/.claude` in both `SKILL.md` files. Then add the contents of `hooks/hooks.json` to `~/.claude/settings.json`, with the script's absolute path in place of `${CLAUDE_PLUGIN_ROOT}`:

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "ExitPlanMode",
        "hooks": [{ "type": "command",
                    "command": "bash /Users/USER/.claude/hooks/save-plan.sh",
                    "timeout": 5 }] }
    ]
  }
}
```

Spell the path out in full: `$CLAUDE_PROJECT_DIR` is reliably expanded in hook commands, `$HOME` and `~` carry no such guarantee.

### Option C — a single project

Same as option B, but in `<repo>/.claude/` instead of `~/.claude/`, with paths becoming `$CLAUDE_PROJECT_DIR/.claude/...`. Only worth it if you want to tune the critic prompt for that specific repo.

---

## Where the plans end up

Always in the repo you are working on, never in the plugin:

```
<repo>/.claude/plans/
├── 20260829-143012.md
└── latest.md          ← the one the skill reads
```

This is the only thing the system writes into your projects. Add `.claude/plans/` to your `.gitignore`, or put it in your global gitignore once and forget it.

---

## Prerequisites

- `jq` — used by the hook and by the Claude skill.
- At least one of `agy` or `claude`. You simply do not use the skill for the other.
- For `agy`: credentials cached from an earlier interactive login (`agy`, once, in a terminal). Nothing else — no per-repository permission grant. An earlier version of this README said otherwise; see the traps below.
- Optional: `timeout` (GNU coreutils, `brew install coreutils` on macOS, where it lands as `gtimeout`). The Claude skill detects either name and runs without a timeout if neither is there; the agy skill uses `--print-timeout` instead.

---

## Usage

```
> [plan mode] design the multi-tenant schema migration
> [Claude proposes the plan — the hook saves it here, approved or not]
> [you leave plan mode]
> review the plan
```

Or, naming the reviewer: *"ask Antigravity about this plan"*, *"have Claude review the plan"*.

It works on a document just as well as on a plan — *"review docs/auth-analysis.md"*, *"dai un'occhiata a questa specifica"* — and the critic follows the document:

| The document | Critic | Evidence it must bring | Stamped? |
|---|---|---|---|
| a plan, in plan mode or `latest.md` | `plan-critic.md` | `file:line` on every point | yes, in the plan |
| an analysis / ADR / post-mortem **about this code** | `plan-critic.md` | `file:line` on every point | no — it's your file |
| a specification, a proposal, a note **not about this code** | `doc-critic.md` | a verbatim quote of the document | no |

The second row is the one worth reading twice: the stamp depends on **whose document it is**, not on which critic ran. Only a plan gets the `> **Review**:` block; on your own files the review is reported in the chat and nothing is written.

Naming the critic overrides the choice. Whichever ran, the closing summary says which — a doc review and a code-grounded one answer different questions, and only one of them was checked against the repo.

**Timing**: the review runs *inside* plan mode, on the plan document, before the plan is proposed. Plan mode blocks writes, not reads, so bash works there — and the plan document is the one file Claude may edit, so it can revise it in place. Asking after you have left plan mode also works; it reads `.claude/plans/latest.md` instead.

---

## Customization

- **Critic prompts**: `reviewers/plan-critic.md` and `reviewers/doc-critic.md`. These are the files you will tweak most often. **One critic per kind of document, shared by both reviewers** — never one per reviewer: the comparability that matters is between `agy` and `claude` on the same document, and splitting along that axis is what would destroy it. The two critics differ on what counts as evidence, not on rigour: plan-critic demands a `file:line` per point, doc-critic a verbatim quote of the document.
- **Response protocol**: `reviewers/response-protocol.md`. Home of the binary `ACCEPTED`/`REJECTED` rule and of what each severity does to the plan.
- **Severity levels and the pass bar**: both critic prompts, which keep them identical on purpose. `FAIL` fires if and only if at least one point is `[BLOCKING]`, and blocking requires naming what concretely goes wrong. Loosen that definition and everything starts failing; tighten it and nothing does. What `[BLOCKING]` *means* is the one thing that differs: implementing the plan produces work to redo, versus acting on the document produces a wrong decision.
- **Which critic runs on what**: the selection rule in each `SKILL.md`, section 2 (Antigravity) / section 1 (Claude). A plan is never classified — it always gets `plan-critic.md`.
- **Default reviewer**: it lives in the `description` of `skills/antigravity` ("use it as the default when the user asks for a review without naming a reviewer"). To change it, move that sentence into the other skill.
- **Reviewer model**: pinned in `skills/antigravity/SKILL.md` to `gemini-3.1-pro-high`, because agy's own default is a Flash tier. Override per run with `PLAN_REVIEW_MODEL=<model>`, or change the pin. This is the single biggest lever on review quality.
- **The agy flag set**: `--mode plan --sandbox --dangerously-skip-permissions --effort high --add-dir`, in `skills/antigravity/SKILL.md`. They work as one unit — the traps below say why pulling one out breaks the others. `--effort high` is the second quality lever after the model pin; the two sandboxing flags are what make the third acceptable.
- **When it fires unprompted**: the trivial/non-trivial line lives in the `description` of `skills/antigravity`. Widen or narrow it there.
- **The hook's notice**: the text it prepends when a plan declares no review. Fixed English string in `hooks/save-plan.sh`, overridable per environment with `PLAN_REVIEW_NOTICE`. The skill's own trace follows the language of the plan; the hook cannot know it.
- **Language**: the instructions are in English, the output follows the language of the conversation or of the document. The rule is written in three places — both critic prompts and the response protocol. It applies to the critics' section headings too: on an Italian document `## Sources read` comes back as `## Fonti lette`, which is why the response protocol matches that section by role rather than by its exact English name.

---

## Known traps

- **Headless `agy` has no workspace, and that is what used to break the review.** `cd` is invisible to it: asked to list its workspace without `--add-dir`, it answers `NO WORKSPACE`. With no file tree the model explores through the shell instead, headless cannot show an approval dialog, and the shell call is auto-denied — **zero bytes on stdout while exiting 0**, with `a tool required the "command" permission … so it was auto-denied` on stderr. Judge the run by its output, never by its exit code: 0 is also what success returns.

  **This README used to diagnose that error as missing permissions** and sent you off to grant them interactively, once per repository. That was wrong, and worth saying plainly because the wrong remedy is the memorable one: the CLI resolves the same `default-cli-project` whatever folder you launch from, and the logs show zero grants *in the runs that succeed too*. The fix is `--add-dir "$PROJECT"` on the command line, plus the flags below.

  **The tool named in the error is not the permission you are missing.** It is whichever call tripped first, and it changes between identical runs — `command`, then `read_file`, then `command` again. Chasing that name is what produced the wrong diagnosis in the first place.

  Check the workspace claim yourself, from inside any repo — it takes one call and no permissions:

  ```bash
  agy --mode plan -p "List the files at the top level of your current workspace.
  Use ONLY your file-listing tool. If you have no workspace, say: NO WORKSPACE." </dev/null
  ```

- **The skill now auto-approves agy's tools, on purpose.** `--dangerously-skip-permissions` is in the command, which reverses this README's earlier position, and it only holds because of what surrounds it: `--mode plan` is agy's read-only execution mode and `--sandbox` adds terminal restrictions. Measured on a throwaway copy of this repo, a full review under those flags left all 18 files byte-identical. It does **not** protect the rest of the filesystem — agy writes inside its own working directory regardless. If that trade is not one you want, drop the flag and declare the shell unavailable in the prompt instead: that also produces a review, from file-reading tools alone, but then `--effort high` has to go too — with the shell denied, high effort makes the model reach for it anyway and the run dies at zero bytes.

- **A long critique comes back as a pointer, not as the review.** Left alone, agy treats an extensive report as an artefact: it writes the review to a file under its own working directory and returns one line on stdout naming the path. That output is *not empty*, so it sails past every "did the run fail" check. The prompt carries an **Output Delivery Constraint** to prevent it — three lines forbidding `write_to_file` and demanding the critique verbatim in the response. If you ever see a plan review summarised as "the review is in review.md", that constraint went missing.

- **The critic and its framing line are one unit, and the framing line is easy to forget.** Both `SKILL.md` bash blocks carry a `FRAMING` string right above the document, and under `plan-critic.md` it orders the reviewer to *"verify every claim it makes by reading this repository yourself"*. Swap `CRITIC` to `doc-critic.md` and leave that line behind, and you have told a reviewer to find code behind a text that has none — it obeys by inventing `file:line` references, and the result is a review that looks grounded and is not. The two variables sit next to each other for this reason. The reverse mistake, doc framing with `plan-critic.md`, is quieter: the review simply stops verifying.

- **`--log-file` is the only real diagnostic.** A muted run gives you one line of stderr and nothing else. `agy … --log-file /tmp/agy.log`, then `grep -iE 'permission|grant|project' /tmp/agy.log`, tells you whether the workspace was lost or a tool stopped the run. It is what turned this whole trap from a guess into a cause.
- **`timeout` does not exist on macOS.** GNU `timeout` is not shipped with macOS; `brew install coreutils` provides it as `gtimeout`. The Claude skill picks whichever exists and runs unwrapped if neither does, so a stock Mac degrades instead of dying on `command not found`. The Antigravity skill uses agy's native `--print-timeout` and needs no wrapper.
- **`$CLAUDE_PROJECT_DIR` is a hook variable, not a shell one.** It is set for hook commands, but it is empty in the shell the skill runs its bash in. `cd "$CLAUDE_PROJECT_DIR"` then silently stays put, and `$CLAUDE_PROJECT_DIR/.claude/plans/latest.md` resolves to `/.claude/plans/latest.md`. The skills use `${CLAUDE_PROJECT_DIR:-$PWD}`.
- **`agy -p` swallows the next argument as its prompt.** Every other flag goes *before* `-p`. `agy -p --mode plan "..."` takes `--mode` as the prompt and drops the real one.
- **agy defaults to a Flash model.** Fine for cost, weak for an adversary, so the skill pins `gemini-3.1-pro-high` instead. The pin can go stale — the Pro line sits at 3.1 while the Flash tiers are already at 3.7 — and an unknown model makes the whole skill fail rather than degrade: `agy models`, then `PLAN_REVIEW_MODEL=<one of them>` or drop the flag. That list also carries Claude and GPT-OSS models — agy is a multi-vendor transport, so a third opinion is a `--model` flag rather than another skill.
- **`.result` on the Claude side**, and `.is_error` is set on a failed run that still exits 0. Reading the wrong field yields empty output and no error.
- **`--max-turns` is undocumented.** It works on `claude -p` but does not appear in `claude --help`. If a future version rejects it, drop the flag rather than the review.
- **`${PIPESTATUS[0]}` is bash-only.** Claude Code's Bash tool runs zsh, where that expands to nothing and the exit code silently vanishes (zsh spells it `$pipestatus[1]`, 1-indexed). The skills redirect the reviewer's output to a file and read plain `$?` instead of piping into `jq`.
- **`claude -p` waits on stdin.** Without `</dev/null` it blocks 3 seconds and warns `no stdin data received in 3s`. Both skills redirect stdin; the prompt is an argument, never piped.
- **`${CLAUDE_PLUGIN_ROOT}` is substituted into the SKILL.md text, not read from the environment.** Claude Code expands it when it loads the skill, so by the time the instructions arrive the path is already absolute and the literal string never reaches a shell. It is reliable in skills for that reason. The *environment variable* of the same name is a different thing and is empty in the shell the Bash tool runs, so a script that generates a command at runtime cannot use it. Note the substitution applies to the braced form `${CLAUDE_PLUGIN_ROOT}`; `$CLAUDE_PLUGIN_ROOT` written bare is left alone.
- **Plugin edits reach a running session only under `--plugin-dir`.** There, changes to `SKILL.md` take effect immediately while changes under `hooks/` do not — those need `/reload-plugins` or a restart, and the trace backstop lives under `hooks/`, so it stays dormant until you reload. Installed from a marketplace none of that applies: you are running the copy under `~/.claude/plugins/cache/`, and nothing you edit in the repo is live until you update *and* restart. See *From disk, and how to reload it* above — in particular that the update is keyed on the version string, so an unbumped `plugin.json` reloads nothing while reporting success.
- **Skills fire everywhere.** At user level or as a plugin they apply in every repo, including ones where `agy` is not installed. If it gets noisy, narrow the `description`s.
- **The hook rewrites the plan it is given.** When the plan carries no `> **Review**:` line in its first ten lines, `save-plan.sh` returns it through `hookSpecificOutput.updatedInput` with a notice prepended, and archives that version. So a plan in `.claude/plans/` can open with a line Claude never wrote. It sets no `permissionDecision` — the approval dialog is untouched — and it builds `updatedInput` from the original `tool_input` object with `.plan` replaced, so any other field survives. If a future version stops honouring `updatedInput` on `ExitPlanMode`, the `systemMessage` and the archived copy still carry the notice: the degradation is partial.
- **`.tool_input.plan` is undocumented.** `hooks/save-plan.sh` reads the plan text from it, but the field no longer appears in the `ExitPlanMode` schema (which now exposes only a deprecated `allowedPrompts`). It still arrives. Nothing critical depends on it any more: the skills pass the document inline and can find it without the hook, so if the field ever disappears you lose the saved history and the hook's notice, not the review or the trace the skill writes itself.
- **`cp`, not `ln -s`, for `latest.md`.** Tempting to symlink; don't. Creating a symlink on Windows/NTFS needs elevated privileges or Developer Mode, and the hook would die with `Operation not permitted`. The copy costs a duplicate file and works everywhere.
- **The hook does not touch your `.gitignore`.** It creates `.claude/plans/` in the target repo and stops there. Writing into another project's git configuration from inside a hook is a surprise nobody asked for, so ignoring that directory stays your call.

---

## Debatable choices

Two things are rigid on purpose, but you may not like them in practice:

- **Binary verdict on each point.** "Partially valid" is the escape hatch through which a critique gets absorbed without changing anything. On some critiques, though, the honest answer really is somewhere in between. If you see forced answers, soften the protocol.
- **The defendant is the judge.** The reviewer says `PASS` or `FAIL`, but it is Claude — the author of the plan — that rules `ACCEPTED` / `REJECTED` on criticism of its own work. The `file:line` requirement and the forced binary make motivated reasoning harder; they do not make it impossible. The protocol compensates by making "everything rejected" a thing that must be said out loud, so a review that changed nothing is visible rather than dissolved into a summary. Read that line when it appears.
- **Adversarial is a persona, not a structure.** The critic has no stake: it does not win by finding a flaw or lose by missing one. What actually does the work is the fresh context reading the real code without the conversation's accumulated assumptions — which is why *"do not prepare context for it"* is the load-bearing instruction in both skills. Start passing it a helpful summary and the tone stays adversarial while the value disappears.

  One thing that is *not* a violation of that rule: the plan document itself travels inline, inside the prompt. It has to — the plan lives outside the repo while you are in plan mode, the reviewer's permissions are anchored to the workspace, and plan mode won't let Claude copy it in. But the document is the **object under review**, not context about the code, and by value or by reference is a transport detail. The line to hold is the other one: no summaries, no extracted snippets, no curated file list. The reviewer opens the repo itself, or the review is worth nothing.

And one limit that does not go away: the critic judges internal consistency and apparent completeness. It does not tell you whether the plan is looking in the right place — only you know that. The review reduces the verification work, it does not replace it.
