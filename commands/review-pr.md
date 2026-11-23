---
description: Review a GitHub pull request (any repo, forks included)
argument-hint: <pr-number | owner/repo#n | PR URL>
allowed-tools: Skill, Read, Grep, Glob, Bash(gh pr view:*), Bash(gh pr diff:*), Bash(gh pr checks:*), Bash(gh pr list:*), Bash(gh repo view:*), Bash(git remote:*), Bash(git rev-parse:*), Bash(git diff:*), Bash(git log:*), Bash(git show:*), Bash(git status:*), Bash(git fetch:*), Bash(git merge-base:*)
---

Review pull request `$ARGUMENTS` using the pr-review skill.

If the skill isn't loaded, read its SKILL.md and follow it exactly. Look for it at
`.claude/skills/pr-review/SKILL.md` in this repo first, then in the user's Claude
config dir (`$CLAUDE_CONFIG_DIR/skills/pr-review/SKILL.md`, default `~/.claude`).

If no argument was given, run `gh pr list` (with `--repo` resolved as in the
skill's step 0) and ask which PR to review.
