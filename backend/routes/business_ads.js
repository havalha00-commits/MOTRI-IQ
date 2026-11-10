import { Router } from "express";
import { pool } from "../config/database.js";
import {
  authenticateCurrentUser,
  optionalCurrentUser
} from "../middleware/current_user.js";
import { isOwnedPublicStorageUrl } from "../services/storage.js";
import { ugcPolicy } from "../services/ugc_policy.js";

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const adStatuses = new Set([
  "pending",
  "approved",
  "rejected",
  "active",
  "expired",
  "paused"
]);
const paymentStatuses = new Set(["unpaid", "pending", "paid", "failed", "refunded"]);
const eventTypes = new Set(["view", "click", "call", "whatsapp", "map", "share"]);
const counters = new Set([
  "views_count",
  "clicks_count",
  "calls_count",
  "whatsapp_clicks"
]);

function boundedNumber(value, fallback, min, max) {
  const parsed = Number.parseInt(value, 10);
  return Number.isInteger(parsed) ? Math.min(Math.max(parsed, min), max) : fallback;
}

export function createBusinessAdsRouter({
  database = pool,
  authenticate = authenticateCurrentUser,
  optionalAuthenticate = optionalCurrentUser,
  policy = ugcPolicy,
  storageUrl = process.env.SUPABASE_URL
} = {}) {
  const router = Router();

  router.post("/submissions", authenticate, async (req, res) => {
    const body = req.body ?? {};
    const {
      ad_id,
      package_id,
      fields,
      logo_url,
      image_urls
    } = body;
    if (
      !uuidPattern.test(ad_id ?? "") ||
      !uuidPattern.test(package_id ?? "") ||
      !fields ||
      typeof fields !== "object" ||
      Array.isArray(fields) ||
      typeof fields.business_name !== "string" ||
      fields.business_name.trim().length < 2 ||
      fields.business_name.trim().length > 100 ||
      typeof fields.category !== "string" ||
      !fields.category.trim() ||
      typeof logo_url !== "string" ||
      !isOwnedPublicStorageUrl(logo_url, {
        baseUrl: storageUrl,
        bucket: "business_ads",
        userId: req.user.id
      }) ||
      !Array.isArray(image_urls) ||
      image_urls.length > 10 ||
      image_urls.some(
        (url) =>
          !isOwnedPublicStorageUrl(url, {
            baseUrl: storageUrl,
            bucket: "business_ads",
            userId: req.user.id
          })
      )
    ) {
      return res.status(400).json({ error: "Invalid business ad submission" });
    }

    try {
      if (!(await policy.hasAccepted(req))) {
        return res.status(403).json({ error: "UGC_POLICY_ACCEPTANCE_REQUIRED" });
      }

      const client = await database.connect();
      try {
        await client.query("BEGIN");
        const existingAdResult = await client.query(
          `SELECT id, user_id, package_id, price
           FROM public.business_ads
           WHERE id = $1
           FOR UPDATE`,
          [ad_id]
        );
        const existingAd = existingAdResult.rows[0];
        if (existingAd && existingAd.user_id !== req.user.id) {
          await client.query("ROLLBACK");
          return res.status(409).json({ error: "Business ad identifier is unavailable" });
        }

        let packageData;
        if (existingAd) {
          if (existingAd.package_id !== package_id) {
            await client.query("ROLLBACK");
            return res.status(409).json({ error: "Business ad submission conflicts" });
          }
          packageData = {
            price: existingAd.price,
            duration_days: 30
          };
        } else {
          const packageResult = await client.query(
            `SELECT price, duration_days
             FROM public.business_ad_packages
             WHERE id = $1 AND is_active = TRUE`,
            [package_id]
          );
          packageData = packageResult.rows[0];
          if (!packageData || Number(packageData.duration_days) < 1) {
            await client.query("ROLLBACK");
            return res.status(409).json({ error: "Business ad package is unavailable" });
          }
          const now = new Date();
          const endAt = new Date(
            now.getTime() + Number(packageData.duration_days) * 86400000
          );
          const fieldsValue = fields;
          await client.query(
            `INSERT INTO public.business_ads (
               id, user_id, business_name, category, description, logo_url,
               image_urls, phone, whatsapp, governorate, area, address,
               latitude, longitude, maps_url, instagram_url, facebook_url,
               working_hours, status, package_id, start_at, end_at, price,
               payment_status
             ) VALUES (
               $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12,
               $13, $14, $15, $16, $17, $18, 'pending', $19, $20, $21,
               $22, 'unpaid'
             )`,
            [
              ad_id,
              req.user.id,
              fieldsValue.business_name.trim(),
              fieldsValue.category.trim(),
              fieldsValue.description ?? null,
              logo_url,
              image_urls,
              fieldsValue.phone ?? null,
              fieldsValue.whatsapp ?? null,
              fieldsValue.governorate ?? null,
              fieldsValue.area ?? null,
              fieldsValue.address ?? null,
              fieldsValue.latitude ?? null,
              fieldsValue.longitude ?? null,
              fieldsValue.maps_url ?? null,
              fieldsValue.instagram_url ?? null,
              fieldsValue.facebook_url ?? null,
              fieldsValue.working_hours ?? null,
              package_id,
              now,
              endAt,
              packageData.price
            ]
          );
        }

        await client.query("COMMIT");
        return res.status(201).json({
          success: true,
          data: { ad_id }
        });
      } catch (error) {
        try {
          await client.query("ROLLBACK");
        } catch (rollbackError) {
          console.error("Business submission rollback failed:", rollbackError.message);
        }
        throw error;
      } finally {
        client.release();
      }
    } catch (error) {
      console.error("Business ad submission failed:", error.message);
      return res.status(503).json({ error: "Failed to submit business ad" });
    }
  });

  router.get("/packages", async (_req, res) => {
    try {
      const result = await database.query(
        `SELECT * FROM public.business_ad_packages
         WHERE is_active = TRUE
         ORDER BY sort_order ASC, created_at ASC`
      );
      return res.json({ success: true, data: result.rows });
    } catch (error) {
      console.error("Business ad packages load failed:", error.message);
      return res.status(500).json({ error: "Failed to load business packages" });
    }
  });

  router.get("/active", async (req, res) => {
    const categories =
      typeof req.query.categories === "string"
        ? [...new Set(req.query.categories.split(",").filter(Boolean))].slice(0, 20)
        : [];
    const limit = boundedNumber(req.query.limit, 10, 1, 100);
    const offset = boundedNumber(req.query.offset, 0, 0, 1000000);
    try {
      const result = await database.query(
        `SELECT * FROM public.business_ads
         WHERE status = 'active'
           AND (cardinality($1::text[]) = 0 OR category = ANY($1::text[]))
         ORDER BY created_at DESC, id DESC
         LIMIT $2 OFFSET $3`,
        [categories, limit, offset]
      );
      return res.json({ success: true, data: result.rows });
    } catch (error) {
      console.error("Active business ads load failed:", error.message);
      return res.status(500).json({ error: "Failed to load business ads" });
    }
  });

  router.get("/admin", authenticate, async (req, res) => {
    if (req.user.is_admin !== true) {
      return res.status(403).json({ error: "Administrator access required" });
    }
    const statuses =
      typeof req.query.statuses === "string"
        ? [...new Set(req.query.statuses.split(",").filter((status) => adStatuses.has(status)))]
        : [];
    if (statuses.length === 0 || statuses.length !== req.query.statuses?.split(",").filter(Boolean).length) {
      return res.status(400).json({ error: "Provide valid business ad statuses" });
    }
    try {
      const result = await database.query(
        `SELECT * FROM public.business_ads
         WHERE status = ANY($1::text[])
         ORDER BY created_at DESC
         LIMIT $2`,
        [statuses, 200 * statuses.length]
      );
      return res.json({ success: true, data: result.rows });
    } catch (error) {
      console.error("Admin business ads load failed:", error.message);
      return res.status(500).json({ error: "Failed to load business ads" });
    }
  });

  router.patch("/admin/:id/decision", authenticate, async (req, res) => {
    if (req.user.is_admin !== true) {
      return res.status(403).json({ error: "Administrator access required" });
    }
    const { id } = req.params;
    const { status, expected_status } =
      req.body ?? {};
    if (
      !uuidPattern.test(id) ||
      !adStatuses.has(status) ||
      !adStatuses.has(expected_status)
    ) {
      return res.status(400).json({ error: "Invalid business ad decision" });
    }

    let client;
    try {
      client = await database.connect();
      await client.query("BEGIN");
      const current = await client.query(
        `SELECT package_id, status, payment_status
         FROM public.business_ads
         WHERE id = $1
         FOR UPDATE`,
        [id]
      );
      const ad = current.rows[0];
      if (
        !ad ||
        (expected_status != null && ad.status !== expected_status)
      ) {
        await client.query("ROLLBACK");
        return res.status(409).json({ error: "Business ad is no longer available" });
      }

      let result;
      if (status === "approved") {
        let durationDays = 30;
        if (ad.package_id) {
          const packageResult = await client.query(
            `SELECT duration_days
             FROM public.business_ad_packages
             WHERE id = $1`,
            [ad.package_id]
          );
          const duration = packageResult.rows[0]?.duration_days;
          if (!Number.isInteger(Number(duration)) || Number(duration) <= 0) {
            await client.query("ROLLBACK");
            return res.status(409).json({ error: "Business ad package is unavailable" });
          }
          durationDays = Number(duration);
        }
        result = await client.query(
          `UPDATE public.business_ads
           SET status = 'active',
               start_at = NOW(),
               end_at = NOW() + ($2 * INTERVAL '1 day'),
               updated_at = NOW()
           WHERE id = $1
           RETURNING id, status, payment_status`,
          [id, durationDays]
        );
      } else {
        result = await client.query(
          `UPDATE public.business_ads
           SET status = $2, updated_at = NOW()
           WHERE id = $1
           RETURNING id, status, payment_status`,
          [id, status]
        );
      }
      await client.query("COMMIT");
      return res.json({ success: true, data: result.rows[0] });
    } catch (error) {
      try {
        await client.query("ROLLBACK");
      } catch (rollbackError) {
        console.error("Business ad decision rollback failed:", rollbackError.message);
      }
      console.error("Business ad decision failed:", error.message);
      return res.status(500).json({ error: "Failed to update business ad" });
    } finally {
      client?.release();
    }
  });

  router.post("/events/counter", optionalAuthenticate, async (req, res) => {
    const { ad_id, counter } = req.body ?? {};
    if (!uuidPattern.test(ad_id ?? "") || !counters.has(counter)) {
      return res.status(400).json({ error: "Invalid business ad counter" });
    }
    try {
      const result = await database.query(
        `UPDATE public.business_ads
         SET ${counter} = ${counter} + 1
         WHERE id = $1 AND status = 'active'
         RETURNING id`,
        [ad_id]
      );
      return res.json({ success: true, updated: result.rowCount === 1 });
    } catch (error) {
      console.error("Business ad counter update failed:", error.message);
      return res.status(500).json({ error: "Failed to update business ad counter" });
    }
  });

  router.post("/events", optionalAuthenticate, async (req, res) => {
    const { ad_id, event_type } = req.body ?? {};
    if (
      !uuidPattern.test(ad_id ?? "") ||
      !eventTypes.has(event_type)
    ) {
      return res.status(400).json({ error: "Invalid business ad event" });
    }
    try {
      const result = await database.query(
        `INSERT INTO public.business_ad_events (ad_id, event_type, user_id)
         SELECT id, $2, $3
         FROM public.business_ads
         WHERE id = $1 AND status = 'active'
         RETURNING id`,
        [ad_id, event_type, req.user?.id ?? null]
      );
      return res.status(201).json({
        success: true,
        recorded: result.rowCount === 1
      });
    } catch (error) {
      console.error("Business ad event logging failed:", error.message);
      return res.status(500).json({ error: "Failed to log business ad event" });
    }
  });

  return router;
}

export default createBusinessAdsRouter();
