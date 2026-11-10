import { Router } from "express";
import { randomUUID } from "node:crypto";
import { pool } from "../config/database.js";
import { authenticateCurrentUser } from "../middleware/current_user.js";

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function createOffersRouter({
  database = pool,
  authenticate = authenticateCurrentUser
} = {}) {
  const router = Router();
  router.use(authenticate);

  router.get("/buyer", async (req, res) => {
    try {
      const result = await database.query(
        `SELECT * FROM public.car_offers
         WHERE buyer_id = $1
         ORDER BY created_at DESC
         LIMIT 100`,
        [req.user.id]
      );
      return res.json({ success: true, data: result.rows });
    } catch (error) {
      console.error("Buyer offers load failed:", error.message);
      return res.status(500).json({ error: "Failed to load offers" });
    }
  });

  router.get("/seller", async (req, res) => {
    try {
      const result = await database.query(
        `SELECT * FROM public.car_offers
         WHERE seller_id = $1
         ORDER BY created_at DESC
         LIMIT 100`,
        [req.user.id]
      );
      return res.json({ success: true, data: result.rows });
    } catch (error) {
      console.error("Seller offers load failed:", error.message);
      return res.status(500).json({ error: "Failed to load offers" });
    }
  });

  router.get("/conversations", async (req, res) => {
    try {
      const result = await database.query(
        `SELECT * FROM public.car_offers
         WHERE status = 'accepted'
           AND (buyer_id = $1 OR seller_id = $1)
         ORDER BY created_at DESC
         LIMIT 50`,
        [req.user.id]
      );
      if (result.rows.length === 0) {
        return res.json({ success: true, data: [] });
      }
      const messages = await database.query(
        `SELECT DISTINCT ON (offer_id)
           offer_id, body, created_at, sender_id
         FROM public.car_offer_messages
         WHERE offer_id = ANY($1::uuid[])
         ORDER BY offer_id, created_at DESC`,
        [result.rows.map((row) => row.id)]
      );
      const latestByOffer = new Map(
        messages.rows.map((message) => [message.offer_id, message])
      );
      return res.json({
        success: true,
        data: result.rows.map((offer) => ({
          ...offer,
          car_offer_messages: latestByOffer.has(offer.id)
            ? [latestByOffer.get(offer.id)]
            : []
        }))
      });
    } catch (error) {
      console.error("Conversations load failed:", error.message);
      return res.status(500).json({ error: "Failed to load conversations" });
    }
  });

  router.get("/:offerId", async (req, res) => {
    if (!uuidPattern.test(req.params.offerId)) {
      return res.status(400).json({ error: "Invalid offer id" });
    }
    try {
      const result = await database.query(
        `SELECT * FROM public.car_offers
         WHERE id = $1 AND (buyer_id = $2 OR seller_id = $2)
         LIMIT 1`,
        [req.params.offerId, req.user.id]
      );
      return res.json({ success: true, data: result.rows[0] ?? null });
    } catch (error) {
      console.error("Offer load failed:", error.message);
      return res.status(500).json({ error: "Failed to load offer" });
    }
  });

  router.post("/", async (req, res) => {
    const carId = req.body?.car_id;
    const offerPrice = Number(req.body?.offer_price);
    if (
      typeof carId !== "string" ||
      !uuidPattern.test(carId) ||
      !Number.isFinite(offerPrice) ||
      offerPrice <= 0
    ) {
      return res.status(400).json({ error: "Invalid car offer" });
    }
    const id = typeof req.body?.id === "string" ? req.body.id : randomUUID();
    if (!uuidPattern.test(id)) {
      return res.status(400).json({ error: "Invalid offer id" });
    }

    try {
      const result = await database.query(
        `INSERT INTO public.car_offers
           (id, car_id, car_title, original_price, buyer_id, seller_id, offer_price, message)
         SELECT
           $1,
           c.id::text,
           COALESCE(c.title, concat_ws(' ', c.brand, c.model)),
           c.price,
           $2,
           c.user_id,
           $3,
           $4
         FROM public.cars c
         WHERE c.id = $5
           AND c.user_id <> $2
           AND c.is_approved = TRUE
           AND c.status = 'active'
         RETURNING id`,
        [
          id,
          req.user.id,
          offerPrice,
          typeof req.body.message === "string" ? req.body.message.trim() || null : null,
          carId
        ]
      );
      if (result.rowCount !== 1) {
        return res.status(409).json({ error: "Car is unavailable for offers" });
      }
      return res.status(201).json({ success: true, data: result.rows[0] });
    } catch (error) {
      console.error("Car offer creation failed:", error.message);
      return res.status(500).json({ error: "Failed to send car offer" });
    }
  });

  router.patch("/:offerId/status", async (req, res) => {
    const status = req.body?.status;
    if (!["accepted", "rejected"].includes(status)) {
      return res.status(400).json({ error: "Invalid offer status" });
    }
    try {
      const result = await database.query(
        `UPDATE public.car_offers
         SET status = $3
         WHERE id = $1 AND seller_id = $2 AND status = 'pending'
         RETURNING id, status`,
        [req.params.offerId, req.user.id, status]
      );
      if (result.rowCount !== 1) {
        return res.status(409).json({ error: "Offer is unavailable for update" });
      }
      return res.json({ success: true, data: result.rows[0] });
    } catch (error) {
      console.error("Car offer update failed:", error.message);
      return res.status(500).json({ error: "Failed to update car offer" });
    }
  });

  router.get("/:offerId/messages", async (req, res) => {
    try {
      const access = await database.query(
        `SELECT id
         FROM public.car_offers o
         WHERE o.id = $1
           AND o.status = 'accepted'
           AND (o.buyer_id = $2 OR o.seller_id = $2)
           AND NOT EXISTS (
             SELECT 1 FROM public.user_blocks b
             WHERE (b.blocker_id = $2 AND b.blocked_id =
               CASE WHEN o.buyer_id = $2 THEN o.seller_id ELSE o.buyer_id END)
                OR (b.blocked_id = $2 AND b.blocker_id =
               CASE WHEN o.buyer_id = $2 THEN o.seller_id ELSE o.buyer_id END)
           )`,
        [req.params.offerId, req.user.id]
      );
      if (access.rowCount !== 1) {
        return res.status(404).json({ error: "Conversation is unavailable" });
      }
      const result = await database.query(
        `SELECT id, offer_id, sender_id, body, created_at
         FROM public.car_offer_messages
         WHERE offer_id = $1
         ORDER BY created_at DESC
         LIMIT 200`,
        [req.params.offerId]
      );
      return res.json({ success: true, data: result.rows });
    } catch (error) {
      console.error("Messages load failed:", error.message);
      return res.status(500).json({ error: "Failed to load messages" });
    }
  });

  router.post("/:offerId/messages", async (req, res) => {
    const body = typeof req.body?.body === "string" ? req.body.body.trim() : "";
    if (!body || body.length > 2000) {
      return res.status(400).json({ error: "Message must contain 1-2000 characters" });
    }
    const id = typeof req.body?.id === "string" ? req.body.id : randomUUID();
    if (!uuidPattern.test(id)) {
      return res.status(400).json({ error: "Invalid message id" });
    }
    try {
      const result = await database.query(
        `INSERT INTO public.car_offer_messages (id, offer_id, sender_id, body)
         SELECT $1, o.id, $2, $3
         FROM public.car_offers o
         WHERE o.id = $4
           AND o.status = 'accepted'
           AND (o.buyer_id = $2 OR o.seller_id = $2)
           AND NOT EXISTS (
             SELECT 1 FROM public.user_blocks b
             WHERE (b.blocker_id = $2 AND b.blocked_id =
               CASE WHEN o.buyer_id = $2 THEN o.seller_id ELSE o.buyer_id END)
                OR (b.blocked_id = $2 AND b.blocker_id =
               CASE WHEN o.buyer_id = $2 THEN o.seller_id ELSE o.buyer_id END)
           )
         RETURNING id`,
        [id, req.user.id, body, req.params.offerId]
      );
      if (result.rowCount !== 1) {
        return res.status(404).json({ error: "Conversation is unavailable" });
      }
      try {
        const participants = await database.query(
          `SELECT buyer_id, seller_id
           FROM public.car_offers
           WHERE id = $1`,
          [req.params.offerId]
        );
        const offer = participants.rows[0];
        if (offer && req.user.id === offer.buyer_id) {
          const updated = await database.query(
            `UPDATE public.seller_response_tracking
             SET last_buyer_message_at = NOW()
             WHERE offer_id = $1 AND seller_id = $2 AND seller_responded = FALSE`,
            [req.params.offerId, offer.seller_id]
          );
          if (updated.rowCount === 0) {
            await database.query(
              `INSERT INTO public.seller_response_tracking
                 (offer_id, seller_id, buyer_id)
               VALUES ($1, $2, $3)`,
              [req.params.offerId, offer.seller_id, offer.buyer_id]
            );
          }
        } else if (offer && req.user.id === offer.seller_id) {
          await database.query(
            `UPDATE public.seller_response_tracking
             SET seller_responded = TRUE, first_response_at = NOW()
             WHERE offer_id = $1 AND seller_id = $2 AND seller_responded = FALSE`,
            [req.params.offerId, offer.seller_id]
          );
        }
      } catch (error) {
        console.error("Seller response tracking update failed:", error.message);
      }
      return res.status(201).json({
        success: true,
        data: {
          id: result.rows[0].id,
          offer_id: req.params.offerId,
          sender_id: req.user.id,
          body
        }
      });
    } catch (error) {
      console.error("Message send failed:", error.message);
      return res.status(500).json({ error: "Failed to send message" });
    }
  });

  return router;
}

export default createOffersRouter();