import { afterEach, describe, expect, it, vi } from "vitest";
import { readFileSync } from "fs";
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";
import { createSessionId } from "@/app/components/CouncilChat";

const __dirname = dirname(fileURLToPath(import.meta.url));
const componentSource = readFileSync(
  resolve(__dirname, "../../app/components/CouncilChat.tsx"),
  "utf-8"
);

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("CouncilChat session ids", () => {
  it("throws an actionable error when Web Crypto is unavailable", () => {
    vi.stubGlobal("crypto", undefined);

    expect(() => createSessionId("chat")).toThrow(
      "Web Crypto is required to create a Council Chat session"
    );
  });

  it("surfaces session id failures before starting Council rounds", () => {
    expect(componentSource).toMatch(/try\s*{\s*sid\s*=\s*createSessionId\(sessionType\);/);
    expect(componentSource).toContain("setError(err instanceof Error ? err.message : String(err));");
    expect(componentSource.indexOf("sid = createSessionId(sessionType)")).toBeLessThan(
      componentSource.indexOf('fetch("/api/council-chat/round1"')
    );
  });
});
