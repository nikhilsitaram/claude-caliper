#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATE="$REPO_ROOT/bin/validate-plan"
FIXTURES="$SCRIPT_DIR/fixtures"
PASS=0
FAIL=0

assert_exit_code() {
  local desc="$1" expected_code="$2"; shift 2
  local actual_code=0
  "$@" > /dev/null 2>&1 || actual_code=$?
  if [ "$actual_code" -eq "$expected_code" ]; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc (expected exit $expected_code, got $actual_code)"
    ((FAIL++)) || true
  fi
}

assert_output_contains() {
  local desc="$1" expected_substr="$2"; shift 2
  local output
  output=$("$@" 2>&1) || true
  if echo "$output" | grep -qF "$expected_substr"; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc (expected '$expected_substr' in output, got: $output)"
    ((FAIL++)) || true
  fi
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

write_plan() {
  local plan_file="$1"
  local criteria_json="$2"
  local scope="$3"
  local plan_dir
  plan_dir="$(dirname "$plan_file")"
  mkdir -p "$plan_dir/phase-a"
  echo "# Phase A Completion Notes" > "$plan_dir/phase-a/completion.md"
  echo "# A1: Test task" > "$plan_dir/phase-a/a1.md"

  if [ "$scope" = "task" ]; then
    jq -n --argjson criteria "$criteria_json" '{
      schema: 1, status: "Not Yet Started", goal: "Test",
      architecture: "Test", tech_stack: "Test",
      phases: [{
        letter: "A", name: "Test", status: "Not Started",
        rationale: "Test",
        tasks: [{
          id: "A1", name: "Test task", status: "pending",
          depends_on: [], files: {create: [], modify: [], test: []},
          verification: "true", done_when: "Tests pass",
          success_criteria: $criteria
        }]
      }]
    }' > "$plan_file"
  elif [ "$scope" = "phase" ]; then
    jq -n --argjson criteria "$criteria_json" '{
      schema: 1, status: "Not Yet Started", goal: "Test",
      architecture: "Test", tech_stack: "Test",
      phases: [{
        letter: "A", name: "Test", status: "Not Started",
        rationale: "Test", success_criteria: $criteria,
        tasks: [{
          id: "A1", name: "Test task", status: "pending",
          depends_on: [], files: {create: [], modify: [], test: []},
          verification: "true", done_when: "Tests pass"
        }]
      }]
    }' > "$plan_file"
  elif [ "$scope" = "plan" ]; then
    jq -n --argjson criteria "$criteria_json" '{
      schema: 1, status: "Not Yet Started", goal: "Test",
      architecture: "Test", tech_stack: "Test",
      success_criteria: $criteria,
      phases: [{
        letter: "A", name: "Test", status: "Not Started",
        rationale: "Test",
        tasks: [{
          id: "A1", name: "Test task", status: "pending",
          depends_on: [], files: {create: [], modify: [], test: []},
          verification: "true", done_when: "Tests pass"
        }]
      }]
    }' > "$plan_file"
  fi
}

echo "Test 1: Matching exit code produces PASS"
write_plan "$TMPDIR/t1/plan.json" '[{"run": "true", "expect_exit": 0}]' "task"
assert_output_contains "exit code match" "PASS" \
  "$VALIDATE" --criteria "$TMPDIR/t1/plan.json" --task A1
assert_exit_code "exit code match exits 0" 0 \
  "$VALIDATE" --criteria "$TMPDIR/t1/plan.json" --task A1

echo "Test 2: Matching output substring produces PASS"
write_plan "$TMPDIR/t2/plan.json" '[{"run": "echo hello world", "expect_output": "hello"}]' "task"
assert_output_contains "output match" "PASS" \
  "$VALIDATE" --criteria "$TMPDIR/t2/plan.json" --task A1
assert_exit_code "output match exits 0" 0 \
  "$VALIDATE" --criteria "$TMPDIR/t2/plan.json" --task A1

echo "Test 3: Both checks pass"
write_plan "$TMPDIR/t3/plan.json" '[{"run": "echo 2 passed", "expect_exit": 0, "expect_output": "2 passed"}]' "task"
assert_output_contains "both checks pass" "PASS" \
  "$VALIDATE" --criteria "$TMPDIR/t3/plan.json" --task A1
assert_exit_code "both checks exits 0" 0 \
  "$VALIDATE" --criteria "$TMPDIR/t3/plan.json" --task A1

echo "Test 4: Exit code mismatch produces FAIL"
write_plan "$TMPDIR/t4/plan.json" '[{"run": "false", "expect_exit": 0}]' "task"
assert_output_contains "exit mismatch" "FAIL" \
  "$VALIDATE" --criteria "$TMPDIR/t4/plan.json" --task A1
assert_exit_code "exit mismatch exits 1" 1 \
  "$VALIDATE" --criteria "$TMPDIR/t4/plan.json" --task A1

echo "Test 5: Output mismatch produces FAIL"
write_plan "$TMPDIR/t5/plan.json" '[{"run": "echo hello", "expect_output": "goodbye"}]' "task"
assert_output_contains "output mismatch" "FAIL" \
  "$VALIDATE" --criteria "$TMPDIR/t5/plan.json" --task A1
assert_exit_code "output mismatch exits 1" 1 \
  "$VALIDATE" --criteria "$TMPDIR/t5/plan.json" --task A1

echo "Test 6: Command exceeding timeout produces TIMEOUT"
if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
  write_plan "$TMPDIR/t6/plan.json" '[{"run": "sleep 10", "expect_exit": 0, "timeout": 1}]' "task"
  assert_output_contains "timeout" "TIMEOUT" \
    "$VALIDATE" --criteria "$TMPDIR/t6/plan.json" --task A1
  assert_exit_code "timeout exits 1" 1 \
    "$VALIDATE" --criteria "$TMPDIR/t6/plan.json" --task A1
else
  echo "SKIP: timeout test (no timeout/gtimeout available)"
fi

echo "Test 7: Warning severity fails but exits 0"
write_plan "$TMPDIR/t7/plan.json" '[{"run": "false", "expect_exit": 0, "severity": "warning"}]' "task"
assert_output_contains "warning severity" "WARN" \
  "$VALIDATE" --criteria "$TMPDIR/t7/plan.json" --task A1
assert_exit_code "warning exits 0" 0 \
  "$VALIDATE" --criteria "$TMPDIR/t7/plan.json" --task A1

echo "Test 8: Empty criteria array exits 0"
write_plan "$TMPDIR/t8/plan.json" '[]' "task"
assert_exit_code "empty criteria exits 0" 0 \
  "$VALIDATE" --criteria "$TMPDIR/t8/plan.json" --task A1

echo "Test 9: Mixed pass and fail exits 1"
write_plan "$TMPDIR/t9/plan.json" '[{"run": "true", "expect_exit": 0}, {"run": "false", "expect_exit": 0}]' "task"
assert_output_contains "mixed has PASS" "PASS" \
  "$VALIDATE" --criteria "$TMPDIR/t9/plan.json" --task A1
assert_output_contains "mixed has FAIL" "FAIL" \
  "$VALIDATE" --criteria "$TMPDIR/t9/plan.json" --task A1
assert_exit_code "mixed exits 1" 1 \
  "$VALIDATE" --criteria "$TMPDIR/t9/plan.json" --task A1

echo "Test 10: Missing target flag exits 2"
write_plan "$TMPDIR/t10/plan.json" '[{"run": "true", "expect_exit": 0}]' "task"
assert_exit_code "missing target flag exits 2" 2 \
  "$VALIDATE" --criteria "$TMPDIR/t10/plan.json"

assert_exit_code "nonexistent task exits 2" 2 \
  "$VALIDATE" --criteria "$TMPDIR/t10/plan.json" --task Z99

assert_exit_code "nonexistent phase exits 2" 2 \
  "$VALIDATE" --criteria "$TMPDIR/t10/plan.json" --phase Z

echo "Test 11: Phase-scope criteria"
write_plan "$TMPDIR/t11/plan.json" '[{"run": "echo phase-ok", "expect_exit": 0, "expect_output": "phase-ok"}]' "phase"
assert_output_contains "phase criteria" "PASS" \
  "$VALIDATE" --criteria "$TMPDIR/t11/plan.json" --phase A
assert_exit_code "phase criteria exits 0" 0 \
  "$VALIDATE" --criteria "$TMPDIR/t11/plan.json" --phase A

echo "Test 12: Plan-scope criteria"
write_plan "$TMPDIR/t12/plan.json" '[{"run": "echo plan-ok", "expect_exit": 0, "expect_output": "plan-ok"}]' "plan"
assert_output_contains "plan criteria" "PASS" \
  "$VALIDATE" --criteria "$TMPDIR/t12/plan.json" --plan
assert_exit_code "plan criteria exits 0" 0 \
  "$VALIDATE" --criteria "$TMPDIR/t12/plan.json" --plan

echo "Test 13: --cwd runs criteria in the given directory"
mkdir -p "$TMPDIR/t13/wt"
touch "$TMPDIR/t13/wt/marker"
write_plan "$TMPDIR/t13/plan.json" '[{"run": "test -f marker", "expect_exit": 0}]' "task"
assert_exit_code "--cwd finds repo-relative file" 0 \
  "$VALIDATE" --criteria "$TMPDIR/t13/plan.json" --task A1 --cwd "$TMPDIR/t13/wt"
assert_exit_code "--cwd accepted before the target flag" 0 \
  "$VALIDATE" --criteria "$TMPDIR/t13/plan.json" --cwd "$TMPDIR/t13/wt" --task A1
assert_exit_code "without --cwd runs in caller's directory" 1 \
  bash -c 'cd "$1" && "$2" --criteria "$3" --task A1' _ "$TMPDIR/t13" "$VALIDATE" "$TMPDIR/t13/plan.json"

echo "Test 14: --cwd applies to phase and plan scope"
mkdir -p "$TMPDIR/t14p/wt" "$TMPDIR/t14l/wt"
touch "$TMPDIR/t14p/wt/marker" "$TMPDIR/t14l/wt/marker"
write_plan "$TMPDIR/t14p/plan.json" '[{"run": "test -f marker", "expect_exit": 0}]' "phase"
write_plan "$TMPDIR/t14l/plan.json" '[{"run": "test -f marker", "expect_exit": 0}]' "plan"
assert_exit_code "--cwd with --phase" 0 \
  "$VALIDATE" --criteria "$TMPDIR/t14p/plan.json" --phase A --cwd "$TMPDIR/t14p/wt"
assert_exit_code "--cwd with --plan" 0 \
  "$VALIDATE" --criteria "$TMPDIR/t14l/plan.json" --plan --cwd "$TMPDIR/t14l/wt"

echo "Test 15: --cwd with a missing directory exits 2 before running criteria"
write_plan "$TMPDIR/t15/plan.json" "$(jq -n --arg f "$TMPDIR/t15-ran" '[{run: ("touch " + $f), expect_exit: 0}]')" "task"
assert_exit_code "missing --cwd dir exits 2" 2 \
  "$VALIDATE" --criteria "$TMPDIR/t15/plan.json" --task A1 --cwd "$TMPDIR/t15/nope"
if [ ! -e "$TMPDIR/t15-ran" ]; then
  echo "PASS: missing --cwd dir runs no criteria"
  ((PASS++)) || true
else
  echo "FAIL: missing --cwd dir runs no criteria (criterion ran anyway)"
  ((FAIL++)) || true
fi
assert_output_contains "missing --cwd dir names the path" "$TMPDIR/t15/nope" \
  "$VALIDATE" --criteria "$TMPDIR/t15/plan.json" --task A1 --cwd "$TMPDIR/t15/nope"
assert_exit_code "--cwd without a value exits 2" 2 \
  "$VALIDATE" --criteria "$TMPDIR/t15/plan.json" --task A1 --cwd

echo "Test 16: --cwd outside --criteria is rejected, not silently ignored"
write_plan "$TMPDIR/t16/plan.json" '[]' "task"
assert_exit_code "--cwd with --schema exits 2" 2 \
  "$VALIDATE" --schema "$TMPDIR/t16/plan.json" --cwd "$TMPDIR/t16"

echo "Test 17: Summary line reports passed/total"
write_plan "$TMPDIR/t17/plan.json" '[{"run": "true", "expect_exit": 0}, {"run": "true", "expect_exit": 0}]' "task"
assert_output_contains "all-pass summary" "task A1: 2/2 criteria passed" \
  "$VALIDATE" --criteria "$TMPDIR/t17/plan.json" --task A1
assert_output_contains "mixed summary" "task A1: 1/2 criteria passed" \
  "$VALIDATE" --criteria "$TMPDIR/t9/plan.json" --task A1
assert_output_contains "warning summary" "task A1: 0/1 criteria passed" \
  "$VALIDATE" --criteria "$TMPDIR/t7/plan.json" --task A1
assert_output_contains "phase summary" "phase A: 1/1 criteria passed" \
  "$VALIDATE" --criteria "$TMPDIR/t11/plan.json" --phase A

echo "Test 18: Empty criteria prints an explicit no-op line"
assert_output_contains "empty summary" "task A1: no criteria defined" \
  "$VALIDATE" --criteria "$TMPDIR/t8/plan.json" --task A1

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
