#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HUD="$ROOT/bin/codex-mini-hud"
PASS=0
FAIL=0
unset CODEX_HUD_CONFIG

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-mini-hud-tests.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

pass() { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }

new_home() {
  export HOME="$TEST_ROOT/home-$1"
  export CODEX_HOME="$HOME/.codex"
  export CODEX_HUD_STATE_DIR="$HOME/.codex-mini-hud"
  export CODEX_HUD_TESTING=1
  mkdir -p "$CODEX_HOME"
}

assert_contains() {
  local label="$1" file="$2" expected="$3"
  if [[ -f "$file" ]] && grep -Fq "$expected" "$file"; then pass "$label"; else fail "$label"; fi
}

assert_not_contains() {
  local label="$1" file="$2" unexpected="$3"
  if [[ ! -f "$file" ]] || ! grep -Fq "$unexpected" "$file"; then pass "$label"; else fail "$label"; fi
}

assert_eq() {
  local label="$1" actual="$2" expected="$3"
  if [[ "$actual" == "$expected" ]]; then pass "$label"; else fail "$label (expected '$expected', got '$actual')"; fi
}

printf 'Running codex-mini-hud tests...\n\n'

# Missing config: create a native footer and uninstall cleanly.
new_home missing
"$HUD" install >/dev/null
assert_contains "creates [tui]" "$CODEX_HOME/config.toml" "[tui]"
assert_contains "adds run state" "$CODEX_HOME/config.toml" '"run-state"'
assert_contains "adds model and reasoning" "$CODEX_HOME/config.toml" '"model-with-reasoning"'
assert_contains "adds context remaining" "$CODEX_HOME/config.toml" '"context-remaining"'
assert_contains "adds five-hour limit" "$CODEX_HOME/config.toml" '"five-hour-limit"'
assert_contains "adds compact branch changes" "$CODEX_HOME/config.toml" '"branch-changes"'
assert_not_contains "default omits weekly limit" "$CODEX_HOME/config.toml" '"weekly-limit"'
assert_not_contains "default omits plan progress" "$CODEX_HOME/config.toml" '"task-progress"'
assert_contains "configures terminal title" "$CODEX_HOME/config.toml" 'terminal_title = ['
assert_contains "title adds native activity" "$CODEX_HOME/config.toml" '"activity"'
assert_contains "title adds project" "$CODEX_HOME/config.toml" '"project-name"'
assert_contains "title carries thread" "$CODEX_HOME/config.toml" '"thread-title"'
"$HUD" uninstall >/dev/null
assert_not_contains "uninstall removes created footer" "$CODEX_HOME/config.toml" "status_line"
assert_eq "uninstall removes originally absent config" "$([[ -e "$CODEX_HOME/config.toml" ]] && printf yes || printf no)" "no"

# Existing config: preserve unrelated content and restore prior managed values.
new_home existing
cat > "$CODEX_HOME/config.toml" <<'EOF'
model = "example"

[tui]
notifications = true
status_line = ["model", "git-branch"]
status_line_use_colors = false
terminal_title = ["project-name"]

[history]
persistence = "none"
EOF
cp "$CODEX_HOME/config.toml" "$HOME/original.toml"
"$HUD" install >/dev/null
assert_contains "preserves sibling tui key" "$CODEX_HOME/config.toml" "notifications = true"
assert_contains "preserves later table" "$CODEX_HOME/config.toml" 'persistence = "none"'
"$HUD" uninstall >/dev/null
if cmp -s "$CODEX_HOME/config.toml" "$HOME/original.toml"; then
  pass "restores exact managed values"
else
  # Whitespace placement can change, so verify semantic preservation separately.
  assert_contains "restores old status line" "$CODEX_HOME/config.toml" 'status_line = ["model", "git-branch"]'
  assert_contains "restores old color setting" "$CODEX_HOME/config.toml" "status_line_use_colors = false"
  assert_contains "restores old terminal title" "$CODEX_HOME/config.toml" 'terminal_title = ["project-name"]'
fi

# Compact and branch options.
new_home options
"$HUD" install --compact --with-git-branch --no-color >/dev/null
assert_contains "branch option" "$CODEX_HOME/config.toml" '"git-branch"'
assert_not_contains "compact omits weekly" "$CODEX_HOME/config.toml" '"weekly-limit"'
assert_not_contains "compact omits progress" "$CODEX_HOME/config.toml" '"task-progress"'
assert_not_contains "compact omits model" "$CODEX_HOME/config.toml" '"model-with-reasoning"'
assert_contains "compact keeps changes" "$CODEX_HOME/config.toml" '"branch-changes"'
assert_contains "no-color option" "$CODEX_HOME/config.toml" "status_line_use_colors = false"

# Reinstall is idempotent when the managed fields are unchanged.
out="$("$HUD" install --compact --with-git-branch --no-color)"
if [[ "$out" == *"already installed"* ]]; then pass "idempotent reinstall"; else fail "idempotent reinstall"; fi
if "$HUD" install >/dev/null 2>&1; then fail "refuses silent preset change"; else pass "refuses silent preset change"; fi

# Uninstall refuses to overwrite a user's later change.
sed -i.bak 's/"context-remaining"/"context-used"/' "$CODEX_HOME/config.toml"
rm -f "$CODEX_HOME/config.toml.bak"
if "$HUD" uninstall >/dev/null 2>&1; then
  fail "refuses changed managed value"
else
  pass "refuses changed managed value"
fi
assert_contains "keeps user modification" "$CODEX_HOME/config.toml" '"context-used"'

new_home titlechange
"$HUD" install >/dev/null
sed -i.bak 's/"activity"/"project-name"/' "$CODEX_HOME/config.toml"
rm -f "$CODEX_HOME/config.toml.bak"
if "$HUD" uninstall >/dev/null 2>&1; then fail "refuses changed terminal title"; else pass "refuses changed terminal title"; fi

# Dry run has no side effects.
new_home dryrun
out="$("$HUD" install --dry-run)"
assert_eq "dry run does not create config" "$([[ -e "$CODEX_HOME/config.toml" ]] && printf yes || printf no)" "no"
assert_eq "dry run does not create state" "$([[ -e "$CODEX_HUD_STATE_DIR" ]] && printf yes || printf no)" "no"
if [[ "$out" == *"status_line"* ]]; then pass "dry run prints diff"; else fail "dry run prints diff"; fi

# Ambiguous TOML is refused without changing the source.
new_home duplicate
cat > "$CODEX_HOME/config.toml" <<'EOF'
[tui]
status_line = ["model"]
status_line = ["context-used"]
EOF
cp "$CODEX_HOME/config.toml" "$HOME/before.toml"
if "$HUD" install >/dev/null 2>&1; then fail "refuses duplicate key"; else pass "refuses duplicate key"; fi
if cmp -s "$CODEX_HOME/config.toml" "$HOME/before.toml"; then pass "duplicate refusal is non-mutating"; else fail "duplicate refusal is non-mutating"; fi

new_home duplicatetitle
cat > "$CODEX_HOME/config.toml" <<'EOF'
[tui]
terminal_title = ["activity"]
terminal_title = ["project-name"]
EOF
cp "$CODEX_HOME/config.toml" "$HOME/before.toml"
if "$HUD" install >/dev/null 2>&1; then fail "refuses duplicate terminal title"; else pass "refuses duplicate terminal title"; fi
if cmp -s "$CODEX_HOME/config.toml" "$HOME/before.toml"; then pass "title duplicate refusal is non-mutating"; else fail "title duplicate refusal is non-mutating"; fi

new_home malformed
cat > "$CODEX_HOME/config.toml" <<'EOF'
[tui]
status_line = [
  "model",

[history]
persistence = "none"
EOF
cp "$CODEX_HOME/config.toml" "$HOME/before.toml"
if "$HUD" install >/dev/null 2>&1; then fail "refuses unterminated status array"; else pass "refuses unterminated status array"; fi
if cmp -s "$CODEX_HOME/config.toml" "$HOME/before.toml"; then pass "malformed refusal is non-mutating"; else fail "malformed refusal is non-mutating"; fi

# Brackets in comments/strings are not structural, and later tables survive.
new_home brackets
cat > "$CODEX_HOME/config.toml" <<'EOF'
[tui]
status_line = [ # [ is only a comment
  "model[with-label]", # ] is only a comment
  "git-branch",
]

[history]
persistence = "none"
EOF
"$HUD" install >/dev/null
assert_contains "commented brackets preserve later table" "$CODEX_HOME/config.toml" "[history]"
assert_contains "commented brackets preserve later value" "$CODEX_HOME/config.toml" 'persistence = "none"'
"$HUD" uninstall >/dev/null
assert_contains "commented status restores" "$CODEX_HOME/config.toml" '"model[with-label]", # ] is only a comment'

# Array tables terminate [tui] and their similarly named keys are untouched.
new_home arraytable
cat > "$CODEX_HOME/config.toml" <<'EOF'
[tui]
notifications = true

[[example]]
status_line = ["belongs-to-example"]
name = "x"
EOF
"$HUD" install >/dev/null
assert_contains "array-table key survives install" "$CODEX_HOME/config.toml" 'status_line = ["belongs-to-example"]'
awk '/^\[\[example\]\]/{seen=1} seen && /"model-with-reasoning"/{bad=1} END{exit bad}' "$CODEX_HOME/config.toml" \
  && pass "HUD fields stay in tui table" || fail "HUD fields stay in tui table"

# Inline root tables are valid TOML but conservatively refused.
new_home inline
printf 'tui = { notifications = true }\n' > "$CODEX_HOME/config.toml"
cp "$CODEX_HOME/config.toml" "$HOME/before.toml"
if "$HUD" install >/dev/null 2>&1; then fail "refuses inline tui table"; else pass "refuses inline tui table"; fi
if cmp -s "$CODEX_HOME/config.toml" "$HOME/before.toml"; then pass "inline refusal is non-mutating"; else fail "inline refusal is non-mutating"; fi

# Nested arrays under [tui] are values, not table headers.
new_home nestedarray
cat > "$CODEX_HOME/config.toml" <<'EOF'
[tui]
some_matrix = [
  [1, 2],
  [3, 4],
]

[history]
persistence = "none"
EOF
"$HUD" install >/dev/null
assert_contains "nested array survives install" "$CODEX_HOME/config.toml" "  [1, 2],"
assert_contains "table after nested array survives" "$CODEX_HOME/config.toml" "[history]"
awk '/^status_line =/{hud=NR} /^\[history\]/{history=NR} END{exit !(hud && history && hud < history)}' "$CODEX_HOME/config.toml" \
  && pass "HUD precedes next table after nested array" || fail "HUD precedes next table after nested array"

# Quoted TOML keys can name the tui table; do not append a duplicate table.
new_home quotedtable
cat > "$CODEX_HOME/config.toml" <<'EOF'
[ "tui" ]
notifications = true

[history]
persistence = "none"
EOF
"$HUD" install >/dev/null
assert_eq "quoted tui table is not duplicated" "$(grep -Ec '^\[[[:space:]]*("tui"|tui)[[:space:]]*\]' "$CODEX_HOME/config.toml")" "1"
assert_contains "quoted tui receives HUD" "$CODEX_HOME/config.toml" '"model-with-reasoning"'

new_home quotedkey
cat > "$CODEX_HOME/config.toml" <<'EOF'
[tui]
"status_line" = ["model"]
EOF
cp "$CODEX_HOME/config.toml" "$HOME/before.toml"
if "$HUD" install >/dev/null 2>&1; then fail "refuses quoted managed key"; else pass "refuses quoted managed key"; fi
if cmp -s "$CODEX_HOME/config.toml" "$HOME/before.toml"; then pass "quoted key refusal is non-mutating"; else fail "quoted key refusal is non-mutating"; fi

# Dotted keys and symlinks are refused.
new_home dotted
printf 'tui.status_line = ["model"]\n' > "$CODEX_HOME/config.toml"
if "$HUD" install >/dev/null 2>&1; then fail "refuses dotted managed key"; else pass "refuses dotted managed key"; fi

new_home spaceddotted
printf '"tui" . "status_line" = ["model"]\n' > "$CODEX_HOME/config.toml"
cp "$CODEX_HOME/config.toml" "$HOME/before.toml"
if "$HUD" install >/dev/null 2>&1; then fail "refuses spaced quoted dotted key"; else pass "refuses spaced quoted dotted key"; fi
if cmp -s "$CODEX_HOME/config.toml" "$HOME/before.toml"; then pass "dotted refusal is non-mutating"; else fail "dotted refusal is non-mutating"; fi

new_home multiline
cat > "$CODEX_HOME/config.toml" <<'EOF'
instructions = """
Example only:
[tui]
status_line = ["keep-this-example"]
"""
EOF
cp "$CODEX_HOME/config.toml" "$HOME/before.toml"
if "$HUD" install >/dev/null 2>&1; then fail "refuses multiline TOML strings"; else pass "refuses multiline TOML strings"; fi
if cmp -s "$CODEX_HOME/config.toml" "$HOME/before.toml"; then pass "multiline refusal is non-mutating"; else fail "multiline refusal is non-mutating"; fi

new_home symlink
printf 'model = "example"\n' > "$HOME/real.toml"
ln -s "$HOME/real.toml" "$CODEX_HOME/config.toml"
if "$HUD" install >/dev/null 2>&1; then fail "refuses config symlink"; else pass "refuses config symlink"; fi

# A failed atomic replacement is non-mutating and leaves no false state.
new_home replacefail
printf 'model = "before"\n' > "$CODEX_HOME/config.toml"
cp "$CODEX_HOME/config.toml" "$HOME/before.toml"
export CODEX_HUD_TEST_FAIL_REPLACE=1
if "$HUD" install >/dev/null 2>&1; then fail "replacement failure returns nonzero"; else pass "replacement failure returns nonzero"; fi
unset CODEX_HUD_TEST_FAIL_REPLACE
if cmp -s "$CODEX_HOME/config.toml" "$HOME/before.toml"; then pass "replacement failure preserves config"; else fail "replacement failure preserves config"; fi
assert_eq "replacement failure cleans state" "$([[ -e "$CODEX_HUD_STATE_DIR" ]] && printf yes || printf no)" "no"

# Incomplete transaction state is recovered when config still matches prior values.
new_home recovery
printf 'model = "before"\n' > "$CODEX_HOME/config.toml"
cp "$CODEX_HOME/config.toml" "$HOME/before.toml"
"$HUD" install >/dev/null
cp "$HOME/before.toml" "$CODEX_HOME/config.toml"
"$HUD" install >/dev/null
assert_contains "recovers incomplete transaction" "$CODEX_HOME/config.toml" '"context-remaining"'

# Interrupted uninstall cleanup succeeds after config was already restored.
new_home uninstallrecovery
cat > "$CODEX_HOME/config.toml" <<'EOF'
[tui]
status_line = ["model"]
EOF
cp "$CODEX_HOME/config.toml" "$HOME/before.toml"
"$HUD" install >/dev/null
cp "$HOME/before.toml" "$CODEX_HOME/config.toml"
"$HUD" uninstall >/dev/null
assert_eq "recovers interrupted uninstall state" "$([[ -e "$CODEX_HUD_STATE_DIR" ]] && printf yes || printf no)" "no"

new_home uninstallmissing
"$HUD" install >/dev/null
rm -f "$CODEX_HOME/config.toml"
"$HUD" uninstall >/dev/null
assert_eq "recovers interrupted uninstall after config removal" "$([[ -e "$CODEX_HUD_STATE_DIR" ]] && printf yes || printf no)" "no"

# Legacy v0.2 state restores its two managed keys without touching titles.
new_home legacyv1
cat > "$CODEX_HOME/config.toml" <<'EOF'
[tui]
status_line = ["context-remaining"]
status_line_use_colors = true
terminal_title = ["project-name", "thread-title"]
EOF
mkdir -p "$CODEX_HUD_STATE_DIR"
printf 'codex-mini-hud-state-v1\n' > "$CODEX_HUD_STATE_DIR/manifest"
printf '%s\n' "$CODEX_HOME/config.toml" > "$CODEX_HUD_STATE_DIR/config-path"
printf '0.2.0\n' > "$CODEX_HUD_STATE_DIR/version"
printf 'yes\n' > "$CODEX_HUD_STATE_DIR/config-existed"
printf 'status_line = ["model"]\n' > "$CODEX_HUD_STATE_DIR/previous-status-line.toml"
printf 'status_line_use_colors = false\n' > "$CODEX_HUD_STATE_DIR/previous-colors.toml"
printf 'status_line = ["context-remaining"]\n' > "$CODEX_HUD_STATE_DIR/installed-status-line.toml"
printf 'status_line_use_colors = true\n' > "$CODEX_HUD_STATE_DIR/installed-colors.toml"
"$HUD" uninstall >/dev/null
assert_contains "legacy uninstall restores status" "$CODEX_HOME/config.toml" 'status_line = ["model"]'
assert_contains "legacy uninstall restores colors" "$CODEX_HOME/config.toml" 'status_line_use_colors = false'
assert_contains "legacy uninstall preserves terminal title" "$CODEX_HOME/config.toml" 'terminal_title = ["project-name", "thread-title"]'
assert_eq "legacy uninstall removes state" "$([[ -e "$CODEX_HUD_STATE_DIR" ]] && printf yes || printf no)" "no"

# Uninstall preserves unexpected files in its private state directory.
new_home statefiles
"$HUD" install >/dev/null
printf 'keep\n' > "$CODEX_HUD_STATE_DIR/user-note"
"$HUD" uninstall >/dev/null 2>&1
assert_contains "preserves unexpected state file" "$CODEX_HUD_STATE_DIR/user-note" "keep"

# Print-config and version are stable, read-only commands.
new_home readonly
out="$("$HUD" print-config --with-git-branch)"
if [[ "$out" == *"[tui]"* && "$out" == *'"git-branch"'* ]]; then pass "print-config"; else fail "print-config"; fi
new_home expanded
out="$("$HUD" print-config --expanded)"
if [[ "$out" == *'"weekly-limit"'* && "$out" == *'"task-progress"'* ]]; then pass "expanded preset"; else fail "expanded preset"; fi

if "$HUD" print-config --compact --expanded >/dev/null 2>&1; then fail "rejects conflicting presets"; else pass "rejects conflicting presets"; fi

out="$("$HUD" print-config --focus)"
if [[ "$out" == *'"task-progress"'* && "$out" == *'"git-branch"'* ]]; then pass "focus preset"; else fail "focus preset"; fi

out="$("$HUD" print-config --fuel)"
if [[ "$out" == *'"weekly-limit"'* && "$out" != *'"branch-changes"'* ]]; then pass "fuel preset"; else fail "fuel preset"; fi

out="$("$HUD" layout)"
if [[ "$out" == *"NOW · ENGINE · FUEL"* && "$out" == *"/rename ✦ auth cleanup"* ]]; then pass "layout legend"; else fail "layout legend"; fi

out="$("$HUD" print-config --private-title)"
if [[ "$out" == *'"activity"'* && "$out" == *'"project-name"'* && "$out" != *'"thread-title"'* ]]; then pass "private title"; else fail "private title"; fi

assert_eq "version" "$("$HUD" version)" "$(cat "$ROOT/VERSION")"

printf '\nResults: %d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
