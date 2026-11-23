# review-process

Local GitHub PR reviews with [Claude Code](https://docs.claude.com/en/docs/claude-code/overview) and the GitHub CLI. Works in plain repos and in **forks** (PRs that live in the upstream repo).

It installs three things:

| Piece | Where | What it does |
|---|---|---|
| `pr-review` skill | `~/.claude/skills/pr-review/SKILL.md` | The review process and standards. Claude loads it automatically whenever you ask for a review. |
| `/review-pr` command | `~/.claude/commands/review-pr.md` | `/review-pr 123` inside Claude. Limits Claude to read-only `gh`/`git` commands. |
| `review-pr` CLI | `~/.local/bin/review-pr` | Fetches the PR into a separate git worktree and starts Claude there. |

Paths shown use the default `~/.claude`. With several Claude accounts, the skill and command go into each account's config dir (e.g. `~/.claude-vo`). See [Multiple Claude accounts](#6-multiple-claude-accounts).

The full design rationale is in [PROCESS.md](PROCESS.md).

---

## 1. Prerequisites

| Tool | Check | Install / login |
|---|---|---|
| Git | `git --version` | — |
| GitHub CLI | `gh --version` | `brew install gh`, then `gh auth login` |
| Claude Code | `claude --version` | `npm install -g @anthropic-ai/claude-code`, then run `claude` and log in |

## 2. Install

```bash
git clone <this repo> ~/development/ai/review-process
cd ~/development/ai/review-process
./install.sh
```

With several Claude accounts (`~/.claude`, `~/.claude-vo`, `~/.claude-personal`, ...):

```bash
./install.sh --list-accounts                    # see what's detected
./install.sh --all-accounts --link              # install for all of them
git config --global review-pr.account personal  # account review-pr uses by default
```

The installer copies files, checks your dependencies, and warns if `~/.local/bin` isn't on your `PATH`. Before overwriting a file that differs, it saves the old one as `*.bak` next to it. To restore an old version, rename the `.bak` file back (e.g. `mv SKILL.md.bak SKILL.md`). Otherwise, delete it once you no longer need it.

| Command | Effect |
|---|---|
| `./install.sh` | Global install (skill + command + CLI) for the current account |
| `./install.sh -a vo -a personal` | Install for specific Claude accounts (see [Multiple accounts](#6-multiple-claude-accounts)) |
| `./install.sh --all-accounts` | Install for every detected account |
| `./install.sh --list-accounts` | Show detected accounts and where it's installed |
| `--link` (add to any of the above) | Use symlinks instead of copies, so edits in this repo apply immediately |
| `./install.sh --no-cli` | Skill and command only |
| `./install.sh --project <repo>` | Copy skill and command into `<repo>/.claude/` so you can commit them for your team |
| `./install.sh --init-standards <repo>` | Create `.claude/review-standards.md` and `CLAUDE.md` templates in a repo |
| `./install.sh --init-standards <repo> --private` | Same, and add them to `.git/info/exclude` so they're never committed (useful in forks) |
| `./install.sh --uninstall [-a NAME \| --all-accounts]` | Remove the install. The CLI stays while any account still uses it. |

With no account flag, the installer targets `$CLAUDE_CONFIG_DIR` if it's set, otherwise `~/.claude`. If you name an account whose folder doesn't exist, the installer stops and asks you to log in to that account first. You can override the CLI location with `BIN_DIR=/some/dir ./install.sh`.

Check that it worked: start `claude` in any repo and ask *"what skills do you have?"*. `pr-review` should be listed, and `/review-pr` should autocomplete.

---

## 3. Usage

### Quick: from inside Claude

```bash
cd my-repo
claude
> /review-pr 123
```

Accepted arguments: `123`, `owner/repo#123`, or `https://github.com/owner/repo/pull/123`. With no argument, Claude lists open PRs and asks which one to review.

Plain requests work too, because the skill triggers on review intent: *"check PR 123"*, *"is my branch ok to merge?"*, *"look over my changes"*.

This reviews from the GitHub diff without checking anything out, so it's quick. Claude reads surrounding files from whatever branch you have checked out.

### Thorough: isolated worktree (recommended)

```bash
cd my-repo
review-pr 123
```

This:
1. Finds the PR (in `upstream` first, then `origin`; see [Forks](#4-forks)).
2. Fetches the PR head and its base branch into private refs (`refs/review/pr-123/*`). It doesn't use `gh pr checkout`, so it won't add remotes or touch your branches.
3. Creates a detached worktree at `../my-repo-review-pr-123`.
4. Starts `claude "/review-pr owner/repo#123"` there, so Claude reads the real PR code.

Your current checkout and uncommitted work aren't touched.

```bash
review-pr 123 --setup "npm ci && npm test"   # install deps / run tests first
review-pr -p 123                             # non-interactive: writes ~/pr-reviews/owner-repo-pr-123.md
review-pr -p 123 -o ~/review.md              # custom output file
review-pr --here 123                         # no worktree, same as /review-pr in the current dir
review-pr -R owner/repo 123                  # force the repo that owns the PR
review-pr -a vo 123                          # use a specific Claude account
review-pr --accounts                         # show accounts and which one applies here
review-pr --list                             # list open PRs in the resolved repo
review-pr --clean 123                        # remove the worktree and refs
review-pr push-comment 123                   # post the finished review (see below)
```

> `--clean` uses `git worktree remove --force`, which deletes uncommitted changes in that review worktree. Don't keep work there.

### Follow-ups in the same session

```
Explain the change in src/payments/service.ts in more detail.
Is blocking issue #1 really a bug? Show me a concrete input that breaks it.
Write the review comments as I would post them on GitHub, concise and polite.
```

### Posting the review: `review-pr push-comment`

Claude never posts anything. When you're happy with the review, post it yourself with one command:

```bash
review-pr push-comment 123                     # post as a comment review
review-pr push-comment 123 --request-changes   # block the merge
review-pr push-comment 123 --approve           # approve
review-pr push-comment 123 --edit              # open in $EDITOR first, then post
```

**Where the text comes from:**

1. `-f FILE`, if you pass it.
2. Otherwise the default review file `~/pr-reviews/<owner>-<repo>-pr-123.md` (the one `review-pr -p` writes, or one you saved earlier).
3. If that file doesn't exist but the review worktree does, it asks your **last Claude session in the worktree** for the final review (`claude -c -p`). The result includes any changes you asked for in follow-ups, such as *"drop nit #2"* or *"make it more polite"*. It's saved to the default file before posting, so you can check it. Use `--regenerate` to export again after more follow-ups.

**Before posting**, it shows the target PR, the event, and a preview, then asks `Post this review? [y/N]`. It also warns when:

- the event conflicts with Claude's verdict (e.g. `--approve` on a review that says *Request changes*)
- this file was already posted (it keeps a `.posted` log next to the review file)
- the PR isn't open

It always passes `--repo`, so it posts to the right repo in forks, and prints the PR URL when done.

**Typical flows:**

```bash
# Interactive: review, refine with follow-ups, exit Claude, then post
review-pr 123
review-pr push-comment 123 --request-changes

# Non-interactive: generate, edit, post
review-pr -p 123
review-pr push-comment 123 --edit

# Fully scripted (no confirmation prompt)
review-pr -p 123 && review-pr push-comment 123 --yes
```

| Option | Effect |
|---|---|
| `--comment` / `--approve` / `--request-changes` | Review event (default `--comment`) |
| `-f, --file FILE` | Post this file instead of the default one |
| `--regenerate` | Export the review from the Claude session again, overwriting the file |
| `-e, --edit` | Open the review in `$VISUAL`/`$EDITOR` before posting |
| `-y, --yes` | Skip confirmation. Use with care; the warnings still print, but nothing stops the post. |
| `-a NAME`, `-R owner/repo` | Same as for reviewing; `-a` picks the Claude account used to export from the session |

> Read the review before you post it. Claude's output is a strong first pass, not the final reviewer. GitHub doesn't let you approve or request changes on your own PR; use `--comment` there.

You can still post by hand with `gh pr review 123 --repo owner/repo --comment --body-file FILE`.

---

## 4. Forks

The usual fork layout:

```bash
git remote -v
origin    git@github.com:you/project.git        # your fork
upstream  git@github.com:org/project.git        # the original
```

If yours has no `upstream`, add it: `git remote add upstream https://github.com/org/project.git`.

How forks are handled:

- **Finding the PR.** The CLI and the skill look for the PR in `upstream` first, then `origin`. Use `-R owner/repo`, `owner/repo#N`, or a PR URL to be explicit.
- **`--repo` on every `gh` call.** gh's default repo in a fork is often wrong, so the tooling never relies on it.
- **Correct base.** The diff is taken against `upstream/<base>`, not your fork's possibly stale copy.
- **PRs from third-party forks.** The head is fetched through `refs/pull/N/head`, so you don't need to add the contributor's remote.
- **Private review rules.** `./install.sh --init-standards . --private` keeps your `.claude/review-standards.md` and `CLAUDE.md` out of git, so they never end up in a PR to upstream.
- **CI.** Missing checks on fork PRs are expected (workflows may be awaiting approval). Changes to CI or build scripts get extra scrutiny.

---

## 5. Per-repo customization

The skill holds the generic standards. Rules specific to one repo go in **`.claude/review-standards.md`**, which overrides the generic standards wherever they conflict:

```bash
./install.sh --init-standards path/to/repo           # committed and shared with the team
./install.sh --init-standards path/to/repo --private # local only
```

The skill also reads `CLAUDE.md`, `CONTRIBUTING.md`, PR templates, and linter configs. It won't flag style issues that a linter already enforces.

To give a team the whole setup without anyone running the installer, use `./install.sh --project path/to/repo` and commit `.claude/`.

---

## 6. Multiple Claude accounts

Claude Code keeps each account in its own config dir, selected with `CLAUDE_CONFIG_DIR`. A common setup uses shell aliases:

```bash
alias claude-personal='CLAUDE_CONFIG_DIR=~/.claude-personal command claude'
alias claude-vo='CLAUDE_CONFIG_DIR=~/.claude-vo command claude'
```

Skills and commands are installed **per config dir**, so install into every account you'll review with.

**Account names.** `-a NAME` resolves to `~/.claude-NAME`. `default` means `~/.claude`. You can also pass a path. Accounts are detected by scanning `~/.claude` and `~/.claude-*`.

```bash
./install.sh --list-accounts        # detected accounts + install status
./install.sh --all-accounts --link  # install everywhere; edits here apply to all
./install.sh -a vo                  # just one account
```

**Choosing the account in `review-pr`.** The first match wins:

1. `-a/--account NAME`: one-off override
2. `CLAUDE_CONFIG_DIR`: an exported env var (e.g. `CLAUDE_CONFIG_DIR=~/.claude-vo review-pr 123`)
3. `git config review-pr.account NAME`: per repo, or `--global` for the machine default
4. `~/.claude`

Per-repo defaults fit the "work fork vs personal project" split well:

```bash
cd ~/work/client-fork && git config review-pr.account vo
cd ~/oss/my-lib       && git config review-pr.account personal
git config --global review-pr.account personal      # fallback everywhere else
review-pr --accounts                                # shows which one applies here
```

> **Aliases don't reach scripts.** If `claude` is an alias for `claude-personal` in your shell, `review-pr` can't see it and would use `~/.claude`. Set `git config --global review-pr.account personal` (or export `CLAUDE_CONFIG_DIR`) so the CLI matches your alias.

`review-pr` prints the account it's using and warns if `pr-review` isn't installed for that account. For `~/.claude` it leaves `CLAUDE_CONFIG_DIR` unset, because setting it would change where Claude looks for its login file (`~/.claude.json`).

Inside Claude, `/review-pr` is only available in accounts where you installed it. Start the right one (`claude-vo`, ...) and it works the same way.

### Multiple GitHub accounts

Claude accounts and GitHub accounts are separate. `review-pr` and Claude call `gh` with whatever GitHub login is currently active. If work and personal PRs need different GitHub logins, use one of these:

```bash
# Option A: switch the active gh account (gh 2.40+ supports several logins)
gh auth switch --user my-work-login
review-pr 123

# Option B: give each GitHub account its own gh config dir
GH_CONFIG_DIR=~/.config/gh-work gh auth login   # once
GH_CONFIG_DIR=~/.config/gh-work review-pr -a vo 123
```

For option B, you can pair the variables in an alias, e.g. `alias review-pr-vo='GH_CONFIG_DIR=~/.config/gh-work review-pr -a vo'`. The environment is passed through to Claude, so its `gh` calls use the same GitHub account.

---

## 7. Layout

```
review-process/
├── install.sh                     # installer
├── bin/review-pr                  # worktree + Claude launcher CLI
├── skills/pr-review/SKILL.md      # review process & standards
├── commands/review-pr.md          # /review-pr slash command
├── templates/
│   ├── review-standards.md        # per-repo rules template
│   └── CLAUDE.md                  # small always-on project context
└── PROCESS.md                     # design notes
```

To tune reviews, edit `skills/pr-review/SKILL.md` and re-run `./install.sh`. With `--link`, edits apply immediately.

## 8. Tips

- **Big PRs:** review one area at a time (*"review only changes under src/api/"*). You get better results and use less of your plan.
- **Usage limits:** Pro/Max limits are shared with claude.ai. Large reviews use more.
- **Print mode permissions:** `claude -p` can only run tools listed in the command's `allowed-tools`. If a review needs more (for example running tests), add it there or use `--setup`.
- **CI automation:** this flow is for running interactively on your machine. For CI, use an API key and check the current Claude Code terms.

## 9. Troubleshooting

| Symptom | Fix |
|---|---|
| `review-pr: command not found` | Add `~/.local/bin` to `PATH`, or reinstall with `BIN_DIR=...` |
| `PR #N not found in: ...` | Use `-R owner/repo`, or add the `upstream` remote |
| `/review-pr` missing in Claude | That account doesn't have it installed. Run `./install.sh --list-accounts`, then `./install.sh -a NAME` and restart `claude` |
| `review-pr` uses the wrong Claude account | Run `review-pr --accounts` to see which one applies and why. Shell aliases don't reach scripts, so set `git config --global review-pr.account NAME` or pass `-a NAME` |
| `Claude config dir not found` | Typo in the account name, or you haven't logged in to it yet: `CLAUDE_CONFIG_DIR=~/.claude-NAME claude` |
| `pr-review is not installed for this account` | `./install.sh -a NAME` (or `--all-accounts`) |
| Claude asks you to log in again | Don't point `CLAUDE_CONFIG_DIR` at `~/.claude` (the default account keeps its login in `~/.claude.json`). Use `-a default` instead |
| PR not found or permission errors with the right Claude account | The wrong **GitHub** login is active. Check `gh auth status` (see [Multiple GitHub accounts](#multiple-github-accounts)) |
| `gh` auth errors | `gh auth status`, then `gh auth login` |
| `push-comment`: `No review file ... and no review worktree` | Run the review first (`review-pr 123` or `review-pr -p 123`), or pass `-f FILE` |
| `push-comment` posted an old version of the review | It reuses the saved file. After more follow-ups, use `--regenerate`, or `--edit` to fix it by hand |
| `push-comment`: `no terminal to confirm` | Running from a script or CI. Add `--yes` |
| `Can not approve your own pull request` | GitHub rule. Use `--comment` |
| Worktree already exists | `review-pr N` reuses and updates it. Use `review-pr --clean N` to start fresh |
