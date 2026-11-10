import {
  isLocalTestStorageMode,
  validateLocalTestStorageConfig,
  validateLocalPublicBase,
  resolveStorageConfig,
} from "../config/localTestStorageGuard.js";

// G10.62 P3.4A: in isolated local-test bootstrap, never implicitly load backend/.env.
// Normal non-local startup preserves dotenv loading.
if (process.env.MOTRI_LOCAL_TEST_ISOLATED !== "1") {
  const dotenv = await import("dotenv");
  dotenv.default?.config?.();
}
const DEFAULT_REGION = "auto";
const PRIVATE_BUCKETS = new Set(["wallet_receipts"]);
const DEFAULT_SIGNED_URL_SECONDS = 300;
const MAX_SIGNED_URL_SECONDS = 3600;
const MAX_KEY_LENGTH = 1024;
const MAX_SEGMENTS = 10;
const MAX_SEGMENT_LENGTH = 255;
const SEGMENT_PATTERN = /^[a-zA-Z0-9._-]+$/;

function requireEnv(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Storage not configured: missing ${name}`);
  }
  return value;
}

function validateObjectKey(key) {
  if (typeof key !== "string" || key.length === 0) {
    throw new Error("Invalid object key: key is required");
  }
  if (key.length > MAX_KEY_LENGTH) {
    throw new Error("Invalid object key: key too long");
  }
  if (key.startsWith("/") || key.includes("\\")) {
    throw new Error("Invalid object key: absolute paths or backslashes are not allowed");
  }
  const segments = key.split("/");
  if (segments.length > MAX_SEGMENTS) {
    throw new Error("Invalid object key: too many segments");
  }
  for (const segment of segments) {
    if (segment.length === 0) {
      throw new Error("Invalid object key: empty segment");
    }
    if (segment.length > MAX_SEGMENT_LENGTH) {
      throw new Error("Invalid object key: segment too long");
    }
    if (segment === "." || segment === "..") {
      throw new Error("Invalid object key: dot segments are not allowed");
    }
    if (!SEGMENT_PATTERN.test(segment)) {
      throw new Error("Invalid object key: illegal characters");
    }
  }
  return true;
}

function validateSignedUrlSeconds(expiresIn) {
  const n = Number(expiresIn);
  if (!Number.isFinite(n) || !Number.isInteger(n)) {
    throw new Error("Invalid expires_in: must be an integer");
  }
  if (n <= 0) {
    throw new Error("Invalid expires_in: must be positive");
  }
  if (n > MAX_SIGNED_URL_SECONDS) {
    throw new Error(`Invalid expires_in: maximum is ${MAX_SIGNED_URL_SECONDS} seconds`);
  }
  return n;
}

export function createObjectStorageService({
  s3Client,
  PutObjectCommand,
  GetObjectCommand,
  DeleteObjectCommand,
  getSignedUrl: presignFn,
  bucket = (envArg) => envArg.STORAGE_PROVIDER === "b2"
    ? envArg.B2_BUCKET
    : envArg.STORAGE_PROVIDER === "r2"
      ? envArg.R2_BUCKET
      : envArg.R2_BUCKET || envArg.B2_BUCKET || envArg.LOCAL_S3_BUCKET || "motri-iq-test",
  region = (envArg) => envArg.STORAGE_PROVIDER === "b2"
    ? envArg.B2_REGION || DEFAULT_REGION
    : envArg.STORAGE_PROVIDER === "r2"
      ? envArg.R2_REGION || DEFAULT_REGION
      : envArg.R2_REGION || envArg.B2_REGION || envArg.LOCAL_S3_REGION || DEFAULT_REGION,
  endpoint = (envArg) => envArg.STORAGE_PROVIDER === "b2"
    ? envArg.B2_ENDPOINT
    : envArg.STORAGE_PROVIDER === "r2"
      ? envArg.R2_ENDPOINT
      : envArg.R2_ENDPOINT || envArg.B2_ENDPOINT || envArg.LOCAL_S3_ENDPOINT,
  accessKeyId = (envArg) => envArg.STORAGE_PROVIDER === "b2"
    ? envArg.B2_KEY_ID
    : envArg.STORAGE_PROVIDER === "r2"
      ? envArg.R2_ACCESS_KEY_ID
      : envArg.R2_ACCESS_KEY_ID || envArg.B2_KEY_ID || envArg.LOCAL_S3_ACCESS_KEY_ID,
  secretAccessKey = (envArg) => envArg.STORAGE_PROVIDER === "b2"
    ? envArg.B2_APPLICATION_KEY
    : envArg.STORAGE_PROVIDER === "r2"
      ? envArg.R2_SECRET_ACCESS_KEY
      : envArg.R2_SECRET_ACCESS_KEY || envArg.B2_APPLICATION_KEY || envArg.LOCAL_S3_SECRET_ACCESS_KEY,
  storageProvider = (envArg) => envArg.STORAGE_PROVIDER || "legacy",
  storagePrefix = (envArg) => envArg.STORAGE_PREFIX || "",
  publicBase,
  privateBuckets = PRIVATE_BUCKETS,
  database,
  ownershipChecker,
  env = process.env,
} = {}) {
  let resolvedBucket, resolvedRegion, resolvedEndpoint, resolvedAccessKeyId, resolvedSecretAccessKey, resolvedPublicBase, resolvedProvider, resolvedPrefix;
  if (isLocalTestStorageMode(env)) {
    // G10.62 P3.2: local-test resolves ONLY explicit LOCAL_S3_* from process.env (never R2/B2, never caller env bypass).
    const local = resolveStorageConfig(process.env);
    resolvedBucket = local.bucket;
    resolvedRegion = local.region;
    resolvedEndpoint = local.endpoint;
    resolvedAccessKeyId = local.accessKeyId;
    resolvedSecretAccessKey = local.secretAccessKey;
    resolvedPublicBase = local.publicBase || "";
    resolvedProvider = "legacy";
    resolvedPrefix = "";
  } else {
    resolvedBucket = typeof bucket === "function" ? bucket(env) : bucket;
    resolvedRegion = typeof region === "function" ? region(env) : region;
    resolvedEndpoint = typeof endpoint === "function" ? endpoint(env) : endpoint;
    resolvedAccessKeyId = typeof accessKeyId === "function" ? accessKeyId(env) : accessKeyId;
    resolvedSecretAccessKey = typeof secretAccessKey === "function" ? secretAccessKey(env) : secretAccessKey;
    resolvedPublicBase = typeof publicBase === "function" ? publicBase(env) : (publicBase ?? (env.R2_PUBLIC_BASE || env.B2_PUBLIC_BASE || env.LOCAL_S3_PUBLIC_BASE || ""));
    resolvedProvider = typeof storageProvider === "function" ? storageProvider(env) : storageProvider;
    resolvedPrefix = typeof storagePrefix === "function" ? storagePrefix(env) : storagePrefix;
  }
  bucket = resolvedBucket;
  region = resolvedRegion;
  endpoint = resolvedEndpoint;
  accessKeyId = resolvedAccessKeyId;
  secretAccessKey = resolvedSecretAccessKey;
  publicBase = resolvedPublicBase;
  storageProvider = resolvedProvider;
  storagePrefix = String(resolvedPrefix || "").replace(/^\/+|\/+$/g, "");
  if (!["legacy", "b2", "r2"].includes(storageProvider)) {
    throw new Error("Storage not configured: STORAGE_PROVIDER must be legacy, b2, or r2");
  }
  if (storageProvider !== "legacy" && !bucket) {
    throw new Error(`Storage not configured: missing ${storageProvider === "b2" ? "B2_BUCKET" : "R2_BUCKET"}`);
  }
  if (storagePrefix) validateObjectKey(`${storagePrefix}/probe`);
  // G10.62 P3/P3.2: fail closed in MOTRI_LOCAL_TEST unless storage config is explicit, valid, and exact local-only.
  // Never log/expose endpoint or credentials. No R2/B2/remote fallback; no alternate-env bypass.
  if (isLocalTestStorageMode(env)) {
    validateLocalTestStorageConfig({ endpoint, accessKeyId, secretAccessKey, publicBase }, { env });
  }
  let s3 = s3Client;
  let presign = presignFn;
  let s3Resolved = false;
  let presignResolved = false;
  let S3Client, PoC, GoC, DoC, LoC, HoC;

  async function loadS3ClientModules() {
  const [{ S3Client: Sc, PutObjectCommand: p, GetObjectCommand: g, DeleteObjectCommand: d, ListObjectsV2Command: l, HeadObjectCommand: h }] =
    await Promise.all([import("@aws-sdk/client-s3")]);
    S3Client = Sc;
    PoC = p;
    GoC = g;
    DoC = d;
    LoC = l;
    HoC = h;
    s3Resolved = true;
  }

  async function loadPresignerModule() {
    const [{ getSignedUrl: gs }] = await Promise.all([import("@aws-sdk/s3-request-presigner")]);
    presign = gs;
    presignResolved = true;
  }

  async function ensureS3() {
    if (s3) return;
    if (isLocalTestStorageMode(env)) {
      validateLocalTestStorageConfig({ endpoint, accessKeyId, secretAccessKey, publicBase }, { env });
    }
    if (!endpoint || !accessKeyId || !secretAccessKey) {
      throw new Error(isLocalTestStorageMode(env)
        ? "LOCAL_TEST_STORAGE_CONFIG_MISSING"
        : "Storage not configured: missing endpoint/access key/secret (R2_* or B2_* S3-compatible env vars)");
    }
    if (s3Resolved) return;
    await loadS3ClientModules();
    s3 = new S3Client({
      region,
      endpoint,
      credentials: { accessKeyId, secretAccessKey },
      forcePathStyle: true,
    });
  }

  async function ensurePresign() {
    if (presign) return;
    if (presignResolved) return;
    await loadPresignerModule();
  }

  function resolvePutObjectCommand() {
    return PutObjectCommand || PoC;
  }

  function resolveGetObjectCommand() {
    return GetObjectCommand || GoC;
  }

  function resolveDeleteObjectCommand() {
    return DeleteObjectCommand || DoC;
  }

  function isPrivateBucket(b) {
    return privateBuckets.has(b);
  }

  function resolveObjectLocation(logicalBucket, key) {
    if (storageProvider === "legacy") return { bucket: logicalBucket, key };
    if (typeof logicalBucket !== "string" || !/^[a-zA-Z0-9_-]+$/.test(logicalBucket)) {
      throw new Error("Invalid logical storage bucket");
    }
    const physicalKey = [storagePrefix, logicalBucket, key].filter(Boolean).join("/");
    validateObjectKey(physicalKey);
    return { bucket, key: physicalKey };
  }

  async function checkOwnership(userId, objectKey, b) {
    if (ownershipChecker) {
      return Boolean(await ownershipChecker(userId, objectKey, b));
    }
    if (database) {
      return Boolean(await databaseOwnershipChecker(userId, objectKey, b));
    }
    return false;
  }

  async function databaseOwnershipChecker(userId, objectKey, b) {
    try {
      if (!userId || !objectKey || !b) return false;
      const table = ownershipTableForBucket(b);
      if (!table) return false;
      const column = ownershipColumnForBucket(b);
      if (!column) return false;
      // مقارنة دقيقة للمفتاح الكامل (exact equality)، لا LIKE ولا ILIKE ولا بحث جزئي.
      const result = await database.query(
        `SELECT 1 FROM public.${table} WHERE ${column} = $1 AND user_id = $2 LIMIT 1`,
        [objectKey, userId]
      );
      if (result.rows.length > 0) return true;

      // Pour wallet_receipts: vérifier aussi upload_authorizations (pré-bind, receipt_image_url NULL).
      // Pas de contrainte used = FALSE ici: le bind consomme l'autorisation, puis télécharge pour vérifier le fichier.
      if (b === "wallet_receipts") {
        const authResult = await database.query(
          `SELECT 1 FROM public.upload_authorizations
           WHERE object_key = $1 AND user_id = $2 AND expires_at > NOW() LIMIT 1`,
          [objectKey, userId]
        );
        return authResult.rows.length > 0;
      }

      return false;
    } catch {
      return false;
    }
  }

  function ownershipTableForBucket(b) {
    const map = {
      cars: "cars",
      wallet_receipts: "wallet_transactions",
      business_ads: "business_ads",
      market_items: "market_items",
      jobs: "jobs",
    };
    return map[b] || null;
  }

  function ownershipColumnForBucket(b) {
    const map = {
      cars: "image_url",
      wallet_receipts: "receipt_image_url",
      business_ads: "logo_url",
      market_items: "images",
      jobs: "images",
    };
    return map[b] || null;
  }

  function isCarObjectKeyShape(key) {
    return typeof key === "string" && /^[0-9a-f-]{36}\/[0-9a-f-]{36}\/[0-9a-f-]{36}\.(jpg|jpeg|png|webp)$/i.test(key);
  }

  return {
    async upload({ bucket: b, key, body, contentType }) {
      validateObjectKey(key);
      await ensureS3();
      const Ctor = resolvePutObjectCommand();
      const location = resolveObjectLocation(b, key);
      const command = new Ctor({ Bucket: location.bucket, Key: location.key, Body: body, ContentType: contentType });
      await s3.send(command);
      return { bucket: b, key, size: body.byteLength || 0 };
    },

    async download({ bucket: b, key, userId }) {
      validateObjectKey(key);
      await ensureS3();
      if (userId) {
        const owned = await checkOwnership(userId, key, b);
        if (!owned) {
          const err = new Error("Forbidden");
          err.statusCode = 403;
          throw err;
        }
      }
      const Ctor = resolveGetObjectCommand();
      const location = resolveObjectLocation(b, key);
      const command = new Ctor({ Bucket: location.bucket, Key: location.key });
      const response = await s3.send(command);
      return {
        bucket: b,
        key,
        body: response.Body,
        contentType: response.ContentType,
        size: response.ContentLength,
        lastModified: response.LastModified,
      };
    },

    // NARROWLY SCOPED internal download for the authorized car-image delivery proxy ONLY.
    // Caller (route) MUST have already validated: carId/slot, DB-stored reference match,
    // approval/ownership authorization, logical bucket "cars", and car key shape. No arbitrary keys.
    // This does NOT bypass bucket/key validation and MUST NOT be used for generic object access.
    async downloadAuthorizedCarImage({ bucket: b, key }) {
      if (b !== "cars") {
        const err = new Error("Forbidden");
        err.statusCode = 403;
        throw err;
      }
      validateObjectKey(key);
      if (!isCarObjectKeyShape(key)) {
        const err = new Error("Invalid object key");
        err.statusCode = 400;
        throw err;
      }
      await ensureS3();
      const Ctor = resolveGetObjectCommand();
      const location = resolveObjectLocation(b, key);
      const command = new Ctor({ Bucket: location.bucket, Key: location.key });
      const response = await s3.send(command);
      return {
        bucket: b,
        key,
        body: response.Body,
        contentType: response.ContentType,
        size: response.ContentLength,
        lastModified: response.LastModified,
      };
    },

    async deleteObject({ bucket: b, key, userId }) {
      validateObjectKey(key);
      await ensureS3();
      if (userId) {
        const owned = await checkOwnership(userId, key, b);
        if (!owned) {
          const err = new Error("Forbidden");
          err.statusCode = 403;
          throw err;
        }
      }
      const Ctor = resolveDeleteObjectCommand();
      const location = resolveObjectLocation(b, key);
      const command = new Ctor({ Bucket: location.bucket, Key: location.key });
      await s3.send(command);
      return { deleted: true, bucket: b, key };
    },

    async getSignedUrl({ bucket: b, key, userId, expiresIn = DEFAULT_SIGNED_URL_SECONDS }) {
      validateObjectKey(key);
      const seconds = validateSignedUrlSeconds(expiresIn);
      await ensureS3();
      await ensurePresign();
      if (userId) {
        const owned = await checkOwnership(userId, key, b);
        if (!owned) {
          const err = new Error("Forbidden");
          err.statusCode = 403;
          throw err;
        }
      }
      const Ctor = resolveGetObjectCommand();
      const location = resolveObjectLocation(b, key);
      const command = new Ctor({ Bucket: location.bucket, Key: location.key });
      const url = await presign(s3, command, { expiresIn: seconds });
      return { url, expiresIn: seconds };
    },

    async getPublicUrl({ bucket: b, key }) {
      if (isPrivateBucket(b)) {
        const err = new Error("Private bucket: public URL not allowed");
        err.statusCode = 403;
        throw err;
      }
      if (isLocalTestStorageMode(env)) {
        // Centralized local-test validation: endpoint/creds/publicBase all checked; remote public base rejected.
        validateLocalTestStorageConfig({ endpoint, accessKeyId, secretAccessKey, publicBase }, { env });
      }
      const base = (isLocalTestStorageMode(env)
        ? (publicBase || endpoint || "")
        : (endpoint || process.env.R2_PUBLIC_BASE || process.env.B2_PUBLIC_BASE || process.env.LOCAL_S3_PUBLIC_BASE || "")
      ).replace(/\/+$/, "");
      if (isLocalTestStorageMode(env)) validateLocalPublicBase(base || null, { env });
      if (!base) {
        const err = new Error("Public URL base not configured");
        err.statusCode = 503;
        throw err;
      }
      const location = resolveObjectLocation(b, key);
      return `${base}/${location.bucket}/${encodeURIComponent(location.key)}`;
    },

    async listObjects({ bucket: b, prefix = "", continuationToken, maxKeys = 100 } = {}) {
      if (prefix) validateObjectKey(prefix.split("/")[0] ? prefix : "a");
      await ensureS3();
      const bounded = Math.min(Math.max(Number(maxKeys) || 100, 1), 1000);
      const Ctor = LoC;
      const namespace = [storagePrefix, b].filter(Boolean).join("/");
      const physicalPrefix = storageProvider === "legacy"
        ? prefix
        : prefix
          ? `${namespace}/${prefix}`
          : `${namespace}/`;
      const physicalBucket = storageProvider === "legacy" ? b : bucket;
      const command = new Ctor({ Bucket: physicalBucket, Prefix: physicalPrefix, ContinuationToken: continuationToken, MaxKeys: bounded });
      const response = await s3.send(command);
      const logicalPrefix = storageProvider === "legacy" ? "" : `${[storagePrefix, b].filter(Boolean).join("/")}/`;
      return {
        objects: (response.Contents || []).map((item) => ({
          key: logicalPrefix && item.Key?.startsWith(logicalPrefix) ? item.Key.slice(logicalPrefix.length) : item.Key,
          size: item.Size,
          lastModified: item.LastModified
        })),
        nextContinuationToken: response.NextContinuationToken || null,
        isTruncated: Boolean(response.IsTruncated),
      };
    },

    async headObject({ bucket: b, key }) {
      validateObjectKey(key);
      await ensureS3();
      const Ctor = HoC;
      const location = resolveObjectLocation(b, key);
      const command = new Ctor({ Bucket: location.bucket, Key: location.key });
      try {
        const response = await s3.send(command);
        return { size: response.ContentLength, lastModified: response.LastModified, contentType: response.ContentType, etag: response.ETag };
      } catch (error) {
        if (error?.$metadata?.httpStatusCode === 404 || error?.name === "NotFound") {
          const err = new Error("Object not found");
          err.statusCode = 404;
          throw err;
        }
        throw error;
      }
    },

    isPrivateBucket,
    checkOwnership,
  };
}

export {
  validateObjectKey,
  validateSignedUrlSeconds,
  DEFAULT_SIGNED_URL_SECONDS,
  MAX_SIGNED_URL_SECONDS,
  PRIVATE_BUCKETS,
};

export const createR2StorageService = createObjectStorageService;
