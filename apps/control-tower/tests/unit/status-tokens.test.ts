/**
 * Unit tests for the shared status vocabulary (AC-2, D-4).
 *
 * Verifies that every status kind maps to a token with a non-empty label and
 * token-driven fg/bg classes (so colour is never the sole signal — WCAG 1.4.1),
 * and that the agent-state / alert-tier / service-health adapters map onto the
 * vocabulary correctly. Pure logic, no DOM needed.
 *
 * Refs: docs/specs/control-tower-redesign.md (AC-2)
 */
import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  STATUS_TOKENS,
  agentStateToStatus,
  tierToStatus,
  healthToStatus,
  type StatusKind,
} from "@/app/components/ui/status";

const ALL_KINDS: StatusKind[] = [
  "idle",
  "working",
  "blocked",
  "ok",
  "warn",
  "critical",
  "info",
  "na",
];

describe("STATUS_TOKENS [AC-2]", () => {
  it("defines a token for every status kind", () => {
    for (const kind of ALL_KINDS) {
      expect(STATUS_TOKENS[kind]).toBeDefined();
    }
  });

  it("every token has a non-empty label so colour is never the sole signal", () => {
    for (const kind of ALL_KINDS) {
      expect(STATUS_TOKENS[kind].label.trim().length).toBeGreaterThan(0);
    }
  });

  it("every token references a status fg + bg token class", () => {
    for (const kind of ALL_KINDS) {
      const t = STATUS_TOKENS[kind];
      expect(t.fg).toMatch(/^text-/);
      expect(t.bg).toMatch(/^bg-/);
    }
  });

  it("only live/urgent states pulse", () => {
    expect(STATUS_TOKENS.working.pulse).toBe(true);
    expect(STATUS_TOKENS.blocked.pulse).toBe(true);
    expect(STATUS_TOKENS.critical.pulse).toBe(true);
    expect(STATUS_TOKENS.idle.pulse).toBe(false);
    expect(STATUS_TOKENS.ok.pulse).toBe(false);
    expect(STATUS_TOKENS.info.pulse).toBe(false);
  });

  it("keeps badge labels on one line in compact dashboard tables", () => {
    const src = readFileSync(
      join(__dirname, "../../app/components/ui/StatusBadge.tsx"),
      "utf8"
    );
    expect(src).toContain("whitespace-nowrap");
  });
});

describe("tierToStatus [AC-2]", () => {
  it("maps info/warn/critical 1:1", () => {
    expect(tierToStatus("info")).toBe("info");
    expect(tierToStatus("warn")).toBe("warn");
    expect(tierToStatus("critical")).toBe("critical");
  });

  it("maps panic onto the critical token", () => {
    expect(tierToStatus("panic")).toBe("critical");
  });
});

describe("agentStateToStatus [AC-2]", () => {
  it("maps agent states exhaustively into status tokens", () => {
    expect(agentStateToStatus("idle")).toBe("idle");
    expect(agentStateToStatus("working")).toBe("working");
    expect(agentStateToStatus("blocked")).toBe("blocked");
  });
});

describe("healthToStatus [AC-2]", () => {
  it("healthy → ok, unhealthy → critical", () => {
    expect(healthToStatus(true)).toBe("ok");
    expect(healthToStatus(false)).toBe("critical");
  });

  it("null (no standby configured) → na, never ok", () => {
    // HA route contract: null must not render as healthy/green.
    expect(healthToStatus(null)).toBe("na");
    expect(healthToStatus(null)).not.toBe("ok");
  });
});
