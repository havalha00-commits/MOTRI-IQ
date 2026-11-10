import { jwtVerify } from "jose";
import { pool } from "../config/database.js";

// G10.62 P3.4E: isolated local-test bootstrap must not implicitly load backend/.env.
// Normal non-local startup preserves dotenv loading.
if (process.env.MOTRI_LOCAL_TEST_ISOLATED !== "1") {
  const dotenv = await import("dotenv");
  dotenv.default?.config?.();
}

const secret = process.env.JWT_SECRET;

if (!secret || secret.length < 64) {
  throw new Error("JWT_SECRET is missing or too short");
}

export function createAuthenticateToken({
  database = pool,
  jwtSecret = secret
} = {}) {
  if (!jwtSecret || jwtSecret.length < 64) {
    throw new Error("JWT_SECRET is missing or too short");
  }

  const signingKey = new TextEncoder().encode(jwtSecret);

  return async function authenticateToken(req, res, next) {
    let payload;

    try {
      const authHeader = req.headers.authorization;

      if (!authHeader?.startsWith("Bearer ")) {
        return res.status(401).json({
          error: "Authentication token required"
        });
      }

      const token = authHeader.slice(7).trim();

      const verified = await jwtVerify(token, signingKey, {
        issuer: "motri-iq-api",
        audience: "authenticated",
        algorithms: ["HS256"]
      });

      payload = verified.payload;

      if (!payload.sub || !payload.sid) {
        return res.status(401).json({
          error: "Invalid user identity or session"
        });
      }
    } catch {
      return res.status(401).json({
        error: "Invalid or expired authentication token"
      });
    }

    try {
      const result = await database.query(
        `SELECT
           u.id,
           u.email,
           EXISTS (
             SELECT 1 FROM public.app_admins a
             WHERE a.user_id = u.id
           ) OR COALESCE(p.is_admin, FALSE) AS is_admin
         FROM public.app_sessions s
         JOIN public.app_users u ON u.id = s.user_id
         LEFT JOIN public.profiles p ON p.id = u.id
         WHERE s.id = $1
           AND s.user_id = $2
           AND s.revoked_at IS NULL
           AND s.expires_at > NOW()
           AND u.email_confirmed_at IS NOT NULL
           AND u.deleted_at IS NULL
           AND (u.banned_until IS NULL OR u.banned_until <= NOW())
         LIMIT 1`,
        [payload.sid, payload.sub]
      );

      const user = result.rows[0];

      if (!user) {
        return res.status(401).json({
          error: "Session is invalid or revoked"
        });
      }

      req.user = {
        id: user.id,
        role: "authenticated",
        email: user.email,
        is_admin: user.is_admin === true
      };

      return next();
    } catch (error) {
      console.error("Session verification failed:", error.message);

      return res.status(503).json({
        error: "Authentication service temporarily unavailable"
      });
    }
  };
}

export const authenticateToken = createAuthenticateToken();
