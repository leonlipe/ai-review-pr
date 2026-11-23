A repeatable flow for reviewing GitHub pull requests locally with Claude Code and the GitHub CLI, using a Claude Pro subscription.

> Verify command names and flags against your installed versions (`claude --help`, `gh --help`). Both tools change often.

### Prerequisites

```bash
mkdir -p ~/.claude/skills/pr-review ~/.claude/commands
cp global/skills/pr-review/SKILL.md ~/.claude/skills/pr-review/
cp global/commands/review-pr.md     ~/.claude/commands/review-pr.md
```
---
## skill
```
---
name: pr-review
description: Code review process and standards for any repository. Use this skill whenever reviewing code, a pull request, a diff, a branch, or a commit, or when asked whether changes are ready to merge, even if the word "review" isn't used (e.g. "check this PR", "look over my changes", "is this ok to merge").
---

# PR Review

Review only. Do NOT modify, create, or delete any files.

## Process

1. **Understand intent.** If a PR number is given, run
   `gh pr view <n> --json title,body,baseRefName,headRefName,files,closingIssuesReferences`.
   Otherwise use the commit messages against the base branch.
2. **Find the base branch.** Use `baseRefName` from the PR. Without a PR, use the
   repo default: `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`.
   Never assume `main`.
3. **Get the change.** `gh pr diff <n>`, or `git diff origin/<base>...HEAD`.
4. **Check CI.** `gh pr checks <n>` when a PR number is available.
5. **Load repo-specific rules.** Check for these and apply any you find; they
   override the generic standards below when they conflict:
   - `.claude/review-standards.md` (repo-specific review rules)
   - `CLAUDE.md`, `CONTRIBUTING.md`, `docs/CONTRIBUTING.md`
   - Linter/formatter configs (`.eslintrc*`, `ruff.toml`, `.editorconfig`, etc.)
     to know which style issues are already enforced and shouldn't be flagged.
6. **Learn the stack.** Identify language, framework, and test runner from files
   like `package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `pom.xml`,
   `Makefile`. Judge the code by that ecosystem's conventions.
7. **Read in context.** For each changed file, read the full file plus closely
   related code (callers, interfaces, tests). Most real bugs are in how the
   change interacts with existing code, not in the diff itself.
8. **Apply the standards**, then write the review in the output format.

## Generic standards

### Correctness
- Edge cases handled: null/empty inputs, boundaries, off-by-one, timeouts.
- No race conditions or shared mutable state without protection.
- The code actually does what the PR description claims.

### Errors
- Errors are handled explicitly; no silent or empty catches.
- Error messages are actionable and don't leak internals to users.

### Security
- No secrets, credentials, tokens, or PII in code, logs, or tests.
- User input is validated; queries are parameterized; no injection paths.
- New endpoints have authentication and authorization checks.
- New dependencies are reasonable, maintained, and pinned per repo convention.

### Tests
- New logic has tests; bug fixes include a regression test.
- Tests assert behavior, not implementation details, and are not superficial.

### Design
- The change follows the patterns already used in this repo.
- No unnecessary complexity, dead code, or leftover debug output.

### Performance
- No N+1 queries, unbounded loops, or loading whole datasets into memory.

## Output format

Start with a 2–3 sentence summary of what the change does and a verdict:
**Approve**, **Approve with comments**, or **Request changes**.
Mention which repo-specific rule files you found and applied, if any.

Then findings grouped by severity:

### 🔴 Blocking
### 🟡 Should fix
### 🟢 Nits / suggestions

Each finding: `path/to/file.ext:LINE` — the problem — a concrete suggested fix.
Write "None." for empty sections. End with any questions for the author.

Only report real issues. Don't pad the review with generic advice, and don't
flag style that a linter or formatter already enforces.
```

---

## Command (review-pr.md)
---
```
---
description: Review a GitHub pull request by number (any repo)
argument-hint: <pr-number>
allowed-tools: Skill, Bash(gh pr view:*), Bash(gh pr diff:*), Bash(gh pr checks:*), Bash(gh repo view:*), Bash(git diff:*), Bash(git log:*), Bash(git fetch:*), Read, Grep, Glob
---

Review pull request #$ARGUMENTS using the pr-review skill. If the skill isn't
loaded, read `~/.claude/skills/pr-review/SKILL.md` and follow it exactly.
```

### Install (install.sh)
```bash
#!/usr/bin/env bash
# Installs the pr-review skill and /review-pr command globally for Claude Code.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

mkdir -p ~/.claude/skills/pr-review ~/.claude/commands
cp "$here/skills/pr-review/SKILL.md" ~/.claude/skills/pr-review/SKILL.md
cp "$here/commands/review-pr.md"     ~/.claude/commands/review-pr.md

echo "Installed:"
echo "  ~/.claude/skills/pr-review/SKILL.md"
echo "  ~/.claude/commands/review-pr.md"
echo
echo "Optional: add the review-pr shell function to your ~/.bashrc or ~/.zshrc."
```
### Review standars template example
```
# Review standards for <repo name>

These rules are read by the global pr-review skill during reviews only.
They override the generic standards when they conflict.

## Architecture
- No direct DB access outside `repositories/`.
- Business logic lives in `services/`, not controllers.

## Conventions
- Public functions need doc comments.
- Feature flags required for user-facing changes.

## Commands
- Tests: npm test
- Lint: npm run lint
```

## Claude
```
# Project context

- Stack: <e.g. TypeScript, Node 20, PostgreSQL>
- Run tests: <e.g. npm test>
- Run linter: <e.g. npm run lint>

Code review standards live in the `pr-review` skill (`.claude/skills/pr-review/`).
```

## 1. Prerequisites

|Tool|Check|Install / login|
|---|---|---|
|Git|`git --version`|—|
|GitHub CLI|`gh --version`|`gh auth login`|
|Claude Code|`claude --version`|`npm install -g @anthropic-ai/claude-code`, then run `claude` and log in with your Pro account|

---

## 2. One-time setup per repo

The review standards live in a **skill** instead of `CLAUDE.md`. `CLAUDE.md` is loaded into every session, while a skill only puts its short `description` in context; the full standards load only when Claude is actually reviewing code.

Repo layout:

```
your-repo/
├── CLAUDE.md                          # small, always-on project context
└── .claude/
    ├── skills/
    │   └── pr-review/
    │       └── SKILL.md               # review process + standards (loaded on demand)
    └── commands/
        └── review-pr.md               # /review-pr <n> → uses the skill
```

### 2.1 Keep `CLAUDE.md` small

Keep only what's useful in every session (stack, how to run tests and lint), plus a pointer to the skill:

```markdown
# Project context
- Stack: <e.g. TypeScript, Node 20, PostgreSQL>
- Run tests: <e.g. npm test>
- Run linter: <e.g. npm run lint>

Code review standards live in the `pr-review` skill (`.claude/skills/pr-review/`).
```

### 2.2 Add the `pr-review` skill

Copy the provided `.claude/skills/pr-review/SKILL.md` into your repo and fill in the `<Customize>` lines in the Architecture section with your own rules.

The `description` in its frontmatter decides when Claude loads it automatically, so it triggers both from `/review-pr` and from plain requests like "look over my changes".

If the standards grow large, split them into files under `.claude/skills/pr-review/references/` (e.g. `security.md`, `frontend.md`) and add a line in `SKILL.md` telling Claude when to read each one. Those files load only when needed.

### 2.3 Add the `/review-pr` command

The command is now a thin trigger that hands off to the skill. `.claude/commands/review-pr.md`:

```markdown
---
description: Review a GitHub pull request by number
argument-hint: <pr-number>
allowed-tools: Skill, Bash(gh pr view:*), Bash(gh pr diff:*), Bash(gh pr checks:*), Bash(git diff:*), Bash(git log:*), Bash(git fetch:*), Read, Grep, Glob
---

Review pull request #$ARGUMENTS using the pr-review skill. If the skill isn't
loaded, read `.claude/skills/pr-review/SKILL.md` and follow it exactly.
```

The fallback line (read the file directly) keeps the command working even if your Claude Code version handles skill invocation differently.

### 2.4 Commit and verify

```bash
git add CLAUDE.md .claude/skills/pr-review/SKILL.md .claude/commands/review-pr.md
git commit -m "Add Claude Code PR review skill and command"
```

Start `claude` in the repo and ask "what skills do you have available?". You should see `pr-review` listed. Check the exact frontmatter fields against your installed version (`claude --help` and the Claude Code docs).

---

## 3. The review flow

### Step 1 — Find the PR

```bash
gh pr list                     # open PRs
gh pr list --search "review-requested:@me"   # PRs waiting on you
```

### Step 2 — Check it out in a separate worktree

This keeps your current branch and uncommitted work untouched.

```bash
PR=123
git fetch origin
git worktree add "../review-pr-$PR" --detach
cd "../review-pr-$PR"
gh pr checkout "$PR"
```

### Step 3 — (Optional) Install deps and run tests

So Claude can reason about real results, or so you can run them yourself:

```bash
npm ci && npm test        # adapt to your stack
```

### Step 4 — Run the review

```bash
claude
```

Then inside Claude Code:

```
/review-pr 123
```

Useful follow-ups in the same session:

```
Explain the change in src/payments/service.ts in more detail.
Is the blocking issue #1 really a bug? Show me a concrete input that breaks it.
Write the review comments as I would post them on GitHub, concise and polite.
```

### Step 5 — Post the review (after you've read it)

Save the final review text to a file outside the repo, then:

```bash
# Comment only
gh pr review 123 --comment --body-file ~/review-123.md

# Request changes
gh pr review 123 --request-changes --body-file ~/review-123.md

# Approve
gh pr review 123 --approve --body "LGTM"
```

> Always read and edit Claude's output before posting. It's a strong first pass, not the final reviewer.

### Step 6 — Clean up

```bash
cd -                                  # back to your main checkout
git worktree remove "../review-pr-$PR"
```

---

## 4. Optional: one-command helper

Add to your `~/.bashrc` or `~/.zshrc`:

```bash
review-pr() {
  local pr="$1"
  if [ -z "$pr" ]; then echo "Usage: review-pr <pr-number>"; return 1; fi
  local dir="../review-pr-$pr"
  git fetch origin || return 1
  git worktree add "$dir" --detach || return 1
  (cd "$dir" && gh pr checkout "$pr" && claude "/review-pr $pr")
  echo "Done. Remove the worktree with: git worktree remove $dir"
}
```

Usage, from inside the repo:

```bash
review-pr 123
```

---

## 5. Non-interactive variant (print mode)

If you just want the review written to a file without an interactive session:

```bash
claude -p "/review-pr 123" > ~/review-123.md
```

Note: in print mode, Claude can only run tools allowed by the command's `allowed-tools` (or your settings), so keep that list in sync with what the review needs.

---

## 6. Tips

- **Big PRs:** ask Claude to review one area at a time (`Review only the changes under src/api/`), which gives better results and uses less of your Pro usage.
- **Usage limits:** Pro limits are shared with claude.ai usage; large reviews consume more.
- **Tune over time:** when Claude misses something or flags noise, update the skill's `SKILL.md` (standards) rather than the command.
- **Keep it local:** this flow uses your subscription interactively on your machine. For automated reviews in CI, use an API key and check the current terms at https://docs.claude.com/en/docs/claude-code/overview.
