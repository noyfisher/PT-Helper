/**
 * Cross-model verification response contract (H1).
 *
 * The client pairs verdicts to exercises POSITIONALLY. Before this, crossVerify
 * did `JSON.parse(content)` and forwarded the object verbatim — so a model that
 * dropped one mid-list result shifted every later verdict onto the wrong
 * exercise, and an exercise flagged unsafe could surface as verified. Length
 * catches drops; only the echoed 1-based `index` catches reordering.
 *
 * Deliberately strict: no lenient defaults for `index`, because a silently
 * defaulted index reintroduces exactly the misattribution it exists to prevent.
 */

import { crossVerifySchema } from "../src/response-schemas";

const ok = { index: 1, safe: true, confidence: 0.9, reasoning: "fine", concerns: [] };

describe("crossVerifySchema", () => {
  it("accepts a well-formed result", () => {
    expect(crossVerifySchema.safeParse({ results: [ok] }).success).toBe(true);
  });

  it("accepts a result carrying only the required fields", () => {
    expect(crossVerifySchema.safeParse({ results: [{ index: 1, safe: false }] }).success).toBe(true);
  });

  it("rejects a missing index — the field the realignment depends on", () => {
    expect(crossVerifySchema.safeParse({ results: [{ safe: true }] }).success).toBe(false);
  });

  it("rejects a non-integer or zero/negative index", () => {
    expect(crossVerifySchema.safeParse({ results: [{ index: 1.5, safe: true }] }).success).toBe(false);
    expect(crossVerifySchema.safeParse({ results: [{ index: 0, safe: true }] }).success).toBe(false);
    expect(crossVerifySchema.safeParse({ results: [{ index: -1, safe: true }] }).success).toBe(false);
  });

  it("rejects a stringified index server-side (the client coerces, the contract does not)", () => {
    expect(crossVerifySchema.safeParse({ results: [{ index: "1", safe: true }] }).success).toBe(false);
  });

  it("rejects a missing or non-boolean `safe` — the verdict itself must never be defaulted", () => {
    expect(crossVerifySchema.safeParse({ results: [{ index: 1 }] }).success).toBe(false);
    expect(crossVerifySchema.safeParse({ results: [{ index: 1, safe: "yes" }] }).success).toBe(false);
  });

  it("rejects an out-of-range confidence", () => {
    expect(crossVerifySchema.safeParse({ results: [{ ...ok, confidence: 1.4 }] }).success).toBe(false);
  });

  it("rejects an empty or missing results array", () => {
    expect(crossVerifySchema.safeParse({ results: [] }).success).toBe(false);
    expect(crossVerifySchema.safeParse({}).success).toBe(false);
  });
});

/**
 * The count/uniqueness/coverage rules the handler layers on top of the schema —
 * a per-element schema cannot express "indices cover 1..n exactly".
 */
function indexProblem(results: { index: number }[], exerciseCount: number): string | null {
  if (results.length !== exerciseCount) {
    return `expected ${exerciseCount} results, got ${results.length}`;
  }
  const seen = new Set<number>();
  for (const r of results) {
    if (r.index < 1 || r.index > exerciseCount) return `index ${r.index} out of range`;
    if (seen.has(r.index)) return `duplicate index ${r.index}`;
    seen.add(r.index);
  }
  return null;
}

describe("crossVerify index coverage rules", () => {
  it("accepts a complete 1..n set in any order", () => {
    expect(indexProblem([{ index: 3 }, { index: 1 }, { index: 2 }], 3)).toBeNull();
  });

  it("rejects a dropped result (the original misalignment trigger)", () => {
    expect(indexProblem([{ index: 1 }, { index: 2 }], 3)).toMatch(/expected 3 results, got 2/);
  });

  it("rejects duplicates and out-of-range indices", () => {
    expect(indexProblem([{ index: 1 }, { index: 1 }], 2)).toMatch(/duplicate/);
    expect(indexProblem([{ index: 1 }, { index: 9 }], 2)).toMatch(/out of range/);
  });
});
