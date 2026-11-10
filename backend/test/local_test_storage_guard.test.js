import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import {
  isLocalTestStorageMode,
  isLocalStorageEndpoint,
  validateLocalTestStorageConfig,
  validateLocalPublicBase,
  assertLocalTestStorageConfig,
  resolveStorageConfig,
  EXACT_LOCAL_S3_ENDPOINT,
} from "../config/localTestStorageGuard.js";
import { createObjectStorageService } from "../services/objectStorage.js";
import { createStorageRouter } from "../routes/storage.js";

const EXACT = "http://127.0.0.1:4566";

function withProcessEnv(patch, fn) {
  const prev = {};
  for (const [k, v] of Object.entries(patch)) {
    prev[k] = Object.prototype.hasOwnProperty.call(process.env, k) ? process.env[k] : undefined;
    if (v === undefined) delete process.env[k]; else process.env[k] = v;
  }
  try {
    return fn();
  } finally {
    for (const [k, v] of Object.entries(prev)) {
      if (v === undefined) delete process.env[k]; else process.env[k] = v;
    }
  }
}

function localProcessEnv(overrides = {}) {
  return {
    MOTRI_LOCAL_TEST: "true",
    LOCAL_S3_ENDPOINT: EXACT,
    LOCAL_S3_ACCESS_KEY_ID: "S3RVER",
    LOCAL_S3_SECRET_ACCESS_KEY: "S3RVER",
    LOCAL_S3_BUCKET: "cars",
    LOCAL_S3_REGION: "us-east-1",
    LOCAL_S3_PUBLIC_BASE: "",
    // Remote vars present must NOT be used in local-test mode
    R2_ENDPOINT: "https://remote-r2.invalid",
    R2_ACCESS_KEY_ID: "R2KEY",
    R2_SECRET_ACCESS_KEY: "R2SECRET",
    R2_PUBLIC_BASE: "https://remote-r2-public.invalid",
    B2_ENDPOINT: "https://remote-b2.invalid",
    B2_KEY_ID: "B2KEY",
    B2_APPLICATION_KEY: "B2SECRET",
    B2_PUBLIC_BASE: "https://remote-b2-public.invalid",
    ...overrides,
  };
}

function mockSvc(localEnvOverrides = {}, extra = {}) {
  return withProcessEnv(localProcessEnv(localEnvOverrides), () =>
    createObjectStorageService({
      env: { MOTRI_LOCAL_TEST: "true" },
      s3Client: { send: async () => ({}) },
      PutObjectCommand: class {},
      GetObjectCommand: class {},
      DeleteObjectCommand: class {},
      getSignedUrl: async () => `${EXACT}/signed`,
      ...extra,
    })
  );
}

test("G10.62 P3.2: local-test mode activates for MOTRI_LOCAL_TEST=true and cannot be bypassed by alternate env", () => {
  withProcessEnv({ MOTRI_LOCAL_TEST: "true" }, () => {
    assert.equal(isLocalTestStorageMode({ MOTRI_LOCAL_TEST: "false" }), true);
    assert.equal(isLocalTestStorageMode({}), true);
  });
  withProcessEnv({ MOTRI_LOCAL_TEST: "false" }, () => {
    assert.equal(isLocalTestStorageMode({ MOTRI_LOCAL_TEST: "true" }), true);
    assert.equal(isLocalTestStorageMode({ MOTRI_LOCAL_TEST: "false" }), false);
  });
  withProcessEnv({ MOTRI_LOCAL_TEST: undefined }, () => {
    assert.equal(isLocalTestStorageMode({}), false);
  });
});

test("G10.62 P3.2: exact local endpoint accepted; wrong host/port/protocol/path/query/fragment rejected", () => {
  const env = { MOTRI_LOCAL_TEST: "true" };
  const ok = { endpoint: EXACT, accessKeyId: "a", secretAccessKey: "b" };
  assert.deepEqual(validateLocalTestStorageConfig(ok, { env }), { active: true });
  assert.equal(isLocalStorageEndpoint(EXACT), true);

  const bad = [
    "http://localhost:4566",
    "http://127.0.0.1:4567",
    "https://127.0.0.1:4566",
    "http://127.0.0.1:4566/path",
    "http://127.0.0.1:4566?x=1",
    "http://127.0.0.1:4566#x",
    "http://[::1]:4566",
    "http://127.0.0.1:4566/",
    "http://user@127.0.0.1:4566",
    "https://remote.example.invalid",
    "://bad",
    "not-a-url",
  ];
  for (const endpoint of bad) {
    assert.throws(
      () => validateLocalTestStorageConfig({ endpoint, accessKeyId: "a", secretAccessKey: "b" }, { env }),
      (e) => e?.code === "LOCAL_TEST_STORAGE_ENDPOINT_NOT_LOCAL" || e?.code === "LOCAL_TEST_STORAGE_ENDPOINT_INVALID",
      `expected rejection for bad endpoint shape`
    );
  }
});

test("G10.62 P3.2: R2/B2 cannot override LOCAL_S3_* in local-test; missing LOCAL_S3_* fails closed", () => {
  withProcessEnv(localProcessEnv(), () => {
    const cfg = resolveStorageConfig({ MOTRI_LOCAL_TEST: "true" });
    assert.equal(cfg.endpoint, EXACT);
    assert.equal(cfg.accessKeyId, "S3RVER");
    assert.equal(cfg.secretAccessKey, "S3RVER");
  });
  withProcessEnv(localProcessEnv({ LOCAL_S3_ENDPOINT: "", LOCAL_S3_ACCESS_KEY_ID: "", LOCAL_S3_SECRET_ACCESS_KEY: "" }), () => {
    assert.throws(() => assertLocalTestStorageConfig({ MOTRI_LOCAL_TEST: "true" }), (e) => e?.code === "LOCAL_TEST_STORAGE_CONFIG_MISSING");
  });
  // R2/B2 present but LOCAL_S3_* missing => fail closed (no remote fallback)
  withProcessEnv(localProcessEnv({ LOCAL_S3_ENDPOINT: undefined, LOCAL_S3_ACCESS_KEY_ID: undefined, LOCAL_S3_SECRET_ACCESS_KEY: undefined }), () => {
    assert.throws(() => assertLocalTestStorageConfig({ MOTRI_LOCAL_TEST: "true" }), (e) => e?.code === "LOCAL_TEST_STORAGE_CONFIG_MISSING" || e?.code === "LOCAL_TEST_STORAGE_CREDENTIALS_MISSING");
  });
});

test("G10.62 P3.2: remote public base rejected (centralized); exact local public base allowed", () => {
  const env = { MOTRI_LOCAL_TEST: "true" };
  assert.throws(() => validateLocalPublicBase("https://remote.example.invalid", { env }), (e) => e?.code === "LOCAL_TEST_STORAGE_PUBLIC_BASE_NOT_LOCAL");
  assert.throws(() => validateLocalPublicBase("http://localhost:4566", { env }), (e) => e?.code === "LOCAL_TEST_STORAGE_PUBLIC_BASE_NOT_LOCAL");
  assert.deepEqual(validateLocalPublicBase(EXACT, { env }), { active: true });
  assert.deepEqual(validateLocalPublicBase("", { env }), { active: true });
  assert.throws(
    () => validateLocalTestStorageConfig({ endpoint: EXACT, accessKeyId: "a", secretAccessKey: "b", publicBase: "https://remote.example.invalid" }, { env }),
    (e) => e?.code === "LOCAL_TEST_STORAGE_PUBLIC_BASE_NOT_LOCAL"
  );
});

test("G10.62 P3.2: getPublicUrl uses centralized local-test validation and rejects remote/mismatched base", async () => {
  const svcOk = mockSvc({ LOCAL_S3_PUBLIC_BASE: EXACT });
  assert.equal(await svcOk.getPublicUrl({ bucket: "cars", key: "u/s/f.jpg" }), `${EXACT}/cars/${encodeURIComponent("u/s/f.jpg")}`);
  // Fallback to exact endpoint when public base empty is allowed by service policy? endpoint is exact; service uses endpoint fallback.
  const svcNoBase = mockSvc({ LOCAL_S3_PUBLIC_BASE: "" });
  assert.equal(await svcNoBase.getPublicUrl({ bucket: "cars", key: "k.jpg" }), `${EXACT}/cars/k.jpg`);
  // Remote public base resolved from process.env must fail in local-test.
  await assert.rejects(async () => {
    const svc = mockSvc({ LOCAL_S3_PUBLIC_BASE: "https://remote.example.invalid" });
    await svc.getPublicUrl({ bucket: "cars", key: "k.jpg" });
  }, (e) => e?.code === "LOCAL_TEST_STORAGE_PUBLIC_BASE_NOT_LOCAL");
});

test("G10.62 P3.2: createObjectStorageService enforces local-only rules and alternate env cannot bypass", () => {
  // Caller passes remote endpoint/creds explicitly; local-test must still read LOCAL_S3_* from process.env and fail if missing.
  withProcessEnv(localProcessEnv({ LOCAL_S3_ENDPOINT: "", LOCAL_S3_ACCESS_KEY_ID: "", LOCAL_S3_SECRET_ACCESS_KEY: "" }), () => {
    assert.throws(
      () => createObjectStorageService({ env: { MOTRI_LOCAL_TEST: "true" }, endpoint: "https://r2.invalid", accessKeyId: "r", secretAccessKey: "s" }),
      (e) => e?.code === "LOCAL_TEST_STORAGE_CONFIG_MISSING" || e?.code === "LOCAL_TEST_STORAGE_CREDENTIALS_MISSING"
    );
  });
  // process.env local-test active, caller tries to bypass by passing non-local env: still enforced.
  withProcessEnv(localProcessEnv({ LOCAL_S3_ENDPOINT: "http://localhost:4566" }), () => {
    assert.throws(
      () => createObjectStorageService({ env: { MOTRI_LOCAL_TEST: "false" }, endpoint: "https://r2.invalid", accessKeyId: "r", secretAccessKey: "s" }),
      (e) => e?.code === "LOCAL_TEST_STORAGE_ENDPOINT_NOT_LOCAL" || e?.code === "LOCAL_TEST_STORAGE_CONFIG_MISSING"
    );
  });
  // Explicit local config from process.env works.
  const svc = mockSvc();
  assert.equal(typeof svc.upload, "function");
});

test("G10.62 P3.2: storage router in local-test uses process env local config; invalid local config returns 503", async () => {
  await withProcessEnv(localProcessEnv({ LOCAL_S3_ENDPOINT: "https://remote.example.invalid" }), async () => {
    const router = createStorageRouter({
      authenticate: (_req, _res, next) => next(),
      env: { MOTRI_LOCAL_TEST: "true" },
    });
    const layer = router.stack.find((l) => l.route?.path === "/sign" && l.route?.methods?.get);
    const handler = layer.route.stack[layer.route.stack.length - 1].handle;
    const res = { statusCode: 200, body: null, status(c) { this.statusCode = c; return this; }, json(b) { this.body = b; return this; } };
    await handler({ query: { bucket: "cars", path: "a/b/c.jpg" }, user: { id: "u1" } }, res);
    assert.equal(res.statusCode, 503);
  });
});

test("G10.62 P3.2: non-local provider behavior unchanged (no exact-endpoint requirement, R2/B2 precedence preserved)", () => {
  const nonLocal = { MOTRI_LOCAL_TEST: "false", R2_ENDPOINT: "https://r2.example.invalid", R2_ACCESS_KEY_ID: "k", R2_SECRET_ACCESS_KEY: "s", R2_PUBLIC_BASE: "https://pub.invalid" };
  withProcessEnv(nonLocal, () => {
    assert.deepEqual(assertLocalTestStorageConfig(nonLocal), { active: false });
    const cfg = resolveStorageConfig(nonLocal);
    assert.equal(cfg.endpoint, "https://r2.example.invalid");
    assert.equal(cfg.accessKeyId, "k");
    assert.equal(cfg.publicBase, "https://pub.invalid");
    // R2/B2 precedence preserved in non-local: B2 only used when R2 missing.
    const b2 = resolveStorageConfig({ MOTRI_LOCAL_TEST: "false", B2_ENDPOINT: "https://b2.example.invalid", B2_KEY_ID: "bk", B2_APPLICATION_KEY: "bs" });
    assert.equal(b2.endpoint, "https://b2.example.invalid");
    // createObjectStorageService in non-local mode accepts explicit remote config (legacy behavior), no exact-endpoint requirement.
    const svc = createObjectStorageService({
      env: nonLocal,
      endpoint: "https://remote.example.invalid",
      accessKeyId: "a",
      secretAccessKey: "b",
      s3Client: { send: async () => ({}) },
      GetObjectCommand: class {},
      getSignedUrl: async () => "https://signed.invalid/x",
    });
    assert.equal(typeof svc.getSignedUrl, "function");
  });
});

test("G10.62 P3.2: static wiring sanity (server/storage/router/local config guard present)", () => {
  const here = path.dirname(fileURLToPath(import.meta.url));
  const server = fs.readFileSync(path.resolve(here, "../server.js"), "utf8");
  const svc = fs.readFileSync(path.resolve(here, "../services/objectStorage.js"), "utf8");
  const guard = fs.readFileSync(path.resolve(here, "../config/localTestStorageGuard.js"), "utf8");
  // P3.4A refactor: local-test enforcement preserved through shared helper/bootstrap/guard.
  assert.ok(server.includes("LOCAL_TEST_STORAGE_GUARD_REFUSED"));
  assert.ok(server.includes("createStorageServiceForEnv") || server.includes("assertLocalTestStorageConfig"));
  assert.ok(svc.includes("resolveStorageConfig(process.env)"));
  assert.ok(svc.includes("validateLocalPublicBase"));
  assert.ok(guard.includes("http://127.0.0.1:4566"));
  assert.ok(guard.includes("LOCAL_S3_"));
  assert.equal(EXACT_LOCAL_S3_ENDPOINT, EXACT);
});

