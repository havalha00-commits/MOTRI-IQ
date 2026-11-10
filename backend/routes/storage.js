import { Router } from "express";
import express from "express";
import { authenticateCurrentUser } from "../middleware/current_user.js";
import {
  createObjectStorageService,
  validateObjectKey,
  DEFAULT_SIGNED_URL_SECONDS,
  MAX_SIGNED_URL_SECONDS
} from "../services/objectStorage.js";
import { isLocalTestStorageMode, assertLocalTestStorageConfig } from "../config/localTestStorageGuard.js";

const MAX_BYTES = 10 * 1024 * 1024;

const ALLOWED_EXTENSIONS = new Map([
  [".jpg", "image/jpeg"],
  [".jpeg", "image/jpeg"],
  [".png", "image/png"],
  [".webp", "image/webp"]
]);

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function isPendingCarKey(userId, segments) {
  if (!Array.isArray(segments) || segments.length !== 3) return false;
  if (segments[0] !== userId) return false;
  const extIndex = segments[2].lastIndexOf(".");
  if (extIndex <= 0) return false;
  const photoId = segments[2].slice(0, extIndex);
  if (!uuidPattern.test(segments[1]) || !uuidPattern.test(photoId)) return false;
  return true;
}

function noOwnership() {
  return async () => false;
}

function extensionOf(key) {
  const idx = key.lastIndexOf(".");
  if (idx <= 0 || idx === key.length - 1) return "";
  return key.slice(idx).toLowerCase();
}

function contentTypeOf(extension) {
  return ALLOWED_EXTENSIONS.get(extension) || null;
}

function magicBytesMatch(bytes, contentType) {
  if (!Buffer.isBuffer(bytes) || bytes.length < 4) return false;
  if (contentType === "image/jpeg") {
    return bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
  }
  if (contentType === "image/png") {
    return bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47;
  }
  if (contentType === "image/webp") {
    return (
      bytes.length >= 12 &&
      bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46 &&
      bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50
    );
  }
  return false;
}

function validateImageUpload(key, contentType, bytes) {
  if (!key || typeof key !== "string") {
    throw new Error("Invalid object key");
  }
  validateObjectKey(key);
  const ext = extensionOf(key);
  if (!ALLOWED_EXTENSIONS.has(ext)) {
    throw new Error("Invalid file extension");
  }
  const expectedType = contentTypeOf(ext);
  if (!contentType || contentType.split(";")[0] !== expectedType) {
    throw new Error("Content-Type does not match file extension");
  }
  if (!magicBytesMatch(bytes, expectedType)) {
    throw new Error("File content does not match declared type");
  }
  return true;
}

function validateSignedUrlSeconds(expiresIn) {
  const n = Number.parseInt(expiresIn ?? String(DEFAULT_SIGNED_URL_SECONDS), 10);
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

export function createStorageRouter({
  authenticate = authenticateCurrentUser,
  storage,
  ownershipChecker = noOwnership(),
  database = null,
  env = process.env,
} = {}) {
  const router = Router();
  // G10.62 P3: in local-test mode, do not silently create a remote/fallback storage service.
  // Prefer explicitly injected storage; if none and local-test is active, require fail-closed local config.
  if (!storage && isLocalTestStorageMode(env)) {
    try {
      assertLocalTestStorageConfig(env);
      storage = createObjectStorageService({ env });
    } catch {
      storage = null;
    }
  }
  if (!storage) {
    storage = isLocalTestStorageMode(env) ? null : createObjectStorageService({ env });
  }
  router.use(authenticate);

  router.put(
    "/object",
    express.raw({ type: ["image/jpeg", "image/png", "image/webp"], limit: MAX_BYTES }),
    async (req, res) => {
      const bucket = req.query.bucket;
      const objectKey = typeof req.query.path === "string" ? req.query.path : "";
      const contentType = req.headers["content-type"]?.split(";")[0];
      const bytes = req.body;

      if (
        !bucket ||
        !objectKey ||
        !Buffer.isBuffer(bytes) ||
        bytes.length === 0 ||
        bytes.length > MAX_BYTES ||
        !contentType
      ) {
        return res.status(400).json({ error: "Invalid upload request" });
      }

    const userId = req.user?.id;
    if (!userId) {
      return res.status(401).json({ error: "Authentication required" });
    }

      try {
        validateImageUpload(objectKey, contentType, bytes);
      } catch (error) {
        return res.status(400).json({ error: error.message });
      }

      if (!storage) {
        return res.status(503).json({ error: "Object storage is unavailable" });
      }

    if (bucket === "cars") {
      if (!database) {
        return res.status(503).json({ error: "Reservation service unavailable" });
      }
      const reservation = await database.query(
        `SELECT 1 FROM public.car_image_upload_reservations
         WHERE object_key = $1 AND user_id = $2 AND expires_at > NOW() AND consumed_at IS NULL
         LIMIT 1`,
        [objectKey, userId]
      );
      if (reservation.rows.length === 0) {
        return res.status(403).json({ error: "Upload reservation required" });
      }
    }

    const owned = bucket === "cars" && isPendingCarKey(userId, objectKey.split("/"))
      ? true
      : await storage.checkOwnership(userId, objectKey, bucket);
    if (!owned) {
        return res.status(403).json({ error: "Object ownership check failed" });
      }

       try {
         const result = await storage.upload({ bucket, key: objectKey, body: bytes, contentType });
         let publicUrl = null;
         try {
           publicUrl = await storage.getPublicUrl({ bucket, key: objectKey });
         } catch {}
         return res.status(201).json({ success: true, data: { ...result, public_url: publicUrl } });
       } catch (error) {
        if (error.statusCode === 403) {
          return res.status(403).json({ error: error.message });
        }
        console.error("Storage upload failed:", error.message);
        return res.status(503).json({ error: "Object storage is unavailable" });
      }
    }
  );

  router.get("/object", async (req, res) => {
    const bucket = req.query.bucket;
    const objectKey = typeof req.query.path === "string" ? req.query.path : "";
    const userId = req.user?.id;

    if (!bucket || !objectKey || !userId) {
      return res.status(400).json({ error: "Invalid download request" });
    }
    if (!storage) return res.status(503).json({ error: "Object storage is unavailable" });

    try {
      validateObjectKey(objectKey);
    } catch (error) {
      return res.status(400).json({ error: error.message });
    }

    try {
      const result = await storage.download({ bucket, key: objectKey, userId });
      res.setHeader("Content-Type", result.contentType || "application/octet-stream");
      if (result.size != null) res.setHeader("Content-Length", String(result.size));
      if (result.lastModified) res.setHeader("Last-Modified", new Date(result.lastModified).toUTCString());
      result.body.pipe(res);
    } catch (error) {
      if (error.statusCode === 403) {
        return res.status(403).json({ error: error.message });
      }
      if (error.statusCode === 404) {
        return res.status(404).json({ error: "Object not found" });
      }
      console.error("Storage download failed:", error.message);
      return res.status(503).json({ error: "Object storage is unavailable" });
    }
  });

  router.delete("/object", async (req, res) => {
    const bucket = req.query.bucket;
    const objectKey = typeof req.query.path === "string" ? req.query.path : "";
    const userId = req.user?.id;

    if (!bucket || !objectKey || !userId) {
      return res.status(400).json({ error: "Invalid delete request" });
    }
    if (!storage) return res.status(503).json({ error: "Object storage is unavailable" });

    try {
      validateObjectKey(objectKey);
    } catch (error) {
      return res.status(400).json({ error: error.message });
    }

    try {
      const result = await storage.deleteObject({ bucket, key: objectKey, userId });
      return res.json({ success: true, data: result });
    } catch (error) {
      if (error.statusCode === 403) {
        return res.status(403).json({ error: error.message });
      }
      if (error.statusCode === 404) {
        return res.status(404).json({ error: "Object not found" });
      }
      console.error("Storage delete failed:", error.message);
      return res.status(503).json({ error: "Object storage is unavailable" });
    }
  });

  router.get("/sign", async (req, res) => {
    const bucket = req.query.bucket;
    const objectKey = typeof req.query.path === "string" ? req.query.path : "";
    const userId = req.user?.id;

    let expiresIn;
    try {
      expiresIn = validateSignedUrlSeconds(req.query.expires_in);
    } catch (error) {
      return res.status(400).json({ error: error.message });
    }

    if (!bucket || !objectKey || !userId) {
      return res.status(400).json({ error: "Invalid sign request" });
    }
    if (!storage) return res.status(503).json({ error: "Object storage is unavailable" });

    try {
      const result = await storage.getSignedUrl({ bucket, key: objectKey, userId, expiresIn });
      return res.json({ success: true, data: result });
    } catch (error) {
      if (error.statusCode === 403) {
        return res.status(403).json({ error: error.message });
      }
      if (error.statusCode === 404) {
        return res.status(404).json({ error: "Object not found" });
      }
      console.error("Storage sign failed:", error.message);
      return res.status(503).json({ error: "Object storage is unavailable" });
    }
  });

  return router;
}

export default createStorageRouter;
