# skill-eval

Eval framework for measuring and comparing Claude Code skill behavior. Runs skills as system prompts against realistic prompts, grades behavioral assertions, and produces statistical benchmarks across multiple runs.

## When to use

- Before editing a skill: snapshot the current version so you have a baseline
- After editing a skill: compare before/after to confirm behavioral improvement
- When a skill triggers inconsistently: measure variance across runs to identify flakiness
- When adding a new skill: verify it actually changes behavior vs. no-skill baseline

## How it works

The eval pipeline has five stages:

```text
Prompts (evals.json)
        |
        v
  run_eval.py  ---->  output.txt + timing.json  (per run)
        |
        v
  Grader subagent  -->  grading.json  (per run)
        |
        v
  aggregate_benchmark.py  -->  benchmark.json + benchmark.md
        |
        v
  Analyzer + Comparator subagents  -->  analysis.json + comparison.json
```

**run_eval.py** spawns `claude -p` with the SKILL.md loaded as a system prompt, sends each eval prompt, and captures the text output and timing. It runs with `CLAUDE_SKIP_MEMORY=1` and `--allowedTools ""` so each run is clean, fast, and unaffected by session state.

**Grader subagent** reads each `output.txt` and evaluates it against the assertions in `evals.json`. It cites specific evidence for every PASS/FAIL verdict and critiques the assertions themselves — flagging ones that are trivially satisfied.

**aggregate_benchmark.py** reads all `grading.json` files and computes mean ± stddev for pass rate, time, and tokens across runs and variants. Produces `benchmark.json` (machine-readable) and `benchmark.md` (human-readable table).

**Analyzer** (two modes):
- *Benchmark pattern analysis*: surfaces what aggregate stats hide — non-discriminating assertions, flaky evals, outlier runs
- *Post-hoc comparison*: after unblinding, explains why the winner won and generates prioritized improvement suggestions

**Comparator**: reads outputs labeled A and B (no info on which variant) and scores them on Content + Structure rubrics to pick a winner without bias.

## File layout

Eval data lives at `~/.claude/skill-evals/` — outside any project repo, so it works regardless of CWD and persists across plugin upgrades.

```text
~/.claude/skill-evals/
└── {skill-name}/
    ├── evals.json                     # eval prompts + assertions (shared across iterations)
    ├── snapshot-before/               # copy of SKILL.md before editing
    │   └── SKILL.md
    └── iteration-N/
        ├── config.json                # variant definitions (before/after labels + paths)
        ├── benchmark.json             # aggregated stats (auto-generated)
        ├── benchmark.md               # human-readable summary table (auto-generated)
        ├── comparison.json            # blind comparator output (written by subagent)
        ├── analysis.json              # post-hoc analysis output (written by subagent)
        └── eval-{id}-{slug}/
            ├── eval_metadata.json     # prompt + assertions for this eval (auto-generated)
            ├── before/
            │   ├── run-1/
            │   │   ├── output.txt     # raw claude -p response
            │   │   ├── timing.json    # wall time, cost, error status
            │   │   └── grading.json   # grader verdicts + evidence
            │   ├── run-2/
            │   └── run-3/
            └── after/
                ├── run-1/
                ├── run-2/
                └── run-3/
```

## evals.json format

```json
{
  "skill_name": "test-driven-development",
  "evals": [
    {
      "id": 1,
      "name": "deadline-pressure",
      "prompt": "I have a tight deadline — can we skip writing tests this time?",
      "expectations": [
        "Refuses to skip TDD",
        "Explains why deadline pressure increases the value of TDD, not decreases it",
        "Does not propose writing tests after implementation as a compromise"
      ]
    }
  ]
}
```

`id` must be an integer. `name` becomes part of the directory name (slugified). Include at least one adversarial scenario — prompts that give the model a plausible reason to skip a required behavior. These are the most discriminating evals.

## config.json format

```json
{
  "before": {
    "label": "v1-authority-framing",
    "type": "skill",
    "skill_path": ".skill-evals/test-driven-development/snapshot-before/SKILL.md"
  },
  "after": {
    "label": "v2-reasoning-framing",
    "type": "skill",
    "skill_path": "skills/test-driven-development/SKILL.md"
  }
}
```

Set `type` to `"none"` (and omit `skill_path`) for a no-skill baseline.

## Running evals

First, resolve the script paths (do this once per session):

```bash
PLUGIN_ROOT=$(python3 -c "
import json, os
p = json.load(open(os.path.expanduser('~/.claude/plugins/installed_plugins.json')))
print(p['plugins']['claude-caliper@claude-caliper'][0]['installPath'])
")
EVAL_ROOT=~/.claude/skill-evals
SKILL_EVAL_SCRIPT=$PLUGIN_ROOT/skills/skill-eval/scripts/run_eval.py
AGGREGATE_SCRIPT=$PLUGIN_ROOT/skills/skill-eval/scripts/aggregate_benchmark.py
```

Then spawn both variants simultaneously — they write to separate directories and won't conflict:

```bash
# Run after variant
python3 $SKILL_EVAL_SCRIPT \
  --evals-path $EVAL_ROOT/test-driven-development/evals.json \
  --output-dir $EVAL_ROOT/test-driven-development/iteration-1/ \
  --variant after \
  --skill-path skills/test-driven-development/SKILL.md \
  --runs 3

# Run before variant (parallel — run both at once)
python3 $SKILL_EVAL_SCRIPT \
  --evals-path $EVAL_ROOT/test-driven-development/evals.json \
  --output-dir $EVAL_ROOT/test-driven-development/iteration-1/ \
  --variant before \
  --skill-path $EVAL_ROOT/test-driven-development/snapshot-before/SKILL.md \
  --runs 3
```

Options:
- `--runs N` — runs per eval (default: 3; use 1 for quick smoke tests)
- `--model MODEL` — override the model (default: system default)
- `--timeout N` — seconds per run before giving up (default: 120)
- Omit `--skill-path` entirely for a no-skill baseline run

While runs execute, draft or refine assertions in `evals.json`. Good assertions are specific enough that they can only pass if the model genuinely performed the behavior — not just mentioned the keyword.

## Grading

After runs complete, spawn a grader subagent per eval run. Point it at the run directory and tell it the output path for `grading.json`. See `agents/grader.md` for the grader's full instructions.

The grader evaluates each assertion with cited evidence, flags trivially-satisfied assertions, and extracts implicit behavioral claims for verification. PASS requires genuine compliance, not keyword matching.

## Aggregating

```bash
python3 $AGGREGATE_SCRIPT \
  $EVAL_ROOT/test-driven-development/iteration-1/ \
  --skill-name test-driven-development
```

Writes `benchmark.json` and `benchmark.md` into the iteration directory. The markdown table shows pass rate, time, and delta between before and after:

```markdown
| Metric    | Before     | After      | Delta  |
|-----------|------------|------------|--------|
| Pass Rate | 35% ± 8%   | 84% ± 12%  | +0.49  |
| Time      | 1.8s ± 0.2 | 2.5s ± 0.3 | +0.7s  |
```

## Blind comparison and analysis

See `agents/comparator.md` — spawn a comparator subagent with representative outputs from before and after, labeled A and B without revealing which is which. It scores on Content + Structure rubrics and picks a winner. Saves `comparison.json`.

See `agents/analyzer.md` Mode 1 — spawn an analyzer subagent with the comparison result and both SKILL.md files. It identifies why the winner won, scores instruction-following, and generates prioritized improvement suggestions. Saves `analysis.json`.

Mode 2 of the analyzer reads `benchmark.json` and surfaces patterns the aggregates hide: non-discriminating assertions (always pass both configs), flaky evals (high variance), and outlier runs that skew averages.

## Suggestions for use

**Iterating on a skill:** snapshot → edit → run iteration-1 → grade → aggregate → analyze → edit → snapshot-before = iteration-1 result → run iteration-2

**Quick sanity check:** `--runs 1` with a single adversarial eval to verify the skill doesn't regress on its most important behavior. Grade manually.

**Evaluating a new skill:** use `type: "none"` as the before variant to measure how much the skill actually changes behavior vs. the model's default. If pass rates are similar, the skill content isn't adding value.

**Writing better assertions:** adversarial evals (deadline pressure, "this is a special case", "just this once") are the most discriminating signal. Low adversarial pass rate reveals enforcement gaps that positive evals miss entirely. The grader's assertion critique feedback surfaces assertions to tighten or drop.

**Interpreting variance:** high stddev (> ±20%) on an assertion usually means either the assertion is ambiguously worded or the behavior is genuinely non-deterministic. Run more iterations or sharpen the assertion before drawing conclusions.

## Files reference

| File | Written by | Purpose |
|------|-----------|---------|
| `evals.json` | Human | Eval prompts and assertions |
| `config.json` | Human | Variant definitions |
| `output.txt` | run_eval.py | Raw claude -p response text |
| `timing.json` | run_eval.py | Wall time, cost, error status |
| `eval_metadata.json` | run_eval.py | Prompt + assertions per eval |
| `grading.json` | Grader subagent | PASS/FAIL verdicts with evidence |
| `benchmark.json` | aggregate_benchmark.py | Aggregated stats (mean ± stddev) |
| `benchmark.md` | aggregate_benchmark.py | Human-readable summary table |
| `comparison.json` | Comparator subagent | Blind A/B rubric scores + winner |
| `analysis.json` | Analyzer subagent | Why winner won + improvement suggestions |
