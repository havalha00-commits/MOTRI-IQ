import pg from "pg";
import { isLocalTestMode, validateLocalTestDatabaseUrl } from "./localTestDatabaseGuard.js";

// G10.62 P3.4A: in isolated local-test bootstrap, never implicitly load backend/.env.
// Normal non-local startup preserves dotenv loading.
if (process.env.MOTRI_LOCAL_TEST_ISOLATED !== "1") {
  const dotenv = await import("dotenv");
  dotenv.default?.config?.();
}

const { Pool } = pg;

export function createPool(env = process.env) {
  if (!env.DATABASE_URL) {
    if (isLocalTestMode(env)) {
      throw new Error("LOCAL_TEST_DATABASE_URL_MISSING");
    }
    throw new Error("DATABASE_URL is missing in .env");
  }

  // G10.62 P2: in local-test mode, fail closed on configured target before creating the pool.
  // Never log or include the URL/components. Non-local behavior unchanged.
  if (isLocalTestMode(env)) {
    try {
      validateLocalTestDatabaseUrl(env.DATABASE_URL, { env });
    } catch (err) {
      throw new Error(err?.code || "LOCAL_TEST_DATABASE_CONFIG_INVALID");
    }
  }

  const pool = new Pool({
    connectionString: env.DATABASE_URL,
    ssl: {
      rejectUnauthorized: false,
    },
    max: 10,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 10000,
  });

  pool.on("error", (err) => {
    console.error("Unexpected database error:", err.message);
  });
  return pool;
}

// G10.62 P3.4C/E: no implicit default pool on module import. Existing routes/services
// import { pool } and use it as a default DB; pool is created lazily on first use.
// Isolated local-test bootstrap creates an explicit pool and injects it into the app.
// In MOTRI_LOCAL_TEST_ISOLATED mode, default pool access fails closed so isolated
// runtime cannot accidentally create/query a default pool; only explicit injected pools
// are allowed. Normal mode preserves lazy creation/compatibility.
let _defaultPool = null;
let _defaultPoolEnv = null;

export function isIsolatedLocalTestRuntime(env = process.env) {
  return env?.MOTRI_LOCAL_TEST_ISOLATED === "1";
}

function getDefaultPool() {
  if (isIsolatedLocalTestRuntime(process.env)) {
    const err = new Error("LOCAL_TEST_DEFAULT_POOL_FORBIDDEN");
    err.code = "LOCAL_TEST_DEFAULT_POOL_FORBIDDEN";
    throw err;
  }
  const envKey = String(process.env.DATABASE_URL || "");
  if (_defaultPool && _defaultPoolEnv === envKey) return _defaultPool;
  _defaultPool = createPool(process.env);
  _defaultPoolEnv = envKey;
  return _defaultPool;
}

function makeLazyMethod(name) {
  return function lazyPoolMethod(...args) {
    const p = getDefaultPool();
    const fn = p[name];
    if (typeof fn !== "function") {
      const err = new Error("LOCAL_TEST_DEFAULT_POOL_METHOD_UNAVAILABLE");
      err.code = "LOCAL_TEST_DEFAULT_POOL_METHOD_UNAVAILABLE";
      throw err;
    }
    return fn.apply(p, args);
  };
}

// Plain delegating object (not a Proxy masquerading as pg.Pool). Exposes common pg.Pool
// methods used by routes/services/tests; lazy-creates default pool only in normal mode.
export const pool = {
  __isLazyDefaultPool: true,
  __getDefaultPool: getDefaultPool,
  query: makeLazyMethod("query"),
  connect: makeLazyMethod("connect"),
  end: makeLazyMethod("end"),
  on: makeLazyMethod("on"),
  off: makeLazyMethod("off"),
  removeListener: makeLazyMethod("removeListener"),
  once: makeLazyMethod("once"),
  emit: makeLazyMethod("emit"),
  addListener: makeLazyMethod("addListener"),
  release: makeLazyMethod("release"),
  get totalCount() { return getDefaultPool().totalCount; },
  get idleCount() { return getDefaultPool().idleCount; },
  get waitingCount() { return getDefaultPool().waitingCount; },
  get options() { return getDefaultPool().options; },
};
