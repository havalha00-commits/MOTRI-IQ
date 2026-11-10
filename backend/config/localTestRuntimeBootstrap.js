import fs from "node:fs";
import path from "node:path";

// G10.62 P3.4A: isolated local-test bootstrap helpers.
// - Loads ONLY an explicitly selected env file (simple KEY=VALUE parser), or uses explicitly prepared process.env.
// - Never loads backend/.env implicitly.
// - Validates explicit env source before importing modules that create DB pool/storage service.
// - No DB/network/service startup performed by this module.

function fail(code) {
  const err = new Error(code);
  err.code = code;
  return err;
}

export function parseEnvFileContent(text) {
  if (typeof text !== "string") throw fail("LOCAL_TEST_ENV_INPUT_INVALID");
  const out = {};
  const lines = text.replace(/^\uFEFF/, "").split(/\r?\n/);
  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) continue;
    const eq = line.indexOf("=");
    if (eq <= 0) throw fail("LOCAL_TEST_ENV_INPUT_INVALID");
    const key = line.slice(0, eq).trim();
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) throw fail("LOCAL_TEST_ENV_INPUT_INVALID");
    let value = line.slice(eq + 1);
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    out[key] = value;
  }
  return out;
}

export function loadExplicitEnvFile(filePath) {
  if (typeof filePath !== "string" || !filePath.trim()) throw fail("LOCAL_TEST_ENV_FILE_REQUIRED");
  const resolved = path.resolve(filePath);
  let text;
  try {
    text = fs.readFileSync(resolved, "utf8");
  } catch {
    throw fail("LOCAL_TEST_ENV_FILE_UNREADABLE");
  }
  return parseEnvFileContent(text);
}

export function applyIsolatedEnv(sourceEnv, targetEnv = process.env) {
  if (!sourceEnv || typeof sourceEnv !== "object" || Array.isArray(sourceEnv)) {
    throw fail("LOCAL_TEST_ENV_INPUT_INVALID");
  }
  for (const [k, v] of Object.entries(sourceEnv)) {
    if (v == null) continue;
    targetEnv[k] = String(v);
  }
  targetEnv.MOTRI_LOCAL_TEST_ISOLATED = "1";
  return targetEnv;
}

export function assertExplicitLocalTestEnvSource(env = process.env) {
  if (env?.MOTRI_LOCAL_TEST_ISOLATED !== "1") throw fail("LOCAL_TEST_EXPLICIT_ENV_REQUIRED");
  if (env?.MOTRI_LOCAL_TEST !== "true") throw fail("LOCAL_TEST_MODE_REQUIRED");
  return true;
}

// Pre-import validation order A-D (no pool/storage module imports, no DB/network).
export async function validateIsolatedLocalTestEnv(env = process.env) {
  assertExplicitLocalTestEnvSource(env);
  const { validateLocalTestDatabaseUrl } = await import("../config/localTestDatabaseGuard.js");
  validateLocalTestDatabaseUrl(env.DATABASE_URL, { env }); // C: URL/db/role/host allowlist
  const { assertLocalTestStorageConfig } = await import("../config/localTestStorageGuard.js");
  assertLocalTestStorageConfig(env); // D: exact LOCAL_S3_* only
  return true;
}
