import assert from "node:assert/strict";
import test from "node:test";
import { createWalletRouter } from "../routes/wallet.js";

const userId = "d1f6b1a2-c3d4-4e5f-8a9b-0c1d2e3f4a5b";
const adminId = "a1f6b1a2-c3d4-4e5f-8a9b-0c1d2e3f4a5b";
const txId = "b1f6b1a2-c3d4-4e5f-8a9b-0c1d2e3f4a5b";

function mockResponse() {
  const res = { statusCode: 200, body: null, status(c){res.statusCode=c;return res;}, json(d){res.body=d;return res;} };
  return res;
}

function findRoute(router, method, path) {
  return router.stack.find((l) => l.route && l.route.path === path && l.route.methods[method]);
}

test("wallet topup: successful creation", async () => {
  const db = { query: async () => ({ rows: [{ id: txId }], rowCount: 1 }) };
  const router = createWalletRouter({ database: db, authenticate: (req,_res,next)=>{req.user={id:userId};next();} });
  const req = { method:"POST", url:"/topups", body:{amount:5000}, user:{id:userId} };
  const res = mockResponse();
  await findRoute(router,"post","/topups").route.stack[0].handle(req,res);
  assert.equal(res.statusCode, 201);
  assert.equal(res.body.success, true);
  assert.equal(res.body.data.id, txId);
});

test("wallet topup: invalid amount", async () => {
  const db = { query: async () => ({ rows: [], rowCount: 0 }) };
  const router = createWalletRouter({ database: db, authenticate: (req,_res,next)=>{req.user={id:userId};next();} });
  for (const amount of [0, -5, 0.5]) {
    const req = { method:"POST", url:"/topups", body:{amount}, user:{id:userId} };
    const res = mockResponse();
    await findRoute(router,"post","/topups").route.stack[0].handle(req,res);
    assert.equal(res.statusCode, 400);
  }
});

test("wallet topup: user_id from req.user only", async () => {
  let captured;
  const db = { query: async (_sql, vals) => { captured = vals; return { rows: [{ id: txId }], rowCount: 1 }; } };
  const router = createWalletRouter({ database: db, authenticate: (req,_res,next)=>{req.user={id:userId};next();} });
  const req = { method:"POST", url:"/topups", body:{amount:1000}, user:{id:userId} };
  const res = mockResponse();
  await findRoute(router,"post","/topups").route.stack[0].handle(req,res);
  assert.equal(captured[0], userId);
});

test("wallet pending: returns last pending for user", async () => {
  const db = { query: async () => ({ rows: [{ id: txId, status: "pending" }], rowCount: 1 }) };
  const router = createWalletRouter({ database: db, authenticate: (req,_res,next)=>{req.user={id:userId};next();} });
  const req = { method:"GET", url:"/topups/pending", user:{id:userId} };
  const res = mockResponse();
  await findRoute(router,"get","/topups/pending").route.stack[0].handle(req,res);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.data.id, txId);
});

test("wallet decide: reject non-admin", async () => {
  const db = { query: async () => ({ rows: [], rowCount: 0 }) };
  const router = createWalletRouter({ database: db, authenticate: (req,_res,next)=>{req.user={id:userId};next();} });
  const req = { method:"POST", url:"/decide", body:{id:txId,status:"confirmed"}, user:{id:userId} };
  const res = mockResponse();
  await findRoute(router,"post","/decide").route.stack[0].handle(req,res);
  assert.equal(res.statusCode, 403);
  assert.equal(res.body.reason, "not_admin");
});

test("wallet decide: bad_id and bad_status", async () => {
  const db = { query: async () => ({ rows: [{1:1}], rowCount: 1 }) };
  const router = createWalletRouter({ database: db, authenticate: (req,_res,next)=>{req.user={id:adminId};next();} });
  const r1 = mockResponse();
  await findRoute(router,"post","/decide").route.stack[0].handle({method:"POST",url:"/decide",body:{id:"bad",status:"confirmed"},user:{id:adminId}}, r1);
  assert.equal(r1.statusCode, 400);
  assert.equal(r1.body.reason, "bad_id");
  const r2 = mockResponse();
  await findRoute(router,"post","/decide").route.stack[0].handle({method:"POST",url:"/decide",body:{id:txId,status:"pending"},user:{id:adminId}}, r2);
  assert.equal(r2.statusCode, 400);
  assert.equal(r2.body.reason, "bad_status");
});

test("wallet decide: not_found", async () => {
  const db = { query: async (sql) => {
    if (sql.includes("app_admins")) return { rows: [{1:1}], rowCount: 1 };
    return { rows: [], rowCount: 0 };
  } };
  const router = createWalletRouter({ database: db, authenticate: (req,_res,next)=>{req.user={id:adminId};next();} });
  const req = { method:"POST", url:"/decide", body:{id:txId,status:"confirmed"}, user:{id:adminId} };
  const res = mockResponse();
  await findRoute(router,"post","/decide").route.stack[0].handle(req,res);
  assert.equal(res.statusCode, 404);
  assert.equal(res.body.reason, "not_found");
});

test("wallet decide: already_decided", async () => {
  const db = { query: async (sql) => {
    if (sql.includes("app_admins")) return { rows: [{1:1}], rowCount: 1 };
    if (sql.includes("SELECT status")) return { rows: [{ status: "confirmed" }], rowCount: 1 };
    return { rows: [], rowCount: 0 };
  } };
  const router = createWalletRouter({ database: db, authenticate: (req,_res,next)=>{req.user={id:adminId};next();} });
  const req = { method:"POST", url:"/decide", body:{id:txId,status:"confirmed"}, user:{id:adminId} };
  const res = mockResponse();
  await findRoute(router,"post","/decide").route.stack[0].handle(req,res);
  assert.equal(res.statusCode, 409);
  assert.equal(res.body.reason, "already_decided");
  assert.equal(res.body.status, "confirmed");
});

test("wallet decide: confirmed and rejected success", async () => {
  for (const st of ["confirmed","rejected"]) {
    const db = { query: async (sql) => {
      if (sql.includes("app_admins")) return { rows: [{1:1}], rowCount: 1 };
      if (sql.includes("SELECT status")) return { rows: [{ status: "pending" }], rowCount: 1 };
      return { rows: [], rowCount: 1 };
    } };
    const router = createWalletRouter({ database: db, authenticate: (req,_res,next)=>{req.user={id:adminId};next();} });
    const req = { method:"POST", url:"/decide", body:{id:txId,status:st}, user:{id:adminId} };
    const res = mockResponse();
    await findRoute(router,"post","/decide").route.stack[0].handle(req,res);
    assert.equal(res.statusCode, 200);
    assert.equal(res.body.ok, true);
    assert.equal(res.body.status, st);
  }
});
