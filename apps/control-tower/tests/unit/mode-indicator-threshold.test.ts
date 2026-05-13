/**
 * Unit tests for ModeIndicator component.
 * U-new-3: The voting threshold denominator (/3) must not be hardcoded.
 *          The denominator should either come from ModeState or not appear at all.
 */
import { describe, it, expect } from "vitest";
import { readFileSync } from "fs";
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));

describe("ModeIndicator threshold display static analysis", () => {
  it("U-new-3: ModeIndicator.tsx does not hardcode /3 as voting threshold denominator", () => {
    const content = readFileSync(
      resolve(__dirname, "../../app/components/ModeIndicator.tsx"),
      "utf-8"
    );
    // The broken pattern: voting_threshold}/3  or  voting_threshold}/3
    // (the literal string "/3" adjacent to voting_threshold display)
    // This is a JSX expression like: {mode.voting_threshold}/3
    const hasHardcodedDenominator = /voting_threshold\}\/3/.test(content);
    expect(hasHardcodedDenominator).toBe(false);
  });
});
