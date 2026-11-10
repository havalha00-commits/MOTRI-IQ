import { Router } from "express";
import { pool } from "../config/database.js";
import { authenticateCurrentUser } from "../middleware/current_user.js";

export function createProfilesRouter({
  database = pool,
  authenticate = authenticateCurrentUser,
} = {}) {
  const router = Router();
  router.use(authenticate);

  router.get("/me", async (req, res) => {
    try {
      const result = await database.query(
        `SELECT
           p.id,
           COALESCE(u.email, $2::text) AS email,
           NULLIF(TRIM(u.phone::text), '') AS phone,
           p.full_name,
           COALESCE(
             NULLIF(TRIM(p.username), ''),
             NULLIF(TRIM(u.username), ''),
             NULLIF(TRIM(p.full_name), ''),
             NULLIF(TRIM(u.email::text), ''),
             ''
           ) AS display_name,
           COALESCE(NULLIF(TRIM(p.username), ''), NULLIF(TRIM(u.username), '')) AS username,
           COALESCE(
             NULLIF(TRIM(u.raw_user_meta_data->>'avatar_url'), ''),
             NULLIF(TRIM(u.raw_user_meta_data->>'picture'), ''),
             NULLIF(TRIM(u.raw_user_meta_data->>'avatar'), '')
           ) AS avatar_url,
           (EXISTS (SELECT 1 FROM public.app_admins a WHERE a.user_id = p.id)
            OR COALESCE(p.is_admin, false)) AS is_admin
         FROM public.profiles p
         LEFT JOIN public.app_users u ON u.id = p.id
         WHERE p.id = $1
         LIMIT 1`,
        [req.user.id, req.user.email ?? null]
      );
      const row = result.rows[0];
      if (!row) return res.status(404).json({ error: "Profile not found" });
      return res.json({
        success: true,
        data: {
          id: row.id,
          email: row.email ?? null,
          phone: row.phone ?? null,
          full_name: row.full_name ?? null,
          display_name: row.display_name ?? "",
          username: row.username ?? null,
          avatar_url: row.avatar_url ?? null,
          is_admin: row.is_admin === true,
        },
      });
    } catch (error) {
      console.error("Profile load failed:", error.message);
      return res.status(500).json({ error: "Failed to load profile" });
    }
  });

  router.post("/username", async (req, res) => {
    const raw = typeof req.body?.username === "string" ? req.body.username : "";
    const normalized = raw.toLowerCase().trim();
    if (!/^[a-z0-9_]{3,24}$/.test(normalized)) {
      return res.status(400).json({ error: "Username must be 3-24 letters, numbers, or underscores" });
    }
    let client;
    try {
      client = await database.connect();
      await client.query("BEGIN");

      // Check conflicts in both sources of truth used by auth/profile flows.
      const conflict = await client.query(
        `SELECT 1
           FROM (
             SELECT id, username FROM public.profiles
             WHERE id <> $1 AND LOWER(TRIM(COALESCE(username, ''))) = $2
             UNION ALL
             SELECT id, username FROM public.app_users
             WHERE id <> $1 AND LOWER(TRIM(COALESCE(username, ''))) = $2
           ) x
          LIMIT 1`,
        [req.user.id, normalized]
      );
      if (conflict.rowCount > 0) {
        await client.query("ROLLBACK");
        return res.status(409).json({ error: "Username is already taken" });
      }

      const profileUpdate = await client.query(
        `UPDATE public.profiles
            SET username = $2
          WHERE id = $1
        RETURNING id`,
        [req.user.id, normalized]
      );
      if (profileUpdate.rowCount !== 1) {
        await client.query("ROLLBACK");
        return res.status(404).json({ error: "Profile not found" });
      }

      // Keep app_users.username aligned with profile identity (column exists in motri_iq_migrated).
      await client.query(
        `UPDATE public.app_users
            SET username = $2,
                updated_at = NOW()
          WHERE id = $1`,
        [req.user.id, normalized]
      );

      await client.query("COMMIT");
      return res.json({ success: true, data: { username: normalized } });
    } catch (error) {
      if (client) try { await client.query("ROLLBACK"); } catch {}
      console.error("Set username failed:", error.message);
      return res.status(500).json({ error: "Failed to set username" });
    } finally {
      client?.release();
    }
  });

  return router;
}

export default createProfilesRouter();
