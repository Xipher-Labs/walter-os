/**
 * spin-spec XSS prevention tests.
 *
 * Verifies that HTML in original_message and synthesis fields is escaped
 * before being sent to the Plane API, preventing stored XSS on the Plane
 * issue description.
 *
 * Refs: docs/specs/walter-council-v2.md
 * Reviewer round 1 finding: stored XSS in Plane via spin-spec (BLOCKER 4).
 */
import { describe, it, expect } from "vitest";
import { escapeHtml, buildIssueDescription } from "@/lib/spin-spec-html";

describe("escapeHtml [security]", () => {
  it("escapes <script> tags", () => {
    const input = "<script>alert(1)</script>";
    expect(escapeHtml(input)).toBe("&lt;script&gt;alert(1)&lt;/script&gt;");
  });

  it("escapes img onerror payload so it is not executable HTML", () => {
    const input = '<img src=x onerror="alert(document.cookie)">';
    const escaped = escapeHtml(input);
    // The < and > must be escaped so the browser cannot parse this as a tag
    expect(escaped).not.toContain("<img");
    expect(escaped).not.toContain('">');
    expect(escaped).toContain("&lt;img");
    // onerror= text survives but is not inside an HTML attribute context
    expect(escaped).toContain("onerror=");
  });

  it("escapes ampersands", () => {
    expect(escapeHtml("a & b")).toBe("a &amp; b");
  });

  it("escapes double quotes", () => {
    expect(escapeHtml('say "hello"')).toBe("say &quot;hello&quot;");
  });

  it("escapes single quotes", () => {
    expect(escapeHtml("it's fine")).toBe("it&#39;s fine");
  });

  it("passes through plain text unchanged", () => {
    const plain = "Spec request: build a better search UX";
    expect(escapeHtml(plain)).toBe(plain);
  });
});

describe("buildIssueDescription [security]", () => {
  it("escapes original_message containing script tag", () => {
    const desc = buildIssueDescription(
      "<script>alert(1)</script>",
      {
        summary: "Summary text",
        convergences: [],
        disagreements: [],
        recommended_path: "Do X",
        next_steps: [],
      },
      "sess-1"
    );
    expect(desc).not.toContain("<script>");
    expect(desc).toContain("&lt;script&gt;");
  });

  it("escapes synthesis summary containing XSS payload", () => {
    const desc = buildIssueDescription("What should we build?", {
      summary: '<img src=x onerror="pwned">Summary',
      convergences: [],
      disagreements: [],
      recommended_path: "Do X",
      next_steps: [],
    }, "sess-2");
    // The tag must be escaped — browser cannot parse &lt;img as an HTML element
    expect(desc).not.toContain("<img");
    expect(desc).not.toContain('">');
    expect(desc).toContain("&lt;img");
  });

  it("escapes synthesis convergences and next_steps", () => {
    const desc = buildIssueDescription("Q?", {
      summary: "Fine",
      convergences: ['<a href="evil">click</a>'],
      disagreements: [],
      recommended_path: "safe",
      next_steps: ["<script>steal()</script>"],
    }, "sess-3");
    expect(desc).not.toContain("<a href");
    expect(desc).not.toContain("<script>");
    expect(desc).toContain("&lt;a href");
    expect(desc).toContain("&lt;script&gt;");
  });
});
