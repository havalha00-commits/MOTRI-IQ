import { Router } from "express";
import { pool } from "../config/database.js";
import { authenticateCurrentUser } from "../middleware/current_user.js";

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function isMissingCarAlertsTable(error) {
  return error?.code === "42P01" &&
    /relation "public\.car_alerts" does not exist/i.test(error.message ?? "");
}

export function createActivityRouter({
  database = pool,
  authenticate = authenticateCurrentUser
} = {}) {
  const router = Router();
  router.use(authenticate);

  router.get("/notifications", async (req, res) => {
    const limit = Number.parseInt(req.query.limit, 10);
    const rowLimit = Number.isInteger(limit) ? Math.min(Math.max(limit, 1), 200) : 100;
    try {
      const result = await database.query(
        `SELECT * FROM public.activity_notifications
         WHERE user_id = $1
         ORDER BY created_at DESC
         LIMIT $2`,
        [req.user.id, rowLimit]
      );
      return res.json({ success: true, data: result.rows });
    } catch (error) {
      console.error("Notifications load failed:", error.message);
      return res.status(500).json({ error: "Failed to load notifications" });
    }
  });

  router.patch("/notifications/:id/read", async (req, res) => {
    if (!uuidPattern.test(req.params.id)) {
      return res.status(400).json({ error: "Invalid notification id" });
    }
    try {
      const result = await database.query(
        `UPDATE public.activity_notifications
         SET read_at = NOW()
         WHERE id = $1 AND user_id = $2 AND read_at IS NULL
         RETURNING id, read_at`,
        [req.params.id, req.user.id]
      );
      return res.json({
        success: true,
        data: result.rows[0] ?? null,
        already_read: result.rowCount === 0
      });
    } catch (error) {
      console.error("Notification update failed:", error.message);
      return res.status(500).json({ error: "Failed to update notification" });
    }
  });

  router.get("/car-alerts", async (req, res) => {
    try {
      const result = await database.query(
        `SELECT alerts.id, alerts.car_id, alerts.created_at, alerts.read_at,
                cars.brand, cars.model, cars.province, cars.city, cars.price
         FROM public.car_alerts AS alerts
         JOIN public.cars AS cars
           ON cars.id = alerts.car_id AND cars.is_approved = TRUE
         WHERE alerts.user_id = $1
         ORDER BY alerts.created_at DESC
         LIMIT 100`,
        [req.user.id]
      );
      return res.json({ success: true, data: result.rows });
    } catch (error) {
      if (isMissingCarAlertsTable(error)) {
        console.warn("Car alerts storage is unavailable; returning an empty list.");
        return res.json({ success: true, data: [], available: false });
      }
      console.error("Car alerts load failed:", error.message);
      return res.status(500).json({ error: "Failed to load car alerts" });
    }
  });

  router.patch("/car-alerts/:id/read", async (req, res) => {
    if (!uuidPattern.test(req.params.id)) {
      return res.status(400).json({ error: "Invalid alert id" });
    }
    try {
      const result = await database.query(
        `UPDATE public.car_alerts
         SET read_at = NOW()
         WHERE id = $1 AND user_id = $2 AND read_at IS NULL
         RETURNING id`,
        [req.params.id, req.user.id]
      );
      return res.json({ success: true, data: result.rows[0] ?? null });
    } catch (error) {
      console.error("Car alert update failed:", error.message);
      return res.status(500).json({ error: "Failed to update car alert" });
    }
  });

  router.post("/saved-searches", async (req, res) => {
    const body = req.body ?? {};
    const textFields = [
      "query_text",
      "brand",
      "province",
      "city",
      "body_type"
    ];
    const numericFields = [
      ["min_year", 1886, 2100],
      ["max_year", 1886, 2100],
      ["min_price", 0, 1000000000],
      ["max_price", 0, 1000000000]
    ];
    if (
      textFields.some(
        (field) =>
          body[field] != null &&
          (typeof body[field] !== "string" || body[field].length > 300)
      ) ||
      numericFields.some(([field, min, max]) => {
        const value = body[field];
        return value != null && (!Number.isFinite(Number(value)) ||
          Number(value) < min || Number(value) > max ||
          (field.endsWith("_year") && !Number.isInteger(Number(value))));
      })
    ) {
      return res.status(400).json({ error: "Invalid saved search" });
    }
    const hasCriteria =
      textFields.some(
        (field) =>
          typeof body[field] === "string" && body[field].trim().length > 0
      ) || numericFields.some(([field]) => body[field] != null);
    if (
      !hasCriteria ||
      (body.min_year != null &&
        body.max_year != null &&
        Number(body.min_year) > Number(body.max_year)) ||
      (body.min_price != null &&
        body.max_price != null &&
        Number(body.min_price) > Number(body.max_price))
    ) {
      return res.status(400).json({ error: "Invalid saved search" });
    }

    const id = typeof body.id === "string" ? body.id : undefined;
    if (id !== undefined && !uuidPattern.test(id)) {
      return res.status(400).json({ error: "Invalid saved search id" });
    }
    const columns = [
      ...(id ? ["id"] : []),
      "user_id",
      ...textFields.filter((field) => Object.hasOwn(body, field)),
      ...numericFields
        .map(([field]) => field)
        .filter((field) => Object.hasOwn(body, field))
    ];
    const values = [
      ...(id ? [id] : []),
      req.user.id,
      ...textFields
        .filter((field) => Object.hasOwn(body, field))
        .map((field) => body[field]?.trim() || null),
      ...numericFields
        .map(([field]) => field)
        .filter((field) => Object.hasOwn(body, field))
        .map((field) => body[field] == null ? null : Number(body[field]))
    ];
    const placeholders = values.map((_, index) => `$${index + 1}`);
    try {
      const result = await database.query(
        `INSERT INTO public.saved_searches (${columns.join(", ")})
         VALUES (${placeholders.join(", ")})
         RETURNING id`,
        values
      );
      return res.status(201).json({ success: true, data: result.rows[0] });
    } catch (error) {
      console.error("Saved search creation failed:", error.message);
      return res.status(500).json({ error: "Failed to save search alert" });
    }
  });

  return router;
}

export default createActivityRouter();
