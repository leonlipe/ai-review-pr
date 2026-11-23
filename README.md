# review-process

Local GitHub PR reviews with [Claude Code](https://docs.claude.com/en/docs/claude-code/overview) and the GitHub CLI. Works in plain repos and in **forks** (PRs that live in the upstream repo).

It installs three things:

| Piece | Where | What it does |
|---|---|---|
| `pr-review` skill | `~/.claude/skills/pr-review/SKILL.md` | The review process and standards. Claude loads it automatically whenever you ask for a review. |
| `/review-pr` command | `~/.claude/commands/review-pr.md` | `/review-pr 123` inside Claude. Limits Claude to read-only `gh`/`git` commands. |
| `review-pr` CLI | `~/.local/bin/review-pr` | Fetches the PR into a separate git worktree and starts Claude there. |

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

The installer copies files (it backs up any existing file it would overwrite as `*.bak`), checks your dependencies, and warns if `~/.local/bin` isn't on your `PATH`.

| Command | Effect |
|---|---|
| `./install.sh` | Global install (skill + command + CLI) |
| `./install.sh --link` | Same, using symlinks so edits in this repo apply immediately |
| `./install.sh --no-cli` | Skill and command only |
| `./install.sh --project <repo>` | Copy skill and command into `<repo>/.claude/` so you can commit them for your team |
| `./install.sh --init-standards <repo>` | Create `.claude/review-standards.md` and `CLAUDE.md` templates in a repo |
| `./install.sh --init-standards <repo> --private` | Same, and add them to `.git/info/exclude` so they're never committed (useful in forks) |
| `./install.sh --uninstall` | Remove the global install |

If you use a custom Claude config dir, the installer respects `CLAUDE_CONFIG_DIR`. You can override the CLI location with `BIN_DIR=/some/dir ./install.sh`.

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
review-pr --list                             # list open PRs in the resolved repo
review-pr --clean 123                        # remove the worktree and refs
```

> `--clean` uses `git worktree remove --force`, which deletes uncommitted changes in that review worktree. Don't keep work there.

### Follow-ups in the same session

```
Explain the change in src/payments/service.ts in more detail.
Is blocking issue #1 really a bug? Show me a concrete input that breaks it.
Write the review comments as I would post them on GitHub, concise and polite.
```

### Posting the review

Claude never posts anything. Read and edit the review first, then post it yourself. **In a fork, always pass `--repo`:**

```bash
gh pr review 123 --repo owner/repo --comment         --body-file ~/pr-reviews/owner-repo-pr-123.md
gh pr review 123 --repo owner/repo --request-changes --body-file ~/pr-reviews/owner-repo-pr-123.md
gh pr review 123 --repo owner/repo --approve --body "LGTM"
```

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

## 6. Layout

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

## 7. Tips

- **Big PRs:** review one area at a time (*"review only changes under src/api/"*). You get better results and use less of your plan.
- **Usage limits:** Pro/Max limits are shared with claude.ai. Large reviews use more.
- **Print mode permissions:** `claude -p` can only run tools listed in the command's `allowed-tools`. If a review needs more (for example running tests), add it there or use `--setup`.
- **CI automation:** this flow is for running interactively on your machine. For CI, use an API key and check the current Claude Code terms.

## 8. Troubleshooting

| Symptom | Fix |
|---|---|
| `review-pr: command not found` | Add `~/.local/bin` to `PATH`, or reinstall with `BIN_DIR=...` |
| `PR #N not found in: ...` | Use `-R owner/repo`, or add the `upstream` remote |
| `/review-pr` missing in Claude | Check that `$CLAUDE_CONFIG_DIR/commands/review-pr.md` exists (default `~/.claude`), then restart `claude` |
| `gh` auth errors | `gh auth status`, then `gh auth login` |
| Worktree already exists | `review-pr N` reuses and updates it. Use `review-pr --clean N` to start fresh |
