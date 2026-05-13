import { NextResponse } from "next/server";
import {
  CONTROL_TOWER_SESSION_COOKIE,
  CONTROL_TOWER_SESSION_TTL_SECONDS,
  constantTimeEqual,
  controlTowerSessionValue,
  getControlTowerAdminToken,
} from "@/lib/control-tower-auth";

function safeNextPath(value: FormDataEntryValue | string | null): string {
  if (typeof value !== "string") return "/";
  if (!value.startsWith("/") || value.startsWith("//")) return "/";
  return value;
}

async function readSubmittedToken(request: Request): Promise<{
  token: string;
  next: string;
}> {
  const contentType = request.headers.get("content-type") ?? "";

  if (contentType.includes("application/json")) {
    const body = (await request.json().catch(() => ({}))) as {
      token?: unknown;
      next?: unknown;
    };
    return {
      token: typeof body.token === "string" ? body.token : "",
      next: safeNextPath(typeof body.next === "string" ? body.next : null),
    };
  }

  const form = await request.formData();
  return {
    token: String(form.get("token") ?? ""),
    next: safeNextPath(form.get("next")),
  };
}

export async function POST(request: Request): Promise<NextResponse> {
  const adminToken = getControlTowerAdminToken();
  if (!adminToken) {
    return NextResponse.json(
      { error: "CONTROL_TOWER_ADMIN_TOKEN is required" },
      { status: 503 }
    );
  }

  const submitted = await readSubmittedToken(request);
  if (!constantTimeEqual(submitted.token, adminToken)) {
    const loginUrl = new URL("/login", request.url);
    loginUrl.searchParams.set("error", "1");
    loginUrl.searchParams.set("next", submitted.next);
    return NextResponse.redirect(loginUrl, 303);
  }

  const response = NextResponse.redirect(new URL(submitted.next, request.url), 303);
  response.cookies.set({
    name: CONTROL_TOWER_SESSION_COOKIE,
    value: await controlTowerSessionValue(adminToken),
    httpOnly: true,
    sameSite: "lax",
    secure: process.env.NODE_ENV === "production",
    path: "/",
    maxAge: CONTROL_TOWER_SESSION_TTL_SECONDS,
  });

  return response;
}
