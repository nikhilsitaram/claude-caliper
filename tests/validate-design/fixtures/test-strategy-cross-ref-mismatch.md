# Design: Test Feature

## Problem

The test system needs a fixture for the Test Strategy cross-reference check. Users are affected because tests can't run without one. Consequences: test suite is incomplete.

## Goal

Provide a fixture for the Test Strategy → Implementation Approach cross-reference rule.

## Success Criteria

- The validator emits `test_strategy_cross_ref` when a path in Test Strategy is missing from Implementation Approach
- The fixture demonstrates the negative case for the new rule

## Architecture

The feature adds `src/handler.ts` for request handling and `src/validator.ts` for input validation. The pipeline is exercised end-to-end by `tests/handler.test.ts`.

## Test Strategy

The handler → validator seam is exercised by `tests/handler.test.ts`, which posts a request to the real handler and asserts the validator runs without mocks. Failure mode caught: validator signature drift.

## Key Decisions

- **Use TypeScript over JavaScript.** Gained: type safety. Given up: build step complexity. Rejected: plain JS — too error-prone for validation logic.

## Non-Goals

- **Performance optimization at this stage** — The initial implementation prioritizes correctness over speed because premature optimization would complicate the validation logic without measurable benefit.
- **Multi-tenant support** — Current architecture assumes single-tenant deployment because the user base does not require isolation boundaries yet.

## Implementation Approach

Create `src/handler.ts` and `src/validator.ts`. Both get unit tests.

## Scope Estimate

Single phase, 3 tasks. Recommended tier: Medium (one coherent change, no genuine parallelism).
