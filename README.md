# plan-review

Adversarial review of Claude Code plans by an external model, with a forced point-by-point response.

It is not an automatic gate: the plan is always saved, you ask for the review when you want it.

---

## How it works

1. Write a plan in plan mode.
2. Claude proposes the plan. A hook writes the plan text to `.claude/plans/latest.md` **in the current repo** — on the proposal, *before* you approve it. It costs milliseconds, blocks nothing, and calls no model.
3. Whenever you want, ask for the review: *"review the plan"*. The skill fires and runs the external reviewer read-only over the repo.
4. The reviewer returns a `PASS` / `FAIL` verdict and labels every point `[BLOCKING]`, `[SHOULD-FIX]` or `[NOTE]`. Claude answers each one `ACCEPTED` / `REJECTED` with its concrete consequence, rewrites the plan for what it accepted, and states what that means: a blocking point needs another pass, a should-fix changes the plan and moves on.

The hook is deliberately on `PreToolUse`, not `PostToolUse`. Saving on approval would only give you the document once the plan is already starting — which is the wrong moment, since the whole point is to review before committing to it. On `PreToolUse` the file exists as soon as the plan is on the table, so you can reject the plan, ask for the review, and iterate. The cost is that `latest.md` also holds plans you turned down; the next proposal overwrites it, so it tracks the most recent plan rather than the last approved one.

Two reviewers are available. Antigravity is the default; Claude only fires if you name it.

| Skill | Command | Read-only | Output |
|---|---|---|---|
| `plan-review-antigravity` | `agy --mode plan` | plan mode; needs a one-time read grant per repo | stdout |
| `plan-review-claude` | `claude -p --permission-mode plan` | flag + tool allowlist | `.result` |

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
│   ├── plan-review-antigravity/SKILL.md
│   └── plan-review-claude/SKILL.md
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

Then replace `${CLAUDE_PLUGIN_ROOT}` with `$HOME/.claude` in both `SKILL.md` files, and add the contents of `hooks/hooks.json` to `~/.claude/settings.json`, with the script's absolute path in place of `${CLAUDE_PLUGIN_ROOT}`:

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
- For `agy`: credentials cached from an earlier interactive login (`agy`, once, in a terminal), **and** a read permission granted once per repository — without it every headless run in that repo returns nothing. See the traps below.
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

**Constraint**: inside plan mode Claude cannot run bash, so the review has to be asked for after leaving the plan, not during it.

---

## Customization

- **Critic prompt**: `reviewers/plan-critic.md`. This is the file you will tweak most often. Deliberately a single file for both reviewers: if it diverges, the critiques stop being comparable.
- **Response protocol**: `reviewers/response-protocol.md`. Home of the binary `ACCEPTED`/`REJECTED` rule and of what each severity does to the plan.
- **Severity levels and the pass bar**: `reviewers/plan-critic.md`. `FAIL` fires if and only if at least one point is `[BLOCKING]`, and blocking requires naming what concretely goes wrong. Loosen that definition and everything starts failing; tighten it and nothing does.
- **Default reviewer**: it lives in the `description` of `plan-review-antigravity` ("use it as the default when the user asks for a review without naming a reviewer"). To change it, move that sentence into the other skill.
- **Reviewer model**: `--model` on the agy command line, or `model` in `~/.gemini/antigravity-cli/settings.json`. This is the single biggest lever on review quality.
- **Language**: the instructions are in English, the output follows the language of the conversation or of the plan. The rule is written in two places — the critic prompt and the response protocol.

---

## Known traps

- **Headless `agy` denies every tool it has not been granted, silently.** In a repo where you have never granted agy anything, the first review returns **zero bytes on stdout while exiting 0** — stderr carries the reason: `a tool required the "read_file" permission that headless mode cannot prompt for, so it was auto-denied`. Headless cannot show you the approval dialog, so it denies. Judge the run by its output, never by its exit code: 0 is also what success returns.

  The fix is a one-time grant **per repository**, made by you, interactively: `cd <repo> && agy`, ask it something that touches the repo ("list the files and summarise the structure"), and approve the read permission with the **persistent** option rather than the single-use one. Then quit. Once per repo, not once per review.

  The skill detects this and hands you those instructions. It does not read, write or repair agy's configuration, and does not go looking for where it lives: a permission that the consumer grants itself is not a permission. agy will suggest `--dangerously-skip-permissions` in its error — don't, it auto-approves writes too.
- **`timeout` does not exist on macOS.** GNU `timeout` is not shipped with macOS; `brew install coreutils` provides it as `gtimeout`. The Claude skill picks whichever exists and runs unwrapped if neither does, so a stock Mac degrades instead of dying on `command not found`. The Antigravity skill uses agy's native `--print-timeout` and needs no wrapper.
- **`$CLAUDE_PROJECT_DIR` is a hook variable, not a shell one.** It is set for hook commands, but it is empty in the shell the skill runs its bash in. `cd "$CLAUDE_PROJECT_DIR"` then silently stays put, and `$CLAUDE_PROJECT_DIR/.claude/plans/latest.md` resolves to `/.claude/plans/latest.md`. The skills use `${CLAUDE_PROJECT_DIR:-$PWD}`.
- **`agy -p` swallows the next argument as its prompt.** Every other flag goes *before* `-p`. `agy -p --mode plan "..."` takes `--mode` as the prompt and drops the real one.
- **agy defaults to a Flash model.** Fine for cost, weak for an adversary. `agy models` lists the alternatives; `gemini-3.1-pro-high` is the better critic. That list also carries Claude and GPT-OSS models — agy is a multi-vendor transport, so a third opinion is a `--model` flag rather than another skill.
- **`.result` on the Claude side**, and `.is_error` is set on a failed run that still exits 0. Reading the wrong field yields empty output and no error.
- **`--max-turns` is undocumented.** It works on `claude -p` but does not appear in `claude --help`. If a future version rejects it, drop the flag rather than the review.
- **`${PIPESTATUS[0]}` is bash-only.** Claude Code's Bash tool runs zsh, where that expands to nothing and the exit code silently vanishes (zsh spells it `$pipestatus[1]`, 1-indexed). The skills redirect the reviewer's output to a file and read plain `$?` instead of piping into `jq`.
- **`claude -p` waits on stdin.** Without `</dev/null` it blocks 3 seconds and warns `no stdin data received in 3s`. Both skills redirect stdin; the prompt is an argument, never piped.
- **`${CLAUDE_PLUGIN_ROOT}` in skills**: guaranteed in hook commands, less so in the context where the skill launches bash. Every SKILL.md carries a `find` fallback for when the variable comes back empty.
- **Plugin edits**: changes to `SKILL.md` take effect immediately; changes under `hooks/` do not. That needs `/reload-plugins` or a restart.
- **Skills fire everywhere.** At user level or as a plugin they apply in every repo, including ones where `agy` is not installed. If it gets noisy, narrow the `description`s.
- **Namespacing**: as a plugin the skills become `/plan-review:plan-review-antigravity`, which is redundant. If that bothers you, rename them to `antigravity` and `claude` and you get `/plan-review:antigravity`.

---

## Debatable choices

Two things are rigid on purpose, but you may not like them in practice:

- **Binary verdict on each point.** "Partially valid" is the escape hatch through which a critique gets absorbed without changing anything. On some critiques, though, the honest answer really is somewhere in between. If you see forced answers, soften the protocol.
- **The defendant is the judge.** The reviewer says `PASS` or `FAIL`, but it is Claude — the author of the plan — that rules `ACCEPTED` / `REJECTED` on criticism of its own work. The `file:line` requirement and the forced binary make motivated reasoning harder; they do not make it impossible. The protocol compensates by making "everything rejected" a thing that must be said out loud, so a review that changed nothing is visible rather than dissolved into a summary. Read that line when it appears.
- **Adversarial is a persona, not a structure.** The critic has no stake: it does not win by finding a flaw or lose by missing one. What actually does the work is the fresh context reading the real code without the conversation's accumulated assumptions — which is why *"do not prepare context for it"* is the load-bearing instruction in both skills. Start passing it a helpful summary and the tone stays adversarial while the value disappears.

And one limit that does not go away: the critic judges internal consistency and apparent completeness. It does not tell you whether the plan is looking in the right place — only you know that. The review reduces the verification work, it does not replace it.
