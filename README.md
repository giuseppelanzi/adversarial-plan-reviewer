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

### When it fires on its own

- **You asked** — a review, a second opinion, a named reviewer, or a plan *and* a review in one breath: it always runs, with no judgement about whether the plan deserves it.
- **You didn't ask** — it runs on any **non-trivial** plan, and any plan with architectural consequences counts as non-trivial. It stays out of trivial ones: a rename, a one-line fix, a mechanical edit to a single file.

The cost is why that line exists: a review is an external model call of up to five minutes, in the middle of planning. On an architectural plan that is time well spent.

The hook is deliberately on `PreToolUse`, not `PostToolUse`. Saving on approval would only give you the document once the plan is already starting — which is the wrong moment, since the whole point is to review before committing to it. On `PreToolUse` the file exists as soon as the plan is on the table, so the after-the-fact path works too: reject the plan, ask for the review, iterate. The cost is that `latest.md` also holds plans you turned down; the next proposal overwrites it, so it tracks the most recent plan rather than the last approved one.

Two reviewers are available. Antigravity is the default; Claude only fires if you name it.

| Skill | Command | Read-only | Output |
|---|---|---|---|
| `/plan-review:antigravity` | `agy --mode plan` | plan mode; needs a one-time permission grant per repo | stdout |
| `/plan-review:claude` | `claude -p --permission-mode plan` | flag + tool allowlist | `.result` |

Antigravity is the default because it is a *different vendor's* model: it does not share your blind spots. Headless Claude verifies a plan against the code well, but it shares your model family, your `CLAUDE.md` and your conventions, which makes it the weaker adversary. Use it when you want repo-grounded verification rather than genuine disagreement.

Gemini CLI used to be the default and has been removed: Google is folding Gemini Code Assist for individuals into Antigravity, and the standalone CLI now answers `IneligibleTierError` on that tier. Nothing was lost in the swap — both are Google, so the cross-vendor axis that makes the review worth running is intact. It is in the git history if you ever want it back.

If a reviewer's CLI fails — not logged in, tools auto-denied, missing binary — the skill reports the CLI's own error and stops. It never retries around the problem and never falls back to a different reviewer on its own: that costs money and answers a question you did not ask. It offers the alternative in one line and waits.

---

## Repo layout

```
claude-ai-reviewer-plugin/
├── .claude-plugin/
│   ├── plugin.json          manifest — this is the only file that belongs in here
│   └── marketplace.json     catalog, so the repo can be installed from itself
├── skills/
│   ├── antigravity/SKILL.md
│   └── claude/SKILL.md
├── reviewers/
│   ├── plan-critic.md        critic system prompt — shared by both skills
│   └── response-protocol.md  how to answer the critique — shared
├── hooks/
│   ├── hooks.json            registers the hook on ExitPlanMode
│   └── save-plan.sh          saves the plan and exits 0
├── .gitignore
└── README.md
```

What is Claude Code convention and what is not:

- **Standard**: `.claude-plugin/plugin.json`, `skills/`, `hooks/hooks.json`. These are discovered on their own.
- **Non-standard**: `reviewers/`. It is my own folder, read only because the SKILL.md files reference its path. Inside a plugin this is legitimate: the files travel with the bundle and resolve through `${CLAUDE_PLUGIN_ROOT}`.

The most common mistake is putting `skills/` or `hooks/` **inside** `.claude-plugin/`. Only the manifest goes there.

---

## Installation

### Option A — as a plugin (recommended)

Push this repo to GitHub, then in Claude Code:

```
/plugin marketplace add giuseppelanzi/claude-ai-reviewer-plugin
/plugin install plan-review@plan-review-marketplace
```

To try it before publishing, without a marketplace:

```bash
claude --plugin-dir /local/path/to/claude-ai-reviewer-plugin
```

After installation the files live under `~/.claude/plugins/`. Do not edit them by hand: change the repo and reinstall.

You can check the manifests at any time with:

```bash
claude plugin validate .
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
- For `agy`: credentials cached from an earlier interactive login (`agy`, once, in a terminal), **and** its permissions granted once per repository — plural, at least `read_file` and `command`. Without them every headless run in that repo returns nothing. See the traps below.
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

It works on an analysis document just as well as on a plan: *"review docs/auth-analysis.md"*.

**Timing**: the review runs *inside* plan mode, on the plan document, before the plan is proposed. Plan mode blocks writes, not reads, so bash works there — and the plan document is the one file Claude may edit, so it can revise it in place. Asking after you have left plan mode also works; it reads `.claude/plans/latest.md` instead.

---

## Customization

- **Critic prompt**: `reviewers/plan-critic.md`. This is the file you will tweak most often. Deliberately a single file for both reviewers: if it diverges, the critiques stop being comparable.
- **Response protocol**: `reviewers/response-protocol.md`. Home of the binary `ACCEPTED`/`REJECTED` rule and of what each severity does to the plan.
- **Severity levels and the pass bar**: `reviewers/plan-critic.md`. `FAIL` fires if and only if at least one point is `[BLOCKING]`, and blocking requires naming what concretely goes wrong. Loosen that definition and everything starts failing; tighten it and nothing does.
- **Default reviewer**: it lives in the `description` of `skills/antigravity` ("use it as the default when the user asks for a review without naming a reviewer"). To change it, move that sentence into the other skill.
- **Reviewer model**: pinned in `skills/antigravity/SKILL.md` to `gemini-3.1-pro-high`, because agy's own default is a Flash tier. Override per run with `PLAN_REVIEW_MODEL=<model>`, or change the pin. This is the single biggest lever on review quality.
- **When it fires unprompted**: the trivial/non-trivial line lives in the `description` of `skills/antigravity`. Widen or narrow it there.
- **Language**: the instructions are in English, the output follows the language of the conversation or of the plan. The rule is written in two places — the critic prompt and the response protocol.

---

## Known traps

- **Headless `agy` denies every tool it has not been granted, silently.** In a repo where you have never granted agy anything, the first review returns **zero bytes on stdout while exiting 0** — stderr carries the reason: `a tool required the "read_file" permission that headless mode cannot prompt for, so it was auto-denied`. Headless cannot show you the approval dialog, so it denies. Judge the run by its output, never by its exit code: 0 is also what success returns.

  The fix is a one-time grant **per repository**, made by you, interactively: `cd <repo> && agy`, ask it something that touches the repo ("list the files and summarise the structure"), and approve every permission it asks for with the **persistent** option rather than the single-use one. Then quit. Once per repo, not once per review.

  **It will ask for more than one** — at least `read_file` and `command` — and a partial grant fails exactly like no grant at all: empty stdout, exit 0, same error naming a different tool. That suggested prompt is worth using verbatim because it exercises both. If a later run fails on a tool you have not seen before, the earlier grant worked and agy got further: keep granting, it is progress rather than a new fault.

  The skill detects this and hands you those instructions. It does not read, write or repair agy's configuration, and does not go looking for where it lives: a permission that the consumer grants itself is not a permission. agy will suggest `--dangerously-skip-permissions` in its error — don't, it auto-approves writes too.
- **`timeout` does not exist on macOS.** GNU `timeout` is not shipped with macOS; `brew install coreutils` provides it as `gtimeout`. The Claude skill picks whichever exists and runs unwrapped if neither does, so a stock Mac degrades instead of dying on `command not found`. The Antigravity skill uses agy's native `--print-timeout` and needs no wrapper.
- **`$CLAUDE_PROJECT_DIR` is a hook variable, not a shell one.** It is set for hook commands, but it is empty in the shell the skill runs its bash in. `cd "$CLAUDE_PROJECT_DIR"` then silently stays put, and `$CLAUDE_PROJECT_DIR/.claude/plans/latest.md` resolves to `/.claude/plans/latest.md`. The skills use `${CLAUDE_PROJECT_DIR:-$PWD}`.
- **`agy -p` swallows the next argument as its prompt.** Every other flag goes *before* `-p`. `agy -p --mode plan "..."` takes `--mode` as the prompt and drops the real one.
- **agy defaults to a Flash model.** Fine for cost, weak for an adversary, so the skill pins `gemini-3.1-pro-high` instead. The pin can go stale — the Pro line sits at 3.1 while the Flash tiers are already at 3.7 — and an unknown model makes the whole skill fail rather than degrade: `agy models`, then `PLAN_REVIEW_MODEL=<one of them>` or drop the flag. That list also carries Claude and GPT-OSS models — agy is a multi-vendor transport, so a third opinion is a `--model` flag rather than another skill.
- **`.result` on the Claude side**, and `.is_error` is set on a failed run that still exits 0. Reading the wrong field yields empty output and no error.
- **`--max-turns` is undocumented.** It works on `claude -p` but does not appear in `claude --help`. If a future version rejects it, drop the flag rather than the review.
- **`${PIPESTATUS[0]}` is bash-only.** Claude Code's Bash tool runs zsh, where that expands to nothing and the exit code silently vanishes (zsh spells it `$pipestatus[1]`, 1-indexed). The skills redirect the reviewer's output to a file and read plain `$?` instead of piping into `jq`.
- **`claude -p` waits on stdin.** Without `</dev/null` it blocks 3 seconds and warns `no stdin data received in 3s`. Both skills redirect stdin; the prompt is an argument, never piped.
- **`${CLAUDE_PLUGIN_ROOT}` is substituted into the SKILL.md text, not read from the environment.** Claude Code expands it when it loads the skill, so by the time the instructions arrive the path is already absolute and the literal string never reaches a shell. It is reliable in skills for that reason. The *environment variable* of the same name is a different thing and is empty in the shell the Bash tool runs, so a script that generates a command at runtime cannot use it. Note the substitution applies to the braced form `${CLAUDE_PLUGIN_ROOT}`; `$CLAUDE_PLUGIN_ROOT` written bare is left alone.
- **Plugin edits**: changes to `SKILL.md` take effect immediately; changes under `hooks/` do not. That needs `/reload-plugins` or a restart.
- **Skills fire everywhere.** At user level or as a plugin they apply in every repo, including ones where `agy` is not installed. If it gets noisy, narrow the `description`s.
- **`.tool_input.plan` is undocumented.** `hooks/save-plan.sh` reads the plan text from it, but the field no longer appears in the `ExitPlanMode` schema (which now exposes only a deprecated `allowedPrompts`). It still arrives. Nothing critical depends on it any more: the skills pass the document inline and can find it without the hook, so if the field ever disappears you lose the saved history, not the review.
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
