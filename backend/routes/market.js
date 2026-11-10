import { Router } from "express";
import express from "express";
import crypto from "node:crypto";
import { pool } from "../config/database.js";
import { authenticateCurrentUser, optionalCurrentUser } from "../middleware/current_user.js";
import { isOwnedPublicStorageUrl } from "../services/storage.js";
import { ugcPolicy } from "../services/ugc_policy.js";

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const marketImageRefPattern = /^mimg_[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const marketImageKeyPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\/(market|job)\/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(jpg|jpeg|png|webp)$/i;
const MARKET_IMAGE_EXT_TO_TYPE = { ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png", ".webp": "image/webp" };
const MARKET_IMAGE_MAX_BYTES = 10 * 1024 * 1024;
const MARKET_IMAGE_TTL_MINUTES = 60;
const MARKET_IMAGE_PUBLIC_CACHE = "public, max-age=0, must-revalidate";
const MARKET_IMAGE_PRIVATE_CACHE = "private, no-store";
const MARKET_BUCKET = "market_images";

function boundedNumber(value, fallback, min, max) {
  const parsed = Number.parseInt(value, 10);
  return Number.isInteger(parsed) ? Math.min(Math.max(parsed, min), max) : fallback;
}
function extOfMarketKey(key) { const i = String(key || "").lastIndexOf("."); return i > 0 ? String(key).slice(i).toLowerCase() : ""; }
function marketDeliveryPath(ref) { return `/api/market/images/${encodeURIComponent(ref)}`; }
function parseMarketImageRef(value) {
  if (typeof value !== "string") return null;
  const v = value.trim();
  if (!v) return null;
  if (marketImageRefPattern.test(v)) return v;
  try {
    const u = new URL(v, "http://local.invalid");
    const m = u.pathname.match(/\/api\/market\/images\/(mimg_[0-9a-f-]{36})$/i);
    if (m) return m[1];
  } catch {}
  const m = v.match(/\/api\/market\/images\/(mimg_[0-9a-f-]{36})$/i);
  return m ? m[1] : null;
}
function isCarOrRawObjectRef(value) {
  if (typeof value !== "string") return false;
  const v = value.trim();
  if (!v) return false;
  if (/\/api\/cars\/[0-9a-f-]{36}\/images\/\d+/i.test(v)) return true;
  // canonical car object key shape - reject as market image ref
  if (/^[0-9a-f-]{36}\/[0-9a-f-]{36}\/[0-9a-f-]{36}\.(jpg|jpeg|png|webp)$/i.test(v)) return true;
  return false;
}
function isLegacyAbsoluteImageUrl(value) {
  if (typeof value !== "string") return false;
  const v = value.trim();
  try { const u = new URL(v); return u.protocol === "http:" || u.protocol === "https:"; } catch { return false; }
}
function isLegacyTrustedUrl(value, { userId, storageUrl, existing = [] } = {}) {
  if (typeof value !== "string") return false;
  const v = value.trim();
  if (existing.includes(v)) return true; // retained value from this listing row (locked owner row)
  if (!isLegacyAbsoluteImageUrl(v)) return false;
  if (storageUrl && isOwnedPublicStorageUrl(v, { baseUrl: storageUrl, bucket: "cars", userId })) return true;
  return false;
}
function validateImageArrayShape(value, jobs) {
  return Array.isArray(value) && value.length <= (jobs ? 5 : 6) && (jobs || value.length >= 2) && value.every((v) => typeof v === "string");
}
function validImageList(value, { jobs, userId, existing = [], storageUrl }) {
  if (!validateImageArrayShape(value, jobs)) return false;
  return value.every((url) => {
    if (typeof url !== "string") return false;
    const v = url.trim();
    if (existing.includes(v)) return true;
    if (isCarOrRawObjectRef(v)) return false;
    if (parseMarketImageRef(v)) return true; // allowed syntactically; ownership/expiry/binding validated in resolveAndBindMarketImages
    return isLegacyTrustedUrl(v, { userId, storageUrl, existing });
  });
}
function sniffMarketImageContentType(bytes, fallbackExt) {
  if (Buffer.isBuffer(bytes) && bytes.length >= 3) {
    if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return "image/jpeg";
    if (bytes.length >= 8 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47) return "image/png";
    if (bytes.length >= 12 && bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46 && bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50) return "image/webp";
  }
  return MARKET_IMAGE_EXT_TO_TYPE[fallbackExt] || null;
}
function normalizeStoredImages(value) {
  if (Array.isArray(value)) return value.filter((v) => typeof v === "string");
  if (typeof value !== "string" || !value.trim()) return [];
  try { const p = JSON.parse(value); return Array.isArray(p) ? p.filter((v) => typeof v === "string") : []; } catch { return []; }
}

async function resolveAndBindMarketImages({ client, userId, images, jobs, existing = [], storageUrl, boundTable, boundId }) {
  if (!validateImageArrayShape(images, jobs)) {
    const err = new Error("Invalid listing images"); err.statusCode = 400; throw err;
  }
  const refs = [];
  const normalized = images.map((raw) => {
    const v = String(raw).trim();
    if (isCarOrRawObjectRef(v)) { const e = new Error("Car/A1/raw object references are not allowed for market images"); e.statusCode = 400; throw e; }
    const ref = parseMarketImageRef(v);
    if (ref) { refs.push(ref); return { kind: "ref", ref }; }
    if (existing.includes(v) || isLegacyTrustedUrl(v, { userId, storageUrl, existing })) return { kind: "legacy", value: v };
    const e = new Error("Invalid or foreign image reference"); e.statusCode = 400; throw e;
  });
  if (refs.length === 0) return images.map((v) => String(v).trim());
  const uniqueRefs = [...new Set(refs)];
  await client.query(
    `UPDATE public.market_image_upload_refs
        SET status = 'expired'
      WHERE status = 'unbound' AND expires_at <= NOW() AND ref = ANY($1::text[])`,
    [uniqueRefs]
  ).catch(() => {});
  const found = await client.query(
    `SELECT ref, user_id, kind, status, expires_at, bound_table, bound_id
       FROM public.market_image_upload_refs
      WHERE ref = ANY($1::text[])
      FOR UPDATE`,
    [uniqueRefs]
  );
  const byRef = new Map(found.rows.map((r) => [r.ref, r]));
  for (const ref of uniqueRefs) {
    const row = byRef.get(ref);
    if (!row || String(row.user_id) !== String(userId)) {
      const err = new Error("Invalid, expired, or unauthorized market image reference"); err.statusCode = 400; throw err;
    }
    const alreadyBoundToSame =
      row.status === "bound" && boundTable && boundId &&
      String(row.bound_table || "") === String(boundTable) &&
      String(row.bound_id || "") === String(boundId);
    if (alreadyBoundToSame) continue;
    if (row.status !== "unbound" || new Date(row.expires_at).getTime() <= Date.now()) {
      const err = new Error("Invalid, expired, or unauthorized market image reference"); err.statusCode = 400; throw err;
    }
  }
  if (boundTable && boundId) {
    const toBind = uniqueRefs.filter((ref) => {
      const row = byRef.get(ref);
      return row && row.status === "unbound";
    });
    if (toBind.length) await client.query(
      `UPDATE public.market_image_upload_refs
          SET status = 'bound', bound_table = $2, bound_id = $3::uuid
        WHERE ref = ANY($1::text[]) AND user_id = $4 AND status = 'unbound' AND expires_at > NOW()`,
      [toBind, boundTable, boundId, userId]
    );
  }
  return normalized.map((n) => n.kind === "legacy" ? n.value : marketDeliveryPath(n.ref));
}

function canViewMarketListing({ listing, user }) {
  if (!listing) return false;
  if (listing.is_approved === true) return true;
  if (!user?.id) return false;
  if (String(listing.user_id) === String(user.id)) return true;
  if (user.is_admin === true) return true;
  return false;
}

export function createMarketRouter({
  database = pool,
  authenticate = authenticateCurrentUser,
  optionalAuthenticate = optionalCurrentUser,
  policy = ugcPolicy,
  storageUrl = process.env.SUPABASE_URL,
  storage = null,
} = {}) {
  const router = Router();
  const optAuth = optionalAuthenticate || ((req, res, next) => {
    if (!req.headers.authorization) return next();
    return authenticate(req, res, next);
  });

  // Read routes allow optional auth so public/ordinary users can view approved listings (enforced in SQL). Mutating routes require authentication.
  router.use((req, res, next) => {
    if (req.method === "GET" && (req.path === "/items" || req.path === "/items/by-ids")) return optAuth(req, res, next);
    return authenticate(req, res, next);
  });

  // M1C: Flutter BackendApi.putBytes sends PUT (body bytes, ?kind=, auth, content-type). Accept PUT as canonical; keep POST for compatibility.
  const uploadHandler = async (req, res) => {
      const userId = req.user?.id;
      if (!userId) return res.status(401).json({ error: "Authentication required" });
      const kind = String(req.query.kind || req.body?.kind || "market").toLowerCase();
      if (!["market", "job"].includes(kind)) return res.status(400).json({ error: "Invalid image kind" });
      const contentType = req.headers["content-type"]?.split(";")[0];
      const bytes = req.body;
      if (!Buffer.isBuffer(bytes) || bytes.length === 0 || bytes.length > MARKET_IMAGE_MAX_BYTES || !contentType) {
        return res.status(400).json({ error: "Invalid image upload" });
      }
      const ext = Object.entries(MARKET_IMAGE_EXT_TO_TYPE).find(([, t]) => t === contentType)?.[0];
      if (!ext) return res.status(400).json({ error: "Invalid content type" });
      const sniffed = sniffMarketImageContentType(bytes, ext);
      if (!sniffed || sniffed !== contentType) return res.status(400).json({ error: "File content does not match declared type" });
      if (!storage || typeof storage.upload !== "function") return res.status(503).json({ error: "Image storage unavailable" });
      const photoId = crypto.randomUUID();
      const objectKey = `${userId}/${kind}/${photoId}${ext}`;
      if (!marketImageKeyPattern.test(objectKey)) return res.status(400).json({ error: "Invalid image key" });
      const ref = `mimg_${crypto.randomUUID()}`;
      const expiresAt = new Date(Date.now() + MARKET_IMAGE_TTL_MINUTES * 60 * 1000).toISOString();
      try {
        await storage.upload({ bucket: MARKET_BUCKET, key: objectKey, body: bytes, contentType });
      } catch (error) {
        console.error("Market image upload failed:", error?.message || "unknown");
        return res.status(503).json({ error: "Image storage unavailable" });
      }
      try {
        await database.query(
          `INSERT INTO public.market_image_upload_refs (ref, user_id, kind, object_key, content_type, size_bytes, status, expires_at)
           VALUES ($1,$2,$3,$4,$5,$6,'unbound',$7::timestamptz)`,
          [ref, userId, kind, objectKey, contentType, bytes.length, expiresAt]
        );
      } catch (error) {
        console.error("Market image ref insert failed:", error?.message || "unknown");
        try { await storage.deleteObject?.({ bucket: MARKET_BUCKET, key: objectKey }); } catch {}
        return res.status(503).json({ error: "Failed to register market image" });
      }
      return res.status(201).json({ success: true, data: { ref, delivery_url: marketDeliveryPath(ref), content_type: contentType, kind, expires_at: expiresAt } });
  };
  router.put("/uploads", express.raw({ type: ["image/jpeg", "image/png", "image/webp"], limit: MARKET_IMAGE_MAX_BYTES }), uploadHandler);
  router.post("/uploads", express.raw({ type: ["image/jpeg", "image/png", "image/webp"], limit: MARKET_IMAGE_MAX_BYTES }), uploadHandler);

  router.get("/items", async (req, res) => {
    try {
      const limit = boundedNumber(req.query.limit, 20, 1, 100);
      const isAdmin = req.user?.is_admin === true;
      const userId = req.user?.id || null;
      const result = await database.query(
        isAdmin
          ? `SELECT * FROM public.market_items ORDER BY created_at DESC LIMIT $1`
          : userId
            ? `SELECT * FROM public.market_items WHERE is_approved = TRUE OR user_id = $2 ORDER BY created_at DESC LIMIT $1`
            : `SELECT * FROM public.market_items WHERE is_approved = TRUE ORDER BY created_at DESC LIMIT $1`,
        isAdmin ? [limit] : userId ? [limit, userId] : [limit]
      );
      return res.json({ success: true, data: result.rows });
    } catch (error) {
      console.error("Market items API error:", error.message);
      return res.status(500).json({ error: "Failed to load market items" });
    }
  });

  router.get("/items/by-ids", async (req, res) => {
    const rawIds = typeof req.query.ids === "string" ? req.query.ids : "";
    const ids = [...new Set(rawIds.split(",").filter((id) => uuidPattern.test(id)))];
    if (ids.length === 0 || ids.length > 100) {
      return res.status(400).json({ error: "Provide 1-100 valid market item ids" });
    }
    try {
      const isAdmin = req.user?.is_admin === true;
      const userId = req.user?.id || null;
      const result = await database.query(
        isAdmin
          ? `SELECT * FROM public.market_items WHERE id = ANY($1::uuid[])`
          : userId
            ? `SELECT * FROM public.market_items WHERE id = ANY($1::uuid[]) AND (is_approved = TRUE OR user_id = $2)`
            : `SELECT * FROM public.market_items WHERE id = ANY($1::uuid[]) AND is_approved = TRUE`,
        isAdmin ? [ids] : userId ? [ids, userId] : [ids]
      );
      return res.json({ success: true, data: result.rows });
    } catch (error) {
      console.error("Market items by id API error:", error.message);
      return res.status(500).json({ error: "Failed to load market items" });
    }
  });

  async function createListing(req, res, jobs) {
    const body = req.body ?? {};
    const id = body.id;
    const title = typeof body.title === "string" ? body.title.trim() : "";
    const description =
      typeof body.description === "string" ? body.description.trim() : null;
    const location =
      typeof body.governorate === "string" ? body.governorate.trim() : null;
    const amount = jobs ? body.salary : body.price;
    const type = body.job_type;
    const images = body.images ?? [];

    if (
      !uuidPattern.test(id ?? "") ||
      title.length === 0 ||
      title.length > 200 ||
      (description != null && description.length > 2000) ||
      (location != null && location.length > 200) ||
      (amount != null &&
        (typeof amount !== "number" || !Number.isFinite(amount) || amount < 0)) ||
      (jobs &&
        (typeof location !== "string" ||
          location.length === 0 ||
          typeof type !== "string" ||
          type.length === 0 ||
          type.length > 64)) ||
      !validImageList(images, { jobs, userId: req.user.id, storageUrl })
    ) {
      return res.status(400).json({ error: "Invalid listing" });
    }

    try {
      if (!(await policy.hasAccepted(req))) {
        return res.status(403).json({ error: "UGC_POLICY_ACCEPTANCE_REQUIRED" });
      }
      const table = jobs ? "public.jobs" : "public.market_items";
      const hasRefs = Array.isArray(images) && images.some((v) => parseMarketImageRef(v));
      const client = hasRefs && typeof database.connect === "function" ? await database.connect() : null;
      const q = client || database;
      try {
        if (client) await client.query("BEGIN");
        const boundImages = await resolveAndBindMarketImages({
          client: q, userId: req.user.id, images, jobs, existing: [], storageUrl, boundTable: table, boundId: id,
        });
        const columns = jobs
          ? "(id, user_id, title, description, salary, governorate, job_type, images, is_approved)"
          : "(id, user_id, title, description, price, images, is_approved)";
        const values = jobs
          ? [id, req.user.id, title, description, amount ?? null, location, type, boundImages]
          : [id, req.user.id, title, description, amount ?? null, boundImages];
        const placeholders = values.map((_, index) => `$${index + 1}`).join(", ");
        const inserted = await q.query(
          `INSERT INTO ${table} ${columns}
           VALUES (${placeholders}, FALSE)
           ON CONFLICT (id) DO NOTHING
           RETURNING id`,
          values
        );
        if (inserted.rowCount === 1 && inserted.rows[0]?.id === id) {
          if (client) await client.query("COMMIT");
          return res.status(201).json({ success: true, data: { id } });
        }
        const existing = await q.query(
          `SELECT id FROM ${table} WHERE id = $1 AND user_id = $2`,
          [id, req.user.id]
        );
        if (client) await client.query("ROLLBACK");
        if (existing.rowCount === 1 && existing.rows[0].id === id) {
          return res.status(200).json({ success: true, data: { id } });
        }
        return res.status(409).json({ error: "Listing identifier is unavailable" });
      } catch (error) {
        if (client) try { await client.query("ROLLBACK"); } catch {}
        throw error;
      } finally {
        if (client) try { client.release(); } catch {}
      }
    } catch (error) {
      if (error?.statusCode) return res.status(error.statusCode).json({ error: error.message });
      console.error("Marketplace listing creation failed:", error.message);
      return res.status(503).json({ error: "Failed to publish listing" });
    }
  }

  async function updateImages(req, res, jobs) {
    const id = req.params.id;
    const images = req.body?.images;
    if (
      !uuidPattern.test(id ?? "") ||
      !Array.isArray(images) ||
      images.length > (jobs ? 5 : 6) ||
      (!jobs && images.length < 2) ||
      images.some((url) => typeof url !== "string")
    ) {
      return res.status(400).json({ error: "Invalid listing images" });
    }
    const table = jobs ? "public.jobs" : "public.market_items";
    const client = typeof database.connect === "function" ? await database.connect() : database;
    const release = client !== database && typeof client.release === "function";
    try {
      await client.query("BEGIN");
      const current = await client.query(
        `SELECT id, images FROM ${table}
         WHERE id = $1 AND user_id = $2
         FOR UPDATE`,
        [id, req.user.id]
      );
      const row = current.rows[0];
      if (!row) {
        await client.query("ROLLBACK");
        return res.status(404).json({ error: "Listing is unavailable" });
      }
      const oldImages = normalizeStoredImages(row.images);
      if (!validImageList(images, {
        jobs,
        userId: req.user.id,
        existing: oldImages,
        storageUrl
      })) {
        await client.query("ROLLBACK");
        return res.status(400).json({ error: "Invalid listing images" });
      }
      const boundImages = await resolveAndBindMarketImages({
        client, userId: req.user.id, images, jobs, existing: oldImages, storageUrl, boundTable: table, boundId: id,
      });
      const updated = await client.query(
        `UPDATE ${table}
         SET images = $3
         WHERE id = $1 AND user_id = $2
         RETURNING id`,
        [id, req.user.id, boundImages]
      );
      await client.query("COMMIT");
      if (updated.rowCount !== 1 || updated.rows[0]?.id !== id) {
        return res.status(409).json({ error: "Listing images were not saved" });
      }
      return res.json({ success: true, data: { id } });
    } catch (error) {
      try { await client.query("ROLLBACK"); } catch (rollbackError) { console.error("Listing image rollback failed:", rollbackError.message); }
      if (error?.statusCode) return res.status(error.statusCode).json({ error: error.message });
      console.error("Listing image update failed:", error.message);
      return res.status(503).json({ error: "Failed to save listing images" });
    } finally {
      if (release) try { client.release(); } catch {}
    }
  }

  async function deleteItem(req, res) {
    const id = req.params.id;
    if (!uuidPattern.test(id ?? "")) {
      return res.status(400).json({ error: "Invalid listing identifier" });
    }
    try {
      const deleted = await database.query(
        `DELETE FROM public.market_items
         WHERE id = $1 AND user_id = $2
         RETURNING id`,
        [id, req.user.id]
      );
      if (deleted.rowCount !== 1 || deleted.rows[0]?.id !== id) {
        return res.status(404).json({ error: "Listing is unavailable" });
      }
      return res.json({ success: true, data: { id } });
    } catch (error) {
      console.error("Marketplace listing deletion failed:", error.message);
      return res.status(503).json({ error: "Failed to delete listing" });
    }
  }

  async function adminDeleteListing(req, res) {
    if (req.user?.is_admin !== true) {
      return res.status(403).json({ ok: false, deleted: 0, reason: "not_admin", error: "Administrator access required" });
    }
    const { table, id } = req.params;
    const allowedTables = new Set(["cars", "market_items", "jobs"]);
    if (!allowedTables.has(table)) {
      return res.status(400).json({ ok: false, deleted: 0, reason: "table_not_allowed", error: "Table not allowed" });
    }
    if (!uuidPattern.test(id ?? "")) {
      return res.status(400).json({ ok: false, deleted: 0, reason: "bad_id", error: "Invalid identifier" });
    }
    const client = typeof database.connect === "function" ? await database.connect() : { query: (sql, values) => database.query(sql, values), release: () => {} };
    try {
      await client.query("BEGIN");
      const deleted = await client.query(
        `DELETE FROM public.${table} WHERE id = $1 RETURNING id`,
        [id]
      );
      if (deleted.rowCount !== 1) {
        await client.query("ROLLBACK");
        return res.status(404).json({ ok: false, deleted: 0, reason: "not_found", error: "Listing not found" });
      }
      await client.query("SAVEPOINT audit_log");
      try {
        await client.query(
          `INSERT INTO public.admin_ad_deletions (ad_table, ad_id, admin_id) VALUES ($1, $2, $3)`,
          [table, id, req.user.id]
        );
        await client.query("RELEASE SAVEPOINT audit_log");
      } catch (auditError) {
        await client.query("ROLLBACK TO SAVEPOINT audit_log");
        console.warn("Admin deletion audit log skipped or failed:", auditError.message);
      }
      await client.query("COMMIT");
      return res.json({ ok: true, deleted: 1, reason: null, data: { id, table } });
    } catch (error) {
      try { await client.query("ROLLBACK"); } catch (_) {}
      console.error("Admin listing deletion failed:", error.message);
      return res.status(503).json({ ok: false, deleted: 0, reason: "db_error", error: "Failed to delete listing" });
    } finally {
      client.release();
    }
  }

  router.post("/items", (req, res) => createListing(req, res, false));
  router.post("/jobs", (req, res) => createListing(req, res, true));
  router.delete("/items/:id", deleteItem);
  router.delete("/admin/ads/:table/:id", adminDeleteListing);
  router.patch("/items/:id/images", (req, res) => updateImages(req, res, false));
  router.patch("/jobs/:id/images", (req, res) => updateImages(req, res, true));

  // Test-only, non-enumerable introspection of injected deps; no behavior/security change.
  Object.defineProperty(router, "__deps", { value: { database, storage, authenticate, optionalAuthenticate }, enumerable: false, configurable: false });
  return router;
}

export function createMarketImageDeliveryRouter({
  database = pool,
  optionalAuthenticate = optionalCurrentUser,
  storage = null,
} = {}) {
  const router = Router();
  router.get("/:ref", optionalAuthenticate, async (req, res) => {
    // No unsafe 304: always revalidate auth + current DB/ref/listing visibility before serving bytes.
    if (req.headers["if-none-match"] || req.headers["if-modified-since"]) {
      res.setHeader("Cache-Control", "no-store");
      return res.status(412).json({ error: "Conditional request not supported; revalidation required" });
    }
    const ref = String(req.params.ref || "");
    if (!marketImageRefPattern.test(ref)) return res.status(404).json({ error: "Not found" });
    try {
      const refRes = await database.query(
        `SELECT ref, user_id, kind, object_key, status, expires_at, bound_table, bound_id
           FROM public.market_image_upload_refs
          WHERE ref = $1
          LIMIT 1`,
        [ref]
      );
      if (refRes.rowCount !== 1) return res.status(404).json({ error: "Not found" });
      const row = refRes.rows[0];
      if (row.status === "expired" || (row.status === "unbound" && new Date(row.expires_at).getTime() <= Date.now())) {
        return res.status(404).json({ error: "Not found" });
      }
      let isPublic = false;
      let listing = null;
      if (row.bound_table && row.bound_id && ["public.market_items", "public.jobs"].includes(row.bound_table)) {
        const t = row.bound_table === "public.jobs" ? "public.jobs" : "public.market_items";
        const lres = await database.query(`SELECT id, user_id, is_approved FROM ${t} WHERE id = $1 LIMIT 1`, [row.bound_id]);
        listing = lres.rows[0] || null;
        if (!listing) return res.status(404).json({ error: "Not found" });
        isPublic = listing.is_approved === true;
      }
      const isOwner = req.user?.id && String(req.user.id) === String(row.user_id);
      const isAdmin = req.user?.is_admin === true;
      if (!isPublic && !isOwner && !isAdmin) return res.status(403).json({ error: "Forbidden" });
      if (!marketImageKeyPattern.test(String(row.object_key || ""))) return res.status(404).json({ error: "Not found" });
      if (!storage || typeof storage.download !== "function") return res.status(503).json({ error: "Image delivery unavailable" });
      const obj = await storage.download({ bucket: MARKET_BUCKET, key: row.object_key });
      const ext = extOfMarketKey(row.object_key);
      const expectedType = MARKET_IMAGE_EXT_TO_TYPE[ext] || null;
      const body = obj.body;
      let prefix = Buffer.alloc(0);
      if (body && typeof body[Symbol.asyncIterator] === "function") {
        for await (const chunk of body) {
          const b = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
          prefix = Buffer.concat([prefix, b]);
          if (prefix.length >= 64) break;
        }
        const sniffed = sniffMarketImageContentType(prefix, ext);
        const type = sniffed || expectedType || "application/octet-stream";
        if (!expectedType || !String(type).startsWith("image/")) return res.status(415).json({ error: "Unsupported image type" });
        res.setHeader("Content-Type", type);
        res.setHeader("X-Content-Type-Options", "nosniff");
        res.setHeader("Cache-Control", isPublic ? MARKET_IMAGE_PUBLIC_CACHE : MARKET_IMAGE_PRIVATE_CACHE);
        if (obj.size != null && Number.isFinite(Number(obj.size))) res.setHeader("Content-Length", String(obj.size));
        if (prefix.length) res.write(prefix);
        for await (const chunk of body) res.write(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
        return res.end();
      }
      const chunks = [];
      if (Buffer.isBuffer(body)) chunks.push(body);
      else if (body && typeof body.pipe === "function") {
        await new Promise((resolve, reject) => { body.on("data", (c) => chunks.push(Buffer.isBuffer(c)?c:Buffer.from(c))); body.on("end", resolve); body.on("error", reject); });
      } else if (body) chunks.push(Buffer.from(body));
      const buf = Buffer.concat(chunks);
      if (!buf.length || buf.length > MARKET_IMAGE_MAX_BYTES) return res.status(404).json({ error: "Not found" });
      const sniffed = sniffMarketImageContentType(buf, ext);
      const type = sniffed || expectedType || "application/octet-stream";
      if (!expectedType || !String(type).startsWith("image/") || (sniffed && expectedType && sniffed !== expectedType)) {
        return res.status(415).json({ error: "Unsupported image type" });
      }
      res.setHeader("Content-Type", type);
      res.setHeader("X-Content-Type-Options", "nosniff");
      res.setHeader("Cache-Control", isPublic ? MARKET_IMAGE_PUBLIC_CACHE : MARKET_IMAGE_PRIVATE_CACHE);
      res.setHeader("Content-Length", String(buf.length));
      return res.status(200).end(buf);
    } catch (error) {
      if (error?.statusCode === 404) return res.status(404).json({ error: "Not found" });
      console.error("Market image delivery failed:", error?.message || "unknown");
      return res.status(503).json({ error: "Image delivery unavailable" });
    }
  });
  // Test-only, non-enumerable introspection of injected deps; no behavior/security change.
  Object.defineProperty(router, "__deps", { value: { database, storage, optionalAuthenticate }, enumerable: false, configurable: false });
  return router;
}

export default createMarketRouter;
