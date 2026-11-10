import { Router } from "express";
import { pool } from "../config/database.js";
import {
  authenticateCurrentUser,
  authenticateBackendIndependent
} from "../middleware/current_user.js";

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function idsFromQuery(value) {
  if (typeof value !== "string") return [];
  return [...new Set(value.split(",").filter((id) => uuidPattern.test(id)))];
}

export function createSellersRouter({
  database = pool,
  authenticate = authenticateCurrentUser,
  authenticateAdminStatus = authenticateBackendIndependent
} = {}) {
  const router = Router();

  router.get("/reviews", async (req, res) => {
    try {
      let result;
      if (req.query.reviewer === "me") {
        return authenticate(req, res, async () => {
          try {
            const ownReviews = await database.query(
              `SELECT r.*, s.showroom_name AS seller_name
               FROM public.seller_reviews r
               LEFT JOIN public.seller_showrooms s ON s.seller_id = r.seller_id
               WHERE r.reviewer_id = $1
               ORDER BY r.created_at DESC
               LIMIT 100`,
              [req.user.id]
            );
            return res.json({ success: true, data: ownReviews.rows });
          } catch (error) {
            console.error("My seller reviews load failed:", error.message);
            return res.status(500).json({ error: "Failed to load reviews" });
          }
        });
      }

      const ids = idsFromQuery(req.query.seller_ids);
      if (req.query.seller_id && uuidPattern.test(req.query.seller_id)) {
        ids.push(req.query.seller_id);
      }
      if (ids.length === 0 || ids.length > 100) {
        return res.status(400).json({ error: "Provide 1-100 seller ids" });
      }
      result = await database.query(
        `SELECT id, seller_id, reviewer_id, rating, comment, created_at
         FROM public.seller_reviews
         WHERE seller_id = ANY($1::uuid[])
         ORDER BY created_at DESC
         LIMIT 500`,
        [ids]
      );
      return res.json({ success: true, data: result.rows });
    } catch (error) {
      console.error("Seller reviews load failed:", error.message);
      return res.status(500).json({ error: "Failed to load reviews" });
    }
  });

  router.get("/verifications", async (req, res) => {
    const ids = idsFromQuery(req.query.ids);
    if (ids.length === 0 || ids.length > 300) {
      return res.status(400).json({ error: "Provide 1-300 seller ids" });
    }
    try {
      const result = await database.query(
        `SELECT seller_id FROM public.seller_verifications
         WHERE seller_id = ANY($1::uuid[])`,
        [ids]
      );
      return res.json({ success: true, data: result.rows });
    } catch (error) {
      console.error("Seller verification load failed:", error.message);
      return res.status(500).json({ error: "Failed to load verifications" });
    }
  });

  router.get("/showrooms/:sellerId", async (req, res) => {
    if (!uuidPattern.test(req.params.sellerId)) {
      return res.status(400).json({ error: "Invalid seller id" });
    }
    try {
      const result = await database.query(
        `SELECT seller_id, showroom_name, city, province, contact_phone,
                description, updated_at
         FROM public.seller_showrooms
         WHERE seller_id = $1`,
        [req.params.sellerId]
      );
      return res.json({ success: true, data: result.rows[0] ?? null });
    } catch (error) {
      console.error("Seller showroom load failed:", error.message);
      return res.status(500).json({ error: "Failed to load showroom" });
    }
  });

  router.get("/reputation/:sellerId", async (req, res) => {
    if (!uuidPattern.test(req.params.sellerId)) {
      return res.status(400).json({ error: "Invalid seller id" });
    }
    try {
      const result = await database.query(
        `SELECT COUNT(*)::integer AS review_count,
                COALESCE(AVG(rating), 0)::numeric AS avg_rating
         FROM public.seller_reviews
         WHERE seller_id = $1`,
        [req.params.sellerId]
      );
      const reviewCount = result.rows[0].review_count;
      const avgRating = Number(result.rows[0].avg_rating);
      const badgeTier =
        avgRating >= 4.5 && reviewCount >= 10
          ? "gold"
          : avgRating >= 4 && reviewCount >= 5
            ? "silver"
            : avgRating >= 3.5 && reviewCount >= 1
              ? "bronze"
              : "none";
      return res.json({
        success: true,
        data: {
          badge_tier: badgeTier,
          avg_rating: avgRating,
          review_count: reviewCount
        }
      });
    } catch (error) {
      console.error("Seller reputation load failed:", error.message);
      return res.status(500).json({ error: "Failed to load reputation" });
    }
  });

  router.get("/admin/status", authenticateAdminStatus, (req, res) =>
    res.json({ success: true, is_admin: req.user.is_admin === true })
  );

  router.put("/showroom", authenticate, async (req, res) => {
    const { showroom_name, city, province, contact_phone, description } =
      req.body ?? {};
    if (
      typeof showroom_name !== "string" ||
      showroom_name.trim().length < 2 ||
      showroom_name.trim().length > 80 ||
      [city, province, contact_phone, description].some(
        (value) => value != null && typeof value !== "string"
      )
    ) {
      return res.status(400).json({ error: "Invalid showroom details" });
    }
    try {
      const result = await database.query(
        `INSERT INTO public.seller_showrooms
           (seller_id, showroom_name, city, province, contact_phone,
            description, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, NOW())
         ON CONFLICT (seller_id) DO UPDATE SET
           showroom_name = EXCLUDED.showroom_name,
           city = EXCLUDED.city,
           province = EXCLUDED.province,
           contact_phone = EXCLUDED.contact_phone,
           description = EXCLUDED.description,
           updated_at = NOW()
         RETURNING seller_id`,
        [
          req.user.id,
          showroom_name.trim(),
          city?.trim() || null,
          province?.trim() || null,
          contact_phone?.trim() || null,
          description?.trim() || null
        ]
      );
      return res.json({ success: true, data: result.rows[0] });
    } catch (error) {
      console.error("Seller showroom save failed:", error.message);
      return res.status(500).json({ error: "Failed to save showroom" });
    }
  });

  router.post("/reviews", authenticate, async (req, res) => {
    const sellerId = req.body?.seller_id;
    const rating = Number(req.body?.rating);
    const comment = req.body?.comment;
    if (
      typeof sellerId !== "string" ||
      !uuidPattern.test(sellerId) ||
      sellerId === req.user.id ||
      !Number.isInteger(rating) ||
      rating < 1 ||
      rating > 5 ||
      (comment != null && (typeof comment !== "string" || comment.length > 2000))
    ) {
      return res.status(400).json({ error: "Invalid seller review" });
    }
    try {
      const result = await database.query(
        `INSERT INTO public.seller_reviews
           (seller_id, reviewer_id, rating, comment)
         VALUES ($1, $2, $3, $4)
         ON CONFLICT (seller_id, reviewer_id) DO UPDATE SET
           rating = EXCLUDED.rating,
           comment = EXCLUDED.comment
         RETURNING id, seller_id, reviewer_id, rating, comment, created_at`,
        [sellerId, req.user.id, rating, comment?.trim() || null]
      );
      return res.json({ success: true, data: result.rows[0] });
    } catch (error) {
      console.error("Seller review save failed:", error.message);
      return res.status(500).json({ error: "Failed to save review" });
    }
  });

  router.post("/verify", authenticate, async (req, res) => {
    const sellerId = req.body?.seller_id;
    if (req.user.is_admin !== true) {
      return res.status(403).json({ error: "Administrator access required" });
    }
    if (typeof sellerId !== "string" || !uuidPattern.test(sellerId)) {
      return res.status(400).json({ error: "Invalid seller id" });
    }
    try {
      const result = await database.query(
        `INSERT INTO public.seller_verifications (seller_id, verified_by, note)
         VALUES ($1, $2, $3)
         RETURNING seller_id`,
        [
          sellerId,
          req.user.id,
          typeof req.body?.note === "string" ? req.body.note.slice(0, 500) : null
        ]
      );
      return res.status(201).json({ success: true, data: result.rows[0] });
    } catch (error) {
      if (error.code === "23505") {
        return res.status(409).json({ error: "Seller is already verified" });
      }
      console.error("Seller verification failed:", error.message);
      return res.status(500).json({ error: "Failed to verify seller" });
    }
  });

  return router;
}

export default createSellersRouter();
