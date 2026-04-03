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
  mkdir -p "$dir/phase-a"
  touch "$dir/phase-a/completion.md"
  CLEANUP_DIRS+=("$dir")
  echo "$dir"
}

make_task_file() {
  local dir="$1" phase_dir="$2" task_id="$3" task_name="$4"
  local id_lower
  id_lower=$(echo "$task_id" | tr '[:upper:]' '[:lower:]')
  echo "# $task_id: $task_name" > "$dir/$phase_dir/$id_lower.md"
}

assert_pass() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label (expected pass, got fail)"
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

echo "Test 1: Task with no dependencies passes"
DIR=$(make_plan_dir)
cat > "$DIR/plan.json" <<'JSON'
{
  "schema": 1, "status": "In Development", "workflow": "pr-create",
  "goal": "test", "architecture": "test", "tech_stack": "test",
  "phases": [{
    "letter": "A", "name": "Phase A", "status": "In Progress",
    "depends_on": [], "rationale": "test",
    "tasks": [{
      "id": "A1", "name": "Task one", "status": "pending",
      "depends_on": [],
      "files": {"create": [], "modify": ["f1.sh"], "test": []},
      "verification": "true", "done_when": "done"
    }]
  }]
}
JSON
make_task_file "$DIR" "phase-a" "A1" "Task one"
assert_pass "task with no dependencies" bash "$VP" --check-deps "$DIR/plan.json" --task A1

echo "Test 2: Task with all dependencies complete passes"
DIR=$(make_plan_dir)
cat > "$DIR/plan.json" <<'JSON'
{
  "schema": 1, "status": "In Development", "workflow": "pr-create",
  "goal": "test", "architecture": "test", "tech_stack": "test",
  "phases": [{
    "letter": "A", "name": "Phase A", "status": "In Progress",
    "depends_on": [], "rationale": "test",
    "tasks": [
      {
        "id": "A1", "name": "Task one", "status": "complete",
        "depends_on": [],
        "files": {"create": [], "modify": ["f1.sh"], "test": []},
        "verification": "true", "done_when": "done"
      },
      {
        "id": "A2", "name": "Task two", "status": "pending",
        "depends_on": ["A1"],
        "files": {"create": [], "modify": ["f2.sh"], "test": []},
        "verification": "true", "done_when": "done"
      }
    ]
  }]
}
JSON
make_task_file "$DIR" "phase-a" "A1" "Task one"
make_task_file "$DIR" "phase-a" "A2" "Task two"
echo "# A1 Completion" > "$DIR/phase-a/a1-completion.md"
assert_pass "task with all deps complete" bash "$VP" --check-deps "$DIR/plan.json" --task A2

echo "Test 3: Task with one dependency still pending fails"
DIR=$(make_plan_dir)
cat > "$DIR/plan.json" <<'JSON'
{
  "schema": 1, "status": "In Development", "workflow": "pr-create",
  "goal": "test", "architecture": "test", "tech_stack": "test",
  "phases": [{
    "letter": "A", "name": "Phase A", "status": "In Progress",
    "depends_on": [], "rationale": "test",
    "tasks": [
      {
        "id": "A1", "name": "Task one", "status": "pending",
        "depends_on": [],
        "files": {"create": [], "modify": ["f1.sh"], "test": []},
        "verification": "true", "done_when": "done"
      },
      {
        "id": "A2", "name": "Task two", "status": "pending",
        "depends_on": ["A1"],
        "files": {"create": [], "modify": ["f2.sh"], "test": []},
        "verification": "true", "done_when": "done"
      }
    ]
  }]
}
JSON
make_task_file "$DIR" "phase-a" "A1" "Task one"
make_task_file "$DIR" "phase-a" "A2" "Task two"
assert_fail "task with pending dependency" bash "$VP" --check-deps "$DIR/plan.json" --task A2

echo "Test 4: Task with one dependency in_progress fails"
DIR=$(make_plan_dir)
cat > "$DIR/plan.json" <<'JSON'
{
  "schema": 1, "status": "In Development", "workflow": "pr-create",
  "goal": "test", "architecture": "test", "tech_stack": "test",
  "phases": [{
    "letter": "A", "name": "Phase A", "status": "In Progress",
    "depends_on": [], "rationale": "test",
    "tasks": [
      {
        "id": "A1", "name": "Task one", "status": "in_progress",
        "depends_on": [],
        "files": {"create": [], "modify": ["f1.sh"], "test": []},
        "verification": "true", "done_when": "done"
      },
      {
        "id": "A2", "name": "Task two", "status": "pending",
        "depends_on": ["A1"],
        "files": {"create": [], "modify": ["f2.sh"], "test": []},
        "verification": "true", "done_when": "done"
      }
    ]
  }]
}
JSON
make_task_file "$DIR" "phase-a" "A1" "Task one"
make_task_file "$DIR" "phase-a" "A2" "Task two"
assert_fail "task with in_progress dependency" bash "$VP" --check-deps "$DIR/plan.json" --task A2

echo "Test 5: Task that doesn't exist fails"
DIR=$(make_plan_dir)
cat > "$DIR/plan.json" <<'JSON'
{
  "schema": 1, "status": "In Development", "workflow": "pr-create",
  "goal": "test", "architecture": "test", "tech_stack": "test",
  "phases": [{
    "letter": "A", "name": "Phase A", "status": "In Progress",
    "depends_on": [], "rationale": "test",
    "tasks": [{
      "id": "A1", "name": "Task one", "status": "pending",
      "depends_on": [],
      "files": {"create": [], "modify": ["f1.sh"], "test": []},
      "verification": "true", "done_when": "done"
    }]
  }]
}
JSON
make_task_file "$DIR" "phase-a" "A1" "Task one"
assert_fail "nonexistent task" bash "$VP" --check-deps "$DIR/plan.json" --task Z99

echo "Test 6: Task with skipped dependency passes"
DIR=$(make_plan_dir)
cat > "$DIR/plan.json" <<'JSON'
{
  "schema": 1, "status": "In Development", "workflow": "pr-create",
  "goal": "test", "architecture": "test", "tech_stack": "test",
  "phases": [{
    "letter": "A", "name": "Phase A", "status": "In Progress",
    "depends_on": [], "rationale": "test",
    "tasks": [
      {
        "id": "A1", "name": "Task one", "status": "skipped",
        "depends_on": [],
        "files": {"create": [], "modify": ["f1.sh"], "test": []},
        "verification": "true", "done_when": "done"
      },
      {
        "id": "A2", "name": "Task two", "status": "pending",
        "depends_on": ["A1"],
        "files": {"create": [], "modify": ["f2.sh"], "test": []},
        "verification": "true", "done_when": "done"
      }
    ]
  }]
}
JSON
make_task_file "$DIR" "phase-a" "A1" "Task one"
make_task_file "$DIR" "phase-a" "A2" "Task two"
assert_pass "task with skipped dependency" bash "$VP" --check-deps "$DIR/plan.json" --task A2

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
