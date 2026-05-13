/**
 * Unit tests for metrics-reader.ts
 * Covers parsing logic for Prometheus textfile format.
 */
import { describe, it, expect } from "vitest";
import { parseLabels, parseMetricsFile } from "../../lib/metrics-reader";

describe("parseLabels", () => {
  it("parses single label", () => {
    expect(parseLabels('agent="coder"')).toEqual({ agent: "coder" });
  });

  it("parses multiple labels", () => {
    expect(parseLabels('agent="coder",state="working"')).toEqual({
      agent: "coder",
      state: "working",
    });
  });

  it("handles empty string", () => {
    expect(parseLabels("")).toEqual({});
  });
});

describe("parseMetricsFile", () => {
  it("parses agent state metrics", () => {
    const content = `
# HELP walter_council_agent_state Current agent state (1=active)
# TYPE walter_council_agent_state gauge
walter_council_agent_state{agent="coder",state="working"} 1 1234567890000
walter_council_agent_state{agent="coder",state="idle"} 0 1234567890000
walter_council_agent_state{agent="reviewer",state="idle"} 1 1234567890000
`;
    const metrics = parseMetricsFile(content);
    const states = metrics.get("walter_council_agent_state")!;
    expect(states).toBeDefined();
    expect(states.length).toBe(3);
    const coderWorking = states.find(
      (e) => e.labels.agent === "coder" && e.labels.state === "working"
    );
    expect(coderWorking?.value).toBe(1);
  });

  it("parses heartbeat age metrics", () => {
    const content = `
# TYPE walter_council_heartbeat_age_seconds gauge
walter_council_heartbeat_age_seconds{agent="coder"} 45.2
`;
    const metrics = parseMetricsFile(content);
    const hb = metrics.get("walter_council_heartbeat_age_seconds")!;
    expect(hb[0].labels.agent).toBe("coder");
    expect(hb[0].value).toBeCloseTo(45.2);
  });

  it("skips comment and empty lines", () => {
    const content = `
# HELP some_metric A metric
# TYPE some_metric gauge

some_metric{label="a"} 1
`;
    const metrics = parseMetricsFile(content);
    expect(metrics.get("some_metric")).toBeDefined();
    expect(metrics.get("some_metric")!.length).toBe(1);
  });

  it("returns empty map for empty content", () => {
    const metrics = parseMetricsFile("");
    expect(metrics.size).toBe(0);
  });
});
