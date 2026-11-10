import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { createMarketRouter, createMarketImageDeliveryRouter } from "../routes/market.js";

test("G10.62 P1: market router factories expose injected database/storage deps (offline)", () => {
  const database = { tag: "pool" };
  const storage = { tag: "storageService", upload: async () => {}, download: async () => {} };
  const market = createMarketRouter({ database, storage });
  const delivery = createMarketImageDeliveryRouter({ database, storage });

  assert.equal(market.__deps.database, database, "market router must use injected database");
  assert.equal(market.__deps.storage, storage, "market router must use injected storage");
  assert.equal(delivery.__deps.database, database, "delivery router must use injected database");
  assert.equal(delivery.__deps.storage, storage, "delivery router must use injected storage");
  assert.equal(market.__deps.database, delivery.__deps.database, "routers must share same database");
  assert.equal(market.__deps.storage, delivery.__deps.storage, "routers must share same storage");
});

test("G10.62 P1: actual server.js wires the SAME pool+storageService into both market routers (source wiring)", () => {
  const here = path.dirname(fileURLToPath(import.meta.url));
  const serverPath = path.resolve(here, "../server.js");
  const src = fs.readFileSync(serverPath, "utf8");

  // Must not use the default-export market router without injected deps.
  assert.ok(!src.includes('import marketRouter, { createMarketImageDeliveryRouter } from "./routes/market.js";'));
  assert.ok(src.includes('import { createMarketRouter, createMarketImageDeliveryRouter } from "./routes/market.js";'));

  // Both runtime mounts must receive the same injected pool + storageService, preserving order.
  const delivery = 'app.use("/api/market/images", createMarketImageDeliveryRouter({ database: pool, storage: storageService }));';
  const main = 'app.use("/api/market", createMarketRouter({ database: pool, storage: storageService }));';
  assert.ok(src.includes(delivery), "delivery router must inject pool+storageService");
  assert.ok(src.includes(main), "market router must inject pool+storageService");
  assert.ok(src.indexOf(delivery) < src.indexOf(main), "delivery must remain mounted before /api/market");

  // No DB/network/provider access: this is a static wiring check over local source.
});
