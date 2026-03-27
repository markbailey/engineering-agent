#!/usr/bin/env bash
# Tests for resolve-toolchain.sh and toolchain integration

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
SCRIPTS="$SCRIPT_DIR/../scripts"

echo "=== resolve-toolchain.sh ==="

# Setup: create a temp repos.json with toolchain and without
TMPDIR_TEST=$(mktemp -d)
cat > "$TMPDIR_TEST/repos.json" <<'RJSON'
{
  "repos": {
    "WITH_TC": {
      "name": "with-tc",
      "path": "/tmp/with-tc",
      "github_repo": "org/with-tc",
      "toolchain": {
        "typecheck": "npx tsc --noEmit",
        "test": "npx vitest run",
        "lint_fix": "npx eslint --fix . && npx prettier --write .",
        "install": "pnpm install --frozen-lockfile"
      }
    },
    "NO_TC": {
      "name": "no-tc",
      "path": "/tmp/no-tc",
      "github_repo": "org/no-tc"
    },
    "NULL_STEP": {
      "name": "null-step",
      "path": "/tmp/null-step",
      "github_repo": "org/null-step",
      "toolchain": {
        "typecheck": null,
        "test": "npm test"
      }
    }
  }
}
RJSON

# Temporarily point AGENT_ROOT to our temp dir by copying the script
cp "$SCRIPTS/resolve-toolchain.sh" "$TMPDIR_TEST/scripts/resolve-toolchain.sh" 2>/dev/null || {
  mkdir -p "$TMPDIR_TEST/scripts"
  cp "$SCRIPTS/resolve-toolchain.sh" "$TMPDIR_TEST/scripts/resolve-toolchain.sh"
}

# We need to run resolve-toolchain from the temp dir so it finds repos.json
# But the script uses SCRIPT_DIR/../repos.json, so we adjust
RESOLVE="$TMPDIR_TEST/scripts/resolve-toolchain.sh"

echo ""
echo "--- Project with toolchain config ---"
out=$("$RESOLVE" WITH_TC typecheck 2>/dev/null)
skip=$(echo "$out" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>process.stdout.write(String(JSON.parse(d).skip)))")
assert_eq "$skip" "false" "WITH_TC typecheck: skip=false"

cmd=$(echo "$out" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>process.stdout.write(JSON.parse(d).command))")
assert_eq "$cmd" "npx tsc --noEmit" "WITH_TC typecheck: correct command"

echo ""
echo "--- Project without toolchain section ---"
out=$("$RESOLVE" NO_TC typecheck 2>/dev/null)
skip=$(echo "$out" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>process.stdout.write(String(JSON.parse(d).skip)))")
assert_eq "$skip" "true" "NO_TC typecheck: skip=true"

echo ""
echo "--- Unknown project key ---"
out=$("$RESOLVE" UNKNOWN typecheck 2>/dev/null)
skip=$(echo "$out" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>process.stdout.write(String(JSON.parse(d).skip)))")
assert_eq "$skip" "true" "UNKNOWN project: skip=true"

echo ""
echo "--- Null step value ---"
out=$("$RESOLVE" NULL_STEP typecheck 2>/dev/null)
skip=$(echo "$out" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>process.stdout.write(String(JSON.parse(d).skip)))")
assert_eq "$skip" "true" "NULL_STEP typecheck (null): skip=true"

out=$("$RESOLVE" NULL_STEP test 2>/dev/null)
skip=$(echo "$out" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>process.stdout.write(String(JSON.parse(d).skip)))")
assert_eq "$skip" "false" "NULL_STEP test: skip=false"

echo ""
echo "--- Unconfigured step ---"
out=$("$RESOLVE" WITH_TC build 2>/dev/null)
skip=$(echo "$out" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>process.stdout.write(String(JSON.parse(d).skip)))")
assert_eq "$skip" "true" "WITH_TC build (not configured): skip=true"

echo ""
echo "=== Integration checks ==="

echo ""
echo "--- regression-guard.sh contains resolve-toolchain ---"
assert_contains "$(cat "$SCRIPTS/regression-guard.sh")" "resolve-toolchain" "regression-guard.sh references resolve-toolchain"

echo ""
echo "--- worktree-init.sh contains resolve-toolchain ---"
assert_contains "$(cat "$SCRIPTS/worktree-init.sh")" "resolve-toolchain" "worktree-init.sh references resolve-toolchain"

# Cleanup
rm -rf "$TMPDIR_TEST"

echo ""
test_summary
