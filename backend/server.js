import express from "express";
import helmet from "helmet";
import { authenticateToken } from "./middleware/auth.js";
import { startServerWithLocalTestDbGuard } from "./config/localTestDatabaseGuard.js";
import { isLocalTestStorageMode, assertLocalTestStorageConfig } from "./config/localTestStorageGuard.js";
import { createCurrentUserAuthenticator } from "./middleware/current_user.js";
import { createStorageRouter } from "./routes/storage.js";
import { createCarsRouter } from "./routes/cars.js";
import authRouter from "./routes/auth.js";
import safetyRouter from "./routes/safety.js";
import favoritesRouter from "./routes/favorites.js";
import requestsRouter from "./routes/requests.js";
import offersRouter from "./routes/offers.js";
import sellersRouter from "./routes/sellers.js";
import activityRouter from "./routes/activity.js";
import businessAdsRouter from "./routes/business_ads.js";
import { createMarketRouter, createMarketImageDeliveryRouter } from "./routes/market.js";
import { createAccountRouter } from "./routes/account.js";
import { createWalletRouter } from "./routes/wallet.js";
import { cleanupExpiredReservations } from "./services/reservationCleanup.js";
import ugcRouter from "./routes/ugc.js";
import profilesRouter from "./routes/profiles.js";

// G10.62 P3.4A: isolated local-test bootstrap must not implicitly load backend/.env.
// Normal non-local startup preserves dotenv loading (legacy behavior).
if (process.env.MOTRI_LOCAL_TEST_ISOLATED !== "1") {
  const dotenv = await import("dotenv");
  dotenv.default?.config?.();
}

export function createOptionalCurrentUser(authenticate) {
  return function optionalCurrentUser(req, res, next) {
    if (!req.headers.authorization) return next();
    return authenticate(req, res, next);
  };
}

export function createStorageServiceForEnv(env = process.env, { createObjectStorageService } = {}) {
  let storageService;
  try {
    if (isLocalTestStorageMode(env)) {
      assertLocalTestStorageConfig(env);
    }
    storageService = createObjectStorageService ? createObjectStorageService({ env }) : null;
    if (!storageService && !createObjectStorageService) {
      throw new Error("STORAGE_SERVICE_FACTORY_REQUIRED");
    }
  } catch (error) {
    if (isLocalTestStorageMode(env)) {
      const err = new Error(`LOCAL_TEST_STORAGE_GUARD_REFUSED: ${error?.code || "LOCAL_TEST_STORAGE_CONFIG_INVALID"}`);
      err.code = error?.code || "LOCAL_TEST_STORAGE_CONFIG_INVALID";
      throw err;
    }
    console.warn("Storage service not initialized (R2 env missing or invalid):", error.message);
    storageService = null;
  }
  return storageService;
}

export async function createApp({ pool, storageService, env = process.env } = {}) {
  const app = express();
  app.locals.storageService = storageService ?? null;

  app.use(helmet());
  app.use(express.json({ limit: "1mb" }));

  // G10.62 P3.4G: isolated local-test runtime mounts ONLY the approved Market image surface
  // with explicit injected pool/storage/auth. No unrelated singleton routers, no /api/uploads,
  // no default pool/auth/policy singletons. Normal production behavior unchanged.
  if (env?.MOTRI_LOCAL_TEST_ISOLATED === "1") {
    const authenticate = createCurrentUserAuthenticator({
      database: pool,
      disableSupabaseFallback: true,
    });
    const optionalAuthenticate = createOptionalCurrentUser(authenticate);
    const marketImageDeliveryRouter = createMarketImageDeliveryRouter({
      database: pool,
      storage: storageService,
      optionalAuthenticate,
    });
    const marketRouter = createMarketRouter({
      database: pool,
      storage: storageService,
      authenticate,
      optionalAuthenticate,
    });

    app.use("/api/market/images", marketImageDeliveryRouter);
    app.use("/api/market", marketRouter);

    app.get("/health", (req, res) => {
      res.json({ status: "ok", service: "MOTRI_IQ Backend", isolated: true });
    });

    app.get("/health/database", async (req, res) => {
      try {
        const result = await pool.query("SELECT current_database() AS database, NOW() AS server_time");
        res.json({ status: "ok", database: result.rows[0].database, connected: true, isolated: true });
      } catch (error) {
        console.error("Neon connection check failed:", error.message);
        res.status(503).json({ status: "error", connected: false, message: "Database connection failed", isolated: true });
      }
    });

    app.locals.__isolatedMarketDeps = {
      database: pool,
      storageService,
      authenticate,
      optionalAuthenticate,
      marketRouter,
      marketImageDeliveryRouter,
    };
    return app;
  }

  app.use("/api/auth", authRouter);
  app.use("/api/safety", safetyRouter);
  app.use("/api/cars", createCarsRouter({ storage: storageService, database: pool }));
  app.use("/api/favorites", favoritesRouter);
  app.use("/api/requests", requestsRouter);
  app.use("/api/offers", offersRouter);
  app.use("/api/sellers", sellersRouter);
  app.use("/api/activity", activityRouter);
  app.use("/api/business-ads", businessAdsRouter);
  // G10.52 M1C: mount delivery before authenticated market router so public/opt-auth image reads work.
  // G10.62 P1: inject the SAME pool + storageService into both market routers (actual runtime wiring).
  app.use("/api/market/images", createMarketImageDeliveryRouter({ database: pool, storage: storageService }));
  app.use("/api/market", createMarketRouter({ database: pool, storage: storageService }));
  // G10.62 P3.4C: Supabase-backed legacy uploads route must NOT be mounted in isolated local-test mode.
  // Market image uploads use /api/market/uploads + injected local objectStorage. Normal production behavior preserved.
  if (!isLocalTestStorageMode(env)) {
    const { default: uploadsRouter } = await import("./routes/uploads.js");
    app.use("/api/uploads", uploadsRouter);
  }
  app.use("/api/profile", profilesRouter);
  app.use("/api/account", createAccountRouter({ database: pool }));
  app.use("/api/wallet", createWalletRouter({ storageService }));
  app.use("/api/storage", createStorageRouter({ storage: storageService, database: pool, env }));
  app.use("/api/ugc", ugcRouter);

  app.get("/health", (req, res) => {
    res.json({ status: "ok", service: "MOTRI_IQ Backend" });
  });

  app.get("/health/database", async (req, res) => {
    try {
      const result = await pool.query("SELECT current_database() AS database, NOW() AS server_time");
      res.json({ status: "ok", database: result.rows[0].database, connected: true });
    } catch (error) {
      console.error("Neon connection check failed:", error.message);
      res.status(503).json({ status: "error", connected: false, message: "Database connection failed" });
    }
  });

  app.get("/api/me", authenticateToken, (req, res) => {
    res.json({ authenticated: true, user: req.user });
  });

  return app;
}

export function scheduleReservationCleanup(env = process.env, { database } = {}) {
  const cleanupInterval = Number(env.RESERVATION_CLEANUP_INTERVAL_MS) || 0;
  if (cleanupInterval > 0 && database) {
    // No immediate query; timer fires only after interval elapses.
    return setInterval(() => {
      cleanupExpiredReservations({
        database,
        batchSize: Number(env.RESERVATION_CLEANUP_BATCH_SIZE) || 100,
      }).catch((error) => {
        console.error("Reservation cleanup failed:", error.message);
      });
    }, cleanupInterval);
  }
  return null;
}

export async function startIsolatedLocalTestServer({
  app,
  pool,
  env = process.env,
  port = Number(env.PORT) || 3000,
} = {}) {
  // Isolated runtime: cleanup disabled by default. No immediate query; scheduling only after verified DB identity.
  return startServerWithLocalTestDbGuard({
    app,
    pool,
    port,
    env,
    onVerified: () => {
      scheduleReservationCleanup(env, { database: pool });
    },
  });
}

// ---------------------------------------------------------------------------
// Default non-local startup (preserved behavior). Never executes in isolated
// local-test bootstrap, which imports exports and starts via explicit path.
// ---------------------------------------------------------------------------
const _isDirectRun = (() => {
  try {
    const argv1 = process.argv[1];
    if (!argv1) return false;
    return import.meta.url === new URL(`file:///${argv1.replace(/\\/g, "/")}`).href
      || import.meta.url.endsWith(argv1.replace(/\\/g, "/"));
  } catch {
    return false;
  }
})();

if (_isDirectRun && process.env.MOTRI_LOCAL_TEST_ISOLATED !== "1") {
  const { pool } = await import("./config/database.js");
  const { createObjectStorageService } = await import("./services/objectStorage.js");
  let storageService = null;
  try {
    storageService = createStorageServiceForEnv(process.env, { createObjectStorageService });
  } catch (err) {
    if (isLocalTestStorageMode(process.env)) {
      console.error(String(err.message || "LOCAL_TEST_STORAGE_GUARD_REFUSED"));
      process.exit(1);
    }
  }
  const app = await createApp({ pool, storageService, env: process.env });
  const PORT = Number(process.env.PORT) || 3000;
  await startServerWithLocalTestDbGuard({
    app,
    pool,
    port: PORT,
    env: process.env,
    onVerified: () => {
      scheduleReservationCleanup(process.env, { database: pool });
    },
  });
}
