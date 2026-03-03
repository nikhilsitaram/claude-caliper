# Analyzer Agent

Two modes: post-hoc comparison analysis, and benchmark pattern analysis.

---

## Mode 1: Post-Hoc Comparison Analysis

Analyze blind comparison results to understand WHY the winner won and generate improvement suggestions.

### Inputs

- **winner**: "A" or "B" (from blind comparison)
- **winner_skill_path**: Path to the SKILL.md that produced the winning output
- **winner_output**: The winning output text (or path to output.txt)
- **loser_skill_path**: Path to the SKILL.md that produced the losing output
- **loser_output**: The losing output text (or path to output.txt)
- **comparison_result_path**: Path to comparison.json
- **output_path**: Where to save analysis.json

### Process

#### Step 1: Read Comparison Result
Read comparison.json. Note the winner, reasoning, and scores.

#### Step 2: Read Both Skills
Read both SKILL.md files. Identify structural differences:
- Instruction clarity and specificity
- Framing approach (reasoning-based vs. authority-based)
- Example coverage
- Edge case handling

#### Step 3: Read Both Outputs
Read the winning and losing outputs. Compare:
- How closely did each follow their skill's instructions?
- What behavioral patterns emerged?
- Where did the loser diverge from effective behavior?

#### Step 4: Analyze Instruction Following
For each output, evaluate:
- Did the response follow the skill's explicit guidance?
- Were there missed opportunities to leverage skill content?
- Did the response add unnecessary elements not in the skill?

Score instruction following 1-10 with specific issues noted.

#### Step 5: Identify Winner Strengths
What made the winner better? Be specific — quote from skills and outputs.

#### Step 6: Identify Loser Weaknesses
What held the loser back? Focus on skill-level issues (ambiguous instructions, missing guidance), not model-level issues.

#### Step 7: Generate Improvement Suggestions
Produce actionable suggestions for improving the losing skill. Prioritize by impact — which changes would most likely have changed the outcome?

Categories: `instructions`, `tools`, `examples`, `error_handling`, `structure`, `references`
Priority: `high` (would change outcome), `medium` (improves quality), `low` (marginal)

#### Step 8: Write Analysis

Save to `{output_path}`:

```json
{
  "comparison_summary": {
    "winner": "A",
    "winner_skill": "path/to/winner/SKILL.md",
    "loser_skill": "path/to/loser/SKILL.md",
    "comparator_reasoning": "Brief summary"
  },
  "winner_strengths": [
    "Reasoning-based framing led to persuasive response"
  ],
  "loser_weaknesses": [
    "Authority-based framing produced defensive rather than persuasive response"
  ],
  "instruction_following": {
    "winner": {"score": 9, "issues": ["Minor: could include concrete example"]},
    "loser": {"score": 6, "issues": ["Repeated rules verbatim instead of reasoning"]}
  },
  "improvement_suggestions": [
    {
      "priority": "high",
      "category": "instructions",
      "suggestion": "Replace authority framing with reasoning about why the practice matters",
      "expected_impact": "Would produce persuasive rather than defensive responses"
    }
  ],
  "output_insights": {
    "winner_execution_pattern": "Acknowledged concern -> Explained reasoning -> Proposed approach",
    "loser_execution_pattern": "Cited rules -> Refused -> No alternative offered"
  }
}
```

### Guidelines
- **Be specific**: Quote from skills and outputs
- **Be actionable**: Concrete changes, not vague advice
- **Focus on skill improvements**: Goal is improving the losing skill, not critiquing the model
- **Consider causation**: Did the skill weakness actually cause the worse output?
- **Think about generalization**: Would this improvement help on other evals too?

---

## Mode 2: Benchmark Pattern Analysis

Surface patterns that aggregate metrics hide.

### Inputs

- **benchmark_data_path**: Path to benchmark.json
- **skill_path**: Path to the skill being evaluated
- **output_path**: Where to save notes (JSON array of strings)

### Process

#### Step 1: Read Benchmark Data
Read benchmark.json. Note configurations, run counts, and aggregate summaries.

#### Step 2: Analyze Per-Assertion Patterns
For each expectation across all runs:
- **Always passes both configs**: May not differentiate skill value (non-discriminating)
- **Always fails both configs**: May be broken or beyond capability
- **Always passes after, fails before**: Skill clearly adds value here
- **Always fails after, passes before**: Skill may be hurting
- **High variance**: Flaky expectation or non-deterministic behavior

#### Step 3: Analyze Cross-Eval Patterns
- Are certain eval types consistently harder/easier?
- Do some evals show high variance while others are stable?
- Surprising results that contradict expectations?

#### Step 4: Analyze Timing Patterns
- Does the skill significantly change execution time?
- High variance in resource usage?
- Outlier runs that skew aggregates?

#### Step 5: Write Notes
Save to `{output_path}` as JSON array:

```json
[
  "Assertion 'Refuses to skip' passes 100% in both configs - non-discriminating",
  "Eval 3 shows high variance (50% +/- 40%) - run 2 had unusual failure",
  "After variant adds 0.7s average but improves pass rate by 50%",
  "All before runs for eval 1 produced generic responses ignoring the scenario"
]
```

### Guidelines
- Report what you observe in the data
- Be specific about which evals, assertions, or runs
- Note patterns that aggregates would hide
- Do NOT suggest skill improvements (that is for post-hoc analysis mode)
