import { Router } from "express";
import bcrypt from "bcryptjs";
import { SignJWT } from "jose";
import {
  createHash,
  randomBytes,
  randomUUID
} from "node:crypto";
import { pool } from "../config/database.js";

const secret = process.env.JWT_SECRET;

if (!secret || secret.length < 64) {
  throw new Error("JWT_SECRET is missing or too short");
}

const ACCESS_SECONDS = 900;
const REFRESH_SECONDS = 30 * 24 * 60 * 60;

function hashToken(token) {
  return createHash("sha256").update(token).digest("hex");
}

function newRefreshToken() {
  return randomBytes(64).toString("base64url");
}

function sendTokens(res, user, accessToken, refreshToken) {
  return res.json({
    authenticated: true,
    access_token: accessToken,
    refresh_token: refreshToken,
    token_type: "Bearer",
    expires_in: ACCESS_SECONDS,
    refresh_expires_in: REFRESH_SECONDS,
    user: {
      id: user.id,
      email: user.email ?? null,
      username: user.username ?? null,
      full_name: user.full_name ?? null,
      phone: user.phone ?? null,
      avatar_url: user.avatar_url ?? null,
      is_admin: user.is_admin === true
    }
  });
}

export function createAuthRouter({
  database = pool,
  comparePassword = bcrypt.compare,
  jwtSecret = secret
} = {}) {
  if (!jwtSecret || jwtSecret.length < 64) {
    throw new Error("JWT_SECRET is missing or too short");
  }

  const router = Router();
  const signingKey = new TextEncoder().encode(jwtSecret);

  async function issueAccessToken(user, sessionId) {
    return new SignJWT({
      email: user.email,
      role: "authenticated",
      is_admin: user.is_admin === true,
      sid: sessionId
    })
      .setProtectedHeader({ alg: "HS256" })
      .setSubject(user.id)
      .setIssuer("motri-iq-api")
      .setAudience("authenticated")
      .setIssuedAt()
      .setExpirationTime("15m")
      .sign(signingKey);
  }

  router.post("/register", async (req, res) => {
    try {
      const email = String(req.body?.email ?? "").trim().toLowerCase();
      const password = req.body?.password;
      const fullName =
        typeof req.body?.full_name === "string" ? req.body.full_name.trim() : "";
      const username =
        typeof req.body?.username === "string"
          ? req.body.username.trim().toLowerCase()
          : "";

      if (!email || !email.includes("@") || typeof password !== "string" || !password) {
        return res.status(400).json({ error: "Email and password are required" });
      }
      if (password.length < 8 || password.length > 1024) {
        return res.status(400).json({ error: "Password requirements not met" });
      }
      if (username && !/^[a-z0-9_]{3,24}$/i.test(username)) {
        return res.status(400).json({ error: "Invalid username" });
      }

      const hash = await bcrypt.hash(password, 12);
      const id = randomUUID();
      let client;
      try {
        client = await database.connect();
        await client.query("BEGIN");
        const existing = await client.query(
          `SELECT id FROM public.app_users WHERE lower(email)=lower($1) LIMIT 1`,
          [email]
        );
        if (existing.rows.length > 0) {
          await client.query("ROLLBACK");
          return res.status(409).json({ error: "Email already registered" });
        }
        if (username) {
          const u = await client.query(
            `SELECT id FROM public.app_users WHERE lower(username)=lower($1) LIMIT 1`,
            [username]
          );
          if (u.rows.length > 0) {
            await client.query("ROLLBACK");
            return res.status(409).json({ error: "Username already taken" });
          }
        }
        await client.query(
          `INSERT INTO public.app_users
             (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, username, raw_user_meta_data)
           VALUES ($1,$2,$3,NOW(),NOW(),NOW(),$4,$5::jsonb)`,
          [id, email, hash, username || null, JSON.stringify({ full_name: fullName || null })]
        );
        await client.query(
          `INSERT INTO public.profiles (id, full_name, username, activation_code, is_admin)
           VALUES ($1,$2,$3,$4,false)
           ON CONFLICT (id) DO UPDATE
             SET username = COALESCE(EXCLUDED.username, public.profiles.username),
                 full_name = COALESCE(NULLIF(EXCLUDED.full_name,''), public.profiles.full_name),
                 activation_code = COALESCE(NULLIF(public.profiles.activation_code,''), EXCLUDED.activation_code)`,
          [
            id,
            fullName || email.split("@")[0] || "User",
            username || `user_${id.slice(0, 8)}`,
            randomBytes(8).toString("hex"),
          ]
        );
        const userRow = await client.query(
          `SELECT u.id, u.email, u.username,
                  EXISTS (SELECT 1 FROM public.app_admins a WHERE a.user_id=u.id) OR COALESCE(p.is_admin,false) AS is_admin
             FROM public.app_users u LEFT JOIN public.profiles p ON p.id=u.id
            WHERE u.id=$1 LIMIT 1`,
          [id]
        );
        const user = userRow.rows[0];
        const sessionId = randomUUID();
        const refreshToken = newRefreshToken();
        const accessToken = await issueAccessToken(user, sessionId);
        await client.query(
          `INSERT INTO public.app_sessions (id,user_id,refresh_token_hash,expires_at)
           VALUES ($1,$2,$3,NOW()+INTERVAL '30 days')`,
          [sessionId, id, hashToken(refreshToken)]
        );
        await client.query("COMMIT");
        return res.status(201).json({
          authenticated: true,
          requires_email_confirmation: false,
          access_token: accessToken,
          refresh_token: refreshToken,
          token_type: "Bearer",
          expires_in: ACCESS_SECONDS,
          refresh_expires_in: REFRESH_SECONDS,
          user: {
            id: user.id,
            email: user.email ?? null,
            username: user.username ?? null,
            full_name: fullName || null,
            phone: null,
            avatar_url: null,
            is_admin: user.is_admin === true
          }
        });
      } catch (e) {
        if (client) try { await client.query("ROLLBACK"); } catch {}
        if (e?.code === "23505") {
          return res.status(409).json({ error: "Account already exists" });
        }
        throw e;
      } finally {
        client?.release();
      }
    } catch (error) {
      console.error("Register failed:", error.message);
      return res.status(500).json({ error: "Authentication service error" });
    }
  });

  router.post("/login", async (req, res) => {
    try {
      const identifier = String(
        req.body?.identifier ?? req.body?.email ?? req.body?.username ?? ""
      ).trim().toLowerCase();
      const password = req.body?.password;

      if (!identifier || typeof password !== "string" || !password) {
        return res.status(400).json({
          error: "Email or username and password are required"
        });
      }

      if (identifier.length > 320 || password.length > 1024) {
        return res.status(400).json({
          error: "Invalid login credentials"
        });
      }

      const identityColumn = identifier.includes("@") ? "email" : "username";
      const result = await database.query(
        `SELECT
           u.id,
           u.email,
           u.username,
           u.encrypted_password,
           u.email_confirmed_at,
           u.banned_until,
           u.deleted_at,
           NULLIF(TRIM(u.phone::text), '') AS phone,
           p.full_name,
           COALESCE(
             NULLIF(TRIM(u.raw_user_meta_data->>'avatar_url'), ''),
             NULLIF(TRIM(u.raw_user_meta_data->>'picture'), ''),
             NULLIF(TRIM(u.raw_user_meta_data->>'avatar'), '')
           ) AS avatar_url,
           (EXISTS (
             SELECT 1 FROM public.app_admins a
             WHERE a.user_id = u.id
           ) OR COALESCE(p.is_admin, FALSE)) AS is_admin
         FROM public.app_users u
         LEFT JOIN public.profiles p ON p.id = u.id
         WHERE ($2 = 'email' AND lower(u.email) = $1)
            OR ($2 = 'username' AND lower(u.username) = $1)
         LIMIT 1`,
        [identifier, identityColumn]
      );

      const user = result.rows[0];

      if (!user || !user.encrypted_password) {
        return res.status(401).json({
          error: "Invalid email or password"
        });
      }

      const passwordMatches = await comparePassword(
        password,
        user.encrypted_password
      );

      if (!passwordMatches) {
        return res.status(401).json({
          error: "Invalid email or password"
        });
      }

      if (
        !user.email_confirmed_at ||
        user.deleted_at ||
        (user.banned_until && new Date(user.banned_until) > new Date())
      ) {
        return res.status(403).json({
          error: "This account cannot sign in"
        });
      }

      const sessionId = randomUUID();
      const refreshToken = newRefreshToken();
      const accessToken = await issueAccessToken(user, sessionId);

      await database.query(
        `INSERT INTO public.app_sessions
           (id, user_id, refresh_token_hash, expires_at)
         VALUES ($1, $2, $3, NOW() + INTERVAL '30 days')`,
        [sessionId, user.id, hashToken(refreshToken)]
      );

      return sendTokens(res, user, accessToken, refreshToken);
    } catch (error) {
      console.error("Login failed:", error.message);

      return res.status(500).json({
        error: "Authentication service error"
      });
    }
  });

  router.post("/refresh", async (req, res) => {
    const refreshToken = req.body?.refresh_token;

    if (
      typeof refreshToken !== "string" ||
      refreshToken.length < 40 ||
      refreshToken.length > 200
    ) {
      return res.status(400).json({
        error: "Refresh token is required"
      });
    }

    let client;

    try {
      client = await database.connect();
      await client.query("BEGIN");

      const result = await client.query(
        `SELECT
           s.id AS session_id,
           u.id,
           u.email,
           u.username,
           u.email_confirmed_at,
           u.banned_until,
           u.deleted_at,
           NULLIF(TRIM(u.phone::text), '') AS phone,
           p.full_name,
           COALESCE(
             NULLIF(TRIM(u.raw_user_meta_data->>'avatar_url'), ''),
             NULLIF(TRIM(u.raw_user_meta_data->>'picture'), ''),
             NULLIF(TRIM(u.raw_user_meta_data->>'avatar'), '')
           ) AS avatar_url,
           (EXISTS (
             SELECT 1 FROM public.app_admins a
             WHERE a.user_id = u.id
           ) OR COALESCE(p.is_admin, FALSE)) AS is_admin
         FROM public.app_sessions s
         JOIN public.app_users u ON u.id = s.user_id
         LEFT JOIN public.profiles p ON p.id = u.id
         WHERE s.refresh_token_hash = $1
           AND s.revoked_at IS NULL
           AND s.expires_at > NOW()
         FOR UPDATE OF s`,
        [hashToken(refreshToken)]
      );

      const user = result.rows[0];

      if (
        !user ||
        !user.email_confirmed_at ||
        user.deleted_at ||
        (user.banned_until && new Date(user.banned_until) > new Date())
      ) {
        await client.query("ROLLBACK");

        return res.status(401).json({
          error: "Invalid or expired refresh token"
        });
      }

      const nextRefreshToken = newRefreshToken();
      const accessToken = await issueAccessToken(
        user,
        user.session_id
      );

      const update = await client.query(
        `UPDATE public.app_sessions
         SET refresh_token_hash = $1,
             expires_at = NOW() + INTERVAL '30 days',
             last_used_at = NOW()
         WHERE id = $2
           AND revoked_at IS NULL
           AND expires_at > NOW()`,
        [hashToken(nextRefreshToken), user.session_id]
      );

      if (update.rowCount !== 1) {
        await client.query("ROLLBACK");
        return res.status(401).json({
          error: "Invalid or expired refresh token"
        });
      }

      await client.query("COMMIT");

      return sendTokens(
        res,
        user,
        accessToken,
        nextRefreshToken
      );
    } catch (error) {
      if (client) {
        try {
          await client.query("ROLLBACK");
        } catch {}
      }

      console.error("Token refresh failed:", error.message);

      return res.status(500).json({
        error: "Authentication service error"
      });
    } finally {
      client?.release();
    }
  });

  router.post("/logout", async (req, res) => {
    const refreshToken = req.body?.refresh_token;

    if (
      typeof refreshToken !== "string" ||
      refreshToken.length < 40 ||
      refreshToken.length > 200
    ) {
      return res.status(400).json({
        error: "Refresh token is required"
      });
    }

    try {
      await database.query(
        `UPDATE public.app_sessions
         SET revoked_at = COALESCE(revoked_at, NOW())
         WHERE refresh_token_hash = $1`,
        [hashToken(refreshToken)]
      );

      return res.json({
        logged_out: true
      });
    } catch (error) {
      console.error("Logout failed:", error.message);

      return res.status(500).json({
        error: "Authentication service error"
      });
    }
  });

  router.post("/reauthenticate", async (req, res) => {
    const userId = req.body?.user_id;
    const password = req.body?.password;
    if (!userId || typeof password !== "string") {
      return res.status(400).json({ error: "Invalid request" });
    }
    let client;
    try {
      client = await database.connect();
      const r = await client.query("SELECT encrypted_password FROM public.app_users WHERE id = $1", [userId]);
      if (r.rows.length === 0) return res.status(401).json({ error: "Invalid credentials" });
      const ok = await comparePassword(password, r.rows[0].encrypted_password);
      if (!ok) return res.status(401).json({ error: "Invalid credentials" });
      const token = await new SignJWT({ purpose: "account_deletion" })
        .setProtectedHeader({ alg: "HS256" })
        .setSubject(userId)
        .setIssuer("motri-iq-api")
        .setAudience("reauth")
        .setIssuedAt()
        .setExpirationTime("5m")
        .sign(signingKey);
      res.json({ reauth_token: token });
    } catch {
      res.status(500).json({ error: "Reauthentication failed" });
    } finally {
      if (client) client.release();
    }
  });

  return router;
}

const router = createAuthRouter();

export default router;
