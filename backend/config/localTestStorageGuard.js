const EXACT_LOCAL_S3_ENDPOINT = "http://127.0.0.1:4566";

export function isLocalTestStorageMode(env = process.env) {
  // Enforcement must not be bypassable by passing an alternate env object.
  return process.env?.MOTRI_LOCAL_TEST === "true" || env?.MOTRI_LOCAL_TEST === "true";
}

function fail(code) {
  const err = new Error(code);
  err.code = code;
  return err;
}

function isExactLocalS3Endpoint(raw) {
  if (typeof raw !== "string") return false;
  const v = raw.trim();
  if (v !== raw) return false; // reject surrounding whitespace as non-exact
  if (v !== EXACT_LOCAL_S3_ENDPOINT) return false;
  let u;
  try {
    u = new URL(v);
  } catch {
    return false;
  }
  return (
    u.protocol === "http:" &&
    u.hostname === "127.0.0.1" &&
    (u.port === "4566" || u.port === "") &&
    u.pathname === "/" &&
    u.search === "" &&
    u.hash === "" &&
    u.username === "" &&
    u.password === ""
  );
}

// Legacy helper retained for non-local callers/tests where broader loopback detection is useful.
// In MOTRI_LOCAL_TEST, exact endpoint is required; do not use this for local-test acceptance.
export function isLocalStorageEndpoint(raw) {
  return isExactLocalS3Endpoint(raw);
}

export function validateLocalPublicBase(raw, { env = process.env } = {}) {
  if (!isLocalTestStorageMode(env)) return { active: false };
  if (raw == null || raw === "") return { active: true };
  if (typeof raw !== "string" || !isExactLocalS3Endpoint(raw)) {
    throw fail("LOCAL_TEST_STORAGE_PUBLIC_BASE_NOT_LOCAL");
  }
  return { active: true };
}

function readLocalS3(env) {
  // Local-test mode resolves ONLY explicit LOCAL_S3_* settings from process.env.
  // R2_* / B2_* are never read in local-test mode and must not override LOCAL_S3_*.
  const src = process.env && typeof process.env === "object" ? process.env : env || {};
  return {
    endpoint: src.LOCAL_S3_ENDPOINT ?? "",
    accessKeyId: src.LOCAL_S3_ACCESS_KEY_ID ?? "",
    secretAccessKey: src.LOCAL_S3_SECRET_ACCESS_KEY ?? "",
    bucket: src.LOCAL_S3_BUCKET || "motri-iq-test",
    region: src.LOCAL_S3_REGION || "auto",
    publicBase: src.LOCAL_S3_PUBLIC_BASE ?? "",
  };
}

// G10.62 P3/P3.2: in MOTRI_LOCAL_TEST, require explicit local-only storage config.
// Reject remote/fallback/missing/invalid config with fixed codes only; never expose URLs/keys.
export function validateLocalTestStorageConfig({ endpoint, accessKeyId, secretAccessKey, publicBase } = {}, { env = process.env } = {}) {
  if (!isLocalTestStorageMode(env)) return { active: false };
  if (typeof endpoint !== "string" || !endpoint.trim()) throw fail("LOCAL_TEST_STORAGE_CONFIG_MISSING");
  if (typeof accessKeyId !== "string" || !accessKeyId || typeof secretAccessKey !== "string" || !secretAccessKey) {
    throw fail("LOCAL_TEST_STORAGE_CREDENTIALS_MISSING");
  }
  if (!isExactLocalS3Endpoint(endpoint)) {
    let u;
    try { u = new URL(String(endpoint).trim()); } catch { throw fail("LOCAL_TEST_STORAGE_ENDPOINT_INVALID"); }
    // Malformed/unsupported URL forms are invalid; valid-but-non-exact endpoints are not local-allowed.
    if (!u || !["http:", "https:"].includes(String(u.protocol || "").toLowerCase())) {
      throw fail("LOCAL_TEST_STORAGE_ENDPOINT_INVALID");
    }
    throw fail("LOCAL_TEST_STORAGE_ENDPOINT_NOT_LOCAL");
  }
  validateLocalPublicBase(publicBase, { env });
  return { active: true };
}

export function resolveStorageConfig(env = process.env) {
  if (isLocalTestStorageMode(env)) {
    return readLocalS3(env);
  }
  return {
    endpoint: env.R2_ENDPOINT || env.B2_ENDPOINT || env.LOCAL_S3_ENDPOINT || "",
    accessKeyId: env.R2_ACCESS_KEY_ID || env.B2_KEY_ID || env.LOCAL_S3_ACCESS_KEY_ID || "",
    secretAccessKey: env.R2_SECRET_ACCESS_KEY || env.B2_APPLICATION_KEY || env.LOCAL_S3_SECRET_ACCESS_KEY || "",
    bucket: env.R2_BUCKET || env.B2_BUCKET || env.LOCAL_S3_BUCKET || "motri-iq-test",
    region: env.R2_REGION || env.B2_REGION || env.LOCAL_S3_REGION || "auto",
    publicBase: env.R2_PUBLIC_BASE || env.B2_PUBLIC_BASE || env.LOCAL_S3_PUBLIC_BASE || "",
  };
}

// Assert config for local-test mode before creating/using a real storage service.
export function assertLocalTestStorageConfig(env = process.env) {
  if (!isLocalTestStorageMode(env)) return { active: false };
  const cfg = resolveStorageConfig(env);
  validateLocalTestStorageConfig(cfg, { env });
  return { active: true };
}

export { EXACT_LOCAL_S3_ENDPOINT };
