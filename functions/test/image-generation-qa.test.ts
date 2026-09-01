/**
 * The QA gate is what stands between a model-generated image and shared Storage
 * that every user reads. It is documented as fail-closed, and the verdict parse
 * was not: `overall_pass !== false` treated a missing, renamed or stringified
 * field as a pass, so a response the model shaped slightly differently published
 * an unvetted image without ever saying "pass".
 *
 * The parse is inline in `runGeminiQA`, so this pins the RULE it now implements.
 */

type QAResult = { overall_pass?: unknown; failures?: string[] };

/** Mirrors the fail-closed check in image-generation.ts. */
function passed(result: QAResult): boolean {
  return result.overall_pass === true;
}

describe("Gemini QA verdict — fails closed", () => {
  it("passes only on an explicit boolean true", () => {
    expect(passed({ overall_pass: true })).toBe(true);
  });

  it("rejects an explicit false", () => {
    expect(passed({ overall_pass: false, failures: ["anatomy"] })).toBe(false);
  });

  it("rejects a MISSING verdict rather than assuming success", () => {
    expect(passed({})).toBe(false);
    expect(passed({ failures: [] })).toBe(false);
  });

  it("rejects a stringified verdict, which the old check accepted", () => {
    // "false" !== false, so `overall_pass !== false` was true → published.
    expect(passed({ overall_pass: "false" })).toBe(false);
    expect(passed({ overall_pass: "true" })).toBe(false);
  });

  it("rejects null and numeric verdicts", () => {
    expect(passed({ overall_pass: null })).toBe(false);
    expect(passed({ overall_pass: 1 })).toBe(false);
  });
});
