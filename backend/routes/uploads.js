import { Router } from "express";
import express from "express";
import { authenticateCurrentUser } from "../middleware/current_user.js";
import { publicStorageUrl } from "../services/storage.js";

const allowedTypes = new Map([
  [".jpg", "image/jpeg"],
  [".jpeg", "image/jpeg"],
  [".png", "image/png"],
  [".webp", "image/webp"]
]);
const allowedBuckets = new Set(["cars", "business_ads"]);
const maxBytes = 10 * 1024 * 1024;
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function isImageData(bytes, contentType) {
  if (contentType === "image/png") {
    return (
      bytes.length >= 8 &&
      bytes[0] === 137 &&
      bytes[1] === 80 &&
      bytes[2] === 78 &&
      bytes[3] === 71
    );
  }
  if (contentType === "image/jpeg") {
    return bytes.length >= 3 && bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255;
  }
  return (
    bytes.length >= 12 &&
    bytes.toString("ascii", 0, 4) === "RIFF" &&
    bytes.toString("ascii", 8, 12) === "WEBP"
  );
}

export function createUploadsRouter({
  authenticate = authenticateCurrentUser,
  supabaseUrl = process.env.SUPABASE_URL,
  publishableKey = process.env.SUPABASE_PUBLISHABLE_KEY,
  fetchImpl = fetch
} = {}) {
  const router = Router();

  router.put(
    "/object",
    authenticate,
    express.raw({
      type: ["image/jpeg", "image/png", "image/webp"],
      limit: maxBytes
    }),
    async (req, res) => {
      const bucket = req.query.bucket;
      const objectPath =
        typeof req.query.path === "string" ? req.query.path : "";
      const segments = objectPath.split("/");
      const contentType = req.headers["content-type"]?.split(";")[0];
      const extension = `.${segments.at(-1)?.split(".").at(-1)?.toLowerCase()}`;
      const bytes = req.body;

      if (
        !allowedBuckets.has(bucket) ||
        !Buffer.isBuffer(bytes) ||
        bytes.length === 0 ||
        bytes.length > maxBytes ||
        segments.length < 2 ||
        segments.length > 8 ||
        segments[0] !== req.user.id ||
        segments.some((segment) => !/^[a-zA-Z0-9._-]+$/.test(segment)) ||
        segments.some((segment) => segment === "." || segment === "..") ||
        !allowedTypes.has(extension) ||
        allowedTypes.get(extension) !== contentType ||
        !isImageData(bytes, contentType) ||
        (bucket === "business_ads" &&
          (segments.length !== 4 ||
            !["logos", "images"].includes(segments[1]) ||
            !uuidPattern.test(segments[2]) ||
            !uuidPattern.test(segments[3].slice(0, -extension.length))))
      ) {
        return res.status(400).json({ error: "Invalid image upload" });
      }

      const authorization = req.headers.authorization;
      if (!authorization?.startsWith("Bearer ")) {
        return res.status(401).json({ error: "Authentication token required" });
      }
      if (!supabaseUrl || !publishableKey) {
        return res.status(503).json({ error: "Image storage is not configured" });
      }

      const encodedPath = segments.map(encodeURIComponent).join("/");
      const target = `${supabaseUrl.replace(/\/+$/, "")}/storage/v1/object/${bucket}/${encodedPath}`;
      try {
        const upstream = await fetchImpl(target, {
          method: "POST",
          headers: {
            apikey: publishableKey,
            authorization,
            "content-type": contentType,
            "x-upsert": "true"
          },
          body: bytes,
          signal: AbortSignal.timeout(30000)
        });
        if (!upstream.ok) {
          console.error("Storage upload rejected:", upstream.status);
          return res.status(502).json({ error: "Image upload failed" });
        }
        return res.status(201).json({
          success: true,
          data: {
            public_url: publicStorageUrl(supabaseUrl, bucket, objectPath)
          }
        });
      } catch (error) {
        console.error("Storage upload failed:", error.message);
        return res.status(503).json({ error: "Image storage is unavailable" });
      }
    }
  );

  return router;
}

export default createUploadsRouter();
