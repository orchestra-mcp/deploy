// Main entry point for Supabase Edge Runtime.
// This file is required by the edge-runtime container's start command.
// Individual edge functions should be placed in sibling directories.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

serve(async (req: Request) => {
  const url = new URL(req.url);

  // Health check endpoint
  if (url.pathname === "/" || url.pathname === "/health") {
    return new Response(JSON.stringify({ status: "ok" }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  return new Response(JSON.stringify({ error: "Function not found" }), {
    status: 404,
    headers: { "Content-Type": "application/json" },
  });
});
