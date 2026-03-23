// Device Authorization Flow (RFC 8628) — for CLI and headless auth.
// POST /functions/v1/device-auth/code   → returns { device_code, user_code, verification_uri }
// POST /functions/v1/device-auth/token  → polls for completed auth
// POST /functions/v1/device-auth/approve → browser submits user_code after login

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "http://supabase-kong:8000";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const DOMAIN = Deno.env.get("DOMAIN") ?? "orchestra-mcp.dev";

function headers(extra?: Record<string, string>) {
  return {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    ...extra,
  };
}

function randomCode(len: number): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no O/0/I/1
  const bytes = new Uint8Array(len);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => chars[b % chars.length]).join("");
}

async function dbFetch(path: string, opts?: RequestInit) {
  return fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    ...opts,
    headers: {
      Authorization: `Bearer ${SERVICE_KEY}`,
      apikey: SERVICE_KEY,
      "Content-Type": "application/json",
      Prefer: "return=representation",
      ...(opts?.headers ?? {}),
    },
  });
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: headers() });
  }

  const url = new URL(req.url);
  const action = url.pathname.split("/").pop();

  // POST /code — generate device + user codes
  if (req.method === "POST" && action === "code") {
    const deviceCode = crypto.randomUUID();
    const userCode = `${randomCode(4)}-${randomCode(4)}`;
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();

    const res = await dbFetch("device_codes", {
      method: "POST",
      body: JSON.stringify({
        device_code: deviceCode,
        user_code: userCode,
        status: "pending",
        expires_at: expiresAt,
      }),
    });

    if (!res.ok) {
      const err = await res.text();
      return new Response(
        JSON.stringify({ error: "Failed to create device code", details: err }),
        { status: 500, headers: headers() },
      );
    }

    return new Response(
      JSON.stringify({
        device_code: deviceCode,
        user_code: userCode,
        verification_uri: `https://${DOMAIN}/cli-auth`,
        expires_in: 600,
        interval: 5,
      }),
      { status: 200, headers: headers() },
    );
  }

  // POST /token — CLI polls for completion
  if (req.method === "POST" && action === "token") {
    const body = await req.json();
    const deviceCode = body.device_code ?? "";

    if (!deviceCode) {
      return new Response(
        JSON.stringify({ error: "device_code is required" }),
        { status: 400, headers: headers() },
      );
    }

    const res = await dbFetch(
      `device_codes?device_code=eq.${deviceCode}&select=*&limit=1`,
    );
    if (!res.ok) {
      return new Response(
        JSON.stringify({ error: "authorization_pending" }),
        { status: 400, headers: headers() },
      );
    }

    const rows = await res.json();
    if (rows.length === 0) {
      return new Response(
        JSON.stringify({ error: "invalid_device_code" }),
        { status: 400, headers: headers() },
      );
    }

    const code = rows[0];

    if (new Date(code.expires_at) < new Date()) {
      return new Response(
        JSON.stringify({ error: "expired_token" }),
        { status: 400, headers: headers() },
      );
    }

    if (code.status === "approved" && code.access_token) {
      // Clean up — delete the used code
      await dbFetch(`device_codes?device_code=eq.${deviceCode}`, {
        method: "DELETE",
      });

      return new Response(
        JSON.stringify({
          access_token: code.access_token,
          token_type: "Bearer",
        }),
        { status: 200, headers: headers() },
      );
    }

    return new Response(
      JSON.stringify({ error: "authorization_pending" }),
      { status: 400, headers: headers() },
    );
  }

  // POST /approve — browser sends user_code + Supabase JWT
  if (req.method === "POST" && action === "approve") {
    const authHeader = req.headers.get("authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      return new Response(
        JSON.stringify({ error: "Authentication required" }),
        { status: 401, headers: headers() },
      );
    }

    const token = authHeader.replace("Bearer ", "");
    const body = await req.json();
    const userCode = (body.user_code ?? "").toUpperCase().trim();

    if (!userCode) {
      return new Response(
        JSON.stringify({ error: "user_code is required" }),
        { status: 400, headers: headers() },
      );
    }

    // Validate the Supabase JWT
    const userRes = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
      headers: { Authorization: `Bearer ${token}`, apikey: token },
    });

    if (!userRes.ok) {
      return new Response(
        JSON.stringify({ error: "Invalid token" }),
        { status: 401, headers: headers() },
      );
    }

    // Find the pending device code
    const codeRes = await dbFetch(
      `device_codes?user_code=eq.${userCode}&status=eq.pending&select=*&limit=1`,
    );
    const codes = await codeRes.json();

    if (!codes || codes.length === 0) {
      return new Response(
        JSON.stringify({ error: "Invalid or expired code" }),
        { status: 400, headers: headers() },
      );
    }

    if (new Date(codes[0].expires_at) < new Date()) {
      return new Response(
        JSON.stringify({ error: "Code expired" }),
        { status: 400, headers: headers() },
      );
    }

    // Approve — store the access token
    await dbFetch(
      `device_codes?device_code=eq.${codes[0].device_code}`,
      {
        method: "PATCH",
        body: JSON.stringify({
          status: "approved",
          access_token: token,
        }),
      },
    );

    return new Response(
      JSON.stringify({ ok: true }),
      { status: 200, headers: headers() },
    );
  }

  return new Response(
    JSON.stringify({ error: "Not found" }),
    { status: 404, headers: headers() },
  );
});
