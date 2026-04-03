#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
pass=0
fail=0

check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "PASS: $desc"
    pass=$((pass + 1))
  else
    echo "FAIL: $desc"
    fail=$((fail + 1))
  fi
}

check "bin/validate-plan exists" test -f "$REPO_ROOT/bin/validate-plan"
check "bin/caliper-settings exists" test -f "$REPO_ROOT/bin/caliper-settings"
check "bin/validate-plan is executable" test -x "$REPO_ROOT/bin/validate-plan"
check "bin/caliper-settings is executable" test -x "$REPO_ROOT/bin/caliper-settings"
check "scripts/ directory does not exist" test ! -d "$REPO_ROOT/scripts"
check_shebang() {
  local line
  line="$(head -1 "$1")"
  test "$line" = "#!/usr/bin/env bash"
}
check "bin/validate-plan has bash shebang" check_shebang "$REPO_ROOT/bin/validate-plan"
check "bin/caliper-settings has bash shebang" check_shebang "$REPO_ROOT/bin/caliper-settings"

echo ""
echo "Results: $pass passed, $fail failed"
test "$fail" -eq 0
