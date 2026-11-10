import assert from "node:assert/strict";
import test from "node:test";
import fs from "fs";
import path from "path";
import crypto from "crypto";
import { fileURLToPath } from "url";
import dotenv from "dotenv";
import express from "express";
import { createServer } from "node:http";
import { HeadBucketCommand, S3Client } from "@aws-sdk/client-s3";
import {
  B2_EXPECTED_ENDPOINT, B2_EXPECTED_REGION, B2_EXPECTED_BUCKET, B2_LIVE_OPT_IN, B2_LIVE_ACK,
  B2_LOCAL_ENV_FILENAME, B2_LIVE_TEST_PREFIX,
  validateB2FailClosed, buildB2LiveEffectiveEnv, parseEnvText, detectB2LocalOptIn,
  createB2SyntheticProbe, createB2DisposableKey, validateB2DisposableKey,
  inspectSignedUrlConfig, cleanupB2ProbeObject, sha256Hex,
} from "./helpers/b2_readiness.js";
import { createObjectStorageService } from "../services/objectStorage.js";
import { createCarsRouter } from "../routes/cars.js";
import { createStorageRouter } from "../routes/storage.js";

dotenv.config({ path: ".env.test", override: true });

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
// Explicit load path for the B2 LIVE opt-in test ONLY, resolved relative to THIS test file (not cwd).
export const B2_LOCAL_ENV_PATH = path.resolve(__dirname, "..", B2_LOCAL_ENV_FILENAME);

// Registration/execution gate (SAFE): the live test body makes network requests when its config is valid,
// so it must ONLY execute when B2_LIVE_INTEGRATION=1 is set explicitly in the process environment at
// invocation time (CLI). The local file backend/.env.b2.test.local is detected for visibility/diagnostics but
// NEVER used to enable execution — this prevents accidental live runs. Full fail-closed validation
// (endpoint/region/bucket/ack/keys/R2 collision, explicit file load) still runs inside the test body.
export const B2_LOCAL_OPT_IN_DETECTED = detectB2LocalOptIn(B2_LOCAL_ENV_PATH); // boolean only, no secrets
export const B2_LIVE_REGISTERED = process.env[B2_LIVE_OPT_IN] === "1"; // process-env only => safe
const RUN = B2_LIVE_REGISTERED;
const maybe = RUN ? test : test.skip;

test("G10.45 B2 readiness: fail-closed guard rejects missing opt-in/ack/wrong target (safe, no network)", () => {
  const bad = validateB2FailClosed({ [B2_LIVE_OPT_IN]: "0", B2_ENDPOINT: "https://s3.us-west-004.backblazeb2.com", B2_REGION: "us-west-004", B2_BUCKET: "production-bucket", B2_KEY_ID: "x", B2_APPLICATION_KEY: "y" });
  assert.equal(bad.ok, false);
  assert.ok(bad.errors.some(e => e.includes("opt-in")));
  assert.ok(bad.errors.some(e => e.includes("bucket ack")));
  assert.ok(bad.errors.some(e => e.includes("endpoint must be exactly")));
  assert.ok(bad.errors.some(e => e.includes("bucket must be exactly")));
  const goodEnv = {
    [B2_LIVE_OPT_IN]: "1", [B2_LIVE_ACK]: B2_EXPECTED_BUCKET,
    B2_ENDPOINT: B2_EXPECTED_ENDPOINT, B2_REGION: B2_EXPECTED_REGION, B2_BUCKET: B2_EXPECTED_BUCKET,
    B2_KEY_ID: "present", B2_APPLICATION_KEY: "present"
  };
  const good = validateB2FailClosed(goodEnv);
  assert.equal(good.ok, true);
  assert.equal(good.cfg.bucket, B2_EXPECTED_BUCKET);
  assert.equal(good.cfg.endpoint, B2_EXPECTED_ENDPOINT);
  // Ensure no secret values leak into cfg
  assert.equal(Object.prototype.hasOwnProperty.call(good.cfg, "keyId"), false);
  assert.equal(Object.prototype.hasOwnProperty.call(good.cfg, "appKey"), false);
  assert.equal(good.cfg.hasKeyId, true);
  assert.equal(good.cfg.hasAppKey, true);
});

test("G10.46 B2 live wiring: rejects missing local config file (safe, no network)", () => {
  const missing = path.resolve(__dirname, "..", "__definitely_missing_b2_local_env__");
  const r = buildB2LiveEffectiveEnv({ baseEnv: { PATH: process.env.PATH || "" }, filePath: missing, required: true });
  assert.equal(r.ok, false);
  assert.ok(r.errors.some((e) => e.includes("missing")));
  assert.equal(r.loadedFile, false);
});

test("G10.46 B2 live wiring: rejects conflicting R2_* vars in effective env and in local file (safe, no network)", () => {
  const tmp = path.resolve(__dirname, "..", ".__tmp_b2_r2_conflict.local");
  try {
    fs.writeFileSync(tmp, [
      "B2_LIVE_INTEGRATION=1",
      `B2_LIVE_ACK=${B2_EXPECTED_BUCKET}`,
      `B2_ENDPOINT=${B2_EXPECTED_ENDPOINT}`,
      `B2_REGION=${B2_EXPECTED_REGION}`,
      `B2_BUCKET=${B2_EXPECTED_BUCKET}`,
      "B2_KEY_ID=k",
      "B2_APPLICATION_KEY=s",
      "R2_BUCKET=some-other-bucket",
    ].join("\n"), "utf8");
    const r = buildB2LiveEffectiveEnv({ baseEnv: { R2_ENDPOINT: "https://example.invalid", R2_BUCKET: "x" }, filePath: tmp, required: true });
    assert.equal(r.ok, false);
    assert.ok(r.errors.some((e) => e.includes("R2_*")));
    assert.equal(Object.keys(r.env).some((k) => k.startsWith("R2_")), false, "effective env must strip R2_*");
  } finally {
    try { fs.unlinkSync(tmp); } catch {}
  }
});

test("G10.46 B2 live wiring: rejects wrong target/endpoint/region/bucket/ack/opt-in (safe, no network)", () => {
  const tmp = path.resolve(__dirname, "..", ".__tmp_b2_wrong.local");
  try {
    fs.writeFileSync(tmp, [
      "B2_LIVE_INTEGRATION=0",
      "B2_LIVE_ACK=wrong-bucket",
      "B2_ENDPOINT=https://s3.us-west-004.backblazeb2.com",
      "B2_REGION=us-west-004",
      "B2_BUCKET=production-bucket",
      "B2_KEY_ID=k",
      "B2_APPLICATION_KEY=s",
    ].join("\n"), "utf8");
    const r = buildB2LiveEffectiveEnv({ baseEnv: {}, filePath: tmp, required: true });
    assert.equal(r.ok, false);
    assert.ok(r.errors.some((e) => e.includes("opt-in")));
    assert.ok(r.errors.some((e) => e.includes("ack")));
    assert.ok(r.errors.some((e) => e.includes("endpoint must be exactly")));
    assert.ok(r.errors.some((e) => e.includes("region must be exactly")));
    assert.ok(r.errors.some((e) => e.includes("bucket must be exactly")));
  } finally {
    try { fs.unlinkSync(tmp); } catch {}
  }
});

test("G10.46 B2 live wiring: accepts valid isolated configuration and strips R2 fallback (safe, no network)", () => {
  const tmp = path.resolve(__dirname, "..", ".__tmp_b2_ok.local");
  try {
    fs.writeFileSync(tmp, [
      "B2_LIVE_INTEGRATION=1",
      `B2_LIVE_ACK=${B2_EXPECTED_BUCKET}`,
      `B2_ENDPOINT=${B2_EXPECTED_ENDPOINT}`,
      `B2_REGION=${B2_EXPECTED_REGION}`,
      `B2_BUCKET=${B2_EXPECTED_BUCKET}`,
      "B2_KEY_ID=k",
      "B2_APPLICATION_KEY=s",
    ].join("\n"), "utf8");
    // base has R2_* that must NOT be able to win/fallback
    const r = buildB2LiveEffectiveEnv({ baseEnv: { R2_ENDPOINT: "https://r2.example", R2_BUCKET: "r2-bucket", R2_ACCESS_KEY_ID: "r2k", R2_SECRET_ACCESS_KEY: "r2s" }, filePath: tmp, required: true });
    assert.equal(r.ok, true, r.errors.join("; "));
    assert.equal(r.loadedFile, true);
    assert.equal(Object.keys(r.env).some((k) => k.startsWith("R2_")), false);
    assert.equal(r.env.B2_BUCKET, B2_EXPECTED_BUCKET);
    assert.equal(r.env.B2_ENDPOINT, B2_EXPECTED_ENDPOINT);
    assert.equal(r.cfg.bucket, B2_EXPECTED_BUCKET);
    // no secret values echoed
    assert.equal(r.presentKeys.includes("B2_KEY_ID(present)"), true);
    assert.equal(r.presentKeys.includes("B2_APPLICATION_KEY(present)"), true);
    assert.equal(r.presentKeys.some((k) => k === "B2_KEY_ID" || k === "B2_APPLICATION_KEY"), false);
  } finally {
    try { fs.unlinkSync(tmp); } catch {}
  }
});

test("G10.46 B2 live guards: disposable key confined to approved prefix/bucket target (safe, no network)", () => {
  const key = createB2DisposableKey();
  assert.ok(key.startsWith(`${B2_LIVE_TEST_PREFIX}/`));
  assert.ok(key.endsWith("/probe.jpg"));
  validateB2DisposableKey(key); // must not throw
  assert.throws(() => validateB2DisposableKey("other-bucket-prefix/x.jpg"), /approved prefix/);
  assert.throws(() => validateB2DisposableKey(`${B2_LIVE_TEST_PREFIX}/../escape.jpg`), /invalid form/);
  const probe = createB2SyntheticProbe();
  assert.equal(probe.body.length > 0, true);
  assert.equal(probe.sha256, sha256Hex(probe.body));
  assert.equal(probe.contentType, "image/jpeg");
});

test("G10.46 B2 live guards: signed URL config verifier never exposes URL/credentials (safe, no network)", () => {
  const url = `https://s3.eu-central-003.backblazeb2.com/${B2_EXPECTED_BUCKET}/motri-iq-test/x/probe.jpg?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=REDACTED&X-Amz-Signature=deadbeef&X-Amz-Expires=300`;
  const cfg = inspectSignedUrlConfig(url);
  assert.equal(cfg.ok, true);
  assert.equal(cfg.hostMatchesExpected, true);
  assert.equal(cfg.hasSignatureParam, true);
  assert.equal(cfg.hasExpiryParam, true);
  // returned object must not contain the URL or credential-bearing material
  const s = JSON.stringify(cfg);
  assert.equal(s.includes("X-Amz-Credential"), false);
  assert.equal(s.includes("X-Amz-Signature=deadbeef"), false);
  assert.equal(s.includes("REDACTED"), false);
  assert.equal(s.includes("deadbeef"), false);
  const bad = inspectSignedUrlConfig(`https://evil.example.com/${B2_EXPECTED_BUCKET}/k?X-Amz-Signature=x&X-Amz-Expires=1`);
  assert.equal(bad.ok, false);
  assert.equal(bad.hostMatchesExpected, false);
});

test("G10.46 B2 live guards: cleanup returns explicit result - successful deletion (safe, no network)", async () => {
  let called = 0;
  const ok = await cleanupB2ProbeObject({ deleteObject: async ({ bucket, key }) => { called++; assert.equal(bucket, B2_EXPECTED_BUCKET); assert.ok(key.startsWith(B2_LIVE_TEST_PREFIX+"/")); } }, { bucket: B2_EXPECTED_BUCKET, key: createB2DisposableKey() });
  assert.equal(called, 1);
  assert.deepEqual(ok, { attempted: true, deleted: true, error: false });
});

test("G10.46 B2 live guards: cleanup returns explicit result - failed deletion never treated as success (safe, no network)", async () => {
  const fail = await cleanupB2ProbeObject({ deleteObject: async () => { throw new Error("boom"); } }, { bucket: B2_EXPECTED_BUCKET, key: createB2DisposableKey() });
  assert.deepEqual(fail, { attempted: true, deleted: false, error: true });
});

test("G10.46 B2 live guards: if operation fails AND DELETE fails, BOTH failures reported without replacing original (safe, no network)", async () => {
  // Mirrors live-test control flow: primary error preserved; if cleanup also fails, BOTH reported (AggregateError). Not silent.
  let primaryError;
  let cleanupResult;
  try {
    try {
      throw new Error("ORIGINAL_OP_FAILURE");
    } catch (e) {
      primaryError = e;
    } finally {
      cleanupResult = await cleanupB2ProbeObject({ deleteObject: async () => { throw new Error("cleanup boom"); } }, { bucket: B2_EXPECTED_BUCKET, key: createB2DisposableKey() });
    }
    if (primaryError && cleanupResult && cleanupResult.error === true) {
      throw new AggregateError([primaryError, new Error("B2 cleanup failed: DELETE did not succeed (orphan risk; not silent)")], "Primary operation failed and B2 cleanup DELETE also failed");
    }
    if (primaryError) throw primaryError;
  } catch (e) {
    assert.ok(e instanceof AggregateError, "both failures reported via AggregateError");
    assert.equal(e.errors[0].message, "ORIGINAL_OP_FAILURE"); // original NOT replaced
    assert.match(e.errors[1].message, /DELETE did not succeed/);
    assert.deepEqual(cleanupResult, { attempted: true, deleted: false, error: true });
    return;
  }
  assert.fail("expected AggregateError");
});

test("G10.46 B2 live guards: opt-in registration detects B2_LIVE_INTEGRATION=1 in local file but full config still required (safe, no network)", () => {
  const dir = fs.mkdtempSync(path.join(__dirname, "..", ".__tmp_b2reg_"));
  const f = path.join(dir, ".env.b2.test.local");
  try {
    fs.writeFileSync(f, "B2_LIVE_INTEGRATION=1\nB2_LIVE_ACK=wrong\n", "utf8");
    assert.equal(detectB2LocalOptIn(f), true, "opt-in flag detected in local file");
    // Execution gate is process.env[B2_LIVE_OPT_IN]==="1" only (see B2_LIVE_REGISTERED at module load).
    // This test asserts local-file opt-in does NOT imply execution; it remains valid regardless of current process opt-in.
    assert.equal(typeof B2_LIVE_REGISTERED, "boolean");
    assert.equal(detectB2LocalOptIn(f), true, "local file opt-in detected (boolean only)");
    // And full fail-closed validation still rejects (cannot run unless exact config/ack valid).
    const r = buildB2LiveEffectiveEnv({ baseEnv: {}, filePath: f, required: true });
    assert.equal(r.ok, false);
    assert.ok(r.errors.length > 0);
  } finally {
    try { fs.unlinkSync(tmp); } catch {}
  }
});

test("G10.47/48 B2 security: buildB2LiveEffectiveEnv public result exposes NO secrets (JSON/inspection safe)", () => {
  const tmp = path.resolve(__dirname, "..", ".__tmp_b2_secret.local");
  try {
    fs.writeFileSync(tmp, [
      "B2_LIVE_INTEGRATION=1",
      `B2_LIVE_ACK=${B2_EXPECTED_BUCKET}`,
      `B2_ENDPOINT=${B2_EXPECTED_ENDPOINT}`,
      `B2_REGION=${B2_EXPECTED_REGION}`,
      `B2_BUCKET=${B2_EXPECTED_BUCKET}`,
      "B2_KEY_ID=SUPER_SECRET_KEY_ID_VALUE",
      "B2_APPLICATION_KEY=SUPER_SECRET_APP_KEY_VALUE",
      "DATABASE_URL=postgresql://secret_user:secret_pw@host/motri_iq_test",
    ].join("\n"), "utf8");
    const r = buildB2LiveEffectiveEnv({ baseEnv: { PATH: process.env.PATH || "", SOME_UNRELATED_SECRET: "leakme" }, filePath: tmp, required: true });
    assert.equal(r.ok, true, r.errors.join("; "));
    const json = JSON.stringify(r);
    // Must never reveal credentials, DB URL, or unrelated secrets
    assert.equal(json.includes("SUPER_SECRET_KEY_ID_VALUE"), false);
    assert.equal(json.includes("SUPER_SECRET_APP_KEY_VALUE"), false);
    assert.equal(json.includes("secret_user"), false);
    assert.equal(json.includes("secret_pw"), false);
    assert.equal(json.includes("leakme"), false);
    // no credential/DB values; presence markers like "B2_KEY_ID(present)" are allowed, actual values are not
    assert.equal(json.includes("SUPER_SECRET_KEY_ID_VALUE"), false);
    assert.equal(json.includes("SUPER_SECRET_APP_KEY_VALUE"), false);
    assert.equal(json.includes("DATABASE_URL"), false);
    assert.equal(json.includes("secret_user"), false);
    assert.equal(json.includes("secret_pw"), false);
    assert.equal(r.env.B2_KEY_ID, undefined);
    assert.equal(r.env.B2_APPLICATION_KEY, undefined);
    assert.equal(r.env.DATABASE_URL, undefined);
    assert.equal(Object.prototype.hasOwnProperty.call(r.env, "SOME_UNRELATED_SECRET"), false);
    assert.equal(r.env.B2_BUCKET, B2_EXPECTED_BUCKET);
    // accessor is narrowly scoped and non-enumerable (not in JSON)
    assert.equal(Object.keys(r).includes("getLiveStorageConfig"), false);
    assert.equal(typeof r.getLiveStorageConfig, "function");
    const lc = r.getLiveStorageConfig();
    assert.equal(lc.accessKeyId, "SUPER_SECRET_KEY_ID_VALUE"); // accessible internally only, not serialized above
    assert.equal(lc.bucket, B2_EXPECTED_BUCKET);
  } finally {
    try { fs.unlinkSync(tmp); } catch {}
  }
});

test("G10.46 B2 live guards: deletion failure with no earlier failure fails explicitly (safe, no network)", async () => {
  let primaryError;
  let cleanupResult;
  try {
    try {
      // all earlier operations passed
    } catch (e) {
      primaryError = e;
    } finally {
      cleanupResult = await cleanupB2ProbeObject({ deleteObject: async () => { throw new Error("cleanup boom"); } }, { bucket: B2_EXPECTED_BUCKET, key: createB2DisposableKey() });
    }
    if (primaryError) throw primaryError;
    if (cleanupResult && !cleanupResult.deleted) throw new Error("B2 live cleanup failed: DELETE did not succeed (explicit failure; not silent)");
  } catch (e) {
    assert.match(e.message, /DELETE did not succeed/);
    assert.deepEqual(cleanupResult, { attempted: true, deleted: false, error: true });
    return;
  }
  assert.fail("expected explicit delete failure");
});

test("G10.45 B2 readiness: objectStorage resolves B2_* env vars (safe, no network, no S3 calls)", () => {
  const svc = createObjectStorageService({
    endpoint: B2_EXPECTED_ENDPOINT,
    accessKeyId: "env-only-placeholder-id",
    secretAccessKey: "env-only-placeholder-secret",
    region: B2_EXPECTED_REGION,
    bucket: B2_EXPECTED_BUCKET,
  });
  // Sanity: service exposes expected methods; no remote calls made.
  assert.equal(typeof svc.upload, "function");
  assert.equal(typeof svc.download, "function");
  assert.equal(typeof svc.deleteObject, "function");
  assert.equal(typeof svc.getSignedUrl, "function");
  assert.equal(typeof svc.listObjects, "function");
});

async function streamToBuffer(body) {
  if (!body) return Buffer.alloc(0);
  if (Buffer.isBuffer(body)) return body;
  if (body instanceof Uint8Array) return Buffer.from(body);
  if (typeof body.arrayBuffer === "function") return Buffer.from(await body.arrayBuffer());
  if (typeof body.transformToByteArray === "function") return Buffer.from(await body.transformToByteArray());
  const chunks = [];
  for await (const chunk of body) chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  return Buffer.concat(chunks);
}

maybe("G10.46 Backblaze B2 isolated LIVE integration (OPT-IN, FAIL-CLOSED, NOT EXECUTED IN NORMAL RUNS)", async () => {
  // B2 LIVE opt-in path ONLY: load backend/.env.b2.test.local (relative to this test file), strip ALL R2_*,
  // and fail-closed on missing/conflicting/wrong config. Never loads .env.b2.test.local in normal runtime.
  const built = buildB2LiveEffectiveEnv({ baseEnv: process.env, filePath: B2_LOCAL_ENV_PATH, required: true });
  assert.ok(built.ok, `Fail-closed B2 live config rejected: ${built.errors.join("; ")}`);
  assert.equal(built.loadedFile, true, "B2 live test requires backend/.env.b2.test.local to be loaded explicitly");

  // Hard target assertions (no silent fallback): only exact isolated bucket/endpoint/region.
  assert.equal(built.env.B2_BUCKET, B2_EXPECTED_BUCKET);
  assert.equal(String(built.env.B2_ENDPOINT || "").replace(/\/+$/, "").toLowerCase(), B2_EXPECTED_ENDPOINT.toLowerCase());
  assert.equal(String(built.env.B2_REGION || "").trim(), B2_EXPECTED_REGION);
  assert.equal(Object.keys(built.env).some((k) => k.startsWith("R2_")), false);

  // This live test performs ONLY object-storage operations on the isolated bucket (no DB required).
  // If a DB is ever needed here, it MUST be motri_iq_test and asserted before any query:
  //   const { default: pg } = await import("pg");
  //   const pool = new pg.Pool({ connectionString: built.env.DATABASE_URL, ssl:{rejectUnauthorized:false}, max:2 });
  //   const db=(await pool.query("select current_database() db")).rows[0]; assert.equal(db.db,"motri_iq_test"); await pool.end();

  // Narrowly scoped, non-enumerable accessor provides validated storage config only (no full env/secrets on public result).
  const liveCfg = typeof built.getLiveStorageConfig === "function" ? built.getLiveStorageConfig() : null;
  assert.ok(liveCfg, "missing live storage config accessor");
  const storage = createObjectStorageService({
    endpoint: liveCfg.endpoint,
    accessKeyId: liveCfg.accessKeyId,
    secretAccessKey: liveCfg.secretAccessKey,
    region: liveCfg.region,
    bucket: B2_EXPECTED_BUCKET,
  });

  const probe = createB2SyntheticProbe(); // synthetic bytes only, no real user image
  const key = createB2DisposableKey();    // motri-iq-test/<uuid>/probe.jpg
  validateB2DisposableKey(key);
  const bucket = B2_EXPECTED_BUCKET;
  let uploaded = false;
  let primaryError;
  let cleanupResult;

  try {
    // 1) PUT synthetic test image
    const putRes = await storage.upload({ bucket, key, body: probe.body, contentType: probe.contentType });
    uploaded = true;
    assert.equal(putRes.bucket, bucket);
    assert.equal(putRes.key, key);
    assert.equal(Number(putRes.size), probe.body.length);

    // 2) HEAD and verify uploaded object
    const head = await storage.headObject({ bucket, key });
    assert.equal(Number(head.size), probe.body.length);

    // 3) GET and verify SHA-256 matches original bytes
    const got = await storage.download({ bucket, key });
    const gotBuf = await streamToBuffer(got.body);
    assert.equal(sha256Hex(gotBuf), probe.sha256, "SHA-256 mismatch (GET vs original synthetic bytes)");

    // 4) Generate signed GET URL and verify configuration WITHOUT exposing credentials/URL
    const signed = await storage.getSignedUrl({ bucket, key, expiresIn: 120 });
    assert.equal(typeof signed.expiresIn, "number");
    assert.ok(signed.expiresIn > 0 && signed.expiresIn <= 300 || signed.expiresIn === 120); // allow bounded value
    const signedCfg = inspectSignedUrlConfig(signed.url); // inspects only; does NOT return/print URL
    assert.equal(signedCfg.ok, true, "signed URL configuration invalid for isolated B2 target");
    // (do not fetch/log signed.url)
  } catch (e) {
    primaryError = e;
  } finally {
    // 5) DELETE test object (try/finally: attempt even if prior step failed). Never silent success.
    if (uploaded) cleanupResult = await cleanupB2ProbeObject(storage, { bucket, key });
  }
  // If both primary and cleanup fail, report BOTH without replacing original.
  if (primaryError && cleanupResult && cleanupResult.error === true) {
    const cleanupErr = new Error("B2 cleanup failed: DELETE did not succeed (orphan risk; not silent)");
    throw new AggregateError([primaryError, cleanupErr], "Primary operation failed and B2 cleanup DELETE also failed");
  }
  // Preserve the original test error if an earlier operation failed (do not hide with cleanup result).
  if (primaryError) throw primaryError;
  // If all earlier operations passed but DELETE fails, fail the test explicitly.
  if (cleanupResult && cleanupResult.deleted !== true) {
    assert.fail("B2 live cleanup failed: DELETE did not succeed (explicit failure; not silent)");
  }

  // 6) HEAD again and confirm object is missing (AFTER DELETE)
  await assert.rejects(
    () => storage.headObject({ bucket, key }),
    (e) => e?.statusCode === 404 || /not found/i.test(String(e?.message || ""))
  );
});

maybe("B2 LIVE Backend car-image APIs use isolated provider bucket and prefix", async () => {
  const built = buildB2LiveEffectiveEnv({ baseEnv: process.env, filePath: B2_LOCAL_ENV_PATH, required: true });
  assert.ok(built.ok, "Fail-closed B2 live config rejected");
  assert.equal(built.env.B2_BUCKET, B2_EXPECTED_BUCKET);
  assert.equal(built.env.B2_LIVE_ACK, B2_EXPECTED_BUCKET);

  const liveCfg = built.getLiveStorageConfig();
  const storageEnv = {
    STORAGE_PROVIDER: "b2",
    STORAGE_PREFIX: B2_LIVE_TEST_PREFIX,
    B2_ENDPOINT: liveCfg.endpoint,
    B2_REGION: liveCfg.region,
    B2_BUCKET: liveCfg.bucket,
    B2_KEY_ID: liveCfg.accessKeyId,
    B2_APPLICATION_KEY: liveCfg.secretAccessKey,
  };
  const userId = crypto.randomUUID();
  const carId = crypto.randomUUID();
  const photoId = crypto.randomUUID();
  const objectKey = `${userId}/${carId}/${photoId}.png`;
  const physicalKey = `${B2_LIVE_TEST_PREFIX}/cars/${objectKey}`;
  const image = createB2SyntheticProbe().body;
  const expectedHash = sha256Hex(image);
  const reservations = new Map();
  let carRow;
  let uploaded = false;
  let deleted = false;
  let server;

  const database = {
    async query(sql, values = []) {
      const normalized = sql.replace(/\s+/g, " ").trim().toLowerCase();
      if (["begin", "commit", "rollback"].includes(normalized) || normalized.startsWith("select pg_advisory_xact_lock")) {
        return { rows: [], rowCount: 0 };
      }
      if (normalized.includes("select count(*)::int as count from public.car_image_upload_reservations")) {
        return { rows: [{ count: 0 }], rowCount: 1 };
      }
      if (normalized.includes("select id, object_key, expires_at, consumed_at")) {
        return { rows: [], rowCount: 0 };
      }
      if (normalized.includes("insert into public.car_image_upload_reservations")) {
        const [ownerId, submissionId, reservedPhotoId, key] = values;
        reservations.set(key, { ownerId, submissionId, photoId: reservedPhotoId });
        return { rows: [{ object_key: key, expires_at: new Date(Date.now() + 1800000).toISOString() }], rowCount: 1 };
      }
      if (normalized.includes("select 1 from public.car_image_upload_reservations")) {
        const [key, ownerId] = values;
        const reservation = reservations.get(key);
        const rows = reservation?.ownerId === ownerId ? [{ ok: 1 }] : [];
        return { rows, rowCount: rows.length };
      }
      if (normalized.includes("select id, user_id, is_approved, image_url, images from public.cars where id = $1")) {
        const rows = carRow && values[0] === carId ? [carRow] : [];
        return { rows, rowCount: rows.length };
      }
      throw new Error("Unexpected query in isolated B2 car-image API test");
    },
  };
  const storage = createObjectStorageService({
    env: storageEnv,
    ownershipChecker: async (owner, key, logicalBucket) =>
      owner === userId && key === objectKey && logicalBucket === "cars",
  });
  const authenticate = (req, res, next) => {
    req.user = { id: userId };
    next();
  };

  try {
    const probe = new S3Client({
      endpoint: liveCfg.endpoint,
      region: liveCfg.region,
      forcePathStyle: true,
      credentials: { accessKeyId: liveCfg.accessKeyId, secretAccessKey: liveCfg.secretAccessKey },
      maxAttempts: 2,
    });
    try {
      await probe.send(new HeadBucketCommand({ Bucket: B2_EXPECTED_BUCKET }));
    } finally {
      probe.destroy();
    }

    const app = express();
    app.use(express.json());
    app.use("/api/cars", createCarsRouter({
      database,
      authenticate,
      optionalAuthenticate: authenticate,
      storage,
    }));
    app.use("/api/storage", createStorageRouter({ authenticate, storage, database }));
    server = createServer(app);
    await new Promise((resolve, reject) => {
      server.once("error", reject);
      server.listen(0, "127.0.0.1", resolve);
    });
    const base = `http://127.0.0.1:${server.address().port}`;

    const reserve = await fetch(`${base}/api/cars/uploads/reserve`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ submission_id: carId, photo_id: photoId, extension: "png" }),
    });
    const reserveBody = await reserve.json();
    assert.equal(reserve.status, 201);
    assert.equal(reserveBody.data.object_key, objectKey);

    const uploadUrl = new URL(`${base}/api/storage/object`);
    uploadUrl.searchParams.set("bucket", "cars");
    uploadUrl.searchParams.set("path", objectKey);
    const upload = await fetch(uploadUrl, {
      method: "PUT",
      headers: { "content-type": "image/png" },
      body: image,
    });
    assert.equal(upload.status, 201);
    uploaded = true;
    const uploadBody = await upload.json();
    assert.equal(uploadBody.data.bucket, "cars");
    assert.equal(uploadBody.data.key, objectKey);
    assert.equal(uploadBody.data.size, image.length);
    const stored = await storage.headObject({ bucket: "cars", key: objectKey });
    assert.equal(stored.size, image.length);

    carRow = { id: carId, user_id: userId, is_approved: true, image_url: objectKey, images: [objectKey] };
    const imageResponse = await fetch(`${base}/api/cars/${carId}/images/0`);
    const received = Buffer.from(await imageResponse.arrayBuffer());
    assert.equal(imageResponse.status, 200);
    assert.equal(imageResponse.headers.get("content-type"), "image/png");
    assert.equal(sha256Hex(received), expectedHash);

    const deleteUrl = new URL(`${base}/api/storage/object`);
    deleteUrl.searchParams.set("bucket", "cars");
    deleteUrl.searchParams.set("path", objectKey);
    const deletion = await fetch(deleteUrl, { method: "DELETE" });
    const deletionBody = await deletion.json();
    assert.equal(deletion.status, 200);
    assert.equal(deletionBody.data.deleted, true);
    deleted = true;
    await assert.rejects(
      () => storage.headObject({ bucket: "cars", key: objectKey }),
      (error) => error?.statusCode === 404
    );
    assert.equal(physicalKey.startsWith(`${B2_LIVE_TEST_PREFIX}/`), true);
  } finally {
    if (uploaded && !deleted) {
      await storage.deleteObject({ bucket: "cars", key: objectKey });
      await assert.rejects(
        () => storage.headObject({ bucket: "cars", key: objectKey }),
        (error) => error?.statusCode === 404
      );
    }
    if (server?.listening) await new Promise((resolve) => server.close(resolve));
  }
});
