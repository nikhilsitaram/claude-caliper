#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/post-tool-use-design-approval.sh"
PASS=0
FAIL=0

assert_file_exists() {
  local desc="$1" file="$2"
  if [[ -f "$file" ]]; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc (file not found: $file)"
    ((FAIL++)) || true
  fi
}

assert_file_not_exists() {
  local desc="$1" file="$2"
  if [[ ! -f "$file" ]]; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc (file should not exist: $file)"
    ((FAIL++)) || true
  fi
}

assert_file_contains() {
  local desc="$1" file="$2" expected="$3"
  if [[ -f "$file" ]] && grep -qF "$expected" "$file"; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc (expected '$expected' in $file)"
    ((FAIL++)) || true
  fi
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "Test 1: Approved with metadata.source creates sentinel"
PLAN_DIR="$TMPDIR/docs/plans/2026-03-20-topic"
mkdir -p "$PLAN_DIR"
INPUT=$(jq -n \
  --arg plan_dir "$PLAN_DIR" \
  '{
    tool_name: "AskUserQuestion",
    session_id: "test-session-123",
    tool_input: {
      metadata: { source: "design-approval" },
      questions: [{ question: ("Design approved? Plan dir: " + $plan_dir) }]
    },
    tool_response: "Approved"
  }')
echo "$INPUT" | bash "$HOOK" 2>/dev/null || true
assert_file_exists "approval with metadata creates sentinel" "$PLAN_DIR/.design-approved"
assert_file_contains "sentinel contains session_id" "$PLAN_DIR/.design-approved" "test-session-123"

echo "Test 2: Approved with text fallback creates sentinel (no metadata)"
PLAN_DIR2="$TMPDIR/docs/plans/2026-03-20-fallback"
mkdir -p "$PLAN_DIR2"
INPUT2=$(jq -n \
  --arg plan_dir "$PLAN_DIR2" \
  '{
    tool_name: "AskUserQuestion",
    session_id: "test-session-123",
    tool_input: {
      questions: [{ question: ("Design approved? Plan dir: " + $plan_dir) }]
    },
    tool_response: "Approved"
  }')
echo "$INPUT2" | bash "$HOOK" 2>/dev/null || true
assert_file_exists "approval via text fallback creates sentinel" "$PLAN_DIR2/.design-approved"

echo "Test 3: Rejected ('Needs changes') does not create sentinel"
PLAN_DIR3="$TMPDIR/docs/plans/2026-03-20-rejected"
mkdir -p "$PLAN_DIR3"
INPUT3=$(jq -n \
  --arg plan_dir "$PLAN_DIR3" \
  '{
    tool_name: "AskUserQuestion",
    session_id: "test-session-123",
    tool_input: {
      metadata: { source: "design-approval" },
      questions: [{ question: ("Design approved? Plan dir: " + $plan_dir) }]
    },
    tool_response: "Needs changes"
  }')
echo "$INPUT3" | bash "$HOOK" 2>/dev/null || true
assert_file_not_exists "rejection does not create sentinel" "$PLAN_DIR3/.design-approved"

echo "Test 4: Non-AskUserQuestion tool is ignored"
PLAN_DIR4="$TMPDIR/docs/plans/2026-03-20-edit"
mkdir -p "$PLAN_DIR4"
INPUT4=$(jq -n \
  --arg plan_dir "$PLAN_DIR4" \
  '{
    tool_name: "Edit",
    session_id: "test-session-123",
    tool_input: {
      metadata: { source: "design-approval" },
      questions: [{ question: ("Design approved? Plan dir: " + $plan_dir) }]
    },
    tool_response: "Approved"
  }')
echo "$INPUT4" | bash "$HOOK" 2>/dev/null || true
assert_file_not_exists "non-AskUserQuestion tool ignored" "$PLAN_DIR4/.design-approved"

echo "Test 5: AskUserQuestion without design-approval metadata or Plan dir text is ignored"
PLAN_DIR5="$TMPDIR/docs/plans/2026-03-20-noplandir"
mkdir -p "$PLAN_DIR5"
INPUT5=$(jq -n \
  '{
    tool_name: "AskUserQuestion",
    session_id: "test-session-123",
    tool_input: {
      questions: [{ question: "Which color do you prefer?" }]
    },
    tool_response: "Approved"
  }')
echo "$INPUT5" | bash "$HOOK" 2>/dev/null || true
assert_file_not_exists "unrelated question ignored" "$PLAN_DIR5/.design-approved"

echo "Test 6: session_id written correctly to sentinel"
PLAN_DIR6="$TMPDIR/docs/plans/2026-03-20-sessid"
mkdir -p "$PLAN_DIR6"
INPUT6=$(jq -n \
  --arg plan_dir "$PLAN_DIR6" \
  '{
    tool_name: "AskUserQuestion",
    session_id: "session-abc-456",
    tool_input: {
      metadata: { source: "design-approval" },
      questions: [{ question: ("Design approved? Plan dir: " + $plan_dir) }]
    },
    tool_response: "Approved"
  }')
echo "$INPUT6" | bash "$HOOK" 2>/dev/null || true
assert_file_contains "sentinel contains correct session_id" "$PLAN_DIR6/.design-approved" "session-abc-456"

echo "Test 7: mkdir -p creates intermediate directories"
PLAN_DIR7="$TMPDIR/new/nested/docs/plans/2026-03-20-test"
INPUT7=$(jq -n \
  --arg plan_dir "$PLAN_DIR7" \
  '{
    tool_name: "AskUserQuestion",
    session_id: "test-session-123",
    tool_input: {
      metadata: { source: "design-approval" },
      questions: [{ question: ("Design approved? Plan dir: " + $plan_dir) }]
    },
    tool_response: "Approved"
  }')
echo "$INPUT7" | bash "$HOOK" 2>/dev/null || true
assert_file_exists "sentinel created in deeply nested path" "$PLAN_DIR7/.design-approved"

echo ""
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
