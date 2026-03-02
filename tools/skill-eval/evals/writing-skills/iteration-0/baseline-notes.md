# Baseline Notes — Iteration 0

**Note:** Baseline evals could not be run via `claude -p` due to nested session guard
(Claude Code cannot launch inside another Claude Code session). Baseline analysis
performed manually by reviewing the current SKILL.md (3,204 words) against eval
expectations.

## Eval 1: New skill creation (SQL migrations)

**Expected behaviors from current SKILL.md:**
- TDD/testing: Strong coverage. "The Iron Law" section, TDD Mapping table, RED-GREEN-REFACTOR section, and the Skill Creation Checklist all emphasize testing first. Agent would likely mention TDD.
- SKILL.md structure: Explicitly documented with YAML frontmatter, body sections template. Agent would propose structure.
- Description field: CSO section (lines 140-267) covers description in detail. Agent would discuss triggering conditions.
- Conciseness: Token Efficiency section (lines 213-266) covers keeping SKILL.md concise. Agent would suggest supporting files for heavy content.

**Verdict:** All 4 expectations would likely PASS with current skill.

## Eval 2: Skill editing (structured logs section)

**Expected behaviors from current SKILL.md:**
- Testing before edit: "The Iron Law" explicitly covers edits: "This applies to NEW skills AND EDITS to existing skills." Agent would mention testing.
- Supporting file consideration: File Organization section and Token Efficiency section discuss when to use supporting files. Agent would consider whether new content belongs in SKILL.md or supporting file.
- Word count: Token Efficiency section mentions target word counts. Agent would check current word count.

**Verdict:** All 3 expectations would likely PASS with current skill.

## Eval 3: Pressure to skip testing

**Expected behaviors from current SKILL.md:**
- Does not skip: "Common Rationalizations" table (lines 444-457) explicitly addresses skipping excuses. The Iron Law section is emphatic. Agent would not skip.
- Explains WHY: The persuasion-principles.md reference, the rationalization table, and Iron Law section explain reasoning. Agent would explain why testing matters.
- Still helps: The skill doesn't say "refuse to help" — it says "test first, then write." Agent would still help create the skill.

**Verdict:** All 3 expectations would likely PASS with current skill.

## Overall Assessment

The current 3,204-word SKILL.md would likely pass all eval expectations. The key
question for the reduction is whether the much shorter version (~500 words) can
maintain the same behavioral influence, particularly around:
1. Testing discipline (the strongest signal in the current skill)
2. Description field optimization (CSO section is detailed and influential)
3. Word count awareness (explicitly called out in Token Efficiency)
