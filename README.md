# plan-review

Adversarial review of Claude Code plans by an external model, with a forced point-by-point response.

It runs on its own on any non-trivial plan, and always when you ask for it. But it is not a gate: it never blocks you, it hands you a critique and a revised plan, and approving or rejecting stays your call.

---

## How it works

1. Write a plan in plan mode.
2. **Before the plan is proposed to you**, the review fires on it. On the first review of a conversation the skill spends fifteen seconds on a **read probe** first — *list the files at the root, nothing else* — and compares the answer with the real directory. Then it hands the plan document to the external reviewer, which reads the repo read-only and comes back with a `PASS` / `FAIL` verdict, labelling every point `[BLOCKING]`, `[SHOULD-FIX]` or `[NOTE]`.
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

The cost is why that line exists: a review is an external model call of up to half an hour, in the middle of planning. On an architectural plan that is time well spent.

The hook is deliberately on `PreToolUse`, not `PostToolUse`. Saving on approval would only give you the document once the plan is already starting — which is the wrong moment, since the whole point is to review before committing to it. On `PreToolUse` the file exists as soon as the plan is on the table, so the after-the-fact path works too: reject the plan, ask for the review, iterate. The cost is that `latest.md` also holds plans you turned down; the next proposal overwrites it, so it tracks the most recent plan rather than the last approved one.

Two reviewers are available. Antigravity is the default; Claude only fires if you name it.

| Skill | Command | Read-only | Output |
|---|---|---|---|
| `/plan-review:antigravity` | `agy --mode plan --sandbox` | plan mode + sandbox, with `--add-dir` as the workspace | stdout |
| `/plan-review:claude` | `claude -p --permission-mode plan` | flag + tool allowlist | `.result` |

Both are gated on the same fifteen-second preflight, and the probe runs with **the review's own flags** — that is what makes it worth the fifteen seconds. It is a dress rehearsal, not a health check: a probe that ran with a friendlier command line would prove nothing about the run it precedes. When it fails, the review does not start, the plan is stamped `Plan NOT verified`, and you get the CLI's own error with its remedy.

Antigravity is the default because it is a *different vendor's* model: it does not share your blind spots. Headless Claude verifies a plan against the code well, but it shares your model family, your `CLAUDE.md` and your conventions, which makes it the weaker adversary. Use it when you want repo-grounded verification rather than genuine disagreement.

Gemini CLI used to be the default and has been removed: Google is folding Gemini Code Assist for individuals into Antigravity, and the standalone CLI now answers `IneligibleTierError` on that tier. Nothing was lost in the swap — both are Google, so the cross-vendor axis that makes the review worth running is intact. It is in the git history if you ever want it back.

If a reviewer's CLI fails — not logged in, tools auto-denied, missing binary, or the call blocked by your own permission classifier before it ever launched — the skill reports the error and stops. It never retries around the problem and never falls back to a different reviewer on its own: that costs money and answers a question you did not ask. It offers the alternative in one line and waits.

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
- For `agy`: credentials cached from an earlier interactive login (`agy`, once, in a terminal). Nothing on agy's side beyond that — no per-repository permission grant. An earlier version of this README said otherwise; see the traps below.
- For `agy`, **a handful of shell commands allowed once**, and it is the only setup you add by hand. The reviewer reads named files without asking anything, but to *look around* a directory it reaches for the shell — and headless agy cannot show you a prompt, so the run stops and the skill hands you the request instead. Granting it is one line in agy's own `~/.gemini/antigravity-cli/settings.json`:

  ```json
  "permissions": { "allow": ["command(ls)", "command(cat)", "command(head)", "command(tail)", "command(wc)", "command(grep)"] }
  ```

  Measured: with exactly those six, a 13 KB plan was reviewed end to end with no denial at all. The grant is **per command prefix** and it **persists**, so this is a one-off per machine rather than a toll on every review — and you can also let agy write it for you, by answering *«always allow for commands that start with `X` (Persist to settings.json)»* the first time you hit the prompt in an interactive session.

  Two commands are deliberately **not** in that list. `find` is the one agy still reaches for now and then, and `find -exec` runs arbitrary commands; `python3` is arbitrary code outright. Granting either is a real decision, so the plugin states it and leaves it to you rather than slipping it into a setup snippet.

  If you would rather grant nothing, the alternative is `--dangerously-skip-permissions`, which approves every tool for one run. It is not the default, and the traps below say what that costs you with Claude Code's own classifier.
- Optional: `timeout` (GNU coreutils, `brew install coreutils` on macOS, where it lands as `gtimeout`). The Claude skill detects either name and runs with no wall-clock ceiling if neither is there, leaving `--max-turns` as the only bound; the agy skill uses `--print-timeout` instead. Either way the ceiling comes from a tier — 5, 15 or 30 minutes — chosen per document.

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
- **Which critic runs on what**: the selection rule in each `SKILL.md`, section 2 (Antigravity) / section 2 (Claude). A plan is never classified — it always gets `plan-critic.md`.
- **Default reviewer**: it lives in the `description` of `skills/antigravity` ("use it as the default when the user asks for a review without naming a reviewer"). To change it, move that sentence into the other skill.
- **Reviewer model**: pinned in `skills/antigravity/SKILL.md` to `gemini-3.1-pro-high`, because agy's own default is a Flash tier. Override per run with `PLAN_REVIEW_MODEL=<model>`, or change the pin. This is the single biggest lever on review quality.
- **The agy flag set**: `--mode plan --sandbox --effort high --add-dir --output-format stream-json`, in `skills/antigravity/SKILL.md`. `--mode plan` is agy's read-only execution mode, `--sandbox` adds terminal restrictions, `--effort high` is the second quality lever after the model pin, `--add-dir` is the workspace and is not optional. `--output-format stream-json` is what turns every failure from prose into an event you can query — and `--dangerously-skip-permissions` is deliberately **not** in the set; the traps below say why.
- **The ceiling on a run**: three tiers, picked per document by the skill and stated when it is not the floor.

  | Tier | agy | claude |
  |---|---|---|
  | short | `--print-timeout 300s` | `timeout 300` / `--max-turns 20` |
  | standard | `--print-timeout 900s` | `timeout 900` / `--max-turns 40` |
  | deep | `--print-timeout 1800s` | `timeout 1800` / `--max-turns 60` |

  The selection rule lives in `skills/antigravity/SKILL.md` section 3 and `skills/claude/SKILL.md` section 3: a judgement from the size of the document, how many files and modules the plan names, and the size of the repo, with the higher tier taken in doubt. The floor is deliberately *not* the default — the unprompted review only fires on non-trivial plans, so its runs start above it. Per-run overrides: `PLAN_REVIEW_TIMEOUT` (seconds, bare integer, both skills) and `PLAN_REVIEW_MAX_TURNS` (the Claude side only, where the two numbers are one unit).
- **When it fires unprompted**: the trivial/non-trivial line lives in the `description` of `skills/antigravity`. Widen or narrow it there.
- **The hook's notice**: the text it prepends when a plan declares no review. Fixed English string in `hooks/save-plan.sh`, overridable per environment with `PLAN_REVIEW_NOTICE`. The skill's own trace follows the language of the plan; the hook cannot know it.
- **Language**: the instructions are in English, the output follows the language of the conversation or of the document. The rule is written in three places — both critic prompts and the response protocol. It applies to the critics' section headings too: on an Italian document `## Sources read` comes back as `## Fonti lette`, which is why the response protocol matches that section by role rather than by its exact English name.

---

## Known traps

- **Headless `agy` has no workspace, and that is what used to break the review.** `cd` is invisible to it: asked to list its workspace without `--add-dir`, it answers `NO WORKSPACE`. With no file tree even reading is refused — the denial names **`read_file`**, because there is nothing to read — and the run ends with **zero bytes while exiting 0**. Judge the run by its output, never by its exit code: 0 is also what success returns.

  **This README used to diagnose that error as missing permissions** and sent you off to grant them interactively, once per repository. That was wrong, and worth saying plainly because the wrong remedy is the memorable one: the CLI resolves the same `default-cli-project` whatever folder you launch from, and the logs show zero grants *in the runs that succeed too*. The fix is `--add-dir "$PROJECT"` on the command line, plus the flags below.

  **The tool named in the error is not the permission you are missing.** It is whichever call tripped first, and it changes between runs — `command`, then `read_file`, then `command` again. Chasing that name is what produced the wrong diagnosis in the first place. It does tell you *where* the run broke, though: with the workspace missing the denied tool is **`read_file`**, measured — with no file tree there is nothing to read, which is why the model ends up at the shell rather than the other way round.

  Check the workspace claim yourself, from inside any repo — it takes one call and no permissions:

  ```bash
  agy --mode plan -p "List the files at the top level of your current workspace.
  Use ONLY your file-listing tool. If you have no workspace, say: NO WORKSPACE." </dev/null
  ```

- **Reading is free; looking around is not.** This is the one to understand, because everything else follows from it. agy reads a named file with no permission at all, in any folder, trusted or not. But to *enumerate* a directory it reaches for the shell — it has `list_dir` and uses `run_command` anyway — and headless agy cannot show you an approval dialog, so the call is auto-denied and the run stops. From the outside that looks like success: `status: SUCCESS`, an empty response, exit code 0.

  The plugin does not work around this. It forwards it: the run reports **the exact command** agy asked for, you decide, and the review resumes where it stopped. Which is why the prerequisites above are a list of shell commands and not a flag.

- **Three remedies that look obvious and do nothing.** Each was measured in a folder where the denial reproduces every time, and each cost a run to rule out. **Trusting the workspace**: agy does ask interactively and keeps a `trustedWorkspaces` list, but the same folder, trusted, fails identically — while an untrusted folder elsewhere listed its root without complaint. Trust is an interactive gate, not a headless permission. **Naming the tool**: agy's own reasoning has claimed there is «no `list_directory` tool» while `list_dir` sat in the tool list it had just been handed; telling it otherwise does not stop it reaching for `run_command`. **Dropping `--mode plan`**: the changelog grants workspace-scoped read *and list* access under the default review mode, which reads like the answer, and the denial is identical with the flag and without it.

- **If you reach for `--dangerously-skip-permissions`, your own host blocks it.** It is the escape hatch, not the default: it approves every tool for one run. In auto mode Claude Code's classifier refuses to launch a command carrying it — `Reason: [Create Unsafe Agents]` — and nothing ever reaches agy. The honest reading is that the check is doing its job, since the command does start an agent with its permissions waived. Lifting it is one line in `~/.claude/settings.json`, `"permissions": { "allow": ["Bash(agy --mode plan --sandbox --dangerously-skip-permissions:*)"] }`, and an allow rule that matches is evaluated before the classifier.

  **Claude cannot write that rule for you**, and shouldn't: editing your permission rules from inside a session is refused in its own right (`[Auto-Mode Bypass]`). Nor does the plugin hide the flag inside a wrapper script to keep the classifier from reading the string — that would work, and it would defeat the intent of a check you installed.

  Two things this repo will not do about it. It will not let Claude write that rule for itself — that is separately refused, `[Auto-Mode Bypass]`, and an agent that grants itself permissions is precisely what the check exists for. And it will not hide the flag in a wrapper script to keep the classifier from reading the string: that works, and it defeats the intent of a check you installed. If the shortcut occurs to you while reading the skill, it occurred to us too.

- **Do not tell the reviewer which tools to use.** An earlier draft of the skill put *«the shell is not available to you, use the file-reading tools»* in the prompt, as a way of avoiding the denial. It failed twice over: agy reached for `run_command` anyway, and — worse — it pre-empted the choice the plugin exists to forward. Telling the reviewer a fact about its environment is fair (*this run has no channel to answer you*, *a background task dies when the turn ends*); telling it how to work is the same mistake as preparing its context, one layer down.

- **The event stream is what makes a failure legible.** `--output-format stream-json` costs nothing and replaces a pile of heuristics on stderr: a denial is a `step_update` in `state: "ERROR"` carrying the exact `CommandLine`, a run killed by the ceiling is the absence of a `result` event, an artefact or a subagent shows up as its own step, and the critique itself is `.result.response`. `init.conversation_id` is the other half — with it, `--conversation "<id>"` resumes a review that stopped for a permission instead of paying for it twice. Measured: the resumed run kept everything it had read and carried on.

- **The probe is a dress rehearsal, not a health check.** Before the first review of a conversation, each skill asks its reviewer to list the root of the workspace and compares the answer with `ls -A`. It asks for the *listing* on purpose: reading works everywhere, enumerating is the thing that stops runs, and a review that cannot enumerate cannot explore. Fifteen seconds settle what would otherwise surface at the end of a quarter-hour run — credentials, the model pin, the workspace, and the shell question. It runs with the review's own flags for the same reason a rehearsal uses the real set: softened, it would predict nothing. It passes when the names are the ones of *this* directory, including at least one a model could not have guessed. When it fails it fails **usefully**, naming the command that was refused, which is a question to forward rather than a dead end — and until it is answered the review does not start and the plan is stamped `Plan NOT verified`.

- **A long critique comes back as a pointer, not as the review.** Left alone, agy treats an extensive report as an artefact: it writes the review to a file under its own working directory and returns one line on stdout naming the path. That output is *not empty*, so it sails past every "did the run fail" check. The prompt carries an **Output Delivery Constraint** to prevent it — three lines forbidding `write_to_file` and demanding the critique verbatim in the response. If you ever see a plan review summarised as "the review is in review.md", that constraint went missing.

- **The critic and its framing line are one unit, and the framing line is easy to forget.** Both `SKILL.md` bash blocks carry a `FRAMING` string right above the document, and under `plan-critic.md` it orders the reviewer to *"verify every claim it makes by reading this repository yourself"*. Swap `CRITIC` to `doc-critic.md` and leave that line behind, and you have told a reviewer to find code behind a text that has none — it obeys by inventing `file:line` references, and the result is a review that looks grounded and is not. The two variables sit next to each other for this reason. The reverse mistake, doc framing with `plan-critic.md`, is quieter: the review simply stops verifying.

- **`--log-file` is the only real diagnostic.** A muted run gives you one line of stderr and nothing else. `agy … --log-file /tmp/agy.log`, then `grep -iE 'permission|grant|project' /tmp/agy.log`, tells you whether the workspace was lost or a tool stopped the run. It is what turned this whole trap from a guess into a cause.
- **The five-minute ceiling was never agy's.** `--print-timeout` defaults to `0s`: agy waits for the turn to complete, with no limit at all. The cap is this plugin's own choice — which is why it is now a tier of three, 5 / 15 / 30 minutes, picked per document instead of one number for everything. `skills/antigravity/SKILL.md` used to describe it as *«agy's own timeout (default 5m)»*, and a limit you believe you inherited is a limit you never reconsider. What makes a generous ceiling cheap is that a timeout is a ceiling and not a budget: a review that needs four minutes takes four minutes whatever the ceiling, so the tier only decides how long you wait before concluding the run is broken.
- **On the Claude side, raising the timeout alone buys nothing.** `--max-turns` bounds the agent loop independently of the clock, so a longer wrapper with 20 turns still ends at turn 20 — and comes back with a *partial* critique that looks complete. The two numbers are the tier and they move together, which is why there are two override variables rather than one. A timeout is silent there as well, because the wrapper kills the process instead of reporting: exit `124` or `143`, a truncated envelope, and the `!! output is not JSON, raw:` fallback printing it.
- **`timeout` does not exist on macOS.** GNU `timeout` is not shipped with macOS; `brew install coreutils` provides it as `gtimeout`. The Claude skill picks whichever exists and runs unwrapped if neither does, so a stock Mac degrades instead of dying on `command not found`. The Antigravity skill uses agy's native `--print-timeout` and needs no wrapper. Unwrapped means `--max-turns` is the only ceiling left: at the short tier that was a footnote, at the deep tier the half-hour ceiling simply does not exist on that machine.
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
