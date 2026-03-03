# JSON Schemas

Data schemas for skill-eval. All files live under `.skill-evals/{skill-name}/`.

---

## evals.json

Eval prompts and assertions. Located at `.skill-evals/{skill-name}/evals.json`.

```json
{
  "skill_name": "test-driven-development",
  "evals": [
    {
      "id": 1,
      "name": "deadline-pressure",
      "prompt": "I have a tight deadline, can we skip tests?",
      "expectations": [
        "Refuses to skip TDD",
        "Explains why deadline pressure increases TDD value",
        "Does not propose writing tests after implementation"
      ]
    }
  ]
}
```

**Fields:**
- `skill_name`: Name matching the skill directory
- `evals[].id`: Unique integer identifier
- `evals[].name`: Descriptive name (used in directory naming)
- `evals[].prompt`: The task prompt sent to `claude -p`
- `evals[].expectations`: Verifiable behavioral assertions

---

## config.json

Variant definitions for an iteration. Located at `.skill-evals/{skill-name}/iteration-N/config.json`.

```json
{
  "before": {
    "label": "v1-authority",
    "type": "skill",
    "skill_path": ".skill-evals/tdd/snapshot-before/SKILL.md"
  },
  "after": {
    "label": "v2-reasoning",
    "type": "skill",
    "skill_path": "skills/test-driven-development/SKILL.md"
  }
}
```

**Fields:**
- `before`/`after`: Variant definitions
- `label`: Human-readable version name
- `type`: `"skill"` (load SKILL.md as system prompt) or `"none"` (no skill baseline)
- `skill_path`: Path to SKILL.md (omit when type is "none")

---

## eval_metadata.json

Per-eval metadata. Located at `.skill-evals/{skill-name}/iteration-N/eval-{id}-{slug}/eval_metadata.json`.

```json
{
  "eval_id": 1,
  "eval_name": "deadline-pressure",
  "prompt": "I have a tight deadline, can we skip tests?",
  "expectations": [
    "Refuses to skip TDD",
    "Explains why deadline pressure increases TDD value"
  ]
}
```

---

## timing.json

Per-run timing. Located at `.../run-{n}/timing.json`.

```json
{
  "duration_ms": 2341,
  "wall_time_seconds": 2.5,
  "cost_usd": 0.003,
  "num_turns": 1,
  "is_error": false,
  "total_duration_seconds": 2.5
}
```

**Fields:**
- `duration_ms`: From `claude -p --output-format json` response
- `wall_time_seconds`: Python-measured wall clock time
- `cost_usd`: From claude response (if available)
- `total_duration_seconds`: Same as wall_time_seconds (compatibility with aggregate script)
- `is_error`: Whether the run errored

---

## grading.json

Per-run grading results. Located at `.../run-{n}/grading.json`.

```json
{
  "expectations": [
    {
      "text": "Refuses to skip TDD",
      "passed": true,
      "evidence": "Response states: 'Skipping tests under deadline pressure is exactly when bugs slip through...'"
    }
  ],
  "summary": {
    "passed": 2,
    "failed": 1,
    "total": 3,
    "pass_rate": 0.67
  },
  "timing": {
    "total_duration_seconds": 2.5
  },
  "claims": [
    {
      "claim": "Response suggests writing tests first",
      "type": "process",
      "verified": true,
      "evidence": "Step 1 in response explicitly says 'write the failing test first'"
    }
  ],
  "eval_feedback": {
    "suggestions": [
      {
        "assertion": "Refuses to skip TDD",
        "reason": "Too easy to satisfy — any mention of tests would pass. Consider: 'Explicitly refuses the request to skip, not just redirects to testing'"
      }
    ],
    "overall": "Assertions check presence but not reasoning quality."
  }
}
```

**Required fields in expectations array:** `text`, `passed`, `evidence` — the aggregate script depends on these exact names.

---

## benchmark.json

Aggregated statistics. Located at `.skill-evals/{skill-name}/iteration-N/benchmark.json`.

```json
{
  "metadata": {
    "skill_name": "test-driven-development",
    "skill_path": "skills/test-driven-development/SKILL.md",
    "timestamp": "2026-03-03T21:00:00Z",
    "evals_run": [1, 2, 3],
    "runs_per_configuration": 3
  },
  "runs": [
    {
      "eval_id": 1,
      "configuration": "after",
      "run_number": 1,
      "result": {
        "pass_rate": 0.85,
        "passed": 6,
        "failed": 1,
        "total": 7,
        "time_seconds": 2.5,
        "tokens": 0,
        "tool_calls": 0,
        "errors": 0
      },
      "expectations": [
        {"text": "...", "passed": true, "evidence": "..."}
      ],
      "notes": []
    }
  ],
  "run_summary": {
    "after": {
      "pass_rate": {"mean": 0.85, "stddev": 0.05, "min": 0.80, "max": 0.90},
      "time_seconds": {"mean": 2.5, "stddev": 0.3, "min": 2.1, "max": 2.8},
      "tokens": {"mean": 0, "stddev": 0, "min": 0, "max": 0}
    },
    "before": {
      "pass_rate": {"mean": 0.35, "stddev": 0.08, "min": 0.28, "max": 0.45},
      "time_seconds": {"mean": 1.8, "stddev": 0.2, "min": 1.5, "max": 2.0},
      "tokens": {"mean": 0, "stddev": 0, "min": 0, "max": 0}
    },
    "delta": {
      "pass_rate": "+0.50",
      "time_seconds": "+0.7",
      "tokens": "+0"
    }
  },
  "notes": []
}
```

---

## comparison.json

Blind comparator output. Located at `.skill-evals/{skill-name}/iteration-N/comparison.json`.

```json
{
  "winner": "A",
  "reasoning": "Output A provides a nuanced explanation of why TDD matters under deadline pressure. Output B simply states tests should be written without addressing the deadline concern.",
  "rubric": {
    "A": {
      "content": {"correctness": 5, "completeness": 5, "accuracy": 4},
      "structure": {"organization": 4, "formatting": 4, "usability": 4},
      "content_score": 4.7,
      "structure_score": 4.0,
      "overall_score": 8.7
    },
    "B": {
      "content": {"correctness": 3, "completeness": 2, "accuracy": 3},
      "structure": {"organization": 3, "formatting": 3, "usability": 3},
      "content_score": 2.7,
      "structure_score": 3.0,
      "overall_score": 5.7
    }
  },
  "output_quality": {
    "A": {
      "score": 9,
      "strengths": ["Addresses deadline concern directly", "Explains TDD value proposition"],
      "weaknesses": ["Slightly verbose"]
    },
    "B": {
      "score": 6,
      "strengths": ["Mentions testing"],
      "weaknesses": ["Does not address deadline pressure", "Generic response"]
    }
  }
}
```

---

## analysis.json

Post-hoc analyzer output. Located at `.skill-evals/{skill-name}/iteration-N/analysis.json`.

```json
{
  "comparison_summary": {
    "winner": "A",
    "winner_skill": "skills/test-driven-development/SKILL.md",
    "loser_skill": ".skill-evals/tdd/snapshot-before/SKILL.md",
    "comparator_reasoning": "Output A provides nuanced explanation under deadline pressure"
  },
  "winner_strengths": [
    "Reasoning-based framing ('you optimize for coherence, not correctness') led to persuasive response",
    "Addressed the emotional context (deadline pressure) directly"
  ],
  "loser_weaknesses": [
    "Authority-based framing ('Iron Law', 'NO EXCEPTIONS') produced defensive rather than persuasive response",
    "Did not acknowledge the deadline concern"
  ],
  "instruction_following": {
    "winner": {"score": 9, "issues": ["Minor: could have included a concrete example"]},
    "loser": {"score": 7, "issues": ["Repeated 'never skip' verbatim instead of reasoning about it"]}
  },
  "improvement_suggestions": [
    {
      "priority": "high",
      "category": "instructions",
      "suggestion": "Replace authority framing with reasoning about why TDD saves time under pressure",
      "expected_impact": "Would produce persuasive rather than defensive responses"
    }
  ],
  "output_insights": {
    "winner_execution_pattern": "Acknowledged concern -> Explained reasoning -> Proposed TDD approach",
    "loser_execution_pattern": "Cited rules -> Refused request -> Offered no alternative"
  }
}
```
