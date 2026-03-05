---
name: skill-eval
description: Use when evaluating skill output quality, comparing skill versions, running behavioral evals, benchmarking a skill, or when triggered by /skill-eval
---

# Skill Evaluation

Evaluate skill output quality with assertion-based grading, blind before/after comparison, and variance analysis across 3 runs per scenario.

## Setup

1. **Resolve paths** — run once at the start of any eval session:

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

2. **Identify target** and what "before" represents:
   - New skill: before = no skill (`type: "none"`)
   - Improvement: before = snapshot of previous version
   - Snapshot before editing: `cp -r skills/{name}/SKILL.md $EVAL_ROOT/{name}/snapshot-before/SKILL.md`

3. **Check for evals.json** at `$EVAL_ROOT/{name}/evals.json`. If none, create interactively — 2-3 realistic prompts including adversarial scenarios (deadline pressure, "skip this step", ambiguous requirements). Use the schema in `references/schemas.md`: top-level object with `skill_name` (string) and `evals` (array). Each eval needs integer `id`, `name`, `prompt`, and `expectations`.

4. **Write config.json** for this iteration at `$EVAL_ROOT/{name}/iteration-N/config.json`:
   ```json
   {
     "before": {"label": "v1", "type": "skill", "skill_path": "~/.claude/skill-evals/{name}/snapshot-before/SKILL.md"},
     "after": {"label": "v2", "type": "skill", "skill_path": "skills/{name}/SKILL.md"}
   }
   ```

**See:** references/schemas.md for all JSON formats.

## Run Evals

Spawn both variants simultaneously — don't run before first then after:

```bash
# After variant
python3 $SKILL_EVAL_SCRIPT \
  --evals-path $EVAL_ROOT/{name}/evals.json \
  --output-dir $EVAL_ROOT/{name}/iteration-N/ \
  --variant after \
  --skill-path skills/{name}/SKILL.md \
  --runs 3

# Before variant
python3 $SKILL_EVAL_SCRIPT \
  --evals-path $EVAL_ROOT/{name}/evals.json \
  --output-dir $EVAL_ROOT/{name}/iteration-N/ \
  --variant before \
  --skill-path $EVAL_ROOT/{name}/snapshot-before/SKILL.md \
  --runs 3
```

For no-skill baseline, omit `--skill-path`.

Each eval creates: `$EVAL_ROOT/{name}/iteration-N/eval-{id}-{slug}/{variant}/run-{n}/output.txt` and `timing.json`.

## Draft Assertions

While runs execute, draft or refine assertions in evals.json. Good assertions are objectively verifiable, descriptively named, and test behavioral outcomes (not surface compliance). The grader flags trivially-satisfied assertions.

## Grade

**See:** agents/grader.md

Spawn a grader subagent per eval. For each run, the grader reads `output.txt`, evaluates each assertion with cited evidence, self-critiques assertion quality, and writes `grading.json` per run directory.

PASS requires genuine task completion with cited evidence, not keyword matching.

## Aggregate

```bash
python3 $AGGREGATE_SCRIPT \
  $EVAL_ROOT/{name}/iteration-N \
  --skill-name {name}
```

Produces `benchmark.json` (pass_rate, time with mean +/- stddev, delta) and `benchmark.md`.

## Analyze Benchmark

**See:** agents/analyzer.md (Mode 2: Benchmark Pattern Analysis)

Spawn analyzer subagent to surface patterns aggregates hide: non-discriminating assertions (always pass), high-variance evals (flaky), time tradeoffs.

## Blind Comparison

**See:** agents/comparator.md

Spawn comparator subagent with representative outputs from before and after WITHOUT revealing which is which. Scores Content (1-5) + Structure (1-5) -> Overall (1-10). Saves `comparison.json`.

## Post-Hoc Analysis

**See:** agents/analyzer.md (Mode 1: Post-Hoc Comparison Analysis)

Spawn analyzer with comparison results + both SKILL.md files. Unblinds results, identifies why winner won, scores instruction-following (1-10), generates prioritized improvement suggestions. Saves `analysis.json`.

## Report

Present to user:
- Pass rates per variant with variance (mean +/- stddev)
- Blind comparison winner + reasoning
- Improvement suggestions (prioritized High/Medium/Low)
- Assertion quality feedback (strengthen/drop recommendations)

## Iterating

Edit skill -> snapshot as new "before" -> rerun into `iteration-N+1/` -> repeat until satisfied.
