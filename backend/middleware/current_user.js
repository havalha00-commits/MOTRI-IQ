import { jwtVerify } from "jose";
import { pool } from "../config/database.js";

// G10.62 P3.4E: isolated local-test bootstrap must not implicitly load backend/.env.
// Normal non-local startup preserves dotenv loading.
if (process.env.MOTRI_LOCAL_TEST_ISOLATED !== "1") {
  const dotenv = await import("dotenv");
  dotenv.default?.config?.();
}

const jwtSecret = process.env.JWT_SECRET;
const signingKey =
  jwtSecret && jwtSecret.length >= 64
    ? new TextEncoder().encode(jwtSecret)
    : null;

export async function verifyIndependentSession(accessToken, database) {
  if (!signingKey) return null;
  let payload;
  try {
    const verified = await jwtVerify(accessToken, signingKey, {
      issuer: "motri-iq-api",
      audience: "authenticated",
      algorithms: ["HS256"],
    });
    payload = verified.payload;
  } catch {
    return null;
  }
  if (!payload?.sub || !payload?.sid) return null;
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
    if (!user) return { rejected: true };
    return {
      id: user.id,
      email: user.email ?? null,
      role: "authenticated",
      is_admin: user.is_admin === true,
    };
  } catch {
    return { serviceError: true };
  }
}

export function createCurrentUserAuthenticator({
  database = pool,
  supabaseUrl = process.env.SUPABASE_URL,
  publishableKey = process.env.SUPABASE_PUBLISHABLE_KEY,
  fetchImpl = fetch,
  // M1E-ISOLATION: when true, never attempt Supabase fallback/verification (local motri_iq_test runs only).
  // Outside this mode, existing behavior is preserved.
  disableSupabaseFallback = process.env.MOTRI_LOCAL_TEST === "true" || process.env.DISABLE_SUPABASE_AUTH_FALLBACK === "true",
} = {}) {
  return async function authenticateCurrentUser(req, res, next) {
    const header = req.headers.authorization;
    if (!header?.startsWith("Bearer ")) {
      return res.status(401).json({ error: "Authentication token required" });
    }

    const accessToken = header.slice(7).trim();
    if (!accessToken) {
      return res.status(401).json({ error: "Invalid authentication token" });
    }

    // Prefer independent auth (Neon-backed sessions) when token verifies.
    const independent = await verifyIndependentSession(accessToken, database);
    if (independent?.id) {
      req.user = independent;
      return next();
    }
    if (independent?.rejected) {
      return res.status(401).json({ error: "Session is invalid or revoked" });
    }
    if (independent?.serviceError) {
      // M1E-ISOLATION: in local test mode never try Supabase fallback.
      if (disableSupabaseFallback) {
        return res.status(503).json({ error: "Authentication service temporarily unavailable" });
      }
      // Fall through to Supabase only if independent path had infra error? Safer to fail closed for independent tokens.
      // But we can't distinguish token type here reliably; try Supabase fallback for migration.
    }

    if (disableSupabaseFallback) {
      if (independent?.serviceError) {
        return res.status(503).json({ error: "Authentication service temporarily unavailable" });
      }
      return res.status(401).json({ error: "Invalid or expired session" });
    }

    if (!supabaseUrl || !publishableKey) {
      if (independent?.serviceError) {
        return res.status(503).json({
          error: "Authentication service temporarily unavailable",
        });
      }
      return res.status(401).json({
        error: "Invalid or expired session",
      });
    }

    try {
      const base = supabaseUrl.replace(/\/+$/, "");
      const response = await fetchImpl(`${base}/auth/v1/user`, {
        headers: {
          apikey: publishableKey,
          authorization: `Bearer ${accessToken}`,
        },
        signal: AbortSignal.timeout(8000),
      });

      if (response.status === 401 || response.status === 403) {
        return res.status(401).json({ error: "Invalid or expired session" });
      }

      if (!response.ok) {
        return res.status(503).json({
          error: "Current-session verification is temporarily unavailable",
        });
      }

      const authenticatedUser = await response.json();
      if (typeof authenticatedUser?.id !== "string") {
        return res.status(401).json({ error: "Invalid user identity" });
      }

      const isBannedByProvider = Boolean(
        (authenticatedUser.banned_until &&
          new Date(authenticatedUser.banned_until) > new Date()) ||
          (authenticatedUser.raw_app_meta_data?.banned_until &&
            new Date(authenticatedUser.raw_app_meta_data.banned_until) >
              new Date())
      );
      const isDeletedByProvider = Boolean(
        authenticatedUser.deleted_at ||
          authenticatedUser.raw_app_meta_data?.deleted_at
      );

      if (isBannedByProvider || isDeletedByProvider) {
        return res.status(401).json({ error: "Account is unavailable" });
      }

      const result = await database.query(
        `SELECT
           $1::uuid AS id,
           COALESCE(u.email, $2::text) AS email,
           (
             EXISTS (
               SELECT 1 FROM public.app_admins a
               WHERE a.user_id = $1::uuid
             ) OR COALESCE(p.is_admin, FALSE)
           ) AS is_admin,
           COALESCE(u.deleted_at IS NOT NULL, FALSE) AS is_deleted,
           COALESCE(u.banned_until IS NOT NULL AND u.banned_until > NOW(), FALSE) AS is_banned
         FROM (SELECT $1::uuid AS id) req_user
         LEFT JOIN public.profiles p ON p.id = req_user.id
         LEFT JOIN public.app_users u ON u.id = req_user.id
         LIMIT 1`,
        [authenticatedUser.id, authenticatedUser.email ?? null]
      );
      const user = result.rows[0];

      if (!user || user.is_deleted === true || user.is_banned === true) {
        return res.status(401).json({ error: "Account is unavailable" });
      }

      req.user = {
        id: user.id ?? authenticatedUser.id,
        email: user.email ?? authenticatedUser.email ?? null,
        role: "authenticated",
        is_admin: user.is_admin === true,
      };
      return next();
    } catch (error) {
      if (error.name === "TimeoutError" || error.name === "AbortError") {
        return res.status(503).json({
          error: "Current-session verification timed out",
        });
      }

      console.error("Current-session verification failed:", error.message);
      return res.status(503).json({
        error: "Current-session verification is temporarily unavailable",
      });
    }
  };
}

export const authenticateCurrentUser = createCurrentUserAuthenticator();

export function optionalCurrentUser(req, res, next) {
  if (!req.headers.authorization) return next();
  return authenticateCurrentUser(req, res, next);
}


/**
 * Backend-independent JWT only (no Supabase fallback). For routes that must
 * not accept legacy Supabase sessions. Derives is_admin from app_admins via
 * the authenticated UUID in Neon.
 */
export function createAuthenticateBackendIndependent({ database = pool } = {}) {
  return async function authenticateBackendIndependent(req, res, next) {
    const header = req.headers.authorization;
    if (!header?.startsWith("Bearer ")) {
      return res.status(401).json({ error: "Authentication token required" });
    }
    const accessToken = header.slice(7).trim();
    if (!accessToken) {
      return res.status(401).json({ error: "Invalid authentication token" });
    }
    const independent = await verifyIndependentSession(accessToken, database);
    if (independent?.id) {
      req.user = independent;
      return next();
    }
    if (independent?.serviceError) {
      return res.status(503).json({ error: "Authentication service temporarily unavailable" });
    }
    return res.status(401).json({ error: "Invalid or expired authentication token" });
  };
}

export const authenticateBackendIndependent = createAuthenticateBackendIndependent();
