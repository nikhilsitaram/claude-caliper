#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VP="$REPO_ROOT/bin/validate-plan"
PASS=0
FAIL=0
CLEANUP_DIRS=()
cleanup() { for d in "${CLEANUP_DIRS[@]}"; do rm -rf "$d"; done; }
trap cleanup EXIT

make_plan_dir() {
  local dir
  dir=$(mktemp -d)
  mkdir -p "$dir/phase-a" "$dir/phase-b"
  touch "$dir/phase-a/completion.md" "$dir/phase-b/completion.md"
  CLEANUP_DIRS+=("$dir")
  echo "$dir"
}

make_task_file() {
  local dir="$1" phase_dir="$2" task_id="$3" task_name="$4"
  local id_lower
  id_lower=$(echo "$task_id" | tr '[:upper:]' '[:lower:]')
  echo "# $task_id: $task_name" > "$dir/$phase_dir/$id_lower.md"
}

write_two_phase_plan() {
  local dir="$1" b1_deps="$2"
  cat > "$dir/plan.json" <<JSON
{
  "schema": 1, "status": "In Development", "workflow": "pr-create",
  "goal": "test", "architecture": "test", "tech_stack": "test",
  "phases": [
    {
      "letter": "A", "name": "Phase A", "status": "Complete (2026-04-27)",
      "depends_on": [], "rationale": "test",
      "tasks": [{
        "id": "A1", "name": "Task A1", "status": "complete",
        "depends_on": [],
        "files": {"create": [], "modify": ["a1.sh"], "test": []},
        "verification": "true", "done_when": "done"
      }]
    },
    {
      "letter": "B", "name": "Phase B", "status": "Not Started",
      "depends_on": ["A"], "rationale": "test",
      "tasks": [{
        "id": "B1", "name": "Task B1", "status": "pending",
        "depends_on": $b1_deps,
        "files": {"create": [], "modify": ["b1.sh"], "test": []},
        "verification": "true", "done_when": "done"
      }]
    }
  ]
}
JSON
  make_task_file "$dir" "phase-a" "A1" "Task A1"
  make_task_file "$dir" "phase-b" "B1" "Task B1"
}

assert_pass() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label (expected pass, got fail)"
    "$@" || true
    FAIL=$((FAIL + 1))
  fi
}

assert_fail() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "FAIL: $label (expected fail, got pass)"
    FAIL=$((FAIL + 1))
  else
    echo "PASS: $label"
    PASS=$((PASS + 1))
  fi
}

echo "Test 1: --check-handoffs passes when target task has matching handoff section"
DIR=$(make_plan_dir)
write_two_phase_plan "$DIR" '["A1"]'
{
  echo "# B1: Task B1"
  echo ""
  echo "## Handoff from A1"
  echo ""
  echo "A1 exports foo()."
} > "$DIR/phase-b/b1.md"
assert_pass "handoff section present" "$VP" --check-handoffs "$DIR/plan.json" --phase A

echo "Test 2: --check-handoffs fails when target task is missing handoff section"
DIR=$(make_plan_dir)
write_two_phase_plan "$DIR" '["A1"]'
assert_fail "handoff section absent" "$VP" --check-handoffs "$DIR/plan.json" --phase A

echo "Test 3: --check-handoffs passes when completion.md has Handoff Notes / None opt-out"
DIR=$(make_plan_dir)
write_two_phase_plan "$DIR" '["A1"]'
{
  echo "## Handoff Notes"
  echo ""
  echo "None — downstream tasks derive context from completion.md."
} > "$DIR/phase-a/completion.md"
assert_pass "global opt-out via None" "$VP" --check-handoffs "$DIR/plan.json" --phase A

echo "Test 3a: opt-out is case-insensitive (lowercase 'none')"
DIR=$(make_plan_dir)
write_two_phase_plan "$DIR" '["A1"]'
{
  echo "## Handoff Notes"
  echo ""
  echo "none."
} > "$DIR/phase-a/completion.md"
assert_pass "lowercase none opts out" "$VP" --check-handoffs "$DIR/plan.json" --phase A

echo "Test 3b: opt-out requires None at start of first content line — substring match does NOT trigger"
DIR=$(make_plan_dir)
write_two_phase_plan "$DIR" '["A1"]'
{
  echo "## Handoff Notes"
  echo ""
  echo "B1 needs none of the cache machinery from A1."
} > "$DIR/phase-a/completion.md"
assert_fail "none in middle of prose does not opt out" "$VP" --check-handoffs "$DIR/plan.json" --phase A

echo "Test 3c: opt-out does not match prefix words (e.g., 'nonesuch')"
DIR=$(make_plan_dir)
write_two_phase_plan "$DIR" '["A1"]'
{
  echo "## Handoff Notes"
  echo ""
  echo "Nonesuch interface is exposed."
} > "$DIR/phase-a/completion.md"
assert_fail "nonesuch does not opt out" "$VP" --check-handoffs "$DIR/plan.json" --phase A

echo "Test 3d: empty Handoff Notes section does not opt out"
DIR=$(make_plan_dir)
write_two_phase_plan "$DIR" '["A1"]'
{
  echo "## Handoff Notes"
  echo ""
} > "$DIR/phase-a/completion.md"
assert_fail "empty section does not opt out" "$VP" --check-handoffs "$DIR/plan.json" --phase A

echo "Test 4: --check-handoffs passes when no future-phase task has dep into this phase"
DIR=$(make_plan_dir)
write_two_phase_plan "$DIR" '[]'
assert_pass "no cross-phase deps" "$VP" --check-handoffs "$DIR/plan.json" --phase A

echo "Test 5: --check-handoffs fails when phase letter doesn't exist"
DIR=$(make_plan_dir)
write_two_phase_plan "$DIR" '["A1"]'
assert_fail "nonexistent phase" "$VP" --check-handoffs "$DIR/plan.json" --phase Z

echo "Test 6: --check-handoffs fails when target file is missing entirely"
DIR=$(make_plan_dir)
write_two_phase_plan "$DIR" '["A1"]'
rm "$DIR/phase-b/b1.md"
assert_fail "target file missing" "$VP" --check-handoffs "$DIR/plan.json" --phase A

echo "Test 7: --check-handoffs requires exact source ID in heading"
DIR=$(make_plan_dir)
write_two_phase_plan "$DIR" '["A1"]'
{
  echo "# B1: Task B1"
  echo ""
  echo "## Handoff from A11"
  echo ""
  echo "wrong source id"
} > "$DIR/phase-b/b1.md"
assert_fail "heading matches different source id" "$VP" --check-handoffs "$DIR/plan.json" --phase A

echo "Test 8: --add-dep adds dep to pending downstream task"
DIR=$(make_plan_dir)
write_two_phase_plan "$DIR" '[]'
assert_pass "add-dep B1 depends on A1" "$VP" --add-dep "$DIR/plan.json" --task B1 --depends-on A1
RESULT=$(jq -r '.phases[].tasks[] | select(.id == "B1") | .depends_on[]' "$DIR/plan.json")
if [[ "$RESULT" == "A1" ]]; then
  echo "PASS: B1.depends_on now contains A1"
  PASS=$((PASS + 1))
else
  echo "FAIL: B1.depends_on = '$RESULT' (expected 'A1')"
  FAIL=$((FAIL + 1))
fi

echo "Test 9: --add-dep is idempotent"
assert_pass "add-dep again (no-op)" "$VP" --add-dep "$DIR/plan.json" --task B1 --depends-on A1
RESULT_LEN=$(jq '.phases[].tasks[] | select(.id == "B1") | .depends_on | length' "$DIR/plan.json")
if [[ "$RESULT_LEN" == "1" ]]; then
  echo "PASS: dep not duplicated"
  PASS=$((PASS + 1))
else
  echo "FAIL: B1.depends_on has length $RESULT_LEN (expected 1)"
  FAIL=$((FAIL + 1))
fi

echo "Test 10: --add-dep regenerates plan.md"
if [[ -f "$DIR/plan.md" ]]; then
  echo "PASS: plan.md exists after --add-dep"
  PASS=$((PASS + 1))
else
  echo "FAIL: plan.md not written"
  FAIL=$((FAIL + 1))
fi

echo "Test 11: --add-dep rejects self-dependency"
DIR=$(make_plan_dir)
write_two_phase_plan "$DIR" '[]'
assert_fail "self-dependency" "$VP" --add-dep "$DIR/plan.json" --task B1 --depends-on B1

echo "Test 12: --add-dep rejects unknown downstream"
DIR=$(make_plan_dir)
write_two_phase_plan "$DIR" '[]'
assert_fail "unknown downstream task" "$VP" --add-dep "$DIR/plan.json" --task Z9 --depends-on A1

echo "Test 13: --add-dep rejects unknown source"
DIR=$(make_plan_dir)
write_two_phase_plan "$DIR" '[]'
assert_fail "unknown source task" "$VP" --add-dep "$DIR/plan.json" --task B1 --depends-on Z9

echo "Test 14: --add-dep rejects reverse-phase dep (source in later phase)"
DIR=$(make_plan_dir)
cat > "$DIR/plan.json" <<'JSON'
{
  "schema": 1, "status": "In Development", "workflow": "pr-create",
  "goal": "test", "architecture": "test", "tech_stack": "test",
  "phases": [
    {
      "letter": "A", "name": "Phase A", "status": "In Progress",
      "depends_on": [], "rationale": "test",
      "tasks": [{
        "id": "A1", "name": "Task A1", "status": "pending",
        "depends_on": [],
        "files": {"create": [], "modify": ["a1.sh"], "test": []},
        "verification": "true", "done_when": "done"
      }]
    },
    {
      "letter": "B", "name": "Phase B", "status": "Not Started",
      "depends_on": ["A"], "rationale": "test",
      "tasks": [{
        "id": "B1", "name": "Task B1", "status": "pending",
        "depends_on": [],
        "files": {"create": [], "modify": ["b1.sh"], "test": []},
        "verification": "true", "done_when": "done"
      }]
    }
  ]
}
JSON
make_task_file "$DIR" "phase-a" "A1" "Task A1"
make_task_file "$DIR" "phase-b" "B1" "Task B1"
assert_fail "A1 cannot depend on B1" "$VP" --add-dep "$DIR/plan.json" --task A1 --depends-on B1

echo "Test 15: --add-dep rejects when downstream is complete"
DIR=$(make_plan_dir)
write_two_phase_plan "$DIR" '[]'
jq '(.phases[].tasks[] | select(.id == "B1")).status = "complete"' "$DIR/plan.json" > "$DIR/plan.json.tmp" && mv "$DIR/plan.json.tmp" "$DIR/plan.json"
assert_fail "downstream already complete" "$VP" --add-dep "$DIR/plan.json" --task B1 --depends-on A1

echo "Test 16: end-to-end — add ad-hoc dep then check-handoffs sees it as required"
DIR=$(make_plan_dir)
write_two_phase_plan "$DIR" '[]'
"$VP" --add-dep "$DIR/plan.json" --task B1 --depends-on A1 >/dev/null
assert_fail "missing handoff after ad-hoc dep added" "$VP" --check-handoffs "$DIR/plan.json" --phase A
{
  echo "# B1: Task B1"
  echo ""
  echo "## Handoff from A1"
  echo ""
  echo "ad-hoc handoff content"
} > "$DIR/phase-b/b1.md"
assert_pass "handoff written satisfies check" "$VP" --check-handoffs "$DIR/plan.json" --phase A

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
