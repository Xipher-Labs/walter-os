/**
 * Unit tests for council-personas.ts
 *
 * Covers AC-7 ordering requirement: Round 2 goes high → medium → low trust tier.
 */
import { describe, it, expect } from "vitest";
import { COUNCIL_PERSONAS, COUNCIL_R2_ORDER } from "../../lib/council-personas";

describe("COUNCIL_PERSONAS", () => {
  it("has exactly 6 agents", () => {
    expect(COUNCIL_PERSONAS.length).toBe(6);
  });

  it("includes all required agents", () => {
    const ids = COUNCIL_PERSONAS.map((p) => p.id);
    expect(ids).toContain("reviewer");
    expect(ids).toContain("triage");
    expect(ids).toContain("researcher");
    expect(ids).toContain("coder");
    expect(ids).toContain("janitor");
    expect(ids).toContain("liaison");
  });

  it("assigns reviewer as high trust", () => {
    const reviewer = COUNCIL_PERSONAS.find((p) => p.id === "reviewer");
    expect(reviewer?.trustTier).toBe("high");
  });

  it("assigns liaison as low trust", () => {
    const liaison = COUNCIL_PERSONAS.find((p) => p.id === "liaison");
    expect(liaison?.trustTier).toBe("low");
  });
});

describe("COUNCIL_R2_ORDER [AC-7]", () => {
  it("has 6 agents in Round 2 order", () => {
    expect(COUNCIL_R2_ORDER.length).toBe(6);
  });

  it("reviewer speaks first (high trust, round2Order=1)", () => {
    expect(COUNCIL_R2_ORDER[0].id).toBe("reviewer");
  });

  it("liaison speaks last (low trust, round2Order=6)", () => {
    expect(COUNCIL_R2_ORDER[COUNCIL_R2_ORDER.length - 1].id).toBe("liaison");
  });

  it("high-trust agents come before low-trust agents", () => {
    const highIdx = COUNCIL_R2_ORDER.findIndex((p) => p.trustTier === "high");
    const lowIdx = COUNCIL_R2_ORDER.findIndex((p) => p.trustTier === "low");
    expect(highIdx).toBeLessThan(lowIdx);
  });

  it("is sorted strictly ascending by round2Order", () => {
    for (let i = 1; i < COUNCIL_R2_ORDER.length; i++) {
      expect(COUNCIL_R2_ORDER[i].round2Order).toBeGreaterThan(
        COUNCIL_R2_ORDER[i - 1].round2Order
      );
    }
  });
});
