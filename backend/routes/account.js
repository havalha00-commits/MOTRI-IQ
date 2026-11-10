import express from "express";
import { jwtVerify } from "jose";
import { createCurrentUserAuthenticator } from "../middleware/current_user.js";

export function createAccountRouter({ database = null, authenticate = null } = {}) {
  const router = express.Router();
  const jwtSecret = process.env.JWT_SECRET;
  const signingKey = new TextEncoder().encode(jwtSecret);
  const auth = authenticate || createCurrentUserAuthenticator({ database });
  router.delete("/", auth, async (req, res) => {
    if (!database || typeof database.connect !== "function") {
      return res.status(503).json({ error: "Account service unavailable" });
    }
    const userId = req.user?.id;
    if (!userId) return res.status(401).json({ error: "Authentication required" });
    if (req.user?.is_admin === true) {
      return res.status(403).json({ error: "Admin accounts cannot be deleted via this endpoint" });
    }
    const reauthToken = req.headers["x-reauth-token"];
    if (!reauthToken) {
      return res.status(401).json({ error: "Reauthentication required" });
    }
    let verified;
    try {
      verified = await jwtVerify(reauthToken, signingKey, {
        issuer: "motri-iq-api",
        audience: "reauth",
        algorithms: ["HS256"],
      });
    } catch {
      return res.status(401).json({ error: "Invalid reauthentication token" });
    }
    if (verified.payload?.sub !== userId || verified.payload?.purpose !== "account_deletion") {
      return res.status(401).json({ error: "Reauthentication mismatch" });
    }
    const client = await database.connect();
    try {
      await client.query("BEGIN");
      const exists = await client.query("SELECT id, deleted_at FROM public.app_users WHERE id = $1", [userId]);
      if (exists.rowCount === 0) {
        await client.query("ROLLBACK");
        return res.status(204).send();
      }
      if (exists.rows[0].deleted_at) {
        await client.query("ROLLBACK");
        return res.status(204).send();
      }
      await client.query("UPDATE public.app_users SET deleted_at = NOW(), email = $2, username = $3, phone = NULL WHERE id = $1", [userId, `deleted_${userId}@deleted.local`, `deleted_${userId}`]);
      await client.query("UPDATE public.profiles SET username = $2, full_name = 'مستخدم محذوف' WHERE id = $1", [userId, `deleted_${userId}`]);
      await client.query("DELETE FROM public.app_sessions WHERE user_id = $1", [userId]);
      await client.query("COMMIT");
      res.status(204).send();
    } catch (error) {
      try { await client.query("ROLLBACK"); } catch {}
      res.status(500).json({ error: "Account deletion failed" });
    } finally {
      client.release();
    }
  });
  return router;
}

export default createAccountRouter;
