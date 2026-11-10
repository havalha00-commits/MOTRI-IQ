import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import dotenv from "dotenv";
import express from "express";
import { createServer } from "node:http";

process.env.MOTRI_LOCAL_TEST_ISOLATED = "1";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const backendDir = path.resolve(__dirname, "..");
const config = dotenv.parse(fs.readFileSync(path.join(backendDir, ".env.b2.test.local")));
const expected = {
  endpoint: "https://s3.eu-central-003.backblazeb2.com",
  region: "eu-central-003",
  bucket: "motri-iq-isolated-test-2026",
  prefix: "motri-iq-test",
};

if (
  config.B2_ENDPOINT !== expected.endpoint ||
  config.B2_REGION !== expected.region ||
  config.B2_BUCKET !== expected.bucket ||
  config.B2_LIVE_INTEGRATION !== "1" ||
  config.B2_LIVE_ACK !== expected.bucket ||
  !config.B2_KEY_ID?.trim() ||
  !config.B2_APPLICATION_KEY?.trim() ||
  Object.keys(config).some((key) => key.startsWith("R2_"))
) {
  throw new Error("Isolated B2 test configuration rejected");
}

const [{ createCarsRouter }, { createStorageRouter }, { createObjectStorageService }] =
  await Promise.all([
    import("../routes/cars.js"),
    import("../routes/storage.js"),
    import("../services/objectStorage.js"),
  ]);

const host = process.env.PHONE_TEST_HOST || "127.0.0.1";
const port = Number(process.env.PHONE_TEST_PORT || 3400);
const usersByEmail = new Map();
const usersByRefreshToken = new Map();
const reservations = new Map();
const cars = new Map();
const userId = crypto.randomUUID();
const testUser = {
  id: userId,
  email: "phone-test@motri-iq.invalid",
  username: "phone_test",
  full_name: "MOTRI Phone Test",
  phone: null,
  is_admin: false,
};
const accessToken = crypto.randomBytes(32).toString("base64url");
const refreshToken = crypto.randomBytes(32).toString("base64url");
const demoCarId = crypto.randomUUID();
const demoPhotoId = crypto.randomUUID();
const demoObjectKey = `${userId}/${demoCarId}/${demoPhotoId}.png`;
const demoImage = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGMwK9oBAAJCAWE1XA0zAAAAAElFTkSuQmCC",
  "base64",
);
usersByEmail.set(testUser.email, { user: testUser, password: "PhoneTestOnly-2026" });
usersByRefreshToken.set(refreshToken, testUser);

function authResponse(res, user) {
  return res.json({
    authenticated: true,
    access_token: accessToken,
    refresh_token: refreshToken,
    token_type: "Bearer",
    expires_in: 3600,
    user,
  });
}

function authenticate(req, res, next) {
  const token = req.headers.authorization?.replace(/^Bearer\s+/i, "");
  if (token !== accessToken) return res.status(401).json({ error: "Test session required" });
  req.user = testUser;
  next();
}

function optionalAuthenticate(req, res, next) {
  if (!req.headers.authorization) return next();
  return authenticate(req, res, next);
}

const database = {
  async connect() {
    return { query: database.query.bind(database), release() {} };
  },

  async query(sql, values = []) {
    const query = sql.replace(/\s+/g, " ").trim().toLowerCase();
    if (
      query === "begin" ||
      query === "commit" ||
      query === "rollback" ||
      query.startsWith("select pg_advisory_xact_lock")
    ) {
      return { rows: [], rowCount: 0 };
    }

    if (query.includes("select count(*)::int as count from public.car_image_upload_reservations")) {
      const active = [...reservations.values()].filter((row) => row.userId === values[0] && !row.consumed).length;
      return { rows: [{ count: active }], rowCount: 1 };
    }

    if (
      query.includes("from public.car_image_upload_reservations") &&
      query.includes("where user_id = $1") &&
      query.includes("photo_id = $3")
    ) {
      const row = [...reservations.values()].find(
        (item) => item.userId === values[0] && item.submissionId === values[1] && item.photoId === values[2],
      );
      return { rows: row ? [{ ...row, is_active: !row.consumed }] : [], rowCount: row ? 1 : 0 };
    }

    if (query.includes("insert into public.car_image_upload_reservations")) {
      const [ownerId, submissionId, photoId, objectKey] = values;
      const row = {
        id: crypto.randomUUID(),
        userId: ownerId,
        submissionId,
        photoId,
        object_key: objectKey,
        expires_at: new Date(Date.now() + 30 * 60 * 1000).toISOString(),
        consumed_at: null,
        consumed: false,
      };
      reservations.set(objectKey, row);
      return { rows: [{ object_key: row.object_key, expires_at: row.expires_at }], rowCount: 1 };
    }

    if (query.includes("select 1 from public.car_image_upload_reservations")) {
      const row = reservations.get(values[0]);
      const ok = row && row.userId === values[1] && !row.consumed;
      return { rows: ok ? [{ ok: 1 }] : [], rowCount: ok ? 1 : 0 };
    }

    if (
      query.includes("from public.car_image_upload_reservations") &&
      query.includes("where user_id = $1 and submission_id = $2 and object_key = any")
    ) {
      const wantedKeys = values[2];
      const rows = wantedKeys
        .map((key) => reservations.get(key))
        .filter((row) => row?.userId === values[0] && row.submissionId === values[1])
        .map((row) => ({ ...row, is_active: !row.consumed }));
      return { rows, rowCount: rows.length };
    }

    if (query.startsWith("update public.car_image_upload_reservations")) {
      const wantedKeys = values[2];
      const rows = [];
      for (const key of wantedKeys) {
        const row = reservations.get(key);
        if (row?.userId === values[0] && row.submissionId === values[1] && !row.consumed) {
          row.consumed = true;
          row.consumed_at = new Date().toISOString();
          rows.push({ object_key: key });
        }
      }
      return { rows, rowCount: rows.length };
    }

    if (query.startsWith("insert into public.cars")) {
      const match = sql.match(/INSERT INTO public\.cars\s*\(([\s\S]*?)\)\s*VALUES/i);
      if (!match) throw new Error("Unexpected test car insert");
      const columns = match[1].split(",").map((column) => column.trim());
      const row = Object.fromEntries(columns.map((column, index) => [column, values[index]]));
      row.user_id = testUser.id;
      row.is_approved = false;
      row.created_at = new Date().toISOString();
      if (!Array.isArray(row.images) && typeof row.image_url === "string") {
        try {
          row.images = JSON.parse(row.image_url);
        } catch {
          row.images = [row.image_url];
        }
      }
      cars.set(row.id, row);
      return { rows: [{ id: row.id }], rowCount: 1 };
    }

    if (query.includes("select id, user_id, is_approved, image_url, images from public.cars where id = $1")) {
      const row = cars.get(values[0]);
      return { rows: row ? [row] : [], rowCount: row ? 1 : 0 };
    }

    if (query.startsWith("select * from public.cars")) {
      let rows = [...cars.values()];
      if (query.includes("is_approved = true")) rows = rows.filter((row) => row.is_approved);
      if (query.includes("user_id = $1")) rows = rows.filter((row) => row.user_id === values[0]);
      return { rows, rowCount: rows.length };
    }

    if (query.startsWith("select brand, model, city, province")) {
      return { rows: [], rowCount: 0 };
    }

    if (query.startsWith("select")) return { rows: [], rowCount: 0 };
    throw new Error("Unsupported operation in isolated phone test backend");
  },
};

const storage = createObjectStorageService({
  env: {
    STORAGE_PROVIDER: "b2",
    STORAGE_PREFIX: expected.prefix,
    B2_ENDPOINT: config.B2_ENDPOINT,
    B2_REGION: config.B2_REGION,
    B2_BUCKET: config.B2_BUCKET,
    B2_KEY_ID: config.B2_KEY_ID,
    B2_APPLICATION_KEY: config.B2_APPLICATION_KEY,
  },
  ownershipChecker: async (owner, key, bucket) =>
    owner === userId && bucket === "cars" && key.startsWith(`${userId}/`),
});

const app = express();
app.use(express.json({ limit: "1mb" }));
app.use((req, _res, next) => {
  console.log(`request ${req.method} ${req.path}`);
  next();
});
app.get("/health", (_req, res) =>
  res.json({ status: "ok", isolated: true, provider: "b2", bucket: expected.bucket, prefix: `${expected.prefix}/` }),
);

app.post("/api/auth/register", (req, res) => {
  const email = String(req.body?.email || "").trim().toLowerCase();
  const password = req.body?.password;
  if (!email.endsWith("@motri-iq.invalid") || password !== "PhoneTestOnly-2026") {
    return res.status(400).json({ error: "Use the temporary test account shown for this phone test" });
  }
  return authResponse(res, testUser);
});
app.post("/api/auth/login", (req, res) => {
  const email = String(req.body?.email || req.body?.identifier || "").trim().toLowerCase();
  const user = usersByEmail.get(email);
  if (!user || req.body?.password !== user.password) {
    return res.status(401).json({ error: "Invalid test credentials" });
  }
  return authResponse(res, user.user);
});
app.post("/api/auth/refresh", (req, res) => {
  const user = usersByRefreshToken.get(req.body?.refresh_token);
  if (!user) return res.status(401).json({ error: "Test session expired" });
  return authResponse(res, user);
});
app.post("/api/auth/logout", (_req, res) => res.json({ success: true }));
app.get("/api/profile/me", authenticate, (_req, res) =>
  res.json({ success: true, data: testUser }),
);
app.get("/__test/status", (_req, res) => {
  const car = [...cars.values()].at(-1) || null;
  res.json({
    isolated: true,
    carCount: cars.size,
    lastCar: car
      ? { id: car.id, is_approved: car.is_approved, imageCount: Array.isArray(car.images) ? car.images.length : 0 }
      : null,
    pendingReservations: [...reservations.values()].filter((row) => !row.consumed).length,
  });
});
app.post("/__test/cleanup", async (_req, res) => {
  let deletedObjects = 0;
  const failed = [];
  for (const car of cars.values()) {
    if (car.id === demoCarId) continue;
    for (const key of car.images || []) {
      try {
        await storage.deleteObject({ bucket: "cars", key, userId });
        deletedObjects++;
      } catch (error) {
        if (error?.statusCode !== 404) failed.push("delete_failed");
      }
    }
  }
  if (failed.length > 0) {
    return res.status(503).json({ success: false, cleanup: "failed" });
  }
  for (const [id] of cars) {
    if (id !== demoCarId) cars.delete(id);
  }
  reservations.clear();
  return res.json({ success: true, cleanup: "complete", deletedObjects });
});

app.use("/api/cars", createCarsRouter({ database, authenticate, optionalAuthenticate, storage }));
app.use("/api/storage", createStorageRouter({ authenticate, storage, database }));

await storage.upload({
  bucket: "cars",
  key: demoObjectKey,
  body: demoImage,
  contentType: "image/png",
});
cars.set(demoCarId, {
  id: demoCarId,
  user_id: userId,
  is_approved: true,
  title: "ISOLATED TEST - NOT A REAL LISTING",
  brand: "MOTRI TEST",
  model: "DEMO",
  year: 2020,
  price: 0,
  city: "Test City",
  province: "Test Region",
  phone: null,
  image_url: demoObjectKey,
  images: [demoObjectKey],
  created_at: new Date().toISOString(),
});

const server = createServer(app);
server.listen(port, host, () => {
  console.log(JSON.stringify({
    status: "ready",
    host,
    port,
    isolated: true,
    provider: "b2",
    bucket: expected.bucket,
    prefix: `${expected.prefix}/`,
    database: "in-memory only",
    supabase: "disabled",
    testEmail: testUser.email,
    testPassword: "PhoneTestOnly-2026",
  }));
});

async function shutdown() {
  for (const car of cars.values()) {
    for (const key of car.images || []) {
      try {
        await storage.deleteObject({ bucket: "cars", key, userId });
      } catch {
        console.error("shutdown_cleanup_failed");
      }
    }
  }
  await new Promise((resolve) => server.close(resolve));
  process.exit(0);
}
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
