import { Router } from "express";
import { pool } from "../config/database.js";
import { authenticateBackendIndependent } from "../middleware/current_user.js";

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function createFavoritesRouter({
  database = pool,
  authenticate = authenticateBackendIndependent
} = {}) {
  const router = Router();

  router.use(authenticate);

  router.get("/", async (req, res) => {
    try {
      const result = await database.query(
        `SELECT id, user_id, item_type, item_id, car_id, created_at
         FROM public.favorites
         WHERE user_id = $1
         ORDER BY created_at DESC
         LIMIT 200`,
        [req.user.id]
      );
      return res.json({ success: true, data: result.rows });
    } catch (error) {
      console.error("Favorites load failed:", error.message);
      return res.status(500).json({ error: "Failed to load favorites" });
    }
  });

  router.put("/:carId", async (req, res) => {
    const { carId } = req.params;
    if (!uuidPattern.test(carId)) {
      return res.status(400).json({ error: "Invalid car id" });
    }
    const favorite = req.body?.favorite;
    if (typeof favorite !== "boolean") {
      return res.status(400).json({ error: "Favorite state is required" });
    }

    const client = await database.connect();
    try {
      await client.query("BEGIN");
      await client.query(
        "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
        [`favorite:${req.user.id}:${carId}`]
      );
      if (favorite) {
        const existing = await client.query(
          `SELECT id FROM public.favorites
           WHERE user_id = $1 AND item_type = 'car' AND car_id = $2
           LIMIT 1`,
          [req.user.id, carId]
        );
        if (existing.rowCount === 0) {
          await client.query(
            `INSERT INTO public.favorites (user_id, item_type, item_id, car_id)
             VALUES ($1, 'car', $2, $2)`,
            [req.user.id, carId]
          );
        }
      } else {
        await client.query(
          `DELETE FROM public.favorites
           WHERE user_id = $1 AND item_type = 'car' AND car_id = $2`,
          [req.user.id, carId]
        );
      }
      await client.query("COMMIT");
      return res.json({ success: true, car_id: carId, favorite });
    } catch (error) {
      try {
        await client.query("ROLLBACK");
      } catch (rollbackError) {
        console.error("Favorite rollback failed:", rollbackError.message);
      }
      console.error("Favorite update failed:", error.message);
      return res.status(500).json({ error: "Failed to update favorite" });
    } finally {
      client.release();
    }
  });

  return router;
}

export default createFavoritesRouter();
