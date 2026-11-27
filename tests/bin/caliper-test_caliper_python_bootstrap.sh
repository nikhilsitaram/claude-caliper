#!/usr/bin/env bash
set -euo pipefail

# uv, python3 and the venv's pip are stubs that log their argv, so nothing
# installs and nothing touches the network. PATH is narrowed to the stubs plus
# /usr/bin:/bin, which keeps a real uv (usually ~/.local/bin or Homebrew) out.

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/caliper-python-bootstrap"

pass=0
fail=0
TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT
BASE="$(cd "$TMPDIR_BASE" && pwd -P)"
LOG="$BASE/log"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1   # no user excludesFile hiding artifacts

check_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "PASS: $desc"; pass=$((pass + 1))
  else
    echo "FAIL: $desc (expected=[$expected] actual=[$actual])"; fail=$((fail + 1))
  fi
}

# uv stub: `uv venv <path>` makes the venv (with uv's own self-ignoring
# .gitignore); `uv pip …` logs, and records the VIRTUAL_ENV it saw. UV_FAIL
# makes pip installs fail; UV_EGG makes them leave a setuptools-style
# p.egg-info/ behind, and UV_STRAY a stray top-level file.
UV_BIN="$BASE/uvbin"
mkdir -p "$UV_BIN"
cat > "$UV_BIN/uv" <<EOF
#!/usr/bin/env bash
echo "uv \$* [cwd=\$(pwd -P)]" >> "$LOG"
if [[ "\$1" == venv ]]; then mkdir -p "\$2/bin" && echo '*' > "\$2/.gitignore"; fi
if [[ "\$1" == pip ]]; then
  echo "VIRTUAL_ENV=\${VIRTUAL_ENV:-}" >> "$BASE/venvlog"
  [[ -z "\${UV_FAIL:-}" ]] || { echo "uv boom" >&2; exit 1; }
  [[ -z "\${UV_EGG:-}" ]] || { mkdir -p p.egg-info && echo x > p.egg-info/PKG-INFO; }
  [[ -z "\${UV_STRAY:-}" ]] || echo x > stray.txt
fi
exit 0
EOF
# python3 stub: `python3 -m venv <path>` makes a venv with a logging pip and,
# like Python < 3.13, no .gitignore.
PY_BIN="$BASE/pybin"
mkdir -p "$PY_BIN"
cat > "$PY_BIN/python3" <<EOF
#!/usr/bin/env bash
echo "python3 \$* [cwd=\$(pwd -P)]" >> "$LOG"
if [[ "\$1 \$2" == "-m venv" ]]; then
  mkdir -p "\$3/bin"
  printf '#!/usr/bin/env bash\necho "pip \$*" >> "$LOG"\n' > "\$3/bin/pip"
  chmod +x "\$3/bin/pip"
fi
EOF
chmod +x "$UV_BIN/uv" "$PY_BIN/python3"

# Sets RC. $1 is the PATH prefix; rest are args. The script's own output is
# dropped: the stubs' log is what the checks read.
run() {
  local prefix="$1"; shift
  : > "$LOG"
  RC=0
  PATH="$prefix:/usr/bin:/bin" "$SCRIPT" "$@" >/dev/null 2>&1 || RC=$?
}
proj() {  # <name> [pyproject|requirements|both|tooling]... -> fresh dir
  local d="$BASE/$1"; shift
  rm -rf "$d"; mkdir -p "$d"
  for kind in "$@"; do
    case "$kind" in
      pyproject) printf '[project]\nname = "p"\n' > "$d/pyproject.toml" ;;
      tooling) printf '[tool.ruff]\nline-length = 100\n' > "$d/pyproject.toml" ;;
      requirements) echo "requests" > "$d/requirements.txt" ;;
    esac
  done
  echo "$d"
}

echo "=== uv: pyproject [project] ==="
D="$(proj uvp pyproject)"
run "$UV_BIN:$PY_BIN" "$D"
check_eq "exit 0" 0 "$RC"
check_eq "venv created at the target, then editable dev install into it" \
  "uv venv .venv [cwd=$D]
uv pip install --python .venv/bin/python -e .[dev] [cwd=$D]" "$(cat "$LOG")"
check_eq "uv's own .gitignore kept" '*' "$(cat "$D/.venv/.gitignore")"

echo "=== uv: inherited VIRTUAL_ENV can't redirect the install ==="
D="$(proj uvve pyproject)"
: > "$BASE/venvlog"
VIRTUAL_ENV="$BASE/elsewhere" run "$UV_BIN:$PY_BIN" "$D"
check_eq "exit 0" 0 "$RC"
check_eq "installer runs with VIRTUAL_ENV cleared" "VIRTUAL_ENV=" "$(cat "$BASE/venvlog")"

echo "=== build artifacts in a git worktree don't read as untracked ==="
D="$(proj egg pyproject)"
git -C "$D" init -q
git -C "$D" add -A
git -C "$D" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -q -m init
mkdir -p "$D/preexisting" && echo x > "$D/preexisting/f"   # untracked before: not ours to hide
UV_EGG=1 run "$UV_BIN:$PY_BIN" "$D"
check_eq "exit 0" 0 "$RC"
check_eq "only the pre-existing untracked dir remains" "?? preexisting/" "$(git -C "$D" status --porcelain)"
check_eq "egg-info ignores itself" '*' "$(cat "$D/p.egg-info/.gitignore" 2>/dev/null)"
rm -rf "$D/preexisting"
D2="$(proj stray pyproject)"
git -C "$D2" init -q
git -C "$D2" add -A
git -C "$D2" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -q -m init
OUT="$(UV_STRAY=1 PATH="$UV_BIN:/usr/bin:/bin" "$SCRIPT" "$D2" 2>&1)" || true
check_eq "a new untracked file is named in a warning" 1 "$(grep -c 'WARNING.*stray.txt' <<<"$OUT")"

echo "=== uv: requirements.txt only ==="
D="$(proj uvr requirements)"
run "$UV_BIN:$PY_BIN" "$D"
check_eq "exit 0" 0 "$RC"
check_eq "installs the requirements file" \
  "uv venv .venv [cwd=$D]
uv pip install --python .venv/bin/python -r requirements.txt [cwd=$D]" "$(cat "$LOG")"

echo "=== uv: both manifests share one venv ==="
D="$(proj uvb pyproject requirements)"
run "$UV_BIN:$PY_BIN" "$D"
check_eq "exit 0" 0 "$RC"
check_eq "venv created once" 1 "$(grep -c '^uv venv' "$LOG")"
check_eq "both installs ran" 2 "$(grep -c '^uv pip install' "$LOG")"

echo "=== uv: existing venv is reused ==="
D="$(proj uvx pyproject)"
mkdir -p "$D/.venv/bin"
run "$UV_BIN:$PY_BIN" "$D"
check_eq "exit 0" 0 "$RC"
check_eq "no new venv" 0 "$(grep -c '^uv venv' "$LOG" || true)"
check_eq "no .gitignore written into a venv it didn't make" no "$([[ -e "$D/.venv/.gitignore" ]] && echo yes || echo no)"

echo "=== uv: failed install exits nonzero ==="
D="$(proj uvf pyproject)"
UV_FAIL=1 run "$UV_BIN:$PY_BIN" "$D"
check_eq "exit nonzero" 1 "$((RC != 0))"

echo "=== no uv: python3 -m venv + pip ==="
D="$(proj pyp pyproject requirements)"
run "$PY_BIN" "$D"
check_eq "exit 0" 0 "$RC"
check_eq "stdlib venv, then the venv's pip for each manifest" \
  "python3 -m venv .venv [cwd=$D]
pip install -e .[dev]
pip install -r requirements.txt" "$(cat "$LOG")"
check_eq "self-ignoring .gitignore added (Python < 3.13 writes none)" '*' "$(cat "$D/.venv/.gitignore")"

echo "=== no Python manifest is a no-op ==="
for kind in none tooling; do
  if [[ "$kind" == none ]]; then D="$(proj none)"; else D="$(proj tool tooling)"; fi
  run "$UV_BIN:$PY_BIN" "$D"
  check_eq "$kind: exit 0" 0 "$RC"
  check_eq "$kind: nothing run" "" "$(cat "$LOG")"
  check_eq "$kind: no venv" no "$([[ -e "$D/.venv" ]] && echo yes || echo no)"
done

echo "=== --like <parent>: mirrors only a real root .venv ==="
PARENT_DIR="$BASE/parent"
mkdir -p "$PARENT_DIR"
D="$(proj like pyproject)"
run "$UV_BIN" --like "$PARENT_DIR" "$D"
check_eq "parent without .venv: exit 0" 0 "$RC"
check_eq "parent without .venv: nothing run" "" "$(cat "$LOG")"
mkdir -p "$BASE/shared-venv"
ln -s "$BASE/shared-venv" "$PARENT_DIR/.venv"
run "$UV_BIN" --like "$PARENT_DIR" "$D"
check_eq "symlinked parent .venv: exit 0" 0 "$RC"
check_eq "symlinked parent .venv: nothing run" "" "$(cat "$LOG")"
rm "$PARENT_DIR/.venv"
mkdir -p "$PARENT_DIR/.venv"
run "$UV_BIN" --like "$PARENT_DIR" "$D"
check_eq "real parent .venv: exit 0" 0 "$RC"
check_eq "real parent .venv: target bootstrapped" 1 "$(grep -c '^uv venv' "$LOG")"

echo "=== usage ==="
run "$UV_BIN"
check_eq "no args: exit 1" 1 "$RC"
run "$UV_BIN" "$BASE/missing"
check_eq "missing dir: exit 1" 1 "$RC"
run "$UV_BIN" --like "$PARENT_DIR"
check_eq "--like without a dir: exit 1" 1 "$RC"
run "$UV_BIN" --like "$BASE/missing" "$D"
check_eq "--like a missing parent: exit 1" 1 "$RC"

echo ""
echo "Results: $pass passed, $fail failed"
test "$fail" -eq 0
