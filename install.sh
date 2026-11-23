#!/usr/bin/env bash
# Installs the pr-review skill, /review-pr command, and review-pr CLI for Claude Code.
# Supports multiple Claude accounts (one config dir per account).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"

usage() {
  cat <<USAGE
Usage: ./install.sh [mode] [options]

Modes:
  (default)               Install skill + command into Claude config dir(s),
                          and the review-pr CLI into $BIN_DIR
  --project DIR           Install skill + command into DIR/.claude (commit to share with team)
  --init-standards DIR    Scaffold DIR/.claude/review-standards.md (+ CLAUDE.md if missing)
  --uninstall             Remove the install from the selected account(s) and the CLI
  --list-accounts         Show detected Claude accounts and install status

Account selection (default and --uninstall modes):
  -a, --account NAME|DIR  Target one account; repeatable. NAME resolves to ~/.claude-NAME,
                          "default" to ~/.claude, or pass a path.
  --all-accounts          Target every detected account (~/.claude, ~/.claude-*)
  (none)                  \$CLAUDE_CONFIG_DIR if set, else ~/.claude

Options:
  --link                  Symlink instead of copy (edits in this repo apply immediately)
  --no-cli                Skip installing/removing the review-pr CLI
  --private               With --init-standards: add the files to .git/info/exclude
                          (useful in forks where you don't want to commit them upstream)
  -h, --help              Show this help

Env: CLAUDE_CONFIG_DIR, BIN_DIR (default ~/.local/bin)
USAGE
}

# --- account helpers (kept in sync with bin/review-pr) ---
resolve_account() { # NAME|PATH -> config dir
  case "$1" in
    default)   echo "$HOME/.claude" ;;
    */*|"~"*)  echo "${1/#\~/$HOME}" ;;
    *)         echo "$HOME/.claude-$1" ;;
  esac
}
account_name() { # config dir -> short name
  case "$1" in
    "$HOME/.claude")   echo "default" ;;
    "$HOME"/.claude-*) echo "${1#"$HOME"/.claude-}" ;;
    *)                 echo "$1" ;;
  esac
}
detect_accounts() {
  local d
  for d in "$HOME/.claude" "$HOME"/.claude-*; do
    [ -d "$d" ] || continue
    if [ -e "$d/settings.json" ] || [ -e "$d/history.jsonl" ] || [ -e "$d/.claude.json" ] || [ -d "$d/projects" ]; then
      echo "$d"
    fi
  done
}

mode="global"; target=""; link=0; cli=1; private=0; all=0; accounts=()
while [ $# -gt 0 ]; do
  case "$1" in
    --project)        mode="project"; target="${2:?--project needs a DIR}"; shift 2 ;;
    --init-standards) mode="standards"; target="${2:?--init-standards needs a DIR}"; shift 2 ;;
    --uninstall)      mode="uninstall"; shift ;;
    --list-accounts)  mode="list"; shift ;;
    -a|--account)     accounts+=("${2:?--account needs a NAME or DIR}"); shift 2 ;;
    --all-accounts)   all=1; shift ;;
    --link)           link=1; shift ;;
    --no-cli)         cli=0; shift ;;
    --private)        private=1; shift ;;
    -h|--help)        usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

# Resolve target config dirs.
targets=()
if [ $all -eq 1 ]; then
  while IFS= read -r d; do targets+=("$d"); done < <(detect_accounts)
  [ ${#targets[@]} -gt 0 ] || { echo "No Claude accounts detected." >&2; exit 1; }
elif [ ${#accounts[@]} -gt 0 ]; then
  for a in "${accounts[@]}"; do targets+=("$(resolve_account "$a")"); done
else
  targets=("${CLAUDE_CONFIG_DIR:-$HOME/.claude}")
fi

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
  list)
    echo "Detected Claude accounts:"
    while IFS= read -r d; do
      if [ -e "$d/skills/pr-review/SKILL.md" ] && [ -e "$d/commands/review-pr.md" ]; then s="installed"; else s="-"; fi
      printf "  %-12s %-40s %s\n" "$(account_name "$d")" "$d" "$s"
    done < <(detect_accounts)
    ;;
  global)
    for dir in "${targets[@]}"; do
      if [ ! -d "$dir" ]; then
        echo "! $dir does not exist. Log in to that account first:" >&2
        echo "    CLAUDE_CONFIG_DIR=$dir claude" >&2
        exit 1
      fi
      echo "Installing for account '$(account_name "$dir")' ($dir):"
      place "$here/skills/pr-review/SKILL.md" "$dir/skills/pr-review/SKILL.md"
      place "$here/commands/review-pr.md"     "$dir/commands/review-pr.md"
    done
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
    if [ $all -eq 0 ]; then
      others=""
      while IFS= read -r d; do
        skip=0; for t in "${targets[@]}"; do [ "$t" = "$d" ] && skip=1; done
        [ $skip -eq 0 ] && others="$others $(account_name "$d")"
      done < <(detect_accounts)
      [ -z "$others" ] || echo "Other accounts detected:$others  (use --account NAME or --all-accounts)"
    fi
    echo
    echo "Done. In any repo: 'review-pr <n>' (pick account with -a NAME) or '/review-pr <n>' inside claude."
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
    for dir in "${targets[@]}"; do
      echo "Uninstalling from account '$(account_name "$dir")' ($dir):"
      for f in "$dir/skills/pr-review/SKILL.md" "$dir/commands/review-pr.md"; do
        if [ -e "$f" ] || [ -L "$f" ]; then rm -f "$f"; echo "  removed $f"; fi
      done
      rmdir "$dir/skills/pr-review" 2>/dev/null || true
    done
    still=""
    while IFS= read -r d; do
      [ -e "$d/skills/pr-review/SKILL.md" ] && still="$still $(account_name "$d")"
    done < <(detect_accounts)
    if [ -n "$still" ]; then
      echo "Keeping $BIN_DIR/review-pr (still installed for:$still)"
    elif [ $cli -eq 1 ] && { [ -e "$BIN_DIR/review-pr" ] || [ -L "$BIN_DIR/review-pr" ]; }; then
      rm -f "$BIN_DIR/review-pr"; echo "  removed $BIN_DIR/review-pr"
    fi
    ;;
esac
