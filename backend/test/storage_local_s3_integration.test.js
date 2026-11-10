import assert from "node:assert/strict";
import test from "node:test";
import crypto from "node:crypto";
import net from "node:net";
import pg from "pg";
import dotenv from "dotenv";
import express from "express";
import { S3Client, CreateBucketCommand, HeadBucketCommand, DeleteObjectsCommand, ListObjectsV2Command } from "@aws-sdk/client-s3";
import { createAuthRouter } from "../routes/auth.js";
import { createCurrentUserAuthenticator } from "../middleware/current_user.js";
import { createCarsRouter } from "../routes/cars.js";
import { createStorageRouter } from "../routes/storage.js";
import { createObjectStorageService } from "../services/objectStorage.js";

dotenv.config({ path: ".env.test", override: true });
const RUN = process.env.LOCAL_S3_INTEGRATION === "1";
const S3_ENDPOINT = process.env.LOCAL_S3_ENDPOINT || "http://127.0.0.1:4566";
const S3_BUCKET = process.env.LOCAL_S3_BUCKET || "cars";
const S3_CREDS = { accessKeyId: "S3RVER", secretAccessKey: "S3RVER" }; // local s3rver test defaults only
const TEST_SECRET = process.env.JWT_SECRET;

const maybe = RUN ? test : test.skip;

function portReachable(url) {
  return new Promise((resolve) => {
    try {
      const u = new URL(url);
      const s = net.connect(Number(u.port || 80), u.hostname);
      const t = setTimeout(() => { s.destroy(); resolve(false); }, 1000);
      s.on("connect", () => { clearTimeout(t); s.end(); resolve(true); });
      s.on("error", () => { clearTimeout(t); resolve(false); });
    } catch { resolve(false); }
  });
}
function pngBytes() { return Buffer.from([137,80,78,71,13,10,26,10,0,0,0,13,73,72,68,82,0,0,0,1,0,0,0,1,8,6,0,0,0,31,21,196,137,0,0,0,10,73,68,65,84,120,156,99,0,1,0,0,5,0,1,13,10,45,180,0,0,0,0,73,69,78,68,174,66,96,130]); }
async function postJson(base, path, body, headers={}){ const r=await fetch(base+path,{method:"POST",headers:{"content-type":"application/json",...headers},body:JSON.stringify(body)}); const t=await r.text(); let j; try{j=JSON.parse(t)}catch{j={_raw:t}}; return {status:r.status,body:j}; }
async function putRaw(base, path, body, headers={}){ const r=await fetch(base+path,{method:"PUT",headers,body}); const t=await r.text(); let j; try{j=JSON.parse(t)}catch{j={_raw:t}}; return {status:r.status,body:j,headers:r.headers}; }
async function getRaw(base, path, headers={}){ const r=await fetch(base+path,{headers}); if((r.headers.get('content-type')||'').includes('json')){ const j=await r.json().catch(()=>null); return {status:r.status,body:j,headers:r.headers}; } const buf=Buffer.from(await r.arrayBuffer()); return {status:r.status,body:buf,headers:r.headers}; }
async function delJson(base, path, headers={}){ const r=await fetch(base+path,{method:"DELETE",headers}); const t=await r.text(); let j; try{j=JSON.parse(t)}catch{j={_raw:t}}; return {status:r.status,body:j}; }

maybe("G10.42.25 local s3rver + motri_iq_test storage route integration (opt-in)", async (t) => {
  assert.ok(TEST_SECRET && TEST_SECRET.length >= 64, "JWT_SECRET missing/short in .env.test");
  assert.ok(await portReachable(S3_ENDPOINT), `local s3 endpoint unreachable: ${S3_ENDPOINT}`);
  const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false }, max: 6 });
  const dbInfo = (await pool.query("select current_database() db, current_user usr")).rows[0];
  assert.equal(dbInfo.db, "motri_iq_test", "ISOLATION: must run against motri_iq_test");

  const s3 = new S3Client({ endpoint: S3_ENDPOINT, region: "us-east-1", forcePathStyle: true, credentials: S3_CREDS });
  try { await s3.send(new HeadBucketCommand({ Bucket: S3_BUCKET })); } catch { await s3.send(new CreateBucketCommand({ Bucket: S3_BUCKET })); }

  const storage = createObjectStorageService({ endpoint: S3_ENDPOINT, accessKeyId: S3_CREDS.accessKeyId, secretAccessKey: S3_CREDS.secretAccessKey, region: "us-east-1", bucket: S3_BUCKET, database: pool });
  const app = express(); app.use(express.json());
  delete process.env.SUPABASE_URL; delete process.env.SUPABASE_PUBLISHABLE_KEY;
  const authMw = createCurrentUserAuthenticator({ database: pool, supabaseUrl: null, publishableKey: null });
  app.use("/api/auth", createAuthRouter({ database: pool, jwtSecret: TEST_SECRET }));
  app.use("/api/cars", createCarsRouter({ database: pool, authenticate: authMw }));
  app.use("/api/storage", createStorageRouter({ authenticate: authMw, storage, database: pool }));
  const server = app.listen(0,"127.0.0.1"); await new Promise(r=>server.once("listening",r));
  const base = `http://127.0.0.1:${server.address().port}`;
  const tag = `g104225_${Date.now()}`; const created = { users: [], keys: [] };

  try {
    const mk = async (n)=>{ const email=`${tag}_${n}@example.test`; const reg=await postJson(base,"/api/auth/register",{email,username:`${tag.slice(-8)}${n}`.slice(0,24),password:"G10.42.25!Disposable",full_name:"S3"}); assert.equal(reg.status,201); created.users.push(reg.body.user.id); return {id:reg.body.user.id, H:{authorization:`Bearer ${reg.body.access_token}`}}; };
    const u1=await mk(1), u2=await mk(2);
    const submission=crypto.randomUUID(), photo=crypto.randomUUID();
    const resv = await postJson(base,"/api/cars/uploads/reserve",{submission_id:submission,photo_id:photo,extension:"png"},u1.H);
    assert.equal(resv.status, 201);
    const objectKey = resv.body.data.object_key; created.keys.push(objectKey);
    const img = pngBytes(); const sha = crypto.createHash('sha256').update(img).digest('hex');

    const put = await putRaw(base, `/api/storage/object?bucket=cars&path=${encodeURIComponent(objectKey)}`, img, {...u1.H, 'content-type':'image/png'});
    assert.equal(put.status, 201, `PUT: ${JSON.stringify(put.body)}`);

    const head = await storage.headObject({ bucket: S3_BUCKET, key: objectKey });
    assert.ok(Number(head.size) > 0);

    // Integrity: direct S3 GET (local s3rver) proves storage round-trip/SHA256.
    // Route GET for bucket=cars enforces ownership via cars.image_url binding (storage checker);
    // pending (reserved, unbound) keys are not claimable via that path without weakening checks.
    const { GetObjectCommand } = await import("@aws-sdk/client-s3");
    const s3Get = await s3.send(new GetObjectCommand({ Bucket: S3_BUCKET, Key: objectKey }));
    const downloaded = Buffer.from(await s3Get.Body.transformToByteArray());
    assert.equal(crypto.createHash('sha256').update(downloaded).digest('hex'), sha, "SHA256 integrity (direct S3 GET)");

    const noResv = await putRaw(base, `/api/storage/object?bucket=cars&path=${encodeURIComponent(`${u1.id}/${crypto.randomUUID()}/${crypto.randomUUID()}.png`)}`, img, {...u1.H,'content-type':'image/png'});
    assert.equal(noResv.status, 403);

    await pool.query("update public.car_image_upload_reservations set expires_at=now()-interval '5 minutes' where user_id=$1 and submission_id=$2 and photo_id=$3",[u1.id,submission,photo]);
    const expPut = await putRaw(base, `/api/storage/object?bucket=cars&path=${encodeURIComponent(objectKey)}`, img, {...u1.H,'content-type':'image/png'});
    assert.equal(expPut.status, 403);
    await pool.query("update public.car_image_upload_reservations set expires_at=now()+interval '30 minutes' where user_id=$1 and submission_id=$2 and photo_id=$3",[u1.id,submission,photo]);

    // Cross-user route GET (ownership enforced): u2 must not access u1's key.
    const xUser = await getRaw(base, `/api/storage/object?bucket=cars&path=${encodeURIComponent(objectKey)}`, u2.H);
    assert.equal(xUser.status, 403);

    const badType = await putRaw(base, `/api/storage/object?bucket=cars&path=${encodeURIComponent(objectKey)}`, Buffer.from('notpng'), {...u1.H,'content-type':'image/png'});
    assert.equal(badType.status, 400);

    // Bind object to owned car row so route-level ownership checks (cars.image_url) can authorize.
    await pool.query(
      `INSERT INTO public.cars (id,user_id,title,brand,model,year,price,image_url,is_approved,status)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,false,'active')`,
      [submission, u1.id, "g104225", "T", "M", 2024, 1, objectKey]
    );
    const getBound = await getRaw(base, `/api/storage/object?bucket=cars&path=${encodeURIComponent(objectKey)}`, u1.H);
    assert.equal(getBound.status, 200);
    assert.equal(crypto.createHash('sha256').update(getBound.body).digest('hex'), sha, "SHA256 integrity (route GET, bound owner)");

    const del = await delJson(base, `/api/storage/object?bucket=cars&path=${encodeURIComponent(objectKey)}`, u1.H);
    assert.ok(del.status === 200 || del.status === 204, `DELETE route: ${del.status} ${JSON.stringify(del.body)}`);
    await assert.rejects(()=>storage.headObject({bucket:S3_BUCKET,key:objectKey}), (e)=>e?.statusCode===404||/NotFound|404/i.test(e?.name+e?.message));

  } finally {
    // cleanup S3 + DB
    try { if(created.keys.length) await s3.send(new DeleteObjectsCommand({Bucket:S3_BUCKET, Delete:{Objects:created.keys.map(Key=>({Key})), Quiet:true}})); } catch {}
    await new Promise(r=>server.close(r));
    if (created.users.length) {
      await pool.query(`delete from public.cars where user_id=any($1::uuid[])`,[created.users]).catch(()=>{});
      await pool.query(`delete from public.car_image_upload_reservations where user_id=any($1::uuid[])`,[created.users]);
      await pool.query(`delete from public.app_sessions where user_id=any($1::uuid[])`,[created.users]);
      await pool.query(`delete from public.profiles where id=any($1::uuid[])`,[created.users]).catch(()=>{});
      await pool.query(`delete from public.app_admins where user_id=any($1::uuid[])`,[created.users]).catch(()=>{});
      await pool.query(`delete from public.app_users where id=any($1::uuid[])`,[created.users]);
    }
    await pool.end(); s3.destroy();
  }
});
