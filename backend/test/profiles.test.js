import assert from "node:assert/strict";
import test from "node:test";
import { createProfilesRouter } from "../routes/profiles.js";

const userId = "d1f6b1a2-c3d4-4e5f-8a9b-0c1d2e3f4a5b";

function mockResponse() {
  const res = { statusCode: 200, body: null, status(c){res.statusCode=c;return res;}, json(d){res.body=d;return res;} };
  return res;
}

function findRoute(router, method, path) {
  return router.stack.find((l) => l.route && l.route.path === path && l.route.methods[method]);
}

test("profiles username: valid name", async () => {
  let captured;
  const client = {
    query: async (sql, vals) => {
      if (sql === "BEGIN" || sql === "COMMIT" || sql === "ROLLBACK") return { rows: [], rowCount: 0 };
      if (sql.includes("UNION ALL") && sql.includes("LIMIT 1")) return { rows: [], rowCount: 0 };
      if (sql.includes("UPDATE public.profiles") && sql.includes("RETURNING")) { captured = vals; return { rows: [{ id: userId }], rowCount: 1 }; }
      if (sql.includes("UPDATE public.app_users")) { captured = vals; return { rows: [], rowCount: 1 }; }
      return { rows: [], rowCount: 1 };
    },
    release() {},
  };
  const db = { connect: async () => client };
  const router = createProfilesRouter({ database: db, authenticate: (req,_res,next)=>{req.user={id:userId};next();} });
  const req = { method:"POST", url:"/username", body:{username:"Alice_99"}, user:{id:userId} };
  const res = mockResponse();
  await findRoute(router,"post","/username").route.stack[0].handle(req,res);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.success, true);
  assert.equal(captured[1], "alice_99");
  assert.equal(captured[0], userId);
});

test("profiles username: too short/long", async () => {
  const db = { query: async () => ({ rows: [], rowCount: 1 }) };
  const router = createProfilesRouter({ database: db, authenticate: (req,_res,next)=>{req.user={id:userId};next();} });
  for (const name of ["ab", "a".repeat(25)]) {
    const req = { method:"POST", url:"/username", body:{username:name}, user:{id:userId} };
    const res = mockResponse();
    await findRoute(router,"post","/username").route.stack[0].handle(req,res);
    assert.equal(res.statusCode, 400);
  }
});

test("profiles username: invalid chars", async () => {
  const db = { query: async () => ({ rows: [], rowCount: 1 }) };
  const router = createProfilesRouter({ database: db, authenticate: (req,_res,next)=>{req.user={id:userId};next();} });
  const req = { method:"POST", url:"/username", body:{username:"bad name!"}, user:{id:userId} };
  const res = mockResponse();
  await findRoute(router,"post","/username").route.stack[0].handle(req,res);
  assert.equal(res.statusCode, 400);
});

// unauthenticated handled by middleware (not unit-tested here)

test("profiles username: update current user", async () => {
  let calls = 0;
  const client = {
    query: async (sql) => {
      if (sql === "BEGIN" || sql === "COMMIT" || sql === "ROLLBACK") return { rows: [], rowCount: 0 };
      if (sql.includes("UNION ALL") && sql.includes("LIMIT 1")) return { rows: [], rowCount: 0 };
      if (sql.includes("UPDATE public.profiles") && sql.includes("RETURNING")) { calls++; return { rows: [{ id: userId }], rowCount: 1 }; }
      if (sql.includes("UPDATE public.app_users")) { calls++; return { rows: [], rowCount: 1 }; }
      return { rows: [], rowCount: 1 };
    },
    release() {},
  };
  const db = { connect: async () => client };
  const router = createProfilesRouter({ database: db, authenticate: (req,_res,next)=>{req.user={id:userId};next();} });
  const req = { method:"POST", url:"/username", body:{username:"new_name"}, user:{id:userId} };
  const res = mockResponse();
  await findRoute(router,"post","/username").route.stack[0].handle(req,res);
  assert.equal(res.statusCode, 200);
  assert.equal(calls, 2);
});
