import assert from "node:assert/strict";
import { once } from "node:events";
import express from "express";
import test from "node:test";
import { createCarsRouter } from "../routes/cars.js";
import { createFavoritesRouter } from "../routes/favorites.js";
import { createOffersRouter } from "../routes/offers.js";
import { createRequestsRouter } from "../routes/requests.js";
import { createActivityRouter } from "../routes/activity.js";
import { createSafetyRouter } from "../routes/safety.js";
import { createSellersRouter } from "../routes/sellers.js";
import { createBusinessAdsRouter } from "../routes/business_ads.js";
import { createMarketRouter } from "../routes/market.js";
import { createUploadsRouter } from "../routes/uploads.js";
import { createUgcRouter } from "../routes/ugc.js";
import { createCurrentUserAuthenticator } from "../middleware/current_user.js";

const userId = "d1f6b1a2-c3d4-4e5f-8a9b-0c1d2e3f4a5b";
const otherId = "a1f6b1a2-c3d4-4e5f-8a9b-0c1d2e3f4a5b";
const carId = "b1f6b1a2-c3d4-4e5f-8a9b-0c1d2e3f4a5b";
const requestId = "c1f6b1a2-c3d4-4e5f-8a9b-0c1d2e3f4a5b";
const offerId = "e1f6b1a2-c3d4-4e5f-8a9b-0c1d2e3f4a5b";

function actorAuth(req, _res, next) {
  req.user = { id: userId, is_admin: false };
  next();
}

async function withRouter(router, path, callback) {
  const app = express();
  app.use(express.json());
  app.use(path, router);
  const server = app.listen(0, "127.0.0.1");
  await once(server, "listening");
  const address = server.address();
  try {
    await callback(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise((resolve, reject) =>
      server.close((error) => (error ? reject(error) : resolve()))
    );
  }
}

async function send(baseUrl, method, path, body) {
  return fetch(`${baseUrl}${path}`, {
    method,
    headers: body ? { "content-type": "application/json" } : {},
    body: body ? JSON.stringify(body) : undefined
  });
}

test("missing car-alert storage returns an empty list without hiding other database errors", async () => {
  let databaseError = Object.assign(
    new Error('relation "public.car_alerts" does not exist'),
    { code: "42P01" }
  );
  const database = {
    async query(sql) {
      assert.match(sql, /FROM public\.car_alerts/);
      throw databaseError;
    }
  };

  await withRouter(
    createActivityRouter({ database, authenticate: actorAuth }),
    "/api/activity",
    async (baseUrl) => {
      const emptyResponse = await send(
        baseUrl,
        "GET",
        "/api/activity/car-alerts"
      );
      assert.equal(emptyResponse.status, 200);
      assert.deepEqual(await emptyResponse.json(), {
        success: true,
        data: [],
        available: false
      });

      databaseError = Object.assign(
        new Error('relation "public.saved_searches" does not exist'),
        { code: "42P01" }
      );
      const failureResponse = await send(
        baseUrl,
        "GET",
        "/api/activity/car-alerts"
      );
      assert.equal(failureResponse.status, 500);
      assert.deepEqual(await failureResponse.json(), {
        error: "Failed to load car alerts"
      });
    }
  );
});

test("car alerts return only rows scoped to the authenticated user and include car details", async () => {
  let executed;
  const alert = {
    id: requestId,
    car_id: carId,
    brand: "Toyota",
    model: "Camry",
    province: "Baghdad",
    city: "Baghdad",
    price: 25000,
    read_at: null
  };
  const database = {
    async query(sql, values) {
      executed = { sql, values };
      return { rows: [alert] };
    }
  };

  await withRouter(
    createActivityRouter({ database, authenticate: actorAuth }),
    "/api/activity",
    async (baseUrl) => {
      const response = await send(
        baseUrl,
        "GET",
        "/api/activity/car-alerts"
      );
      assert.equal(response.status, 200);
      assert.deepEqual((await response.json()).data, [alert]);
      assert.deepEqual(executed.values, [userId]);
      assert.match(executed.sql, /JOIN public\.cars/);
      assert.match(executed.sql, /alerts\.user_id = \$1/);
      assert.match(executed.sql, /cars\.is_approved = TRUE/);
    }
  );
});

test("current-user auth trusts the verified provider identity, not token contents", async () => {
  const queries = [];
  const authenticate = createCurrentUserAuthenticator({
    database: {
      async query(sql, values) {
        queries.push({ sql, values });
        return {
          rows: [{ id: otherId, email: "person@example.test", is_admin: true }]
        };
      }
    },
    supabaseUrl: "https://example.test",
    publishableKey: "publishable",
    fetchImpl: async (url, options) => {
      assert.equal(url, "https://example.test/auth/v1/user");
      assert.equal(options.headers.authorization, "Bearer opaque-session-token");
      return new Response(JSON.stringify({ id: otherId }), { status: 200 });
    }
  });
  const app = express();
  app.get("/protected", authenticate, (req, res) => res.json(req.user));
  const server = app.listen(0, "127.0.0.1");
  await once(server, "listening");
  const address = server.address();

  try {
    const response = await fetch(`http://127.0.0.1:${address.port}/protected`, {
      headers: { authorization: "Bearer opaque-session-token" }
    });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {
      id: otherId,
      email: "person@example.test",
      role: "authenticated",
      is_admin: true
    });
    assert.equal(queries[0].values[0], otherId);
  } finally {
    await new Promise((resolve, reject) =>
      server.close((error) => (error ? reject(error) : resolve()))
    );
  }
});

test("car creation assigns ownership from the authenticated user", async () => {
  const statements = [];
  const database = {
    async query(sql, values) {
      statements.push({ sql, values });
      return { rows: [{ id: carId }] };
    }
  };
  await withRouter(
    createCarsRouter({ database, authenticate: actorAuth }),
    "/api/cars",
    async (baseUrl) => {
      const response = await send(baseUrl, "POST", "/api/cars", {
        id: carId,
        brand: "Toyota",
        model: "Corolla",
        user_id: otherId,
        is_approved: true
      });
      assert.equal(response.status, 201);
      const insert = statements.find((entry) => /INSERT INTO public.cars/.test(entry.sql));
      assert.ok(insert);
      assert.equal(insert.values[1], userId);
      assert.match(insert.sql, /is_approved/);
      assert.equal(insert.values.at(-1), false);
      assert.equal(insert.values.includes(otherId), false);
    }
  );
});

test("favorite updates are scoped to the authenticated user", async () => {
  const statements = [];
  const client = {
    async query(sql, values = []) {
      statements.push({ sql, values });
      if (sql.includes("SELECT id FROM public.favorites")) {
        return { rowCount: 0, rows: [] };
      }
      return { rowCount: 1, rows: [] };
    },
    release() {}
  };
  const database = { connect: async () => client };
  await withRouter(
    createFavoritesRouter({ database, authenticate: actorAuth }),
    "/api/favorites",
    async (baseUrl) => {
      const response = await send(
        baseUrl,
        "PUT",
        `/api/favorites/${carId}`,
        { favorite: true, user_id: otherId }
      );
      assert.equal(response.status, 200);
      const insert = statements.find((entry) =>
        entry.sql.includes("INSERT INTO public.favorites")
      );
      assert.equal(insert.values[0], userId);
      assert.equal(insert.values[1], carId);
    }
  );
});

test("request creation assigns the buyer from the authenticated user", async () => {
  let executed;
  const database = {
    async query(sql, values) {
      executed = { sql, values };
      return { rows: [{ id: requestId }], rowCount: 1 };
    }
  };
  await withRouter(
    createRequestsRouter({ database, authenticate: actorAuth }),
    "/api/requests",
    async (baseUrl) => {
      const response = await send(baseUrl, "POST", "/api/requests", {
        id: requestId,
        brand: "Toyota",
        max_price: 10000,
        buyer_id: otherId
      });
      assert.equal(response.status, 201);
      assert.equal(executed.values[1], userId);
      assert.match(executed.sql, /buyer_id/);
      assert.equal(executed.values.includes(otherId), false);
    }
  );
});

test("message sending derives sender and block check from the authenticated user", async () => {
  const statements = [];
  const database = {
    async query(sql, values) {
      statements.push({ sql, values });
      return { rows: [{ id: "f1f6b1a2-c3d4-4e5f-8a9b-0c1d2e3f4a5b" }], rowCount: 1 };
    }
  };
  await withRouter(
    createOffersRouter({ database, authenticate: actorAuth }),
    "/api/offers",
    async (baseUrl) => {
      const response = await send(
        baseUrl,
        "POST",
        `/api/offers/${offerId}/messages`,
        { body: "Hello", sender_id: otherId }
      );
      assert.equal(response.status, 201);
      assert.equal(statements[0].values[1], userId);
      assert.match(statements[0].sql, /NOT EXISTS\s*\(\s*SELECT 1 FROM public\.user_blocks/);
      assert.equal(statements[0].values.includes(otherId), false);
    }
  );
});

test("message history checks membership and mutual blocks before reading", async () => {
  const queries = [];
  const database = {
    async query(sql, values) {
      queries.push({ sql, values });
      return queries.length === 1
        ? { rowCount: 1, rows: [{ id: offerId }] }
        : { rowCount: 0, rows: [] };
    }
  };
  await withRouter(
    createOffersRouter({ database, authenticate: actorAuth }),
    "/api/offers",
    async (baseUrl) => {
      const response = await send(
        baseUrl,
        "GET",
        `/api/offers/${offerId}/messages`
      );
      assert.equal(response.status, 200);
      assert.equal(queries[0].values[1], userId);
      assert.match(queries[0].sql, /NOT EXISTS\s*\(\s*SELECT 1 FROM public\.user_blocks/);
      assert.equal(queries[1].values[0], offerId);
    }
  );
});

test("market listing deletion is scoped to the authenticated user", async () => {
  let executed;
  const database = {
    async query(sql, values) {
      executed = { sql, values };
      return { rowCount: 1, rows: [{ id: carId }] };
    }
  };
  await withRouter(
    createMarketRouter({ database, authenticate: actorAuth }),
    "/api/market",
    async (baseUrl) => {
      const response = await send(
        baseUrl,
        "DELETE",
        `/api/market/items/${carId}`
      );
      assert.equal(response.status, 200);
      assert.deepEqual(await response.json(), {
        success: true,
        data: { id: carId }
      });
      assert.deepEqual(executed.values, [carId, userId]);
      assert.match(executed.sql, /WHERE id = \$1 AND user_id = \$2/);
    }
  );
});

test("car search validates filters and parameterizes values", async () => {
  let executed;
  const database = {
    async query(sql, values) {
      executed = { sql, values };
      return { rows: [] };
    }
  };
  await withRouter(createCarsRouter({ database }), "/api/cars", async (baseUrl) => {
    const filters = [
      {
        clauses: [
          { column: "city", operator: "ilike", value: "%Baghdad%" },
          { column: "province", operator: "ilike", value: "%Baghdad%" }
        ]
      },
      { column: "year", operator: "gte", value: "2020" }
    ];
    const response = await fetch(
      `${baseUrl}/api/cars/search?filters=${encodeURIComponent(JSON.stringify(filters))}&limit=17&offset=34`
    );
    assert.equal(response.status, 200);
    assert.match(executed.sql, /c\.is_approved = TRUE/);
    assert.match(executed.sql, /ILIKE/);
    assert.match(executed.sql, / OR /);
    assert.deepEqual(executed.values, ["%Baghdad%", "%Baghdad%", 2020, 17, 34]);

    const invalid = await fetch(
      `${baseUrl}/api/cars/search?filters=${encodeURIComponent(JSON.stringify([{ column: "user_id", operator: "eq", value: otherId }]))}`
    );
    assert.equal(invalid.status, 400);
  });
});

test("most-liked cars are public, approved-only, and ordered by favorite count", async () => {
  let executed;
  const rows = [
    { id: carId, brand: "Toyota", model: "Corolla", favorite_count: 12 },
    { id: requestId, brand: "Honda", model: "Civic", favorite_count: 4 }
  ];
  let authCalls = 0;
  const database = {
    async query(sql, values) {
      executed = { sql, values };
      return { rows };
    }
  };
  await withRouter(
    createCarsRouter({
      database,
      authenticate(_req, _res, next) {
        authCalls++;
        next();
      }
    }),
    "/api/cars",
    async (baseUrl) => {
      const response = await fetch(`${baseUrl}/api/cars/most-liked?limit=7`);
      assert.equal(response.status, 200);
      const json = await response.json();
      assert.deepEqual(json.data.map((car) => car.favorite_count), [12, 4]);
      assert.equal(json.data[0].model, "Corolla");
      assert.equal(json.data[0].user_id, undefined);
      assert.deepEqual(executed.values, [7]);
      assert.match(executed.sql, /FROM public\.cars c/);
      assert.match(executed.sql, /LEFT JOIN/);
      assert.match(executed.sql, /COUNT\(DISTINCT user_id\)::int AS favorite_count/);
      assert.match(executed.sql, /item_type = 'car'/);
      assert.match(executed.sql, /WHERE c\.is_approved = TRUE/);
      assert.match(executed.sql, /ORDER BY COALESCE\(f\.favorite_count, 0\) DESC/);
      assert.equal(authCalls, 0);
    }
  );
});

test("saved searches take ownership from the authenticated identity", async () => {
  let executed;
  const database = {
    async query(sql, values) {
      executed = { sql, values };
      return { rows: [{ id: requestId }] };
    }
  };
  await withRouter(
    createActivityRouter({ database, authenticate: actorAuth }),
    "/api/activity",
    async (baseUrl) => {
      const response = await send(baseUrl, "POST", "/api/activity/saved-searches", {
        user_id: otherId,
        brand: "Toyota",
        min_year: 2020
      });
      assert.equal(response.status, 201);
      assert.equal(executed.values[0], userId);
      assert.equal(executed.values.includes(otherId), false);
      assert.match(executed.sql, /INSERT INTO public\.saved_searches/);
    }
  );
});

test("saved searches require at least one criterion and ordered ranges", async () => {
  let calls = 0;
  const database = {
    async query() {
      calls++;
      return { rows: [{ id: requestId }] };
    }
  };
  await withRouter(
    createActivityRouter({ database, authenticate: actorAuth }),
    "/api/activity",
    async (baseUrl) => {
      const empty = await send(
        baseUrl,
        "POST",
        "/api/activity/saved-searches",
        { brand: "  " }
      );
      assert.equal(empty.status, 400);
      const reversed = await send(
        baseUrl,
        "POST",
        "/api/activity/saved-searches",
        { min_year: 2024, max_year: 2020 }
      );
      assert.equal(reversed.status, 400);
      const fractionalYear = await send(
        baseUrl,
        "POST",
        "/api/activity/saved-searches",
        { min_year: 2020.5 }
      );
      assert.equal(fractionalYear.status, 400);
      assert.equal(calls, 0);
    }
  );
});

test("seller reviews are scoped to requested seller ids", async () => {
  let executed;
  const database = {
    async query(sql, values) {
      executed = { sql, values };
      return { rows: [] };
    }
  };
  await withRouter(
    createSellersRouter({ database, authenticate: actorAuth }),
    "/api/sellers",
    async (baseUrl) => {
      const response = await fetch(
        `${baseUrl}/api/sellers/reviews?seller_ids=${userId},${otherId}`
      );
      assert.equal(response.status, 200);
      assert.deepEqual(executed.values, [[userId, otherId]]);
      assert.match(executed.sql, /seller_id = ANY/);
    }
  );
});

test("user reports derive reporter id and verify offer participants", async () => {
  const calls = [];
  const database = {
    async query(sql, values) {
      calls.push({ sql, values });
      return calls.length === 1
        ? { rowCount: 1, rows: [{ id: offerId }] }
        : {
            rowCount: 1,
            rows: [{ id: requestId, status: "open", created_at: "now" }]
          };
    }
  };
  await withRouter(
    createSafetyRouter({ database, authenticate: actorAuth }),
    "/api/safety",
    async (baseUrl) => {
      const response = await send(baseUrl, "POST", "/api/safety/reports", {
        id: requestId,
        reporter_id: otherId,
        reported_user_id: otherId,
        offer_id: offerId,
        reason: "harassment",
        details: "details"
      });
      assert.equal(response.status, 201);
      assert.equal(calls[0].values[1], userId);
      assert.equal(calls[1].values[1], userId);
      assert.equal(calls[1].values[2], otherId);
    }
  );
});

test("car reports derive reporter id and admin report endpoints enforce role", async () => {
  let inserted;
  const database = {
    async query(sql, values) {
      inserted = { sql, values };
      return { rowCount: 1, rows: [{ id: requestId, car_id: carId }] };
    }
  };
  await withRouter(
    createSafetyRouter({ database, authenticate: actorAuth }),
    "/api/safety",
    async (baseUrl) => {
      const response = await send(baseUrl, "POST", "/api/safety/car-reports", {
        id: requestId,
        car_id: carId,
        reporter_id: otherId,
        seller_id: otherId,
        reason: "misleading information"
      });
      assert.equal(response.status, 201);
      assert.equal(inserted.values[2], userId);

      const admin = await send(baseUrl, "GET", "/api/safety/admin/car-reports");
      assert.equal(admin.status, 403);
    }
  );
});

test("business ad public reads and counters use allowlisted filters", async () => {
  const calls = [];
  const database = {
    async query(sql, values) {
      calls.push({ sql, values });
      return { rowCount: 1, rows: [{ id: carId }] };
    }
  };
  await withRouter(
    createBusinessAdsRouter({ database }),
    "/api/business-ads",
    async (baseUrl) => {
      const active = await fetch(
        `${baseUrl}/api/business-ads/active?categories=garage,parts&limit=5&offset=2`
      );
      assert.equal(active.status, 200);
      assert.deepEqual(calls[0].values, [["garage", "parts"], 5, 2]);
      assert.match(calls[0].sql, /category = ANY/);

      const counter = await send(
        baseUrl,
        "POST",
        "/api/business-ads/events/counter",
        { ad_id: carId, counter: "views_count" }
      );
      assert.equal(counter.status, 200);
      assert.deepEqual(calls[1].values, [carId]);
      assert.match(calls[1].sql, /views_count = views_count \+ 1/);

      const invalid = await send(
        baseUrl,
        "POST",
        "/api/business-ads/events/counter",
        { ad_id: carId, counter: "user_id = 'x'" }
      );
      assert.equal(invalid.status, 400);
      assert.equal(calls.length, 2);
    }
  );
});

test("business ad public feed returns a valid empty result without a session", async () => {
  const database = {
    async query() {
      return { rowCount: 0, rows: [] };
    }
  };
  await withRouter(
    createBusinessAdsRouter({ database }),
    "/api/business-ads",
    async (baseUrl) => {
      const response = await fetch(`${baseUrl}/api/business-ads/active`);
      assert.equal(response.status, 200);
      assert.deepEqual(await response.json(), {
        success: true,
        data: []
      });
    }
  );
});

test("business ad admin decisions require admin and apply approval transactionally", async () => {
  const statements = [];
  const client = {
    async query(sql, values = []) {
      statements.push({ sql, values });
      if (sql.includes("SELECT package_id, status, payment_status")) {
        return {
          rows: [{
            package_id: requestId,
            status: "pending",
            payment_status: "unpaid"
          }]
        };
      }
      if (sql.includes("SELECT duration_days")) {
        return { rows: [{ duration_days: 14 }] };
      }
      if (sql.includes("UPDATE public.business_ads")) {
        return {
          rowCount: 1,
          rows: [{ id: carId, status: "approved", payment_status: "paid" }]
        };
      }
      return { rowCount: 0, rows: [] };
    },
    release() {}
  };
  const database = {
    connect: async () => client,
    async query() {
      throw new Error("unexpected query");
    }
  };
  const adminAuth = (req, _res, next) => {
    req.user = { id: userId, is_admin: true };
    next();
  };
  await withRouter(
    createBusinessAdsRouter({
      database,
      authenticate: (req, res, next) => {
        req.user = { id: userId, is_admin: false };
        next();
      }
    }),
    "/api/business-ads",
    async (baseUrl) => {
      const denied = await fetch(
        `${baseUrl}/api/business-ads/admin?statuses=pending`
      );
      assert.equal(denied.status, 403);
    }
  );
  await withRouter(
    createBusinessAdsRouter({ database, authenticate: adminAuth }),
    "/api/business-ads",
    async (baseUrl) => {
      const response = await send(
        baseUrl,
        "PATCH",
        `/api/business-ads/admin/${carId}/decision`,
        {
          status: "approved",
          expected_status: "pending",
          expected_payment_status: "unpaid"
        }
      );
      assert.equal(response.status, 200);
      assert.deepEqual((await response.json()).data, {
        id: carId,
        status: "approved",
        payment_status: "paid"
      });
      assert.equal(statements[0].sql, "BEGIN");
      assert.match(statements[1].sql, /FOR UPDATE/);
      assert.equal(statements[2].values[0], requestId);
      assert.equal(statements[3].values[1], 14);
      assert.equal(statements.at(-1).sql, "COMMIT");
    }
  );
});

test("market listing creation derives owner and refuses missing UGC consent", async () => {
  const statements = [];
  const database = {
    async query(sql, values) {
      statements.push({ sql, values });
      return { rowCount: 1, rows: [{ id: carId }] };
    }
  };
  const image = `https://storage.example/storage/v1/object/public/cars/${userId}/market_draft/${carId}.png`;
  await withRouter(
    createMarketRouter({
      database,
      authenticate: actorAuth,
      storageUrl: "https://storage.example",
      policy: { hasAccepted: async () => false }
    }),
    "/api/market",
    async (baseUrl) => {
      const denied = await send(baseUrl, "POST", "/api/market/items", {
        id: carId,
        title: "Test part",
        price: 250,
        images: [image, image]
      });
      assert.equal(denied.status, 403);
      assert.equal(statements.length, 0);
    }
  );
  await withRouter(
    createMarketRouter({
      database,
      authenticate: actorAuth,
      storageUrl: "https://storage.example",
      policy: { hasAccepted: async () => true }
    }),
    "/api/market",
    async (baseUrl) => {
      const response = await send(baseUrl, "POST", "/api/market/items", {
        id: carId,
        user_id: otherId,
        title: "Test part",
        price: 250,
        images: [image, image],
        is_approved: true
      });
      assert.equal(response.status, 201);
      assert.equal(statements[0].values[1], userId);
      assert.equal(statements[0].values.includes(otherId), false);
      assert.match(statements[0].sql, /is_approved\)/);
      assert.match(statements[0].sql, /FALSE/);
    }
  );
});

test("market image updates lock owner row and retain existing external images", async () => {
  const oldImage = "https://old-storage.example/legacy.png";
  const newImage = `https://storage.example/storage/v1/object/public/cars/${userId}/market_draft/${carId}.png`;
  const statements = [];
  const client = {
    async query(sql, values = []) {
      statements.push({ sql, values });
      if (sql.includes("SELECT id, images")) {
        return { rows: [{ id: carId, images: [oldImage] }], rowCount: 1 };
      }
      if (sql.includes("UPDATE public.market_items")) {
        return { rows: [{ id: carId }], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    },
    release() {}
  };
  await withRouter(
    createMarketRouter({
      database: { connect: async () => client },
      authenticate: actorAuth,
      storageUrl: "https://storage.example",
      policy: { hasAccepted: async () => true }
    }),
    "/api/market",
    async (baseUrl) => {
      const response = await send(
        baseUrl,
        "PATCH",
        `/api/market/items/${carId}/images`,
        { images: [oldImage, newImage] }
      );
      assert.equal(response.status, 200);
      assert.equal(statements[0].sql, "BEGIN");
      assert.match(statements[1].sql, /user_id = \$2[\s\S]*FOR UPDATE/);
      assert.deepEqual(statements[1].values, [carId, userId]);
      assert.deepEqual(statements[2].values, [carId, userId, [oldImage, newImage]]);
      assert.equal(statements.at(-1).sql, "COMMIT");
    }
  );
});

test("upload proxy enforces caller-owned paths and forwards the user token", async () => {
  const calls = [];
  await withRouter(
    createUploadsRouter({
      authenticate: actorAuth,
      supabaseUrl: "https://storage.example",
      publishableKey: "publishable",
      fetchImpl: async (url, options) => {
        calls.push({ url, options });
        return new Response("{}", { status: 200 });
      }
    }),
    "/api/uploads",
    async (baseUrl) => {
      const bytes = Buffer.from(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ",
        "base64"
      );
      const path = `${userId}/market_draft/${carId}.png`;
      const response = await fetch(
        `${baseUrl}/api/uploads/object?bucket=cars&path=${encodeURIComponent(path)}`,
        {
          method: "PUT",
          headers: {
            authorization: "Bearer user-session-token",
            "content-type": "image/png"
          },
          body: bytes
        }
      );
      assert.equal(response.status, 201);
      assert.equal(calls.length, 1);
      assert.match(calls[0].options.headers.authorization, /^Bearer .*token$/);
      assert.match(calls[0].url, /\/storage\/v1\/object\/cars\//);

      const denied = await fetch(
        `${baseUrl}/api/uploads/object?bucket=cars&path=${encodeURIComponent(`${otherId}/market_draft/${carId}.png`)}`,
        {
          method: "PUT",
          headers: { "content-type": "image/png" },
          body: bytes
        }
      );
      assert.equal(denied.status, 400);
      assert.equal(calls.length, 1);
    }
  );
});

test("UGC consent endpoints accept only the fixed policy version", async () => {
  const calls = [];
  await withRouter(
    createUgcRouter({
      authenticate: actorAuth,
      policy: {
        async hasAccepted() {
          calls.push("status");
          return false;
        },
        async accept() {
          calls.push("accept");
          return true;
        }
      }
    }),
    "/api/ugc",
    async (baseUrl) => {
      const status = await fetch(`${baseUrl}/api/ugc/acceptance`);
      assert.equal(status.status, 200);
      assert.deepEqual((await status.json()).data, {
        accepted: false,
        policy_version: "2026-11-05"
      });

      const invalid = await send(baseUrl, "POST", "/api/ugc/acceptance", {
        policy_version: "unapproved"
      });
      assert.equal(invalid.status, 400);

      const accepted = await send(baseUrl, "POST", "/api/ugc/acceptance", {
        policy_version: "2026-11-05"
      });
      assert.equal(accepted.status, 200);
      assert.deepEqual(calls, ["status", "accept"]);
    }
  );
});

test("admin ad deletion requires admin, validates table and id, and audits deletion", async () => {
  const statements = [];
  const client = {
    async query(sql, values = []) {
      statements.push({ sql, values });
      if (sql.includes("DELETE FROM public.cars")) {
        return { rowCount: 1, rows: [{ id: carId }] };
      }
      if (sql.includes("INSERT INTO public.admin_ad_deletions")) {
        return { rowCount: 1, rows: [] };
      }
      return { rowCount: 0, rows: [] };
    },
    release() {}
  };
  const database = {
    connect: async () => client,
    async query(sql, values) {
      return client.query(sql, values);
    }
  };

  const nonAdminAuth = (req, _res, next) => {
    req.user = { id: userId, is_admin: false };
    next();
  };
  const adminAuth = (req, _res, next) => {
    req.user = { id: otherId, is_admin: true };
    next();
  };

  await withRouter(
    createMarketRouter({ database, authenticate: nonAdminAuth }),
    "/api/market",
    async (baseUrl) => {
      const response = await send(
        baseUrl,
        "DELETE",
        `/api/market/admin/ads/cars/${carId}`
      );
      assert.equal(response.status, 403);
      const body = await response.json();
      assert.equal(body.ok, false);
      assert.equal(body.reason, "not_admin");
    }
  );

  await withRouter(
    createMarketRouter({ database, authenticate: adminAuth }),
    "/api/market",
    async (baseUrl) => {
      const response = await send(
        baseUrl,
        "DELETE",
        `/api/market/admin/ads/profiles/${carId}`
      );
      assert.equal(response.status, 400);
      const body = await response.json();
      assert.equal(body.ok, false);
      assert.equal(body.reason, "table_not_allowed");
    }
  );

  await withRouter(
    createMarketRouter({ database, authenticate: adminAuth }),
    "/api/market",
    async (baseUrl) => {
      const response = await send(
        baseUrl,
        "DELETE",
        "/api/market/admin/ads/cars/invalid-id"
      );
      assert.equal(response.status, 400);
      const body = await response.json();
      assert.equal(body.ok, false);
      assert.equal(body.reason, "bad_id");
    }
  );

  const notFoundClient = {
    async query(sql, values = []) {
      statements.push({ sql, values });
      return { rowCount: 0, rows: [] };
    },
    release() {}
  };
  await withRouter(
    createMarketRouter({
      database: { connect: async () => notFoundClient },
      authenticate: adminAuth
    }),
    "/api/market",
    async (baseUrl) => {
      const response = await send(
        baseUrl,
        "DELETE",
        `/api/market/admin/ads/cars/${carId}`
      );
      assert.equal(response.status, 404);
      const body = await response.json();
      assert.equal(body.ok, false);
      assert.equal(body.reason, "not_found");
    }
  );

  statements.length = 0;
  await withRouter(
    createMarketRouter({ database, authenticate: adminAuth }),
    "/api/market",
    async (baseUrl) => {
      const response = await send(
        baseUrl,
        "DELETE",
        `/api/market/admin/ads/cars/${carId}`
      );
      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(body.ok, true);
      assert.equal(body.deleted, 1);
      assert.equal(body.data.id, carId);
      assert.equal(body.data.table, "cars");

      assert.equal(statements[0].sql, "BEGIN");
      assert.match(statements[1].sql, /DELETE FROM public\.cars\s+WHERE id = \$1/);
      assert.equal(statements[1].values[0], carId);
      assert.match(statements[3].sql, /INSERT INTO public\.admin_ad_deletions/);
      assert.deepEqual(statements[3].values, ["cars", carId, otherId]);
      assert.equal(statements.at(-1).sql, "COMMIT");
    }
  );
});
