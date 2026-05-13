export const CONTROL_TOWER_SESSION_COOKIE = "control_tower_session";
export const CONTROL_TOWER_SESSION_TTL_SECONDS = 60 * 60 * 12;

type EnvLike = Record<string, string | undefined>;

const SESSION_PREFIX = "ct1";
const encoder = new TextEncoder();
let sessionKeyCache:
  | {
      adminToken: string;
      keyPromise: Promise<CryptoKey>;
    }
  | undefined;

export function isControlTowerBypassPath(pathname: string): boolean {
  return (
    pathname === "/api/health" ||
    pathname === "/login" ||
    pathname === "/api/login" ||
    pathname === "/api/logout" ||
    pathname === "/favicon.ico" ||
    pathname.startsWith("/_next/") ||
    pathname.startsWith("/assets/")
  );
}

export function getControlTowerAdminToken(env: EnvLike = process.env): string {
  return (env.CONTROL_TOWER_ADMIN_TOKEN ?? "").trim();
}

export function isExplicitDevAuthBypassAllowed(
  env: EnvLike = process.env
): boolean {
  return (
    env.CONTROL_TOWER_AUTH_DISABLED === "true" &&
    env.NODE_ENV !== "production"
  );
}

export function constantTimeEqual(a: string, b: string): boolean {
  const maxLength = Math.max(a.length, b.length);
  let diff = a.length ^ b.length;

  for (let i = 0; i < maxLength; i += 1) {
    diff |= (a.charCodeAt(i) || 0) ^ (b.charCodeAt(i) || 0);
  }

  return diff === 0;
}

export async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(input));
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function hex(buffer: ArrayBuffer): string {
  return Array.from(new Uint8Array(buffer))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function sessionPayload(expiresAt: number): string {
  return `${SESSION_PREFIX}.${expiresAt}`;
}

function sessionSigningKey(adminToken: string): Promise<CryptoKey> {
  if (sessionKeyCache?.adminToken === adminToken) {
    return sessionKeyCache.keyPromise;
  }

  const keyPromise = crypto.subtle.importKey(
    "raw",
    encoder.encode(`control-tower-session:${adminToken}`),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  sessionKeyCache = { adminToken, keyPromise };
  return keyPromise;
}

async function sessionSignature(
  adminToken: string,
  expiresAt: number
): Promise<string> {
  const key = await sessionSigningKey(adminToken);
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(sessionPayload(expiresAt))
  );
  return hex(signature);
}

export async function controlTowerSessionValue(
  adminToken: string,
  nowMs = Date.now(),
  ttlSeconds = CONTROL_TOWER_SESSION_TTL_SECONDS
): Promise<string> {
  const expiresAt = Math.floor(nowMs / 1000) + ttlSeconds;
  return `${sessionPayload(expiresAt)}.${await sessionSignature(
    adminToken,
    expiresAt
  )}`;
}

async function isValidSessionCookie(
  sessionCookie: string,
  adminToken: string,
  nowMs: number
): Promise<boolean> {
  const [prefix, expiresAtRaw, signature, extra] = sessionCookie.split(".");
  if (prefix !== SESSION_PREFIX || extra !== undefined) return false;

  const expiresAt = Number(expiresAtRaw);
  if (!Number.isSafeInteger(expiresAt)) return false;
  if (expiresAt <= Math.floor(nowMs / 1000)) return false;

  const expectedSignature = await sessionSignature(adminToken, expiresAt);
  return constantTimeEqual(signature ?? "", expectedSignature);
}

function bearerToken(headers: Headers): string | null {
  const raw = headers.get("authorization");
  if (!raw) return null;

  const match = /^Bearer\s+(.+)$/i.exec(raw.trim());
  return match ? match[1].trim() : null;
}

export type ControlTowerAuthResult =
  | { allowed: true; reason: "bearer" | "cookie" | "dev-disabled" }
  | { allowed: false; reason: "missing-token"; status: 503 }
  | { allowed: false; reason: "unauthorized"; status: 401 };

export async function authorizeControlTowerRequest(
  headers: Headers,
  sessionCookie: string | undefined,
  env: EnvLike = process.env,
  nowMs = Date.now()
): Promise<ControlTowerAuthResult> {
  if (isExplicitDevAuthBypassAllowed(env)) {
    return { allowed: true, reason: "dev-disabled" };
  }

  const adminToken = getControlTowerAdminToken(env);
  if (!adminToken) {
    return { allowed: false, reason: "missing-token", status: 503 };
  }

  const bearer = bearerToken(headers);
  if (bearer && constantTimeEqual(bearer, adminToken)) {
    return { allowed: true, reason: "bearer" };
  }

  if (sessionCookie) {
    if (await isValidSessionCookie(sessionCookie, adminToken, nowMs)) {
      return { allowed: true, reason: "cookie" };
    }
  }

  return { allowed: false, reason: "unauthorized", status: 401 };
}
