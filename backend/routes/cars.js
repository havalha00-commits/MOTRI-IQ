import { Router } from "express";
import { randomUUID } from "node:crypto";
import { pool } from "../config/database.js";
import { authenticateCurrentUser, optionalCurrentUser } from "../middleware/current_user.js";

const carColumns = [
  "title",
  "brand",
  "model",
  "year",
  "price",
  "governorate",
  "fuel",
  "transmission",
  "mileage",
  "description",
  "phone",
  "images",
  "city",
  "image_url",
  "province",
  "body_type",
  "seller_phone",
  "plate_regions"
];
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const carObjectKeyPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(jpg|jpeg|png|webp)$/i;
const CAR_IMAGE_EXT_TO_TYPE = { ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png", ".webp": "image/webp" };
const CAR_IMAGE_MAX_BYTES = 10 * 1024 * 1024;
// Public images must revalidate so revoked approval/deleted/replaced references are enforced before any cached reuse.
const CAR_IMAGE_PUBLIC_CACHE = "public, max-age=0, must-revalidate";
const CAR_IMAGE_PRIVATE_CACHE = "private, no-store";
const CAR_IMAGE_RATE_LIMIT = { windowMs: 60_000, max: 120, maxEntries: 5000 };
const _carImageRate = new Map();
const searchColumns = new Set([
  "brand",
  "model",
  "year",
  "fuel",
  "transmission",
  "body_type",
  "city",
  "province",
  "governorate",
  "title",
  "price",
  "mileage"
]);
const numericColumns = new Set(["year", "price", "mileage"]);

function isCanonicalCarObjectKey(value) {
  return typeof value === "string" && carObjectKeyPattern.test(value.trim());
}
function isLegacyAbsoluteImageUrl(value) {
  if (typeof value !== "string") return false;
  const v = value.trim();
  if (!v) return false;
  try { const u = new URL(v); return u.protocol === "http:" || u.protocol === "https:"; } catch { return false; }
}
function parseImagesField(value) {
  if (Array.isArray(value)) return value;
  if (typeof value !== "string" || !value.trim()) return null;
  try { const p = JSON.parse(value); return Array.isArray(p) ? p : null; } catch { return null; }
}
function getCarImageSlotValues(row) {
  const arr = parseImagesField(row?.images);
  if (arr && arr.length) return arr;
  const single = row?.image_url;
  if (single == null) return [];
  return [single];
}
function maskImageValueForApi(value, { publicContext }) {
  if (value == null) return null;
  if (typeof value !== "string") return null;
  const v = value.trim();
  if (!v) return null;
  if (isLegacyAbsoluteImageUrl(v)) return v;
  if (isCanonicalCarObjectKey(v)) return publicContext ? null : null; // never expose raw object keys (public or general API); display via image_urls
  return publicContext ? null : v; // unknown form hidden in public context
}
function buildCarImageUrls(row, { publicContext } = {}) {
  const vals = getCarImageSlotValues(row);
  const carId = row?.id;
  return vals.map((v, slot) => {
    if (v == null) return null;
    const s = typeof v === "string" ? v.trim() : String(v);
    if (isLegacyAbsoluteImageUrl(s)) return s;
    if (isCanonicalCarObjectKey(s) && carId && uuidPattern.test(String(carId))) return `/api/cars/${carId}/images/${slot}`;
    return null;
  });
}
function shapeCarRowForApi(row, { publicContext } = {}) {
  if (!row || typeof row !== "object") return row;
  const out = { ...row };
  const vals = getCarImageSlotValues(row);
  if (vals.length) {
    const masked = vals.map((v) => maskImageValueForApi(v, { publicContext }));
    // Preserve existing field shapes where safe: keep images as array when parsed array; keep image_url as scalar/legacy.
    out.images = masked;
    if (Object.hasOwn(row, "image_url")) {
      const first = masked[0] ?? null;
      out.image_url = first;
    }
  }
  out.image_urls = buildCarImageUrls(row, { publicContext });
  return out;
}
function shapeCarRowsForApi(rows, opts) {
  return Array.isArray(rows) ? rows.map((r) => shapeCarRowForApi(r, opts)) : rows;
}
function allowCarImageRequest(ip) {
  const now = Date.now();
  const k = String(ip || "unknown").slice(0, 128);
  let e = _carImageRate.get(k);
  if (!e || now - e.start >= CAR_IMAGE_RATE_LIMIT.windowMs) e = { start: now, count: 0 };
  e.count += 1;
  if (_carImageRate.size > CAR_IMAGE_RATE_LIMIT.maxEntries) {
    for (const [key, val] of _carImageRate) { if (now - val.start >= CAR_IMAGE_RATE_LIMIT.windowMs) _carImageRate.delete(key); if (_carImageRate.size <= CAR_IMAGE_RATE_LIMIT.maxEntries) break; }
  }
  _carImageRate.set(k, e);
  return e.count <= CAR_IMAGE_RATE_LIMIT.max;
}
function sniffCarImageContentType(bytes, fallbackExt) {
  if (Buffer.isBuffer(bytes) && bytes.length >= 3) {
    if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return "image/jpeg";
    if (bytes.length >= 8 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47) return "image/png";
    if (bytes.length >= 12 && bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46 && bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50) return "image/webp";
  }
  return CAR_IMAGE_EXT_TO_TYPE[fallbackExt] || null;
}
function extOfKey(key) { const i = String(key||"").lastIndexOf("."); return i > 0 ? String(key).slice(i).toLowerCase() : ""; }

function boundedNumber(value, fallback, min, max) {
  const parsed = Number.parseInt(value, 10);
  return Number.isInteger(parsed) ? Math.min(Math.max(parsed, min), max) : fallback;
}

function addSearchCondition(condition, values) {
  if (
    !condition ||
    typeof condition !== "object" ||
    !searchColumns.has(condition.column) ||
    typeof condition.value !== "string" ||
    condition.value.length > 256
  ) {
    throw new TypeError("Invalid car search filter");
  }

  const { column, operator } = condition;
  const allowedOperator =
    operator === "eq" ||
    operator === "ilike" ||
    (numericColumns.has(column) && ["gte", "lte"].includes(operator));
  if (!allowedOperator) throw new TypeError("Invalid car search operator");

  let value = condition.value;
  if (numericColumns.has(column)) {
    value = Number(value);
    if (!Number.isFinite(value)) throw new TypeError("Invalid numeric filter");
  }
  values.push(value);
  return `c.${column} ${operator === "eq" ? "=" : operator === "ilike" ? "ILIKE" : operator === "gte" ? ">=" : "<="} $${values.length}`;
}

function carSearchQuery(query) {
  let conditions;
  try {
    conditions = query.filters ? JSON.parse(query.filters) : [];
  } catch {
    throw new TypeError("Invalid car search filters");
  }
  if (!Array.isArray(conditions) || conditions.length > 40) {
    throw new TypeError("Invalid car search filters");
  }

  const values = [];
  const where = ["c.is_approved = TRUE"];
  for (const step of conditions) {
    if (step && Array.isArray(step.clauses)) {
      if (step.clauses.length < 1 || step.clauses.length > 8) {
        throw new TypeError("Invalid grouped car search filter");
      }
      where.push(
        `(${step.clauses.map((clause) => addSearchCondition(clause, values)).join(" OR ")})`
      );
    } else {
      where.push(addSearchCondition(step, values));
    }
  }

  for (const [parameter, column, operator] of [
    ["min_year", "year", ">="],
    ["max_year", "year", "<="],
    ["min_price", "price", ">="],
    ["max_price", "price", "<="],
    ["max_mileage", "mileage", "<="]
  ]) {
    if (query[parameter] === undefined || query[parameter] === "") continue;
    const number = Number(query[parameter]);
    if (!Number.isFinite(number)) throw new TypeError("Invalid numeric filter");
    values.push(number);
    where.push(`c.${column} ${operator} $${values.length}`);
  }

  const orderBy =
    query.sort === "price_asc"
      ? "c.price ASC"
      : query.sort === "price_desc"
        ? "c.price DESC"
        : "c.created_at DESC";
  const limit = boundedNumber(query.limit, 20, 1, 100);
  const offset = boundedNumber(query.offset, 0, 0, 1000000);
  values.push(limit, offset);
  return {
    sql: `SELECT c.*
          FROM public.cars c
          WHERE ${where.join(" AND ")}
          ORDER BY ${orderBy}, c.id DESC
          LIMIT $${values.length - 1} OFFSET $${values.length}`,
    values
  };
}

function createCarPayload(body, { creating = false } = {}) {
  const payload = {};
  for (const column of carColumns) {
    if (Object.hasOwn(body, column)) payload[column] = body[column];
  }
  if (creating) {
    if (typeof payload.brand !== "string" || !payload.brand.trim()) {
      throw new TypeError("Brand is required");
    }
    if (typeof payload.model !== "string" || !payload.model.trim()) {
      throw new TypeError("Model is required");
    }
  }
  if (Object.hasOwn(payload, "plate_regions")) {
    const value = payload.plate_regions;
    if (value !== null) {
      let parsed = value;
      if (typeof value === "string") {
        try {
          parsed = JSON.parse(value);
        } catch {
          throw new TypeError("Invalid plate_regions");
        }
      }
      if (!Array.isArray(parsed)) throw new TypeError("Invalid plate_regions");
      for (const entry of parsed) {
        if (entry === null || typeof entry !== "object" || Array.isArray(entry)) {
          throw new TypeError("Invalid plate_regions");
        }
        for (const key of ["x", "y", "w", "h"]) {
          if (typeof entry[key] !== "number" || !Number.isFinite(entry[key])) {
            throw new TypeError("Invalid plate_regions");
          }
        }
      }
      payload.plate_regions = typeof value === "string" ? value : JSON.stringify(value);
    }
  }
  return payload;
}

function collectBoundImageKeys(payload) {
  const keys = [];
  const append = (value) => {
    if (typeof value !== "string" || !value.trim()) return;
    const trimmed = value.trim();
    try {
      const parsed = JSON.parse(trimmed);
      if (Array.isArray(parsed)) {
        for (const item of parsed) {
          if (typeof item === "string" && item.trim()) keys.push(item.trim());
        }
        return;
      }
    } catch {}
    keys.push(trimmed);
  };
  append(payload.image_url);
  if (typeof payload.images === "string") {
    append(payload.images);
  }
  if (Array.isArray(payload.images)) {
    payload.images.forEach(append);
  }
  return [...new Set(keys)];
}

function parseCarObjectKey(key, userId, submissionId) {
  if (typeof key !== "string" || !key) return null;
  const parts = key.split("/");
  if (parts.length !== 3) return null;
  const [ownerId, subId, file] = parts;
  if (ownerId !== userId || subId !== submissionId) return null;
  const dot = file.lastIndexOf(".");
  if (dot <= 0) return null;
  const photoId = file.slice(0, dot);
  const ext = file.slice(dot + 1).toLowerCase();
  if (!uuidPattern.test(ownerId) || !uuidPattern.test(subId) || !uuidPattern.test(photoId)) return null;
  if (!["jpg", "jpeg", "png", "webp"].includes(ext)) return null;
  return { objectKey: key, photoId };
}

async function validateAndConsumeBoundImages({ client, userId, submissionId, payload, storage, bucket = "cars" }) {
  const keys = collectBoundImageKeys(payload);
  if (keys.length === 0) return [];
  if (keys.length > 15) {
    const err = new Error("Too many images");
    err.statusCode = 400;
    throw err;
  }
  const parsed = keys.map((key) => {
    const info = parseCarObjectKey(key, userId, submissionId);
    if (!info) {
      const err = new Error("Invalid or unauthorized image key");
      err.statusCode = 403;
      throw err;
    }
    return info;
  });

  if (storage && typeof storage.headObject === "function") {
    for (const { objectKey } of parsed) {
      try {
        await storage.headObject({ bucket, key: objectKey });
      } catch (e) {
        const err = new Error("Uploaded image object not found");
        err.statusCode = 400;
        err.cause = e;
        throw err;
      }
    }
  }

  await client.query("SELECT pg_advisory_xact_lock(hashtext($1))", [`${userId}:${submissionId}`]);
  const resv = await client.query(
    `SELECT id, object_key, consumed_at, expires_at, (expires_at > NOW()) AS is_active
     FROM public.car_image_upload_reservations
     WHERE user_id = $1 AND submission_id = $2 AND object_key = ANY($3::text[])
     FOR UPDATE`,
    [userId, submissionId, keys]
  );
  const byKey = new Map(resv.rows.map((r) => [r.object_key, r]));
  for (const key of keys) {
    const row = byKey.get(key);
    if (!row || row.consumed_at || !row.is_active) {
      const err = new Error("Image reservation missing, expired, or consumed");
      err.statusCode = 403;
      throw err;
    }
  }
  const consumed = await client.query(
    `UPDATE public.car_image_upload_reservations
     SET consumed_at = NOW()
     WHERE user_id = $1 AND submission_id = $2 AND object_key = ANY($3::text[])
       AND consumed_at IS NULL AND expires_at > NOW()
     RETURNING object_key`,
    [userId, submissionId, keys]
  );
  if (consumed.rowCount !== keys.length) {
    const err = new Error("Image reservation consumption failed");
    err.statusCode = 409;
    throw err;
  }
  return keys;
}

export function createCarsRouter({
  database = pool,
  authenticate = authenticateCurrentUser,
  optionalAuthenticate = optionalCurrentUser,
  storage = null
} = {}) {
  const router = Router();
  // Wrapper: optional auth that respects injected authenticator (important for isolated tests).
  const optAuth = optionalAuthenticate || ((req, res, next) => {
    if (!req.headers.authorization) return next();
    return authenticate(req, res, next);
  });

  router.get("/most-liked", async (req, res) => {
    const limit = boundedNumber(req.query.limit, 10, 1, 50);
    try {
      const result = await database.query(
        `SELECT c.*,
                COALESCE(f.favorite_count, 0)::int AS favorite_count
         FROM public.cars c
         LEFT JOIN (
           SELECT car_id, COUNT(DISTINCT user_id)::int AS favorite_count
           FROM public.favorites
           WHERE item_type = 'car' AND car_id IS NOT NULL
           GROUP BY car_id
         ) f ON f.car_id = c.id::text
         WHERE c.is_approved = TRUE
         ORDER BY COALESCE(f.favorite_count, 0) DESC, c.created_at DESC, c.id DESC
         LIMIT $1`,
        [limit]
      );
      return res.json({
        success: true,
        data: shapeCarRowsForApi(result.rows, { publicContext: true })
      });
    } catch (error) {
      console.error("Most-liked cars API error:", error.message);
      return res.status(500).json({ error: "Failed to load most-liked cars" });
    }
  });

  router.post("/uploads/reserve", authenticate, async (req, res) => {
    const userId = req.user?.id;
    if (!userId) return res.status(401).json({ error: "Authentication required" });
    const submissionId = req.body?.submission_id;
    const photoId = req.body?.photo_id;
    const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    if (!uuidPattern.test(submissionId) || !uuidPattern.test(photoId)) {
      return res.status(400).json({ error: "Invalid submission or photo id" });
    }
    const ext = typeof req.body?.extension === "string" ? req.body.extension.toLowerCase().replace(/^\./, "") : "jpg";
    if (!["jpg", "jpeg", "png", "webp"].includes(ext)) {
      return res.status(400).json({ error: "Invalid file extension" });
    }
    const objectKey = `${userId}/${submissionId}/${photoId}.${ext}`;
    const poolOrDb = database;
    let client;
    let mustRelease = false;
    try {
      if (typeof poolOrDb.connect === "function") {
        client = await poolOrDb.connect();
        mustRelease = true;
      } else {
        client = poolOrDb;
      }
      await client.query("BEGIN");
      await client.query("SELECT pg_advisory_xact_lock(hashtext($1))", [`${userId}:${submissionId}`]);
      const countResult = await client.query(
        `SELECT COUNT(*)::int AS count FROM public.car_image_upload_reservations
         WHERE user_id = $1 AND submission_id = $2 AND consumed_at IS NULL AND expires_at > NOW()`,
        [userId, submissionId]
      );
      if (countResult.rows[0].count >= 15) {
        await client.query("ROLLBACK");
        return res.status(409).json({ error: "Maximum 15 images per submission" });
      }
      const existing = await client.query(
        `SELECT id, object_key, expires_at, consumed_at,
                (expires_at > NOW()) AS is_active
         FROM public.car_image_upload_reservations
         WHERE user_id = $1 AND submission_id = $2 AND photo_id = $3
         FOR UPDATE`,
        [userId, submissionId, photoId]
      );
      if (existing.rows.length > 0) {
        const row = existing.rows[0];
        if (row.consumed_at) {
          await client.query("ROLLBACK");
          return res.status(409).json({ error: "Reservation already consumed" });
        }
        if (row.is_active) {
          await client.query("COMMIT");
          return res.status(200).json({ success: true, data: { object_key: row.object_key, expires_at: row.expires_at } });
        }
        const renewed = await client.query(
          `UPDATE public.car_image_upload_reservations
           SET object_key = $4, expires_at = NOW() + INTERVAL '30 minutes', consumed_at = NULL
           WHERE id = $1 AND user_id = $2 AND submission_id = $3 AND consumed_at IS NULL
           RETURNING object_key, expires_at`,
          [row.id, userId, submissionId, objectKey]
        );
        if (renewed.rowCount !== 1) {
          await client.query("ROLLBACK");
          return res.status(409).json({ error: "Reservation state changed" });
        }
        await client.query("COMMIT");
        return res.status(200).json({ success: true, data: renewed.rows[0] });
      }
      const inserted = await client.query(
        `INSERT INTO public.car_image_upload_reservations (user_id, submission_id, photo_id, object_key, expires_at)
         VALUES ($1, $2, $3, $4, NOW() + INTERVAL '30 minutes')
         ON CONFLICT (user_id, submission_id, photo_id) DO NOTHING
         RETURNING object_key, expires_at`,
        [userId, submissionId, photoId, objectKey]
      );
      if (inserted.rowCount === 1) {
        await client.query("COMMIT");
        return res.status(201).json({ success: true, data: inserted.rows[0] });
      }
      const raced = await client.query(
        `SELECT object_key, expires_at, consumed_at, (expires_at > NOW()) AS is_active
         FROM public.car_image_upload_reservations
         WHERE user_id = $1 AND submission_id = $2 AND photo_id = $3
         FOR UPDATE`,
        [userId, submissionId, photoId]
      );
      const row = raced.rows[0];
      if (row && !row.consumed_at && row.is_active) {
        await client.query("COMMIT");
        return res.status(200).json({ success: true, data: { object_key: row.object_key, expires_at: row.expires_at } });
      }
      if (row && !row.consumed_at) {
        const renewed = await client.query(
          `UPDATE public.car_image_upload_reservations
           SET object_key = $4, expires_at = NOW() + INTERVAL '30 minutes', consumed_at = NULL
           WHERE id = (SELECT id FROM public.car_image_upload_reservations WHERE user_id=$1 AND submission_id=$2 AND photo_id=$3 FOR UPDATE) AND consumed_at IS NULL
           RETURNING object_key, expires_at`,
          [userId, submissionId, photoId, objectKey]
        );
        if (renewed.rowCount === 1) {
          await client.query("COMMIT");
          return res.status(200).json({ success: true, data: renewed.rows[0] });
        }
      }
      await client.query("ROLLBACK");
      return res.status(409).json({ error: "Reservation state changed" });
    } catch (error) {
      try { await client?.query("ROLLBACK"); } catch {}
      return res.status(500).json({ error: "Failed to reserve upload" });
    } finally {
      if (mustRelease) try { client.release(); } catch {}
    }
  });


  router.get("/search", async (req, res) => {
    let query;
    try {
      query = carSearchQuery(req.query);
    } catch (error) {
      return res.status(400).json({ error: error.message });
    }
    try {
      const result = await database.query(query.sql, query.values);
      return res.json({ success: true, data: shapeCarRowsForApi(result.rows, { publicContext: true }) });
    } catch (error) {
      console.error("Car search API error:", error.message);
      return res.status(500).json({ error: "Failed to search cars" });
    }
  });

  router.get("/vocabulary", async (_req, res) => {
    try {
      const result = await database.query(
        `SELECT brand, model, city, province, fuel, transmission, body_type
         FROM public.cars
         WHERE is_approved = TRUE
         ORDER BY created_at DESC
         LIMIT 1000`
      );
      return res.json({ success: true, data: result.rows });
    } catch (error) {
      console.error("Car vocabulary API error:", error.message);
      return res.status(500).json({ error: "Failed to load car vocabulary" });
    }
  });

  router.get("/", async (req, res) => {
    try {
     const limit = boundedNumber(req.query.limit, 20, 1, 100);
     const offset = boundedNumber(req.query.offset, 0, 0, 1000000);
     const brand = typeof req.query.brand === "string" ? req.query.brand.trim() : null;
     const values = [];
     const conditions = ["is_approved = TRUE"];
     if (brand) {
       values.push(brand);
       conditions.push(`brand = $${values.length}`);
     }
     values.push(limit, offset);
     const result = await database.query(
       `SELECT *
        FROM public.cars
        WHERE ${conditions.join(" AND ")}
        ORDER BY created_at DESC, id DESC
        LIMIT $${values.length - 1} OFFSET $${values.length}`,
       values
     );

      return res.json({
        success: true,
        data: shapeCarRowsForApi(result.rows, { publicContext: true }),
        count: result.rows.length,
        limit,
        offset
      });
    } catch (error) {
      console.error("Cars API error:", error.message);
      return res.status(500).json({
        success: false,
        message: "Failed to load cars"
      });
    }
  });

  router.get("/featured", async (req, res) => {
    const since = req.query.since;
    const cutoff = typeof since === "string" ? new Date(since) : null;
    if (since !== undefined && (!cutoff || Number.isNaN(cutoff.valueOf()))) {
      return res.status(400).json({ error: "Invalid date filter" });
    }
    try {
      const limit = boundedNumber(req.query.limit, 10, 1, 50);
      const result = await database.query(
        `SELECT *
         FROM public.cars
         WHERE is_approved = TRUE
           AND ($1::timestamptz IS NULL OR created_at >= $1)
         ORDER BY created_at DESC, id DESC
         LIMIT $2`,
        [cutoff?.toISOString() ?? null, limit]
      );
      return res.json({ success: true, data: shapeCarRowsForApi(result.rows, { publicContext: true }) });
    } catch (error) {
      console.error("Featured cars API error:", error.message);
      return res.status(500).json({ error: "Failed to load featured cars" });
    }
  });

  router.get("/seller/:sellerId", async (req, res) => {
    try {
      const result = await database.query(
        `SELECT *
         FROM public.cars
         WHERE user_id = $1 AND is_approved = TRUE
         ORDER BY created_at DESC
         LIMIT 30`,
        [req.params.sellerId]
      );
      return res.json({ success: true, data: shapeCarRowsForApi(result.rows, { publicContext: true }) });
    } catch (error) {
      console.error("Seller cars API error:", error.message);
      return res.status(500).json({ error: "Failed to load seller cars" });
    }
  });

  router.get("/by-ids", async (req, res) => {
    const rawIds = typeof req.query.ids === "string" ? req.query.ids : "";
    const ids = [...new Set(rawIds.split(",").filter((id) => uuidPattern.test(id)))];
    if (ids.length === 0 || ids.length > 100) {
      return res.status(400).json({ error: "Provide 1-100 valid car ids" });
    }
    try {
      const result = await database.query(
        `SELECT *
         FROM public.cars
         WHERE is_approved = TRUE AND id = ANY($1::uuid[])
         ORDER BY created_at DESC`,
        [ids]
      );
      return res.json({ success: true, data: shapeCarRowsForApi(result.rows, { publicContext: true }) });
    } catch (error) {
      console.error("Cars by id API error:", error.message);
      return res.status(500).json({ error: "Failed to load cars" });
    }
  });

  router.get("/my", authenticate, async (req, res) => {
    try {
      const result = await database.query(
        `SELECT *
         FROM public.cars
         WHERE user_id = $1
         ORDER BY created_at DESC
         LIMIT 50`,
        [req.user.id]
      );
      return res.json({
        success: true,
        data: shapeCarRowsForApi(result.rows, { publicContext: false, owner: true }),
        count: result.rows.length
      });
    } catch (error) {
      console.error("My cars API error:", error.message);
      return res.status(500).json({
        success: false,
        message: "Failed to load your cars"
      });
    }
  });

  // A1 (G10.51): backend-controlled car image delivery. Slot-based (no arbitrary object key input).
  // Public access only for approved/public cars (is_approved=TRUE). Owner access requires auth + exact ownership.
  // Never proxies arbitrary legacy URLs server-side; never returns signed URLs/object keys. Private buckets isolated (fixed bucket cars).
  // Cache hardening (4C): NEVER return conditional 304 before DB auth/current image-reference validation.
  // Conditional responses are disabled: ignore If-None-Match/If-Modified-Since and always serve current content after full revalidation.
  router.get("/:carId/images/:slot", optAuth, async (req, res) => {
    if (!allowCarImageRequest(req.ip)) return res.status(429).json({ error: "Too many requests" });
    const carId = String(req.params.carId || "");
    if (!uuidPattern.test(carId)) return res.status(400).json({ error: "Invalid car id" });
    const slotRaw = String(req.params.slot ?? "");
    if (!/^\d+$/.test(slotRaw)) return res.status(400).json({ error: "Invalid image slot" });
    const slot = Number(slotRaw);
    if (!Number.isInteger(slot) || slot < 0 || slot > 14) return res.status(400).json({ error: "Invalid image slot" });

    try {
      // ORDERING GUARANTEE (4C): (1) load current DB state, (2) authorize visibility/ownership, (3) resolve current slot reference.
      // No 304/ETag/Last-Modified validation is performed; revoked approval/deleted car/replaced reference can never reuse an old validator.
      const carRes = await database.query(
        `SELECT id, user_id, is_approved, image_url, images FROM public.cars WHERE id = $1 LIMIT 1`,
        [carId]
      );
      if (carRes.rowCount !== 1) return res.status(404).json({ error: "Not found" });
      const car = carRes.rows[0];
      const isOwner = req.user?.id && String(req.user.id) === String(car.user_id);
      // Public visibility baseline: is_approved=TRUE. Approved sold cars remain publicly visible (product decision). Do not add status='active'.
      const isPublic = car.is_approved === true;
      if (!isPublic && !isOwner) return res.status(403).json({ error: "Forbidden" });

      const vals = getCarImageSlotValues(car);
      if (slot >= vals.length) return res.status(404).json({ error: "Not found" });
      const ref = vals[slot];
      const refStr = typeof ref === "string" ? ref.trim() : "";
      if (isLegacyAbsoluteImageUrl(refStr)) {
        // Never proxy arbitrary legacy URLs server-side. Client should use image_urls; redirect preserves legacy display safely.
        try { const u = new URL(refStr); if (u.protocol === "http:" || u.protocol === "https:") return res.redirect(302, u.toString()); } catch {}
        return res.status(404).json({ error: "Not found" });
      }
      if (!isCanonicalCarObjectKey(refStr)) return res.status(404).json({ error: "Not found" });

      if (!storage || typeof storage.downloadAuthorizedCarImage !== "function") {
        return res.status(503).json({ error: "Image delivery unavailable" });
      }
      // Only after DB auth + current slot reference validation: fetch the exact current object (fixed bucket cars).
      const obj = await storage.downloadAuthorizedCarImage({ bucket: "cars", key: refStr });
      const ext = extOfKey(refStr);
      const expectedType = CAR_IMAGE_EXT_TO_TYPE[ext] || null;
      const body = obj.body;
      const chunks = [];
      if (Buffer.isBuffer(body)) chunks.push(body);
      else if (body && typeof body[Symbol.asyncIterator] === "function") {
        let totalBytes = 0;
        for await (const chunk of body) {
          const bytes = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
          totalBytes += bytes.length;
          if (totalBytes > CAR_IMAGE_MAX_BYTES) {
            body.destroy?.();
            return res.status(404).json({ error: "Not found" });
          }
          chunks.push(bytes);
        }
      } else if (body && typeof body.pipe === "function") {
        await new Promise((resolve, reject) => {
          let totalBytes = 0;
          body.on("data", (chunk) => {
            const bytes = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
            totalBytes += bytes.length;
            if (totalBytes > CAR_IMAGE_MAX_BYTES) {
              body.destroy();
              reject(Object.assign(new Error("Image exceeds maximum size"), { statusCode: 413 }));
              return;
            }
            chunks.push(bytes);
          });
          body.on("end", resolve);
          body.on("error", reject);
        });
      } else if (body) {
        chunks.push(Buffer.from(body));
      }
      const buf = Buffer.concat(chunks);
      if (!buf.length || buf.length > CAR_IMAGE_MAX_BYTES) return res.status(404).json({ error: "Not found" });
      const sniffed = sniffCarImageContentType(buf, ext);
      const type = sniffed || expectedType || "application/octet-stream";
      if (!expectedType || !String(type).startsWith("image/") || (sniffed && expectedType && sniffed !== expectedType)) {
        return res.status(415).json({ error: "Unsupported image type" });
      }
      res.setHeader("Content-Type", type);
      res.setHeader("X-Content-Type-Options", "nosniff");
      res.setHeader("Cache-Control", isPublic ? CAR_IMAGE_PUBLIC_CACHE : CAR_IMAGE_PRIVATE_CACHE);
      res.setHeader("Content-Length", String(buf.length));
      return res.status(200).end(buf);
    } catch (error) {
      if (res.headersSent) {
        res.destroy(error);
        return;
      }
      if (error?.statusCode === 404) return res.status(404).json({ error: "Not found" });
      if (error?.statusCode === 413) return res.status(413).json({ error: "Image exceeds maximum size" });
      console.error("Car image delivery failed:", error?.message || "unknown");
      return res.status(503).json({ error: "Image delivery unavailable" });
    }
  });

  router.post("/", authenticate, async (req, res) => {
    let payload;
    try {
      payload = createCarPayload(req.body, { creating: true });
    } catch (error) {
      return res.status(400).json({ error: error.message });
    }

    const id = typeof req.body?.id === "string" ? req.body.id : randomUUID();
    if (!uuidPattern.test(id)) {
      return res.status(400).json({ error: "Invalid car id" });
    }
    if (Array.isArray(payload.images)) {
      payload.images = payload.images.filter((value) => typeof value === "string");
    }
    const imageKeys = collectBoundImageKeys(payload);
    if (imageKeys.length > 0) {
      payload.images = imageKeys;
      payload.image_url = imageKeys[0];
    }

    const poolOrDb = database;
    let client;
    let mustRelease = false;
    try {
      if (typeof poolOrDb.connect === "function") {
        client = await poolOrDb.connect();
        mustRelease = true;
      } else {
        client = poolOrDb;
      }
      await client.query("BEGIN");
      await validateAndConsumeBoundImages({
        client,
        userId: req.user.id,
        submissionId: id,
        payload,
        storage
      });
      const columns = ["id", "user_id", ...Object.keys(payload), "is_approved"];
      const values = [id, req.user.id, ...Object.values(payload), false];
      const placeholders = values.map((_, index) => `$${index + 1}`);
      const result = await client.query(
        `INSERT INTO public.cars (${columns.join(", ")})
         VALUES (${placeholders.join(", ")})
         RETURNING id`,
        values
      );
      await client.query("COMMIT");
      return res.status(201).json({ success: true, data: result.rows[0] });
    } catch (error) {
      try { await client?.query("ROLLBACK"); } catch {}
      if (error?.statusCode && error.statusCode >= 400 && error.statusCode < 500) {
        return res.status(error.statusCode).json({ error: error.message });
      }
      console.error("Car creation failed:", error.message);
      return res.status(500).json({ error: "Failed to submit car listing" });
    } finally {
      if (mustRelease) try { client.release(); } catch {}
    }
  });

  router.patch("/my/:id", authenticate, async (req, res) => {
    let payload;
    try {
      payload = createCarPayload(req.body);
    } catch (error) {
      return res.status(400).json({ error: error.message });
    }
    if (Array.isArray(payload.images)) {
      payload.images = payload.images.filter((value) => typeof value === "string");
    }
    const entries = Object.entries(payload);
    if (entries.length === 0) {
      return res.status(400).json({ error: "No editable car fields provided" });
    }

    const carId = req.params.id;
    const touchesImages = Object.hasOwn(payload, "image_url") || Object.hasOwn(payload, "images");
    const poolOrDb = database;
    let client;
    let mustRelease = false;
    try {
      if (typeof poolOrDb.connect === "function") {
        client = await poolOrDb.connect();
        mustRelease = true;
      } else {
        client = poolOrDb;
      }
      await client.query("BEGIN");
      const existingCar = await client.query(
        `SELECT id, image_url, images
         FROM public.cars
         WHERE id = $1 AND user_id = $2
         FOR UPDATE`,
        [carId, req.user.id]
      );
      if (existingCar.rowCount !== 1) {
        await client.query("ROLLBACK");
        return res.status(404).json({ error: "Car listing not found" });
      }

      if (touchesImages) {
        let existingImages = existingCar.rows[0].images;
        if (typeof existingImages === "string") {
          try {
            const parsed = JSON.parse(existingImages);
            if (Array.isArray(parsed)) existingImages = parsed;
          } catch {}
        }
        const existingKeys = new Set(
          collectBoundImageKeys({
            image_url: existingCar.rows[0].image_url,
            images: existingImages
          })
        );
        const requestedKeys = collectBoundImageKeys(payload);
        // Every requested key must be an already-bound key of this car OR a newly validated+consumed key.
        for (const key of requestedKeys) {
          if (existingKeys.has(key)) continue;
          // parse/ownership/submission checked by validateAndConsumeBoundImages; reject early for clarity if malformed/wrong scope
          if (!parseCarObjectKey(key, req.user.id, carId)) {
            const err = new Error("Invalid or unauthorized image key");
            err.statusCode = 403;
            throw err;
          }
        }
        const newKeys = requestedKeys.filter((key) => !existingKeys.has(key));
        if (newKeys.length > 0) {
          await validateAndConsumeBoundImages({
            client,
            userId: req.user.id,
            submissionId: carId,
            payload: { images: newKeys },
            storage
          });
        }
      }

      const sets = entries.map(([column], index) => `${column} = $${index + 3}`);
      const result = await client.query(
        `UPDATE public.cars
         SET ${sets.join(", ")}
         WHERE id = $1 AND user_id = $2
         RETURNING id`,
        [carId, req.user.id, ...entries.map(([, value]) => value)]
      );
      if (result.rowCount !== 1) {
        await client.query("ROLLBACK");
        return res.status(404).json({ error: "Car listing not found" });
      }
      await client.query("COMMIT");
      return res.json({ success: true, data: result.rows[0] });
    } catch (error) {
      try { await client?.query("ROLLBACK"); } catch {}
      if (error?.statusCode && error.statusCode >= 400 && error.statusCode < 500) {
        return res.status(error.statusCode).json({ error: error.message });
      }
      console.error("Car update failed:", error.message);
      return res.status(500).json({ error: "Failed to update car listing" });
    } finally {
      if (mustRelease) try { client.release(); } catch {}
    }
  });

  router.patch("/my/:id/status", authenticate, async (req, res) => {
    const status = req.body?.status;
    if (!["active", "sold"].includes(status)) {
      return res.status(400).json({ error: "Invalid car status" });
    }
    try {
      const result = await database.query(
        `UPDATE public.cars
         SET status = $3
         WHERE id = $1 AND user_id = $2
         RETURNING id, status`,
        [req.params.id, req.user.id, status]
      );
      if (result.rowCount !== 1) {
        return res.status(404).json({ error: "Car listing not found" });
      }
      return res.json({ success: true, data: result.rows[0] });
    } catch (error) {
      console.error("Car status update failed:", error.message);
      return res.status(500).json({ error: "Failed to update car status" });
    }
  });

  router.delete("/my/:id", authenticate, async (req, res) => {
    try {
      const result = await database.query(
        `DELETE FROM public.cars
         WHERE id = $1 AND user_id = $2
         RETURNING id`,
        [req.params.id, req.user.id]
      );
      if (result.rowCount !== 1) {
        return res.status(404).json({ error: "Car listing not found" });
      }
      return res.json({ success: true, data: result.rows[0] });
    } catch (error) {
      console.error("Car deletion failed:", error.message);
      return res.status(500).json({ error: "Failed to delete car listing" });
    }
  });

  return router;
}

export default createCarsRouter();
