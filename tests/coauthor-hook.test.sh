#!/usr/bin/env bash
# coauthor-hook.test.sh — Verify install-coauthor-hook.sh installs a working
# prepare-commit-msg hook that appends the Claude co-author trailer
# idempotently, and does not clobber foreign hooks.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
AGENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALLER="$AGENT_ROOT/scripts/install-coauthor-hook.sh"

# Isolate from the user's global git config so a globally-configured
# core.hooksPath cannot redirect hook execution elsewhere.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "=== install-coauthor-hook.sh ==="

# --- Setup: a scratch git repo ---
repo="$tmp/repo"
mkdir -p "$repo"
git -C "$repo" init --initial-branch=main -q
git -C "$repo" config user.name "Test User"
git -C "$repo" config user.email "test@example.com"
# Disable any global/system hook path so our per-repo hook is what runs.
git -C "$repo" config --unset-all core.hooksPath 2>/dev/null || true

# --- Install into the repo ---
out=$(bash "$INSTALLER" "$repo" 2>/dev/null) || true
assert_contains "$out" '"installed":true' "installer reports installed"
assert_contains "$out" '"action":"created"' "first install records created"

hook_file="$repo/.git/hooks/prepare-commit-msg"
if [[ -x "$hook_file" ]]; then
  assert_eq "1" "1" "hook file exists and is executable"
else
  assert_eq "0" "1" "hook file exists and is executable"
fi

# --- Second install is idempotent (unchanged) ---
out=$(bash "$INSTALLER" "$repo" 2>/dev/null) || true
assert_contains "$out" '"action":"unchanged"' "re-install is unchanged"

# --- End-to-end: commit and confirm trailer appears exactly once ---
echo "hello" > "$repo/file.txt"
git -C "$repo" add file.txt
git -C "$repo" commit -m "feat(test): initial commit" -q

msg=$(git -C "$repo" log -1 --pretty=%B)
count=$(echo "$msg" | grep -c "^Co-Authored-By: Claude <noreply@anthropic.com>$" || true)
assert_eq "$count" "1" "commit has exactly one Claude co-author trailer"

# --- Idempotent across amend (hook runs again, trailer must not duplicate) ---
git -C "$repo" commit --amend --no-edit -q
msg=$(git -C "$repo" log -1 --pretty=%B)
count=$(echo "$msg" | grep -c "^Co-Authored-By: Claude <noreply@anthropic.com>$" || true)
assert_eq "$count" "1" "amend does not duplicate the trailer"

# --- Foreign hook is backed up, not clobbered ---
repo2="$tmp/repo2"
mkdir -p "$repo2"
git -C "$repo2" init --initial-branch=main -q
git -C "$repo2" config user.name "Test User"
git -C "$repo2" config user.email "test@example.com"
git -C "$repo2" config core.hooksPath ""
foreign="$repo2/.git/hooks/prepare-commit-msg"
mkdir -p "$(dirname "$foreign")"
cat > "$foreign" <<'F'
#!/usr/bin/env bash
# A pre-existing hook unrelated to engineering-agent
exit 0
F
chmod +x "$foreign"

out=$(bash "$INSTALLER" "$repo2" 2>/dev/null) || true
assert_contains "$out" '"action":"replaced"' "foreign hook replacement reported"

# Foreign backup preserved
backup_count=$(ls "$repo2/.git/hooks/" | grep -c 'prepare-commit-msg.pre-coauthor' || true)
assert_eq "$backup_count" "1" "foreign hook backed up"

# Replacement hook installs cleanly on re-run
out=$(bash "$INSTALLER" "$repo2" 2>/dev/null) || true
assert_contains "$out" '"action":"unchanged"' "subsequent install of same hook is unchanged"

# --- Non-existent worktree path errors cleanly ---
rc=0
bash "$INSTALLER" "$tmp/does-not-exist" >/dev/null 2>&1 || rc=$?
assert_exit "$rc" "1" "nonexistent worktree path fails fast"

echo ""
test_summary
