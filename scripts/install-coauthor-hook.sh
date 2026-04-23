#!/usr/bin/env bash
# install-coauthor-hook.sh — install a per-worktree prepare-commit-msg hook
# that idempotently appends a "Co-Authored-By: Claude" trailer to every
# commit made inside the worktree (task commits, QA auto-fix, merge commits,
# revert commits — anything that runs through `git commit`).
#
# The hook is written to the worktree's own git-dir (not the shared
# common-dir), so it applies only to agent worktrees and never to the
# human's personal checkouts.
#
# Arg: $1=worktree_path
# Output: JSON { "installed": true, "hook": "...", "action": "created|updated|unchanged" }
# Exit: 0=ok, 1=error

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: install-coauthor-hook.sh <worktree_path>" >&2
  exit 1
fi

wt_path="$1"

if [[ ! -d "$wt_path" ]]; then
  echo "ERROR: Worktree path does not exist: $wt_path" >&2
  exit 1
fi

# Resolve the per-worktree git-dir. For a linked worktree this is
# something like <main-repo>/.git/worktrees/<name>; for the main
# checkout it is <repo>/.git.
git_dir=$(git -C "$wt_path" rev-parse --git-dir 2>/dev/null || true)
if [[ -z "$git_dir" ]]; then
  echo "ERROR: not a git worktree: $wt_path" >&2
  exit 1
fi
if [[ "$git_dir" != /* ]]; then
  git_dir="$wt_path/$git_dir"
fi

hooks_dir="$git_dir/hooks"
mkdir -p "$hooks_dir"

hook_file="$hooks_dir/prepare-commit-msg"

# Marker line lets us detect and refresh an older copy of our hook.
marker='# engineering-agent:coauthor-hook'

new_contents=$(cat <<'HOOK_EOF'
#!/usr/bin/env bash
# engineering-agent:coauthor-hook
# Auto-installed by scripts/install-coauthor-hook.sh.
# Idempotently appends a Claude co-author trailer to every commit.
# Runs for all commit sources (message, template, merge, squash, commit/amend).

COMMIT_MSG_FILE="$1"

# Guard: git must be available and the msg file must exist.
command -v git >/dev/null 2>&1 || exit 0
[[ -f "$COMMIT_MSG_FILE" ]] || exit 0

# --if-exists doNothing keeps the trailer a single entry across amends,
# rebases, and hook reruns.
git interpret-trailers \
  --if-exists doNothing \
  --trailer "Co-Authored-By: Claude <noreply@anthropic.com>" \
  --in-place "$COMMIT_MSG_FILE"
HOOK_EOF
)

action="created"
if [[ -f "$hook_file" ]]; then
  existing=$(cat "$hook_file")
  if [[ "$existing" == "$new_contents" ]]; then
    action="unchanged"
  elif grep -q "$marker" "$hook_file" 2>/dev/null; then
    action="updated"
  else
    # Foreign hook present — do NOT clobber. Back it up and install ours.
    backup="$hook_file.pre-coauthor.$(date +%s).bak"
    mv "$hook_file" "$backup"
    action="replaced"
    echo "WARNING: pre-existing prepare-commit-msg hook backed up to $backup" >&2
  fi
fi

if [[ "$action" != "unchanged" ]]; then
  printf '%s\n' "$new_contents" > "$hook_file"
  chmod +x "$hook_file"
fi

# --- Guard against core.hooksPath override ---
# If core.hooksPath is set (globally, or in the repo's shared config), git
# redirects hook lookup away from the per-worktree $GIT_DIR/hooks folder we
# just wrote into, so our hook never runs. Detect this via rev-parse (which
# reports the effective path after overrides), then pin a per-worktree
# override so our hook is always used. Scoped to this worktree only — the
# user's personal checkout is not touched.
hookspath_pinned="false"
effective_hooks=$(git -C "$wt_path" rev-parse --git-path hooks 2>/dev/null || true)
if [[ -n "$effective_hooks" ]]; then
  if [[ "$effective_hooks" != /* ]]; then
    effective_hooks="$wt_path/$effective_hooks"
  fi
  # Canonicalise via parent dir — the target dir may not exist yet when
  # core.hooksPath points somewhere outside the repo.
  canon_path() {
    local p="$1" d b
    d=$(dirname "$p"); b=$(basename "$p")
    if [[ -d "$d" ]]; then
      printf '%s/%s\n' "$(cd "$d" && pwd -P)" "$b"
    else
      printf '%s\n' "$p"
    fi
  }
  eff_abs=$(canon_path "$effective_hooks")
  ours_abs=$(canon_path "$hooks_dir")
  if [[ "$eff_abs" != "$ours_abs" ]]; then
    # extensions.worktreeConfig must be enabled on the shared repo config
    # for `git config --worktree` to write to the per-worktree config file.
    # Idempotent — already-true is a no-op.
    git -C "$wt_path" config extensions.worktreeConfig true >/dev/null 2>&1 || true
    if git -C "$wt_path" config --worktree core.hooksPath "$hooks_dir" >/dev/null 2>&1; then
      hookspath_pinned="true"
      echo "INFO: core.hooksPath was overridden ($effective_hooks) — pinned per-worktree hooksPath to $hooks_dir" >&2
    else
      echo "WARNING: core.hooksPath is overridden and could not be pinned per-worktree; the co-author trailer may not be appended" >&2
    fi
  fi
fi

# Escape the hook path for JSON
hook_file_json=${hook_file//\\/\\\\}
hook_file_json=${hook_file_json//\"/\\\"}
echo "{\"installed\":true,\"hook\":\"$hook_file_json\",\"action\":\"$action\",\"hookspath_pinned\":$hookspath_pinned}"
exit 0
