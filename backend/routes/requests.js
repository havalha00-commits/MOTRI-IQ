import { Router } from "express";
import { randomUUID } from "node:crypto";
import { pool } from "../config/database.js";
import { authenticateCurrentUser } from "../middleware/current_user.js";

const requestFields = [
  "brand",
  "model",
  "year_from",
  "year_to",
  "max_price",
  "province",
  "city",
  "details"
];
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function requestPayload(body) {
  const payload = Object.fromEntries(
    requestFields
      .filter((field) => Object.hasOwn(body, field))
      .map((field) => [field, body[field]])
  );
  if (typeof payload.brand !== "string" || !payload.brand.trim()) {
    throw new TypeError("Brand is required");
  }
  if (!Number.isFinite(Number(payload.max_price)) || Number(payload.max_price) <= 0) {
    throw new TypeError("A positive maximum price is required");
  }
  return payload;
}

export function createRequestsRouter({
  database = pool,
  authenticate = authenticateCurrentUser
} = {}) {
  const router = Router();
  const optionalAuthenticate = (req, res, next) => {
    if (!req.headers.authorization) return next();
    return authenticate(req, res, next);
  };

  router.get("/", optionalAuthenticate, async (req, res) => {
    try {
      const result = await database.query(
        `SELECT *
         FROM public.car_requests
         WHERE status = 'open'
         ORDER BY created_at DESC
         LIMIT 50`
      );
      if (!req.user || result.rows.length === 0) {
        return res.json({ success: true, data: result.rows });
      }
      const offers = await database.query(
        `SELECT * FROM public.car_request_offers
         WHERE request_id = ANY($1::uuid[]) AND seller_id = $2
         ORDER BY created_at DESC`,
        [result.rows.map((row) => row.id), req.user.id]
      );
      const byRequest = new Map(result.rows.map((row) => [row.id, []]));
      for (const offer of offers.rows) {
        byRequest.get(offer.request_id)?.push(offer);
      }
      return res.json({
        success: true,
        data: result.rows.map((row) => ({
          ...row,
          car_request_offers: byRequest.get(row.id) ?? []
        }))
      });
    } catch (error) {
      console.error("Open requests load failed:", error.message);
      return res.status(500).json({ error: "Failed to load requests" });
    }
  });

  router.get("/mine", authenticate, async (req, res) => {
    try {
      const requests = await database.query(
        `SELECT *
         FROM public.car_requests
         WHERE buyer_id = $1
         ORDER BY created_at DESC
         LIMIT 50`,
        [req.user.id]
      );
      const rows = requests.rows;
      if (rows.length === 0) {
        return res.json({ success: true, data: [] });
      }

      const offers = await database.query(
        `SELECT *
         FROM public.car_request_offers
         WHERE request_id = ANY($1::uuid[])
           AND buyer_id = $2
         ORDER BY created_at DESC`,
        [rows.map((row) => row.id), req.user.id]
      );
      const byRequest = new Map(rows.map((row) => [row.id, []]));
      for (const offer of offers.rows) {
        byRequest.get(offer.request_id)?.push(offer);
      }
      return res.json({
        success: true,
        data: rows.map((row) => ({
          ...row,
          car_request_offers: byRequest.get(row.id) ?? []
        }))
      });
    } catch (error) {
      console.error("My requests load failed:", error.message);
      return res.status(500).json({ error: "Failed to load your requests" });
    }
  });

  router.post("/", authenticate, async (req, res) => {
    let payload;
    try {
      payload = requestPayload(req.body ?? {});
    } catch (error) {
      return res.status(400).json({ error: error.message });
    }
    const id = typeof req.body?.id === "string" ? req.body.id : randomUUID();
    if (!uuidPattern.test(id)) {
      return res.status(400).json({ error: "Invalid request id" });
    }
    const columns = ["id", "buyer_id", ...Object.keys(payload)];
    const values = [id, req.user.id, ...Object.values(payload)];
    const placeholders = values.map((_, index) => `$${index + 1}`);

    try {
      const result = await database.query(
        `INSERT INTO public.car_requests (${columns.join(", ")})
         VALUES (${placeholders.join(", ")})
         RETURNING id`,
        values
      );
      return res.status(201).json({ success: true, data: result.rows[0] });
    } catch (error) {
      console.error("Request creation failed:", error.message);
      return res.status(500).json({ error: "Failed to create car request" });
    }
  });

  router.patch("/:id/close", authenticate, async (req, res) => {
    try {
      const result = await database.query(
        `UPDATE public.car_requests
         SET status = 'closed'
         WHERE id = $1 AND buyer_id = $2 AND status = 'open'
         RETURNING id, status`,
        [req.params.id, req.user.id]
      );
      if (result.rowCount !== 1) {
        return res.status(409).json({ error: "Request is not open or not owned by you" });
      }
      return res.json({ success: true, data: result.rows[0] });
    } catch (error) {
      console.error("Request close failed:", error.message);
      return res.status(500).json({ error: "Failed to close car request" });
    }
  });

  router.post("/:id/offers", authenticate, async (req, res) => {
    const requestId = req.params.id;
    const vehicle = req.body?.vehicle;
    const offerPrice = Number(req.body?.offer_price);
    if (
      !uuidPattern.test(requestId) ||
      typeof vehicle !== "string" ||
      !vehicle.trim() ||
      !Number.isFinite(offerPrice) ||
      offerPrice <= 0
    ) {
      return res.status(400).json({ error: "Invalid request offer" });
    }
    const id = typeof req.body?.id === "string" ? req.body.id : randomUUID();
    if (!uuidPattern.test(id)) {
      return res.status(400).json({ error: "Invalid offer id" });
    }

    try {
      const result = await database.query(
        `INSERT INTO public.car_request_offers
           (id, request_id, buyer_id, seller_id, vehicle, offer_price, message)
         SELECT $1, r.id, r.buyer_id, $2, $3, $4, $5
         FROM public.car_requests r
         WHERE r.id = $6
           AND r.status = 'open'
           AND r.buyer_id <> $2
         RETURNING id`,
        [
          id,
          req.user.id,
          vehicle.trim(),
          offerPrice,
          typeof req.body.message === "string" ? req.body.message.trim() || null : null,
          requestId
        ]
      );
      if (result.rowCount !== 1) {
        return res.status(409).json({ error: "Request is unavailable" });
      }
      return res.status(201).json({ success: true, data: result.rows[0] });
    } catch (error) {
      if (error.code === "23505") {
        return res.status(409).json({ error: "An offer already exists" });
      }
      console.error("Request offer creation failed:", error.message);
      return res.status(500).json({ error: "Failed to send request offer" });
    }
  });

  router.patch("/:requestId/offers/:offerId", authenticate, async (req, res) => {
    const status = req.body?.status;
    if (!["accepted", "rejected"].includes(status)) {
      return res.status(400).json({ error: "Invalid offer decision" });
    }
    try {
      const result = await database.query(
        `UPDATE public.car_request_offers o
         SET status = $4
         FROM public.car_requests r
         WHERE o.id = $1
           AND o.request_id = $2
           AND o.request_id = r.id
           AND r.buyer_id = $3
           AND o.buyer_id = $3
           AND o.status = 'pending'
         RETURNING o.id, o.status`,
        [req.params.offerId, req.params.requestId, req.user.id, status]
      );
      if (result.rowCount !== 1) {
        return res.status(409).json({ error: "Offer is unavailable for decision" });
      }
      return res.json({ success: true, data: result.rows[0] });
    } catch (error) {
      console.error("Request offer decision failed:", error.message);
      return res.status(500).json({ error: "Failed to update request offer" });
    }
  });

  return router;
}

export default createRequestsRouter();