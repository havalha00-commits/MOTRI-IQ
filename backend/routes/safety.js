import { Router } from "express";
import { randomUUID } from "node:crypto";
import { pool } from "../config/database.js";
import { authenticateCurrentUser } from "../middleware/current_user.js";

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const userReportReasons = [
  "harassment",
  "hate_speech",
  "sexual_content",
  "spam",
  "fraud",
  "other"
];

export function createSafetyRouter({
  database = pool,
  authenticate = authenticateCurrentUser
} = {}) {
  const router = Router();
  router.use(authenticate);

  function requireAdmin(req, res) {
    if (req.user.is_admin === true) return true;
    res.status(403).json({ error: "Administrator access required" });
    return false;
  }

  router.get("/blocks/:userId", async (req, res) => {
    const target = req.params.userId;
    if (!uuidPattern.test(target) || target === req.user.id) {
      return res.status(400).json({ error: "Invalid user ID" });
    }

    try {
      const result = await database.query(
        `SELECT
           EXISTS (
             SELECT 1 FROM public.user_blocks
             WHERE blocker_id = $1 AND blocked_id = $2
           ) AS blocked_by_me,
           EXISTS (
             SELECT 1 FROM public.user_blocks
             WHERE blocker_id = $2 AND blocked_id = $1
           ) AS blocked_me`,
        [req.user.id, target]
      );
      return res.json(result.rows[0]);
    } catch (error) {
      console.error("Block status failed:", error.message);
      return res.status(500).json({ error: "Could not check block status" });
    }
  });

  router.post("/blocks", async (req, res) => {
    const target = req.body?.blocked_user_id;
    if (!uuidPattern.test(target ?? "") || target === req.user.id) {
      return res.status(400).json({ error: "Invalid user ID" });
    }

    try {
      const result = await database.query(
        `INSERT INTO public.user_blocks (blocker_id, blocked_id)
         SELECT $1, id FROM public.profiles WHERE id = $2
         ON CONFLICT (blocker_id, blocked_id) DO NOTHING
         RETURNING blocked_id`,
        [req.user.id, target]
      );
      if (result.rowCount === 0) {
        const exists = await database.query(
          "SELECT 1 FROM public.profiles WHERE id = $1",
          [target]
        );
        if (exists.rowCount === 0) {
          return res.status(404).json({ error: "User not found" });
        }
      }
      return res.json({ success: true, blocked: true });
    } catch (error) {
      console.error("Block user failed:", error.message);
      return res.status(500).json({ error: "Could not block user" });
    }
  });

  router.delete("/blocks/:userId", async (req, res) => {
    const target = req.params.userId;
    if (!uuidPattern.test(target) || target === req.user.id) {
      return res.status(400).json({ error: "Invalid user ID" });
    }
    try {
      await database.query(
        `DELETE FROM public.user_blocks
         WHERE blocker_id = $1 AND blocked_id = $2`,
        [req.user.id, target]
      );
      return res.json({ success: true, blocked: false });
    } catch (error) {
      console.error("Unblock user failed:", error.message);
      return res.status(500).json({ error: "Could not unblock user" });
    }
  });

  router.post("/reports", async (req, res) => {
    const { reported_user_id, offer_id, reason, details = "" } = req.body ?? {};
    const id = typeof req.body?.id === "string" ? req.body.id : randomUUID();
    if (
      !uuidPattern.test(id) ||
      !uuidPattern.test(reported_user_id ?? "") ||
      !uuidPattern.test(offer_id ?? "") ||
      reported_user_id === req.user.id
    ) {
      return res.status(400).json({ error: "Invalid user or offer ID" });
    }
    if (!userReportReasons.includes(reason)) {
      return res.status(400).json({ error: "Invalid report reason" });
    }
    if (typeof details !== "string" || details.length > 2000) {
      return res.status(400).json({ error: "Invalid report details" });
    }

    try {
      const offer = await database.query(
        `SELECT id FROM public.car_offers
         WHERE id = $1
           AND ((buyer_id = $2 AND seller_id = $3)
             OR (seller_id = $2 AND buyer_id = $3))`,
        [offer_id, req.user.id, reported_user_id]
      );
      if (offer.rowCount === 0) {
        return res.status(403).json({ error: "Offer participants do not match" });
      }
      const result = await database.query(
        `INSERT INTO public.user_reports
           (id, reporter_id, reported_user_id, offer_id, reason, details)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING id, status, created_at`,
        [id, req.user.id, reported_user_id, offer_id, reason, details.trim()]
      );
      return res.status(201).json({ success: true, data: result.rows[0] });
    } catch (error) {
      if (error.code === "23505") {
        return res.status(409).json({ error: "Report already submitted" });
      }
      console.error("User report creation failed:", error.message);
      return res.status(500).json({ error: "Could not submit report" });
    }
  });

  router.post("/car-reports", async (req, res) => {
    const { car_id, seller_id, reason } = req.body ?? {};
    const id = typeof req.body?.id === "string" ? req.body.id : randomUUID();
    if (
      !uuidPattern.test(id) ||
      typeof car_id !== "string" ||
      !car_id.trim() ||
      car_id.length > 100 ||
      (seller_id != null &&
        (typeof seller_id !== "string" ||
          !uuidPattern.test(seller_id) ||
          seller_id === req.user.id)) ||
      typeof reason !== "string" ||
      !reason.trim() ||
      reason.length > 200
    ) {
      return res.status(400).json({ error: "Invalid car report" });
    }
    try {
      const result = await database.query(
        `INSERT INTO public.car_reports
           (id, car_id, reporter_id, seller_id, reason)
         VALUES ($1, $2, $3, $4, $5)
         RETURNING id, car_id, created_at`,
        [id, car_id.trim(), req.user.id, seller_id ?? null, reason.trim()]
      );
      return res.status(201).json({ success: true, data: result.rows[0] });
    } catch (error) {
      if (error.code === "23505") {
        return res.status(409).json({ error: "Car already reported" });
      }
      console.error("Car report creation failed:", error.message);
      return res.status(500).json({ error: "Could not submit car report" });
    }
  });

  router.get("/admin/car-reports", (req, res, next) => {
    if (!requireAdmin(req, res)) return;
    next();
  }, async (_req, res) => {
    try {
      const result = await database.query(
        `SELECT * FROM public.car_reports
         ORDER BY created_at DESC
         LIMIT 200`
      );
      return res.json({ success: true, data: result.rows });
    } catch (error) {
      console.error("Admin car reports load failed:", error.message);
      return res.status(500).json({ error: "Failed to load reports" });
    }
  });

  router.patch("/admin/car-reports/:id", (req, res, next) => {
    if (!requireAdmin(req, res)) return;
    next();
  }, async (req, res) => {
    const { id } = req.params;
    const { status, expected_status } = req.body ?? {};
    if (!uuidPattern.test(id) || !["open", "resolved", "closed"].includes(status)) {
      return res.status(400).json({ error: "Invalid report update" });
    }
    try {
      const result = await database.query(
        `UPDATE public.car_reports
         SET status = $2,
             reviewed_by = CASE WHEN $2 = 'open' THEN NULL ELSE $3 END,
             reviewed_at = CASE WHEN $2 = 'open' THEN NULL ELSE NOW() END
         WHERE id = $1
           AND ($4::text IS NULL OR status = $4)
         RETURNING id, status`,
        [id, status, req.user.id, expected_status ?? null]
      );
      if (result.rowCount !== 1) {
        return res.status(409).json({ error: "Report is no longer available" });
      }
      return res.json({ success: true, data: result.rows[0] });
    } catch (error) {
      console.error("Admin car report update failed:", error.message);
      return res.status(500).json({ error: "Failed to update report" });
    }
  });

  router.get("/admin/car-reports/:carId/car", (req, res, next) => {
    if (!requireAdmin(req, res)) return;
    next();
  }, async (req, res) => {
    if (typeof req.params.carId !== "string" || req.params.carId.length > 100) {
      return res.status(400).json({ error: "Invalid car id" });
    }
    try {
      const result = await database.query(
        `SELECT * FROM public.cars WHERE id::text = $1 LIMIT 1`,
        [req.params.carId]
      );
      return res.json({ success: true, data: result.rows[0] ?? null });
    } catch (error) {
      console.error("Reported car load failed:", error.message);
      return res.status(500).json({ error: "Failed to load reported car" });
    }
  });

  router.get("/admin/user-reports", (req, res, next) => {
    if (!requireAdmin(req, res)) return;
    next();
  }, async (_req, res) => {
    try {
      const result = await database.query(
        `SELECT * FROM public.user_reports
         ORDER BY created_at DESC
         LIMIT 200`
      );
      return res.json({ success: true, data: result.rows });
    } catch (error) {
      console.error("Admin user reports load failed:", error.message);
      return res.status(500).json({ error: "Failed to load user reports" });
    }
  });

  return router;
}

export default createSafetyRouter();
