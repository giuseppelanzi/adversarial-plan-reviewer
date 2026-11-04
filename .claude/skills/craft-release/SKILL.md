---
name: craft-release
description: Generate release notes for a plugin version from the commits merged into main since the previous version, show them for review, then publish them as a draft GitHub release on confirmation.
user-invocable: true
context: fork
allowed-tools: Read, Write, Bash(git *), Bash(gh *)
argument-hint: "[previous-version] [new-version]"
---

## How releases work here

A release is the commit on `origin/main` where `.claude-plugin/plugin.json`
first carries the new `version` — normally the merge of the `vX.Y.Z-<slug>`
pull request. Work merged before the bump ships with it; work merged after it
waits for the next bump.

The tag is `v<version>` (`v0.9.0`), and so is the release title. Older versions
have no tag, so a version is resolved to its commit through the manifest's
history, not through tags.

This skill never creates or pushes a tag with git. GitHub creates the tag, at
the commit given as `--target`, when the user publishes the draft.

## Range

Arguments: $ARGUMENTS

Read that line as up to two whitespace-separated versions, the previous one then
the new one. Parse it yourself: positional placeholders never reach this skill,
and relying on them makes it fall back to auto-detection silently rather than
fail. Drop a leading `v` from either version.

First bring the remote refs up to date:

```
git fetch origin --tags
```

To resolve a version `X.Y.Z` to its commit, use the tag when there is one:

```
git rev-parse --verify --quiet vX.Y.Z^{commit}
```

and otherwise the first commit on main's first-parent line that brings the
version in — the **first** line of:

```
git log origin/main --first-parent --reverse --format='%H %s' -S'"version": "X.Y.Z"' -- .claude-plugin/plugin.json
```

A later line is where the version was replaced by the next one; ignore it. If
neither command returns a commit, stop and say so: the version was never on
`origin/main` — a release PR not merged yet, or a typo. Do not guess a
substitute.

Then find the versions:

- **Two versions given**: resolve both.
- **One version given**: it is the new one; derive the previous one as below.
- **None given**: the new version is the one on main —
  `git show origin/main:.claude-plugin/plugin.json` — and you resolve it.

The previous version, when not given, is the one the new version replaced. Read
it from the first parent of the new version's commit, then resolve it:

```
git show <new-commit>^:.claude-plugin/plugin.json
```

The range is `<previous-commit>..<new-commit>`, and the version being released
is the new one. Then gather the material for the range:

```
git log <range> --format='%h %s%n%n%b'
git diff <range> --stat
```

Also run `git log <new-commit>..origin/main --oneline`. If it lists anything,
tell the user: those commits are on main but not in this release — they ship
with the next bump.

Never take a version from `.claude-plugin/plugin.json` in the working tree. The
user bumps it when they decide, often well before the commit, so the working
tree may already carry a version that is not on main. Versions come from
commits only, through `git show <commit>:<path>`.

## Step 1 — Write the notes

Work from the commit log and the `--stat` list of changed files. The commit
bodies here are prose and say what changed and why; take the user-visible part.
Leave out how the change was measured, the plan review and its verdict, and the
`Verified:` line — that is how the work was done, not what the user gets. Never
dump the full diff of the range. When a commit message is not enough to tell
what changed for the user, inspect that one file with
`git diff <range> -- <path>` before describing it.

A range between two commits reads committed objects only, so uncommitted work
in the tree cannot leak into the notes.

The user here is someone who installed the plugin. Changes to `CLAUDE.md`,
`.claude/`, `.gitignore`, and to the README alone with no behaviour behind them,
are internal: leave them out.

Read the template in template.md and follow that format. Categorize into: new
features, improvements, bug fixes, breaking changes. Drop any section with no
entries, Migration included.

Two things a user must do by hand after updating, and they go under Breaking
changes, with the step under Migration:

- `reviewers/agy-plan-reviewer.md` changed in the range — check
  `git diff <range> --stat -- reviewers/agy-plan-reviewer.md`. The Antigravity
  preflight compares the installed agent with the shipped one byte for byte and
  refuses a stale copy, so every Antigravity user must copy the agent again. The
  preflight hands them the `cp` command with the path filled in; say that.
- A new requirement, or a pinned model changed — `gemini-4-argon-high`,
  `gpt-6.1-sol` — so the review fails until the user has access to it.

Always write the notes in English, whatever language the conversation is in.
They are published on GitHub, where the audience is not the maintainer. This
applies to the notes themselves — keep talking to the user in their language.

Start the body at the first `##` heading, with no title line above it. GitHub
renders the release title over the body already, so an `# ...` heading there
would show up twice.

Save the result to `ReleaseNotes/RELEASE_NOTES_<version>.md`, where `<version>`
is the version being released — `ReleaseNotes/RELEASE_NOTES_0.9.0.md`. The
directory is gitignored, so the notes never reach a commit; they live on GitHub
instead. Writing the file creates the directory when it is missing, which it
will be on a fresh clone. The filename carries the version so that writing the
notes of an old release cannot clobber the notes of one still in preparation.

Being gitignored, these files are fair game for `git clean -xfd`. Do not treat
them as durable: publish, or copy the text out.

If that file already exists, do not overwrite it blindly. Read it, show the
user what is already there, and ask whether to replace it or to keep it and
write the new notes to a different name. Their previous draft may hold edits
worth keeping.

## Step 2 — Show them and stop

Print the full notes in the reply, with the range and the two commits they
came from.

Then run `gh release list` to find out what publishing would actually do, and
`gh release view v<version>` when a release for the tag is listed. Those reads
are the only `gh` commands allowed in this step. Say which of the three cases
applies before asking:

- No release for the tag: a new draft will be created.
- A draft release exists: its notes will be replaced, still a draft.
- A **published** release exists: its notes will be rewritten in public, and
  the release stays published. Show what its current body holds, so the user
  knows what they are about to lose. Never present this case as "publishing a
  draft" — it is not one.

Now ask whether to go ahead, and stop. Publishing is the user's call, so a
missing answer means no: if they have not answered, or ask for changes, revise
the notes and show them again. Only an explicit go-ahead reaches step 3.

## Step 3 — Publish

Only after that go-ahead, and only for the case you named in step 2.

If a release for the tag exists, update it rather than creating a duplicate:

```
gh release edit v<version> --notes-file ReleaseNotes/RELEASE_NOTES_<version>.md
```

If the release turns out to be published and step 2 did not name that case —
someone published it in between, say — stop and ask again. The go-ahead you
hold covers a draft, not a live rewrite.

If no release exists for the tag, create it as a draft, at the full hash of the
new version's commit:

```
gh release create v<version> --title "v<version>" --target <new-commit> --notes-file ReleaseNotes/RELEASE_NOTES_<version>.md --draft
```

`--target` is always needed here: the tag does not exist yet, and without it
GitHub would put the tag on the tip of main when the draft is published, which
may hold commits merged after the bump.

Never change a release's published state. A draft stays a draft: do not pass
`--latest`, and do not run `gh release edit --draft=false`. A release that was
already published stays published — editing its notes must not also promote or
demote it. Turning a draft live is the user's job, on GitHub.

Finally, print the release URL.
