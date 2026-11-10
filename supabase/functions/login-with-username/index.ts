import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";

function firstKey(...values: (string | undefined)[]): string {
  for (const value of values) {
    if (!value) continue;
    try {
      const parsed = JSON.parse(value) as Record<string, unknown>;
      const key = Object.values(parsed).find((item) => typeof item === "string");
      if (typeof key === "string") return key;
    } catch {
      return value;
    }
  }
  return "";
}

const serviceRoleKey = firstKey(
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
  Deno.env.get("SUPABASE_SECRET_KEYS"),
);
const publishableKey = firstKey(
  Deno.env.get("SUPABASE_ANON_KEY"),
  Deno.env.get("SUPABASE_PUBLISHABLE_KEYS"),
);

const admin = createClient(supabaseUrl, serviceRoleKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});
const authClient = createClient(supabaseUrl, publishableKey ?? "", {
  auth: { autoRefreshToken: false, persistSession: false },
});

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function respond(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return respond({ error: "Invalid request" }, 405);
  }

  try {
    const { username, password } = await request.json();
    const normalizedUsername = String(username ?? "").trim().toLowerCase();

    if (!/^[a-z0-9_]{3,24}$/.test(normalizedUsername) ||
        typeof password !== "string" || password.length < 1) {
      return respond({ error: "اسم المستخدم أو كلمة المرور غير صحيحة" }, 400);
    }

    const { data: mapping, error: mappingError } = await admin
      .from("app_usernames")
      .select("user_id")
      .eq("username", normalizedUsername)
      .maybeSingle();

    if (mappingError || !mapping) {
      return respond({ error: "اسم المستخدم أو كلمة المرور غير صحيحة" }, 400);
    }

    const { data: userResult, error: userError } =
      await admin.auth.admin.getUserById(mapping.user_id);
    const email = userResult.user?.email;
    if (userError || !email) {
      return respond({ error: "اسم المستخدم أو كلمة المرور غير صحيحة" }, 400);
    }

    const { data: signIn, error: signInError } =
      await authClient.auth.signInWithPassword({ email, password });

    if (signInError || !signIn.session) {
      return respond({ error: "اسم المستخدم أو كلمة المرور غير صحيحة" }, 400);
    }

    return respond({
      access_token: signIn.session.access_token,
      refresh_token: signIn.session.refresh_token,
    });
  } catch {
    return respond({ error: "تعذر تسجيل الدخول. حاول مرة ثانية." }, 400);
  }
});