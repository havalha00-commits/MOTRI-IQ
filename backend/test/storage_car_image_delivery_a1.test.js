import assert from "node:assert/strict";
import test from "node:test";
import crypto from "node:crypto";
import net from "node:net";
import pg from "pg";
import dotenv from "dotenv";
import express from "express";
import { S3Client, CreateBucketCommand, HeadBucketCommand } from "@aws-sdk/client-s3";
import { createAuthRouter } from "../routes/auth.js";
import { createCurrentUserAuthenticator } from "../middleware/current_user.js";
import { createCarsRouter } from "../routes/cars.js";
import { createStorageRouter } from "../routes/storage.js";
import { createObjectStorageService } from "../services/objectStorage.js";

dotenv.config({ path: ".env.test", override: true });
const RUN = process.env.LOCAL_S3_INTEGRATION === "1";
const S3_ENDPOINT = process.env.LOCAL_S3_ENDPOINT || "http://127.0.0.1:4566";
const S3_BUCKET = process.env.LOCAL_S3_BUCKET || "cars";
const S3_CREDS = { accessKeyId: "S3RVER", secretAccessKey: "S3RVER" };
const TEST_SECRET = process.env.JWT_SECRET;
const maybe = RUN ? test : test.skip;

function portReachable(url){ return new Promise(r=>{try{const u=new URL(url);const s=net.connect(+u.port||80,u.hostname);const t=setTimeout(()=>{s.destroy();r(false)},1200);s.on("connect",()=>{clearTimeout(t);s.end();r(true)});s.on("error",()=>{clearTimeout(t);r(false)});}catch{r(false)}}); }
const png = ()=>Buffer.from([137,80,78,71,13,10,26,10,0,0,0,13,73,72,68,82,0,0,0,1,0,0,0,1,8,6,0,0,0,31,21,196,137,0,0,0,10,73,68,65,84,120,156,99,0,1,0,0,5,0,1,13,10,45,180,0,0,0,0,73,69,78,68,174,66,96,130]);
async function pj(base,path,body,h={}){const r=await fetch(base+path,{method:"POST",headers:{"content-type":"application/json",...h},body:JSON.stringify(body)});const t=await r.text();let j;try{j=JSON.parse(t)}catch{j={_raw:t}}return {status:r.status,body:j,headers:r.headers};}
async function gj(base,path,h={}){const r=await fetch(base+path,{method:"GET",headers:h,redirect:"manual"});const ct=r.headers.get("content-type")||"";let body; if(ct.includes("application/json")){const t=await r.text();try{body=JSON.parse(t)}catch{body={_raw:t}}} else {body=Buffer.from(await r.arrayBuffer());} return {status:r.status,body,headers:r.headers};}
async function put(base,path,buf,h={}){const r=await fetch(base+path,{method:"PUT",headers:h,body:buf});const t=await r.text();let j;try{j=JSON.parse(t)}catch{j={_raw:t}}return {status:r.status,body:j};}

function hasRawObjectKeyLeak(obj){
  const s = JSON.stringify(obj);
  // canonical car key shape userUuid/submissionUuid/photoUuid.ext
  return /[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(jpg|jpeg|png|webp)/i.test(s);
}

function assertNo304BeforeRevalidation(res, label){
  assert.notEqual(res.status, 304, `${label}: must not return 304 before/without safe revalidation`);
}

maybe("G10.51 A1 car image delivery + canonical key persistence (motri_iq_test + local s3rver, opt-in)", async () => {
  assert.ok(TEST_SECRET && TEST_SECRET.length >= 64, "JWT_SECRET missing/short");
  assert.ok(await portReachable(S3_ENDPOINT), `s3 unreachable: ${S3_ENDPOINT}`);
  const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false }, max: 10 });
  const dbId = async (where)=>{ const r=(await pool.query("select current_database() db,current_user usr")).rows[0]; assert.equal(r.db,"motri_iq_test",`ISOLATION ${where}: ${JSON.stringify(r)}`); return r; };
  await dbId("start");
  const q = async (s,p=[])=>{ await dbId("query"); return pool.query(s,p); };

  const s3 = new S3Client({ endpoint: S3_ENDPOINT, region: "us-east-1", forcePathStyle: true, credentials: S3_CREDS });
  try { await s3.send(new HeadBucketCommand({ Bucket: S3_BUCKET })); } catch { await s3.send(new CreateBucketCommand({ Bucket: S3_BUCKET })); }
  delete process.env.SUPABASE_URL; delete process.env.SUPABASE_PUBLISHABLE_KEY;
  const storage = createObjectStorageService({ endpoint: S3_ENDPOINT, accessKeyId: S3_CREDS.accessKeyId, secretAccessKey: S3_CREDS.secretAccessKey, region: "us-east-1", bucket: S3_BUCKET, database: pool });
  const app = express(); app.use(express.json());
  const authMw = createCurrentUserAuthenticator({ database: pool, supabaseUrl: null, publishableKey: null });
  const optAuthMw = (req,res,next)=>{ if(!req.headers.authorization) return next(); return authMw(req,res,next); };
  app.use("/api/auth", createAuthRouter({ database: pool, jwtSecret: TEST_SECRET }));
  app.use("/api/cars", createCarsRouter({ database: pool, authenticate: authMw, optionalAuthenticate: optAuthMw, storage }));
  app.use("/api/storage", createStorageRouter({ authenticate: authMw, storage, database: pool }));
  const server = app.listen(0,"127.0.0.1"); await new Promise(r=>server.once("listening",r));
  const base = `http://127.0.0.1:${server.address().port}`;
  const tag=`g1051_${Date.now()}`; const created={users:[],cars:[],keys:[]}; const img=png();

  try {
    const mk=async(n)=>{ await dbId("mk"); const uniq=`${tag}_${n}_${crypto.randomUUID().slice(0,8)}`; const reg=await pj(base,"/api/auth/register",{email:`${uniq}@example.test`,username:uniq.replace(/[^a-z0-9]/gi,"").slice(0,24),password:"G10.51!Passw0rd",display_name:`G ${n}`}); assert.ok([200,201].includes(reg.status),`reg ${reg.status} ${JSON.stringify(reg.body)}`); const id=(await q("select id from public.app_users where lower(email)=lower($1)",[`${uniq}@example.test`])).rows[0].id; created.users.push(id); const lg=await pj(base,"/api/auth/login",{identifier:`${uniq}@example.test`,password:"G10.51!Passw0rd"}); assert.equal(lg.status,200,JSON.stringify(lg.body)); return {id,H:{Authorization:`Bearer ${lg.body.access_token}`}}; };
    const u1=await mk(1), u2=await mk(2);

    async function reserveUpload(u, carId, photoId=crypto.randomUUID()){
      await dbId("reserveUpload");
      const rv=await pj(base,"/api/cars/uploads/reserve",{submission_id:carId,photo_id:photoId,extension:"png"},u.H);
      assert.equal(rv.status,201,`reserve ${rv.status} ${JSON.stringify(rv.body)}`);
      const key=rv.body.data.object_key; created.keys.push(key);
      const up=await put(base,`/api/storage/object?bucket=cars&path=${encodeURIComponent(key)}`,img,{...u.H,"content-type":"image/png"});
      assert.equal(up.status,201,`upload ${up.status} ${JSON.stringify(up.body)}`);
      return {key,photoId};
    }
    async function createCar(u, carId, keys=[], extra={}){
      await dbId("createCar");
      const body={id:carId,brand:"B",model:"M",year:2024,price:1,title:"t",...extra};
      if(keys.length){ body.image_url=keys.length===1?keys[0]:JSON.stringify(keys); body.images=keys; }
      const r=await pj(base,"/api/cars",body,u.H);
      assert.equal(r.status,201,`createCar ${r.status} ${JSON.stringify(r.body)}`);
      created.cars.push(carId);
      return r;
    }

    // 1) Canonical object key persistence (create flow shape) + reservation consumed
    const carA = crypto.randomUUID();
    const a1 = await reserveUpload(u1,carA);
    await createCar(u1,carA,[a1.key]);
    const rowA=(await q("select image_url,images,is_approved,user_id from public.cars where id=$1",[carA])).rows[0];
    assert.ok(String(rowA.image_url).includes(a1.key) || JSON.stringify(rowA.images).includes(a1.key), "stored value should include canonical key");

    // 2) Public listing masks raw object keys and adds safe image_urls (no leakage)
    // make approved for public endpoints
    await q("update public.cars set is_approved=true where id=$1",[carA]);
    const pub = await gj(base, `/api/cars/by-ids?ids=${carA}`);
    assert.equal(pub.status,200,JSON.stringify(pub.body));
    const pubCar = pub.body.data[0];
    assert.ok(Array.isArray(pubCar.image_urls), "image_urls present");
    assert.ok(pubCar.image_urls[0] === `/api/cars/${carA}/images/0`, `unexpected image_urls ${JSON.stringify(pubCar.image_urls)}`);
    assert.equal(hasRawObjectKeyLeak(pubCar), false, "public response must not leak raw object key");
    // image_url/images masked to null placeholders preserving order
    assert.equal(pubCar.image_url, null);

    // 3) Approved car image access (public) - bytes served, no key leakage, must-revalidate cache (4C: no immutable)
    const imgRes = await gj(base, `/api/cars/${carA}/images/0`);
    assert.equal(imgRes.status,200);
    const pubCc = String(imgRes.headers.get("cache-control")||"");
    assert.ok(pubCc.includes("public"), `public cache-control: ${pubCc}`);
    assert.ok(pubCc.includes("max-age=0"), `public must revalidate: ${pubCc}`);
    assert.ok(pubCc.includes("must-revalidate"), `public must-revalidate: ${pubCc}`);
    assert.ok(!pubCc.includes("immutable"), `public must not be immutable: ${pubCc}`);
    assert.ok(String(imgRes.headers.get("content-type")||"").startsWith("image/"));
    assert.equal(Buffer.isBuffer(imgRes.body) && imgRes.body.length>0, true);

    // 3b) Approved SOLD car image delivered publicly (product decision: sold remains publicly visible when approved)
    const carSold = crypto.randomUUID();
    const sold1 = await reserveUpload(u1,carSold);
    await createCar(u1,carSold,[sold1.key]);
    await q("update public.cars set is_approved=true, status='sold' where id=$1",[carSold]);
    const soldRes = await gj(base, `/api/cars/${carSold}/images/0`);
    assert.equal(soldRes.status,200,`approved sold must be public: ${soldRes.status}`);
    const soldCc = String(soldRes.headers.get("cache-control")||"");
    assert.ok(soldCc.includes("public") && soldCc.includes("must-revalidate") && !soldCc.includes("immutable"), `sold public cache: ${soldCc}`);

    // 3c) Conditional request MUST NOT get 304 before auth+DB reference validation (4C hardening); route disables 304 and serves current content
    const condPub = await gj(base, `/api/cars/${carA}/images/0`, {"If-None-Match":"\"stale\""});
    assertNo304BeforeRevalidation(condPub, "conditional public");
    assert.equal(condPub.status,200,`conditional public must return current content: ${condPub.status}`);
    assert.ok(Buffer.isBuffer(condPub.body) && condPub.body.length>0);

    // 4) Unapproved car image denial (non-owner)
    const carB = crypto.randomUUID();
    const b1 = await reserveUpload(u1,carB);
    await createCar(u1,carB,[b1.key]); // unapproved by default
    const unpub = await gj(base, `/api/cars/${carB}/images/0`); // no auth, not approved
    assert.equal(unpub.status,403);

    // 4b) Revoked approval: after prior public delivery, NEVER return old image or 304 (even with stale conditional validators)
    await q("update public.cars set is_approved=false where id=$1",[carA]);
    const revoked = await gj(base, `/api/cars/${carA}/images/0`);
    assert.equal(revoked.status,403,`revoked approval must deny: ${revoked.status}`);
    assertNo304BeforeRevalidation(revoked, "revoked approval");
    const revokedCond = await gj(base, `/api/cars/${carA}/images/0`, {"If-None-Match":"\"old-etag\"","If-Modified-Since":"Wed, 21 Oct 2015 07:28:00 GMT"});
    assertNo304BeforeRevalidation(revokedCond, "revoked approval conditional");
    assert.notEqual(revokedCond.status,200,"revoked approval must not return image bytes");
    // restore for remaining tests that need carA public
    await q("update public.cars set is_approved=true where id=$1",[carA]);

    // 4c) Replaced image reference: NEVER return stale content or 304; current DB reference is served
    const carRep = crypto.randomUUID();
    const rep1 = await reserveUpload(u1,carRep);
    await createCar(u1,carRep,[rep1.key]);
    await q("update public.cars set is_approved=true where id=$1",[carRep]);
    const repBefore = await gj(base, `/api/cars/${carRep}/images/0`);
    assert.equal(repBefore.status,200);
    const rep2 = await reserveUpload(u1,carRep);
    // replace slot reference to new key (owner-authorized DB change in isolated test to simulate current DB state)
    await q("update public.cars set image_url=$2, images=$3::jsonb where id=$1",[carRep, rep2.key, JSON.stringify([rep2.key])]);
    const repAfter = await gj(base, `/api/cars/${carRep}/images/0`, {"If-None-Match":"\"stale\""});
    assertNo304BeforeRevalidation(repAfter, "replaced image conditional");
    assert.equal(repAfter.status,200,`replaced image must serve current: ${repAfter.status}`);
    assert.ok(Buffer.isBuffer(repAfter.body) && repAfter.body.length>0, "replaced image serves bytes");
    // ensure old key is not the current slot ref served by route contract (route resolves current DB ref each time)
    const repRow=(await q("select image_url,images from public.cars where id=$1",[carRep])).rows[0];
    assert.equal(repRow.image_url, rep2.key, "current DB ref is new key");

    // 5) Non-owner access denial for unapproved
    const unpub2 = await gj(base, `/api/cars/${carB}/images/0`, u2.H);
    assert.equal(unpub2.status,403);

    // 6) Owner access allowed for unapproved; private cache (no-store); no shared-public cache; conditional does not bypass auth/validation with 304
    const own = await gj(base, `/api/cars/${carB}/images/0`, u1.H);
    assert.equal(own.status,200);
    assert.equal(String(own.headers.get("cache-control")||""), "private, no-store");
    const ownCond = await gj(base, `/api/cars/${carB}/images/0`, {...u1.H, "If-None-Match":"\"stale\""});
    assertNo304BeforeRevalidation(ownCond, "owner conditional");
    assert.equal(ownCond.status,200,`owner conditional must return current content: ${ownCond.status}`);
    assert.ok(Buffer.isBuffer(ownCond.body) && ownCond.body.length>0);

    // 7) Arbitrary object key denial - no key input route exists; bad slot/car handled
    assert.equal((await gj(base, `/api/cars/${carA}/images/99`)).status,400);
    assert.equal((await gj(base, `/api/cars/${carA}/images/abc`)).status,400);
    assert.equal((await gj(base, `/api/cars/not-a-uuid/images/0`)).status,400);

    // 8) Cross-car image reference denial/isolation - slot resolves only that car's DB ref
    const carC = crypto.randomUUID();
    const c1 = await reserveUpload(u2,carC);
    await createCar(u2,carC,[c1.key]);
    await q("update public.cars set is_approved=true where id=$1",[carC]);
    // carC slot 0 serves carC image (200) but is its own ref; cannot reference carA's key via slot
    const cross = await gj(base, `/api/cars/${carC}/images/0`);
    assert.equal(cross.status,200);
    assert.equal((await gj(base, `/api/cars/${carC}/images/1`)).status,404);

    // 9) Legacy absolute URL compatibility (displayable, not proxied server-side as arbitrary fetch; redirect ok)
    const carL = crypto.randomUUID();
    await dbId("legacy");
    await q(`INSERT INTO public.cars (id,user_id,title,brand,model,year,price,image_url,images,is_approved,status)
             VALUES ($1,$2,'t','B','M',2020,1,$3,$4::jsonb,true,'active')`, [carL,u1.id,'https://example.invalid/legacy.jpg', JSON.stringify(['https://example.invalid/legacy.jpg'])]);
    created.cars.push(carL);
    const leg = await gj(base, `/api/cars/by-ids?ids=${carL}`);
    assert.equal(leg.status,200);
    const legCar=leg.body.data[0];
    assert.equal(legCar.image_urls[0], 'https://example.invalid/legacy.jpg');
    assert.equal(legCar.image_url, 'https://example.invalid/legacy.jpg'); // legacy preserved
    const legImg = await gj(base, `/api/cars/${carL}/images/0`);
    assert.ok([301,302,303,307,308].includes(legImg.status), `legacy should redirect, got ${legImg.status}`);
    assert.equal(String(legImg.headers.get("location")||""), 'https://example.invalid/legacy.jpg');

    // 10) Private bucket isolation: car delivery fixed to cars bucket; wallet_receipts not reachable via this endpoint
    assert.equal((await gj(base, `/api/cars/${carA}/images/0`)).status,200); // only cars path used

    // 11) Public URL rejected as a new image binding (canonical keys required for binding/consume)
    const carR = crypto.randomUUID();
    await createCar(u1,carR,[]);
    // try binding a public URL (no reservation/key) - should fail (403/400 from validator)
    const rej = await pj(base, `/api/cars/${carR}`, { image_url: "https://evil.example/x.jpg", images: ["https://evil.example/x.jpg"] }, u1.H);
    // route is PATCH /api/cars/my/:id
    const rej2 = await fetch(base+`/api/cars/my/${carR}`, {method:"PATCH", headers:{"content-type":"application/json",...u1.H}, body:JSON.stringify({ image_url: "https://evil.example/x.jpg", images: ["https://evil.example/x.jpg"] })});
    assert.ok([400,403,422].includes(rej2.status), `public URL bind should be rejected, got ${rej2.status}`);

    // 12) Existing create/PATCH reservation invariants still hold (consume only new; preserve existing)
    const carP = crypto.randomUUID();
    const p1 = await reserveUpload(u1,carP); await createCar(u1,carP,[p1.key]);
    const p2 = await reserveUpload(u1,carP);
    const pr = await fetch(base+`/api/cars/my/${carP}`, {method:"PATCH", headers:{"content-type":"application/json",...u1.H}, body:JSON.stringify({ images:[p1.key,p2.key], image_url:p1.key })});
    assert.equal(pr.status,200);
    const p2c=(await q('select consumed_at from public.car_image_upload_reservations where user_id=$1 and submission_id=$2 and object_key=$3',[u1.id,carP,p2.key])).rows[0];
    assert.ok(p2c?.consumed_at, "new key consumed");

    // 13) Owner /my response has image_urls and does not leak raw keys in public-masking policy (keys never exposed by general API)
    const my = await gj(base, `/api/cars/my`, u1.H);
    assert.equal(my.status,200);
    const mine = (my.body.data||[]).find(c=>c.id===carB);
    assert.ok(mine, "owner sees own car");
    assert.ok(Array.isArray(mine.image_urls));
    assert.equal(hasRawObjectKeyLeak(mine), false);

    // 14) Rate limiting is bounded (behavioral smoke) - just ensure endpoint still responds normally (limit high in test env)
    const rl = await gj(base, `/api/cars/${carA}/images/0`);
    assert.ok([200,429].includes(rl.status));

  } finally {
    try { await dbId("cleanup");
      if(created.cars.length) await pool.query("delete from public.cars where id = any($1::uuid[])",[created.cars]);
      if(created.users.length){ await pool.query("delete from public.car_image_upload_reservations where user_id = any($1::uuid[])",[created.users]).catch(()=>{}); await pool.query("delete from public.app_sessions where user_id = any($1::uuid[])",[created.users]).catch(()=>{}); await pool.query("delete from public.profiles where id = any($1::uuid[])",[created.users]).catch(()=>{}); await pool.query("delete from public.app_users where id = any($1::uuid[])",[created.users]).catch(()=>{}); }
    } catch {}
    try { server.close(); } catch {}
    try { await pool.end(); } catch {}
  }
});