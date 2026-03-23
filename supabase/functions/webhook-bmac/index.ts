// Buy Me a Coffee Webhook — verifies HMAC signature, updates sponsors table.
// POST /functions/v1/webhook-bmac

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const BMAC_SECRET = Deno.env.get("BMAC_WEBHOOK_SECRET") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "http://supabase-kong:8000";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

async function verifyHmac(body: string, signature: string): Promise<boolean> {
  if (!BMAC_SECRET || !signature) return false;

  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(BMAC_SECRET),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const sig = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(body),
  );

  const expected = Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  return expected === signature.toLowerCase();
}

serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  const rawBody = await req.text();
  const signature = req.headers.get("x-bmac-signature") ?? "";

  if (BMAC_SECRET && !(await verifyHmac(rawBody, signature))) {
    return new Response(JSON.stringify({ error: "Invalid signature" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  let payload: Record<string, unknown>;
  try {
    payload = JSON.parse(rawBody);
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const type = payload.type as string ?? "";
  const data = (payload.data ?? payload) as Record<string, unknown>;

  const supporter = {
    external_id: String(data.supporter_id ?? data.id ?? ""),
    name: String(data.supporter_name ?? data.name ?? "Anonymous"),
    email: String(data.supporter_email ?? data.email ?? ""),
    amount: Number(data.total_amount ?? data.amount ?? 0),
    currency: String(data.currency ?? "USD"),
    message: String(data.support_note ?? data.message ?? ""),
    event_type: type || "one_time",
    provider: "buymeacoffee",
  };

  // Upsert into sponsors table
  const res = await fetch(`${SUPABASE_URL}/rest/v1/sponsors`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${SERVICE_KEY}`,
      apikey: SERVICE_KEY,
      "Content-Type": "application/json",
      Prefer: "resolution=merge-duplicates",
    },
    body: JSON.stringify(supporter),
  });

  if (!res.ok) {
    const err = await res.text();
    console.error("Failed to upsert sponsor:", err);
    return new Response(
      JSON.stringify({ error: "Failed to record sponsorship" }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }

  return new Response(
    JSON.stringify({ ok: true }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
});
