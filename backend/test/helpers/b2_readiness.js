import fs from "fs";
import path from "path";
import crypto from "crypto";

/**
 * Fail-closed guards for isolated Backblaze B2 (S3-compatible) integration tests.
 * NEVER prints secrets. NEVER connects to B2. NEVER permits production targets.
 *
 * Live B2 tests must be explicitly opted-in and confined to the isolated endpoint, bucket, and prefix.
 */
export const B2_EXPECTED_ENDPOINT = "https://s3.eu-central-003.backblazeb2.com";
export const B2_EXPECTED_REGION = "eu-central-003";
export const B2_EXPECTED_BUCKET = "motri-iq-isolated-test-2026";
export const B2_LIVE_OPT_IN = "B2_LIVE_INTEGRATION"; // must be "1" to allow any live B2 test
export const B2_LIVE_ACK = "B2_LIVE_ACK"; // must be exact bucket name as explicit operator ack
export const B2_LOCAL_ENV_FILENAME = ".env.b2.test.local";

function normEndpoint(v) {
  const s = String(v ?? "").trim().replace(/\/+$/, "");
  return s.toLowerCase();
}

export function getB2ConfigFromEnv(env = process.env) {
  // B2-only resolution for the B2 live path (no R2 fallback).
  return {
    endpoint: env.B2_ENDPOINT || "",
    region: env.B2_REGION || "",
    bucket: env.B2_BUCKET || "",
    keyId: env.B2_KEY_ID || "",
    appKey: env.B2_APPLICATION_KEY || "",
  };
}

export function getB2ConfigFromEnvWithR2Fallback(env = process.env) {
  return {
    endpoint: env.B2_ENDPOINT || env.R2_ENDPOINT || "",
    region: env.B2_REGION || env.R2_REGION || "",
    bucket: env.B2_BUCKET || env.R2_BUCKET || "",
    keyId: env.B2_KEY_ID || env.R2_ACCESS_KEY_ID || "",
    appKey: env.B2_APPLICATION_KEY || env.R2_SECRET_ACCESS_KEY || "",
  };
}

export function validateB2FailClosed(env = process.env) {
  const cfg = getB2ConfigFromEnvWithR2Fallback(env);
  const errors = [];
  if (env[B2_LIVE_OPT_IN] !== "1") errors.push(`explicit opt-in required: ${B2_LIVE_OPT_IN}=1`);
  if (env[B2_LIVE_ACK] !== B2_EXPECTED_BUCKET) errors.push(`explicit bucket ack required: ${B2_LIVE_ACK}=${B2_EXPECTED_BUCKET}`);
  if (normEndpoint(cfg.endpoint) !== normEndpoint(B2_EXPECTED_ENDPOINT)) errors.push(`endpoint must be exactly ${B2_EXPECTED_ENDPOINT}`);
  if (String(cfg.region || "").trim() !== B2_EXPECTED_REGION) errors.push(`region must be exactly ${B2_EXPECTED_REGION}`);
  if (String(cfg.bucket || "").trim() !== B2_EXPECTED_BUCKET) errors.push(`bucket must be exactly ${B2_EXPECTED_BUCKET}`);
  // Presence only - NEVER validate/print secret values.
  if (!String(cfg.keyId || "").trim()) errors.push("B2_KEY_ID/R2_ACCESS_KEY_ID missing (value not inspected)");
  if (!String(cfg.appKey || "").trim()) errors.push("B2_APPLICATION_KEY/R2_SECRET_ACCESS_KEY missing (value not inspected)");
  return { ok: errors.length === 0, errors, cfg: { endpoint: normEndpoint(cfg.endpoint), region: String(cfg.region||"").trim(), bucket: String(cfg.bucket||"").trim(), hasKeyId: Boolean(String(cfg.keyId||"").trim()), hasAppKey: Boolean(String(cfg.appKey||"").trim()) } };
}

export function parseEnvText(text) {
  const out = {};
  for (const raw of String(text || "").split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith("#")) continue;
    const m = line.match(/^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/);
    if (!m) continue;
    let v = m[2];
    if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) v = v.slice(1, -1);
    out[m[1]] = v;
  }
  return out;
}

// Allowlist of non-secret fields exposed on the public/sanitized env view (no creds, no DB URL, no R2_*).
const B2_SAFE_PUBLIC_ENV_KEYS = new Set(["B2_ENDPOINT", "B2_REGION", "B2_BUCKET", "B2_LIVE_INTEGRATION", "B2_LIVE_ACK"]);

/**
 * Build effective env for the B2 LIVE test path ONLY.
 * - Does NOT mutate process.env/global runtime.
 * - Strips ALL R2_* from the base env (no R2 fallback during B2 live test).
 * - Loads backend/.env.b2.test.local ONLY when filePath is provided (caller passes path relative to test file).
 * - Rejects if the local file contains ANY R2_* key (collision/ambiguity) or if effective env ends up with R2_*.
 * - Rejects missing file when required=true (opt-in live path).
 * - Public result is SAFE for JSON serialization/inspection: NO B2_KEY_ID/B2_APPLICATION_KEY/DATABASE_URL/unrelated secrets.
 *   `env` is a sanitized non-secret view (allowlisted B2 config only). Validated credentials are available ONLY via
 *   a non-enumerable accessor `getLiveStorageConfig()` for the explicitly opted-in live test path.
 */
export function buildB2LiveEffectiveEnv({ baseEnv = process.env, filePath = null, required = false } = {}) {
  const errors = [];
  // Internal effective env (never exposed on public result) — used for fail-closed validation and live storage config.
  const internal = {};
  for (const [k, v] of Object.entries(baseEnv || {})) {
    if (k.startsWith("R2_")) continue; // hard strip: no fallback to R2 during B2 live test
    internal[k] = v;
  }
  let loadedFile = false;
  let parsedKeys = [];
  if (filePath) {
    const abs = path.resolve(filePath);
    if (!fs.existsSync(abs)) {
      if (required) errors.push(`B2 local env file missing: ${path.basename(abs)}`);
    } else {
      let parsed;
      try { parsed = parseEnvText(fs.readFileSync(abs, "utf8")); }
      catch (e) { errors.push(`B2 local env file unreadable: ${path.basename(abs)} (${e?.code || "error"})`); parsed = {}; }
      parsedKeys = Object.keys(parsed);
      const r2InFile = parsedKeys.filter((k) => k.startsWith("R2_"));
      if (r2InFile.length) errors.push(`B2 local env file must not define R2_* variables (found keys: ${r2InFile.join(",")})`);
      for (const [k, v] of Object.entries(parsed)) {
        if (k.startsWith("R2_")) continue;
        internal[k] = v; // file values apply to B2 live test env only (not global runtime)
      }
      loadedFile = true;
    }
  } else if (required) {
    errors.push("B2 local env file path not provided");
  }
  const r2Effective = Object.keys(internal).filter((k) => k.startsWith("R2_"));
  if (r2Effective.length) errors.push(`R2_* variables present in effective B2 live test env (keys: ${r2Effective.join(",")})`);
  // B2-only validation (no R2 fallback) for the live path.
  const cfgResolved = getB2ConfigFromEnv(internal);
  if (internal[B2_LIVE_OPT_IN] !== "1") errors.push(`explicit opt-in required: ${B2_LIVE_OPT_IN}=1`);
  if (internal[B2_LIVE_ACK] !== B2_EXPECTED_BUCKET) errors.push(`explicit bucket ack required: ${B2_LIVE_ACK}=${B2_EXPECTED_BUCKET}`);
  if (normEndpoint(cfgResolved.endpoint) !== normEndpoint(B2_EXPECTED_ENDPOINT)) errors.push(`endpoint must be exactly ${B2_EXPECTED_ENDPOINT}`);
  if (String(cfgResolved.region || "").trim() !== B2_EXPECTED_REGION) errors.push(`region must be exactly ${B2_EXPECTED_REGION}`);
  if (String(cfgResolved.bucket || "").trim() !== B2_EXPECTED_BUCKET) errors.push(`bucket must be exactly ${B2_EXPECTED_BUCKET}`);
  if (!String(cfgResolved.keyId || "").trim()) errors.push("B2_KEY_ID missing (value not inspected)");
  if (!String(cfgResolved.appKey || "").trim()) errors.push("B2_APPLICATION_KEY missing (value not inspected)");
  // Public presence markers: only safe B2 config/ack/opt-in keys + credential presence booleans (no DB URL, no unrelated secrets, no values).
  const B2_SAFE_PRESENT_KEYS = new Set(["B2_ENDPOINT","B2_REGION","B2_BUCKET","B2_LIVE_INTEGRATION","B2_LIVE_ACK","B2_KEY_ID","B2_APPLICATION_KEY"]);
  const presentKeys = parsedKeys
    .filter((k) => B2_SAFE_PRESENT_KEYS.has(k))
    .map((k) => (k === "B2_KEY_ID" ? "B2_KEY_ID(present)" : k === "B2_APPLICATION_KEY" ? "B2_APPLICATION_KEY(present)" : k));
  // Sanitized public env view: allowlisted non-secret B2 config only (no creds, no DATABASE_URL, no unrelated/R2 vars).
  const safeEnv = {};
  for (const k of B2_SAFE_PUBLIC_ENV_KEYS) if (Object.prototype.hasOwnProperty.call(internal, k)) safeEnv[k] = internal[k];
  const result = {
    ok: errors.length === 0,
    errors,
    env: safeEnv,
    loadedFile,
    cfg: { endpoint: normEndpoint(cfgResolved.endpoint), region: String(cfgResolved.region||"").trim(), bucket: String(cfgResolved.bucket||"").trim(), hasKeyId: Boolean(String(cfgResolved.keyId||"").trim()), hasAppKey: Boolean(String(cfgResolved.appKey||"").trim()) },
    presentKeys,
  };
  // Narrowly scoped, non-enumerable accessor for the explicitly opted-in live test path ONLY.
  // Not enumerable/JSON-serialized; exposes only validated storage config (not the whole env).
  Object.defineProperty(result, "getLiveStorageConfig", {
    enumerable: false, configurable: false, writable: false,
    value: () => ({
      endpoint: String(internal.B2_ENDPOINT || "").trim(),
      region: String(internal.B2_REGION || "").trim(),
      bucket: String(internal.B2_BUCKET || "").trim(),
      accessKeyId: String(internal.B2_KEY_ID || ""),
      secretAccessKey: String(internal.B2_APPLICATION_KEY || ""),
    }),
  });
  return result;
}

export async function assertTestDatabase(pool) {
  const r = (await pool.query("select current_database() db, current_user usr")).rows[0];
  if (r.db !== "motri_iq_test") {
    throw new Error(`ISOLATION: expected motri_iq_test, got ${JSON.stringify({ db: r.db, usr: r.usr })}`);
  }
  return r;
}

export const B2_LIVE_TEST_PREFIX = "motri-iq-test";

export function createB2SyntheticProbe() {
  // Small deterministic synthetic bytes (not a real user image).
  const body = Buffer.from([
    137,80,78,71,13,10,26,10,0,0,0,13,73,72,68,82,0,0,0,1,0,0,0,1,8,6,0,0,0,31,21,196,137,
    0,0,0,10,73,68,65,84,120,156,99,0,1,0,0,5,0,1,13,10,45,180,0,0,0,0,73,69,78,68,174,66,96,130
  ]);
  return { body, contentType: "image/jpeg", sha256: crypto.createHash("sha256").update(body).digest("hex") };
}

export function createB2DisposableKey(prefix = B2_LIVE_TEST_PREFIX) {
  return `${prefix}/${crypto.randomUUID()}/probe.jpg`;
}

export function validateB2DisposableKey(key, prefix = B2_LIVE_TEST_PREFIX) {
  if (typeof key !== "string" || !key.startsWith(prefix + "/")) throw new Error("disposable key must be under approved prefix");
  if (!/^[a-zA-Z0-9._\/-]+$/.test(key) || key.includes("..")) throw new Error("disposable key has invalid form");
  return true;
}

export function sha256Hex(buf) {
  return crypto.createHash("sha256").update(Buffer.isBuffer(buf) ? buf : Buffer.from(buf)).digest("hex");
}

export function inspectSignedUrlConfig(url) {
  // Configuration verification only. NEVER return/print the URL or any credential-bearing query params.
  const u = new URL(String(url || ""));
  const host = (u.hostname || "").toLowerCase();
  const expectedHost = (new URL(B2_EXPECTED_ENDPOINT)).hostname.toLowerCase();
  const qp = u.searchParams;
  const hasSig = qp.has("X-Amz-Signature") || qp.has("Signature") || qp.has("x-amz-signature");
  const hasExpires = qp.has("X-Amz-Expires") || qp.has("Expires") || qp.has("x-amz-expires");
  return {
    ok: host === expectedHost && hasSig && hasExpires && /^https:$/i.test(u.protocol),
    protocol: u.protocol.replace(/:$/, ""),
    hostMatchesExpected: host === expectedHost,
    hasSignatureParam: hasSig,
    hasExpiryParam: hasExpires,
  };
}

export function detectB2LocalOptIn(filePath) {
  // Safe, offline, minimal line-based scan. Inspects ONLY B2_LIVE_INTEGRATION=1.
  // NEVER parses/retains/returns other env values or secrets. Boolean only.
  try {
    if (!filePath || !fs.existsSync(filePath)) return false;
    const text = fs.readFileSync(filePath, "utf8");
    for (const raw of String(text).split(/\r?\n/)) {
      const line = raw.trim();
      if (!line || line.startsWith("#")) continue;
      // match only the specific key; accept optional whitespace and optional quotes
      const m = line.match(/^B2_LIVE_INTEGRATION\s*=\s*(.*)$/);
      if (!m) continue;
      let v = (m[1] ?? "").trim();
      if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) v = v.slice(1, -1);
      return v === "1";
    }
    return false;
  } catch {
    return false;
  }
}

export async function cleanupB2ProbeObject(storage, { bucket, key } = {}) {
  // Best-effort delete for try/finally. Returns explicit structured result; never exposes secrets/object contents.
  // Delete failure is never treated as success — callers must check `deleted`.
  if (!storage || !bucket || !key) return { attempted: false, deleted: false, error: true };
  try {
    await storage.deleteObject({ bucket, key });
    return { attempted: true, deleted: true, error: false };
  } catch {
    return { attempted: true, deleted: false, error: true };
  }
}
