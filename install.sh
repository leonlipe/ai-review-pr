#!/usr/bin/env bash
# Installs the pr-review skill, /review-pr command, and review-pr CLI for Claude Code.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"

usage() {
  cat <<USAGE
Usage: ./install.sh [mode] [options]

Modes:
  (default)               Global install: skill + command into $CLAUDE_DIR,
                          review-pr CLI into $BIN_DIR
  --project DIR           Install skill + command into DIR/.claude (commit to share with team)
  --init-standards DIR    Scaffold DIR/.claude/review-standards.md (+ CLAUDE.md if missing)
  --uninstall             Remove the global install

Options:
  --link                  Symlink instead of copy (edits in this repo apply immediately)
  --no-cli                Skip installing the review-pr CLI
  --private               With --init-standards: add the files to .git/info/exclude
                          (useful in forks where you don't want to commit them upstream)
  -h, --help              Show this help

Env: CLAUDE_CONFIG_DIR (default ~/.claude), BIN_DIR (default ~/.local/bin)
USAGE
}

mode="global"; target=""; link=0; cli=1; private=0
while [ $# -gt 0 ]; do
  case "$1" in
    --project)        mode="project"; target="${2:?--project needs a DIR}"; shift 2 ;;
    --init-standards) mode="standards"; target="${2:?--init-standards needs a DIR}"; shift 2 ;;
    --uninstall)      mode="uninstall"; shift ;;
    --link)           link=1; shift ;;
    --no-cli)         cli=0; shift ;;
    --private)        private=1; shift ;;
    -h|--help)        usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

place() { # src dest
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [ -e "$dest" ] && [ ! -L "$dest" ] && ! cmp -s "$src" "$dest"; then
    cp "$dest" "$dest.bak"
    echo "  (backed up existing $dest → $dest.bak)"
  fi
  rm -f "$dest"
  if [ $link -eq 1 ]; then ln -s "$src" "$dest"; else cp "$src" "$dest"; fi
  echo "  $dest"
}

check_deps() {
  local missing=0
  for t in git gh claude; do
    command -v "$t" >/dev/null || { echo "  ! $t not found in PATH"; missing=1; }
  done
  if command -v gh >/dev/null && ! gh auth status >/dev/null 2>&1; then
    echo "  ! gh is not authenticated: run 'gh auth login'"
  fi
  [ $missing -eq 0 ] && echo "  git, gh, claude: OK"
  return 0
}

case "$mode" in
  global)
    echo "Installing into $CLAUDE_DIR:"
    place "$here/skills/pr-review/SKILL.md" "$CLAUDE_DIR/skills/pr-review/SKILL.md"
    place "$here/commands/review-pr.md"     "$CLAUDE_DIR/commands/review-pr.md"
    if [ $cli -eq 1 ]; then
      echo "Installing CLI into $BIN_DIR:"
      place "$here/bin/review-pr" "$BIN_DIR/review-pr"
      chmod +x "$BIN_DIR/review-pr"
      case ":$PATH:" in
        *":$BIN_DIR:"*) ;;
        *) echo "  ! $BIN_DIR is not in PATH. Add to ~/.zshrc or ~/.bashrc:"
           echo "      export PATH=\"$BIN_DIR:\$PATH\"" ;;
      esac
    fi
    echo "Checking dependencies:"; check_deps
    echo; echo "Done. In any repo: 'review-pr <n>' or, inside claude, '/review-pr <n>'."
    ;;
  project)
    [ -d "$target" ] || { echo "No such directory: $target" >&2; exit 1; }
    target="$(cd "$target" && pwd)"
    link=0  # symlinks into this repo would break for teammates
    echo "Installing into $target/.claude:"
    place "$here/skills/pr-review/SKILL.md" "$target/.claude/skills/pr-review/SKILL.md"
    place "$here/commands/review-pr.md"     "$target/.claude/commands/review-pr.md"
    echo; echo "Commit .claude/skills/pr-review and .claude/commands/review-pr.md to share."
    ;;
  standards)
    [ -d "$target" ] || { echo "No such directory: $target" >&2; exit 1; }
    target="$(cd "$target" && pwd)"
    created=()
    if [ -e "$target/.claude/review-standards.md" ]; then
      echo "  exists: $target/.claude/review-standards.md (left untouched)"
    else
      mkdir -p "$target/.claude"
      cp "$here/templates/review-standards.md" "$target/.claude/review-standards.md"
      echo "  created $target/.claude/review-standards.md"
      created+=(".claude/review-standards.md")
    fi
    if [ -e "$target/CLAUDE.md" ]; then
      echo "  exists: $target/CLAUDE.md (left untouched)"
    else
      cp "$here/templates/CLAUDE.md" "$target/CLAUDE.md"
      echo "  created $target/CLAUDE.md"
      created+=("CLAUDE.md")
    fi
    if [ $private -eq 1 ] && [ ${#created[@]} -gt 0 ]; then
      gitdir="$(git -C "$target" rev-parse --git-common-dir 2>/dev/null || true)"
      if [ -n "$gitdir" ]; then
        case "$gitdir" in /*) ;; *) gitdir="$target/$gitdir" ;; esac
        mkdir -p "$gitdir/info"
        for f in "${created[@]}"; do
          grep -qxF "/$f" "$gitdir/info/exclude" 2>/dev/null || echo "/$f" >> "$gitdir/info/exclude"
        done
        echo "  added to $gitdir/info/exclude: ${created[*]}"
      else
        echo "  ! $target is not a git repo; --private ignored"
      fi
    fi
    echo; echo "Fill in the <placeholders> in the created files."
    ;;
  uninstall)
    for f in "$CLAUDE_DIR/skills/pr-review/SKILL.md" "$CLAUDE_DIR/commands/review-pr.md" "$BIN_DIR/review-pr"; do
      if [ -e "$f" ] || [ -L "$f" ]; then rm -f "$f"; echo "  removed $f"; fi
    done
    rmdir "$CLAUDE_DIR/skills/pr-review" 2>/dev/null || true
    ;;
esac
