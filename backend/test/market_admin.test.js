import assert from "node:assert/strict";
import test from "node:test";
import { createMarketRouter } from "../routes/market.js";

const userId = "d1f6b1a2-c3d4-4e5f-8a9b-0c1d2e3f4a5b";
const otherId = "a1f6b1a2-c3d4-4e5f-8a9b-0c1d2e3f4a5b";
const carId = "b1f6b1a2-c3d4-4e5f-8a9b-0c1d2e3f4a5b";

function mockResponse() {
  const res = {
    statusCode: 200,
    body: null,
    status(code) {
      res.statusCode = code;
      return res;
    },
    json(data) {
      res.body = data;
      return res;
    }
  };
  return res;
}

test("admin delete listing unit mocks: reject non-admin", async () => {
  const router = createMarketRouter({
    database: {},
    authenticate: (req, _res, next) => {
      req.user = { id: userId, is_admin: false };
      next();
    }
  });

  const req = {
    method: "DELETE",
    url: `/admin/ads/cars/${carId}`,
    params: { table: "cars", id: carId },
    user: { id: userId, is_admin: false }
  };
  const res = mockResponse();

  // Find the route handler from router stack
  const route = router.stack.find(
    (layer) => layer.route && layer.route.path === "/admin/ads/:table/:id" && layer.route.methods.delete
  );
  assert.ok(route, "Admin delete route should be registered");

  await route.route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 403);
  assert.equal(res.body.ok, false);
  assert.equal(res.body.reason, "not_admin");
});

test("admin delete listing unit mocks: reject invalid table", async () => {
  const router = createMarketRouter({
    database: {},
    authenticate: (req, _res, next) => next()
  });

  const req = {
    method: "DELETE",
    url: `/admin/ads/profiles/${carId}`,
    params: { table: "profiles", id: carId },
    user: { id: otherId, is_admin: true }
  };
  const res = mockResponse();

  const route = router.stack.find(
    (layer) => layer.route && layer.route.path === "/admin/ads/:table/:id" && layer.route.methods.delete
  );
  await route.route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 400);
  assert.equal(res.body.ok, false);
  assert.equal(res.body.reason, "table_not_allowed");
});

test("admin delete listing unit mocks: reject bad id", async () => {
  const router = createMarketRouter({
    database: {},
    authenticate: (req, _res, next) => next()
  });

  const req = {
    method: "DELETE",
    url: `/admin/ads/cars/invalid-uuid`,
    params: { table: "cars", id: "invalid-uuid" },
    user: { id: otherId, is_admin: true }
  };
  const res = mockResponse();

  const route = router.stack.find(
    (layer) => layer.route && layer.route.path === "/admin/ads/:table/:id" && layer.route.methods.delete
  );
  await route.route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 400);
  assert.equal(res.body.ok, false);
  assert.equal(res.body.reason, "bad_id");
});

test("admin delete listing unit mocks: not found", async () => {
  const statements = [];
  const client = {
    async query(sql, values = []) {
      statements.push({ sql, values });
      return { rowCount: 0, rows: [] };
    },
    release() {}
  };

  const router = createMarketRouter({
    database: { connect: async () => client },
    authenticate: (req, _res, next) => next()
  });

  const req = {
    method: "DELETE",
    url: `/admin/ads/cars/${carId}`,
    params: { table: "cars", id: carId },
    user: { id: otherId, is_admin: true }
  };
  const res = mockResponse();

  const route = router.stack.find(
    (layer) => layer.route && layer.route.path === "/admin/ads/:table/:id" && layer.route.methods.delete
  );
  await route.route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 404);
  assert.equal(res.body.ok, false);
  assert.equal(res.body.reason, "not_found");
  assert.equal(statements[0].sql, "BEGIN");
  assert.equal(statements[2].sql, "ROLLBACK");
});

test("admin delete listing unit mocks: successful delete and audit", async () => {
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

  const router = createMarketRouter({
    database: { connect: async () => client },
    authenticate: (req, _res, next) => next()
  });

  const req = {
    method: "DELETE",
    url: `/admin/ads/cars/${carId}`,
    params: { table: "cars", id: carId },
    user: { id: otherId, is_admin: true }
  };
  const res = mockResponse();

  const route = router.stack.find(
    (layer) => layer.route && layer.route.path === "/admin/ads/:table/:id" && layer.route.methods.delete
  );
  await route.route.stack[0].handle(req, res);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.ok, true);
  assert.equal(res.body.deleted, 1);
  assert.equal(res.body.data.id, carId);
  assert.equal(res.body.data.table, "cars");

  assert.equal(statements[0].sql, "BEGIN");
  assert.match(statements[1].sql, /DELETE FROM public\.cars\s+WHERE id = \$1/);
  assert.equal(statements[1].values[0], carId);
  assert.match(statements[3].sql, /INSERT INTO public\.admin_ad_deletions/);
  assert.deepEqual(statements[3].values, ["cars", carId, otherId]);
  assert.equal(statements.at(-1).sql, "COMMIT");
});
