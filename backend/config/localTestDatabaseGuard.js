const REQUIRED_DB = "motri_iq_test";
const REQUIRED_USER = "neondb_owner";
const ALLOWED_HOSTS_ENV = "LOCAL_TEST_DB_ALLOWED_HOSTS";

export function isLocalTestMode(env = process.env) {
  return env?.MOTRI_LOCAL_TEST === "true";
}

function fail(code) {
  const err = new Error(code);
  err.code = code;
  return err;
}

function decodedUsername(u) {
  const raw = u.username || "";
  try {
    return decodeURIComponent(raw);
  } catch {
    return raw;
  }
}

function normalizeHostname(host) {
  const h = String(host || "").trim().toLowerCase();
  if (!h) return "";
  // Strip brackets for IPv6 literals in URL.hostname form.
  return h.replace(/^\[|\]$/g, "");
}

function parseAllowedHosts(raw) {
  if (typeof raw !== "string") return [];
  const hosts = raw
    .split(/[\s,;]+/)
    .map((v) => normalizeHostname(v))
    .filter(Boolean);
  return [...new Set(hosts)];
}

export function validateLocalTestDatabaseUrl(raw, { env = process.env, enforceLocalTestHostAllowlist } = {}) {
  if (typeof raw !== "string" || raw.trim() === "") {
    throw fail("LOCAL_TEST_DATABASE_URL_MISSING");
  }
  let url;
  try {
    url = new URL(raw);
  } catch {
    // Non-URL forms (e.g. libpq key/value connection strings) are rejected in local-test mode.
    throw fail("LOCAL_TEST_DATABASE_URL_INVALID");
  }
  const proto = String(url.protocol || "").toLowerCase();
  if (proto !== "postgres:" && proto !== "postgresql:") {
    throw fail("LOCAL_TEST_DATABASE_URL_UNSUPPORTED");
  }
  const dbName = (url.pathname || "").replace(/^\/+/, "").split("/")[0];
  if (!dbName) throw fail("LOCAL_TEST_DATABASE_DB_MISSING");
  if (dbName !== REQUIRED_DB) throw fail("LOCAL_TEST_DATABASE_DB_NOT_ALLOWED");
  const user = decodedUsername(url);
  if (!user) throw fail("LOCAL_TEST_DATABASE_ROLE_MISSING");
  if (user !== REQUIRED_USER) throw fail("LOCAL_TEST_DATABASE_ROLE_NOT_ALLOWED");

  // G10.62 P2.1: in local-test mode, require explicit non-empty hostname allowlist; reject unlisted/missing/malformed hosts.
  // Never print connection details. Preserve db/user/protocol checks above for stable fail-closed behavior.
  const enforceHost = enforceLocalTestHostAllowlist === true || isLocalTestMode(env);
  if (enforceHost) {
    const allowlist = parseAllowedHosts(env?.[ALLOWED_HOSTS_ENV]);
    if (allowlist.length === 0) throw fail("LOCAL_TEST_DB_HOST_ALLOWLIST_MISSING");
    const host = normalizeHostname(url.hostname);
    if (!host) throw fail("LOCAL_TEST_DB_HOST_MISSING");
    if (!allowlist.includes(host)) throw fail("LOCAL_TEST_DB_HOST_NOT_ALLOWED");
  }
  return { dbName, user };
}

export function assertLocalTestDatabaseConfig(env = process.env) {
  if (!isLocalTestMode(env)) return { active: false };
  validateLocalTestDatabaseUrl(env.DATABASE_URL, { env });
  return { active: true };
}

export async function verifyLocalTestDatabaseIdentity(pool, { log = console.error } = {}) {
  if (!pool || typeof pool.connect !== "function") {
    throw fail("LOCAL_TEST_DATABASE_POOL_UNAVAILABLE");
  }
  let client;
  try {
    client = await pool.connect();
  } catch {
    throw fail("LOCAL_TEST_DATABASE_CONNECT_FAILED");
  }
  try {
    const result = await client.query("SELECT current_database() AS db, current_user AS usr");
    const row = result?.rows?.[0] || {};
    if (row.db !== REQUIRED_DB) throw fail("LOCAL_TEST_DATABASE_IDENTITY_DB_MISMATCH");
    if (row.usr !== REQUIRED_USER) throw fail("LOCAL_TEST_DATABASE_IDENTITY_ROLE_MISMATCH");
    return { verified: true };
  } catch (err) {
    if (err?.code && String(err.code).startsWith("LOCAL_TEST_DATABASE_")) throw err;
    throw fail("LOCAL_TEST_DATABASE_IDENTITY_QUERY_FAILED");
  } finally {
    try {
      await client?.release?.();
    } catch {
      // release failure must not mask identity result; do not expose details
      if (typeof log === "function") log("LOCAL_TEST_DATABASE_CLIENT_RELEASE_FAILED");
    }
  }
}

export async function startServerWithLocalTestDbGuard({
  app,
  pool,
  port,
  env = process.env,
  listen = (p, cb) => app.listen(p, cb),
  exit = (code) => process.exit(code),
  log = console.error,
  onVerified = () => {},
} = {}) {
  if (!isLocalTestMode(env)) {
    onVerified();
    return listen(port, () => {
      log(`MOTRI_IQ Backend running on port ${port}`);
    });
  }
  try {
    validateLocalTestDatabaseUrl(env.DATABASE_URL, { env });
  } catch (err) {
    log(`LOCAL_TEST_DB_GUARD_REFUSED: ${err?.code || "LOCAL_TEST_DATABASE_URL_INVALID"}`);
    return exit(1);
  }
  try {
    await verifyLocalTestDatabaseIdentity(pool, { log });
  } catch (err) {
    log(`LOCAL_TEST_DB_GUARD_REFUSED: ${err?.code || "LOCAL_TEST_DATABASE_IDENTITY_FAILED"}`);
    return exit(1);
  }
  onVerified();
  return listen(port, () => {
    log(`MOTRI_IQ Backend running on port ${port} (local-test DB verified)`);
  });
}
