// MCP Token Exchange — exchanges a Supabase JWT for an MCP-scoped token.
// POST /functions/v1/mcp-token { "supabase_token": "..." }
// Returns { "mcp_token": "...", "expires_in": 3600 }

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { create, getNumericDate } from "https://deno.land/x/djwt@v3.0.2/mod.ts";

const MCP_JWT_SECRET = Deno.env.get("MCP_JWT_SECRET") ?? Deno.env.get("JWT_SECRET") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "http://supabase-kong:8000";
const MCP_TOKEN_TTL = 3600; // 1 hour

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Authorization",
      },
    });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  try {
    const body = await req.json();
    const supabaseToken = body.supabase_token ?? "";

    if (!supabaseToken) {
      return new Response(
        JSON.stringify({ error: "supabase_token is required" }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    // Validate the Supabase token against GoTrue's /auth/v1/user endpoint.
    const userRes = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
      headers: { Authorization: `Bearer ${supabaseToken}`, apikey: supabaseToken },
    });

    if (!userRes.ok) {
      return new Response(
        JSON.stringify({ error: "Invalid or expired Supabase token" }),
        { status: 401, headers: { "Content-Type": "application/json" } },
      );
    }

    const user = await userRes.json();

    // Look up the user's role from the public.users table.
    const dbRes = await fetch(
      `${SUPABASE_URL}/rest/v1/users?select=id,role&auth_id=eq.${user.id}&limit=1`,
      {
        headers: {
          Authorization: `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""}`,
          apikey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
        },
      },
    );

    let role = "user";
    let userId = 0;
    if (dbRes.ok) {
      const rows = await dbRes.json();
      if (rows.length > 0) {
        role = rows[0].role ?? "user";
        userId = rows[0].id ?? 0;
      }
    }

    // Create an MCP-scoped JWT.
    const key = await crypto.subtle.importKey(
      "raw",
      new TextEncoder().encode(MCP_JWT_SECRET),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"],
    );

    const now = Math.floor(Date.now() / 1000);
    const mcpToken = await create(
      { alg: "HS256", typ: "JWT" },
      {
        sub: String(userId),
        email: user.email ?? "",
        role,
        aud: "mcp",
        iat: now,
        exp: getNumericDate(MCP_TOKEN_TTL),
      },
      key,
    );

    return new Response(
      JSON.stringify({ mcp_token: mcpToken, expires_in: MCP_TOKEN_TTL }),
      {
        status: 200,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      },
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: "Internal error", details: String(err) }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
