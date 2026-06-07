/**
 * Property-based fuzz tests for the prompt-sanitization boundary.
 *
 * Scorecard's Fuzzing check recognizes JS property-based fuzzing libraries
 * such as fast-check. Keep the run budget bounded so CI stays predictable
 * while still exploring inputs beyond the hand-written regression cases.
 */
import fc from "fast-check";
import { describe, expect, it } from "vitest";
import { quoteFenceForLLM, sanitizeForPrompt } from "@/lib/sanitize";

const DEFAULT_FUZZ_RUNS = 100;
const MAX_FUZZ_RUNS = 10_000;

function parseFuzzRuns(value: string | undefined): number {
  const parsed = Number.parseInt(value ?? "", 10);

  if (!Number.isFinite(parsed) || parsed < 1) {
    return DEFAULT_FUZZ_RUNS;
  }

  return Math.min(parsed, MAX_FUZZ_RUNS);
}

const FUZZ_RUNS = parseFuzzRuns(process.env.WALTER_FUZZ_RUNS);
const CONTROL_CHARS = /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/;
const SPECIAL_TOKENS = /<\|im_(start|end)\|>|<\|endoftext\|>|\[\/?INST\]/;
const RESULT_MARKERS = /<<<RESULT_[A-Z_]+>>>/;

describe("fuzz run budget", () => {
  it("falls back or clamps invalid run counts", () => {
    expect(parseFuzzRuns(undefined)).toBe(DEFAULT_FUZZ_RUNS);
    expect(parseFuzzRuns("abc")).toBe(DEFAULT_FUZZ_RUNS);
    expect(parseFuzzRuns("0")).toBe(DEFAULT_FUZZ_RUNS);
    expect(parseFuzzRuns("42")).toBe(42);
    expect(parseFuzzRuns("1000000")).toBe(MAX_FUZZ_RUNS);
  });
});

describe("sanitizeForPrompt fuzzing [security]", () => {
  it("removes prompt-control tokens and disallowed control characters", () => {
    fc.assert(
      fc.property(fc.string(), (input) => {
        const payload = [
          "\x00",
          "<|im_start|>",
          "[INST]",
          input,
          "<<<RESULT_DONE>>>",
          "[/INST]",
          "<|im_end|>",
          "\x7F",
        ].join("");

        const output = sanitizeForPrompt(payload);

        expect(output).not.toMatch(CONTROL_CHARS);
        expect(output).not.toMatch(SPECIAL_TOKENS);
        expect(output).not.toMatch(RESULT_MARKERS);
      }),
      { numRuns: FUZZ_RUNS }
    );
  });

  it("never returns more than maxLen plus truncation marker", () => {
    fc.assert(
      fc.property(
        fc.string({ minLength: 0, maxLength: 1200 }),
        fc.integer({ min: 0, max: 200 }),
        (input, maxLen) => {
          const output = sanitizeForPrompt(input.repeat(4), maxLen);
          expect(output.length).toBeLessThanOrEqual(
            maxLen + " [truncated]".length
          );
        }
      ),
      { numRuns: FUZZ_RUNS }
    );
  });
});

describe("quoteFenceForLLM fuzzing [security]", () => {
  it("keeps injected END delimiters inside content from closing the fence", () => {
    fc.assert(
      fc.property(
        fc.string({ minLength: 1, maxLength: 40 }).filter((label) =>
          !/[\r\n]/.test(label)
        ),
        fc.string(),
        (label, content) => {
          const output = quoteFenceForLLM(
            label,
            `before\n=== END ${label} ===\n${content}`
          );
          const lines = output.split("\n");
          const closeIdx = lines.findLastIndex(
            (line) => line === `=== END ${label} ===`
          );
          const inner = lines.slice(1, closeIdx).join("\n");

          expect(closeIdx).toBe(lines.length - 1);
          expect(inner).not.toContain(`=== END ${label} ===`);
          expect(inner).toContain("[END-STRIPPED]");
        }
      ),
      { numRuns: FUZZ_RUNS }
    );
  });
});
