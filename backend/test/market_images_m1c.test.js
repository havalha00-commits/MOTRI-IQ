import assert from "node:assert/strict";
import test from "node:test";
import crypto from "node:crypto";
import fs from "node:fs";
import net from "node:net";
import path from "node:path";
import pg from "pg";
import dotenv from "dotenv";
import express from "express";
import { S3Client, CreateBucketCommand, HeadBucketCommand } from "@aws-sdk/client-s3";
import { createAuthRouter } from "../routes/auth.js";
import { createCurrentUserAuthenticator } from "../middleware/current_user.js";
import { createMarketRouter, createMarketImageDeliveryRouter } from "../routes/market.js";
import { createObjectStorageService } from "../services/objectStorage.js";

dotenv.config({ path: ".env.test", override: true });
const RUN = process.env.LOCAL_S3_INTEGRATION === "1";
const S3_ENDPOINT = process.env.LOCAL_S3_ENDPOINT || "http://127.0.0.1:4566";
const S3_BUCKET = process.env.MARKET_S3_BUCKET || "market_images";
const S3_CREDS = { accessKeyId: "S3RVER", secretAccessKey: "S3RVER" };
const TEST_SECRET = process.env.JWT_SECRET;
const maybe = RUN ? test : test.skip;

function portReachable(url){ return new Promise(r=>{try{const u=new URL(url);const s=net.connect(+u.port||80,u.hostname);const t=setTimeout(()=>{s.destroy();r(false)},1200);s.on("connect",()=>{clearTimeout(t);s.end();r(true)});s.on("error",()=>{clearTimeout(t);r(false)});}catch{r(false)}}); }
const png = ()=>Buffer.from([137,80,78,71,13,10,26,10,0,0,0,13,73,72,68,82,0,0,0,1,0,0,0,1,8,6,0,0,0,31,21,196,137,0,0,0,10,73,68,65,84,120,156,99,0,1,0,0,5,0,1,13,10,45,180,0,0,0,0,73,69,78,68,174,66,96,130]);
async function pj(base,path,body,h={}){const r=await fetch(base+path,{method:"POST",headers:{"content-type":"application/json",...h},body:JSON.stringify(body)});const t=await r.text();let j;try{j=JSON.parse(t)}catch{j={_raw:t}}return {status:r.status,body:j,headers:r.headers};}
async function gj(base,path,h={}){const r=await fetch(base+path,{method:"GET",headers:h,redirect:"manual"});const ct=r.headers.get("content-type")||"";let body; if(ct.includes("application/json")){const t=await r.text();try{body=JSON.parse(t)}catch{body={_raw:t}}} else {body=Buffer.from(await r.arrayBuffer());} return {status:r.status,body,headers:r.headers};}
async function patch(base,path,body,h={}){const r=await fetch(base+path,{method:"PATCH",headers:{"content-type":"application/json",...h},body:JSON.stringify(body)});const t=await r.text();let j;try{j=JSON.parse(t)}catch{j={_raw:t}}return {status:r.status,body:j};}
// Exact Flutter contract: BackendApi.putBytes => HTTP PUT, raw bytes body, query params, Authorization/content-type headers.
async function putBytes(base,path,buf,h={}){const r=await fetch(base+path,{method:"PUT",headers:h,body:buf});const t=await r.text();let j;try{j=JSON.parse(t)}catch{j={_raw:t}}return {status:r.status,body:j,headers:r.headers};}
async function postBytes(base,path,buf,h={}){const r=await fetch(base+path,{method:"POST",headers:h,body:buf});const t=await r.text();let j;try{j=JSON.parse(t)}catch{j={_raw:t}}return {status:r.status,body:j,headers:r.headers};}

function hasRawObjectKeyLeak(s){ return /[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\/(market|job)\/[0-9a-f-]{36}\.(jpg|jpeg|png|webp)/i.test(String(s)); }

maybe("G10.52 M1C market image upload/binding/delivery/visibility (motri_iq_test + local s3rver, opt-in)", async () => {
  assert.ok(TEST_SECRET && TEST_SECRET.length >= 64, "JWT_SECRET missing/short");
  assert.ok(await portReachable(S3_ENDPOINT), `s3 unreachable: ${S3_ENDPOINT}`);
  const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false }, max: 10 });
  const dbId = async (where)=>{ const r=(await pool.query("select current_database() db,current_user usr")).rows[0]; assert.equal(r.db,"motri_iq_test",`ISOLATION ${where}: ${JSON.stringify(r)}`); assert.equal(r.usr,"neondb_owner",`ISOLATION ${where}: ${JSON.stringify(r)}`); return r; };
  await dbId("start");
  const q = async (s,p=[])=>{ await dbId("query"); return pool.query(s,p); };

  // Apply isolated fixtures only (IF NOT EXISTS)
  const bootstrap = fs.readFileSync(path.resolve("scripts/bootstrap_test_schema.sql"), "utf8");
  await dbId("bootstrap");
  await pool.query(bootstrap);

  const s3 = new S3Client({ endpoint: S3_ENDPOINT, region: "us-east-1", forcePathStyle: true, credentials: S3_CREDS });
  try { await s3.send(new HeadBucketCommand({ Bucket: S3_BUCKET })); } catch { await s3.send(new CreateBucketCommand({ Bucket: S3_BUCKET })); }
  delete process.env.SUPABASE_URL; delete process.env.SUPABASE_PUBLISHABLE_KEY;
  const storage = createObjectStorageService({ endpoint: S3_ENDPOINT, accessKeyId: S3_CREDS.accessKeyId, secretAccessKey: S3_CREDS.secretAccessKey, region: "us-east-1", bucket: S3_BUCKET, database: pool });
  const app = express(); app.use(express.json());
  const authMw = createCurrentUserAuthenticator({ database: pool, supabaseUrl: null, publishableKey: null });
  const optAuthMw = (req,res,next)=>{ if(!req.headers.authorization) return next(); return authMw(req,res,next); };
  app.use("/api/auth", createAuthRouter({ database: pool, jwtSecret: TEST_SECRET }));
  app.use("/api/market/images", createMarketImageDeliveryRouter({ database: pool, optionalAuthenticate: optAuthMw, storage }));
  app.use("/api/market", createMarketRouter({ database: pool, authenticate: authMw, optionalAuthenticate: optAuthMw, storage, policy: { hasAccepted: async () => true }, storageUrl: "https://legacy-storage.example" }));
  const server = app.listen(0,"127.0.0.1"); await new Promise(r=>server.once("listening",r));
  const base = `http://127.0.0.1:${server.address().port}`;
  const tag=`g1052_${Date.now()}`; const created={users:[],items:[],jobs:[],refs:[]}; const img=png();

  try {
    const mk=async(n,admin=false)=>{ await dbId("mk"); const uniq=`${tag}_${n}_${crypto.randomUUID().slice(0,8)}`; const reg=await pj(base,"/api/auth/register",{email:`${uniq}@example.test`,username:uniq.replace(/[^a-z0-9]/gi,"").slice(0,24),password:"G10.52!Passw0rd",display_name:`G ${n}`}); assert.ok([200,201].includes(reg.status),`reg ${reg.status} ${JSON.stringify(reg.body)}`); const id=(await q("select id from public.app_users where lower(email)=lower($1)",[`${uniq}@example.test`])).rows[0].id; created.users.push(id); if(admin){ await q("insert into public.profiles (id,is_admin) values ($1,true) on conflict (id) do update set is_admin=true",[id]).catch(()=>{}); await q("create table if not exists public.app_admins (user_id uuid primary key)").catch(()=>{}); await q("insert into public.app_admins (user_id) values ($1) on conflict do nothing",[id]).catch(()=>{}); } const lg=await pj(base,"/api/auth/login",{identifier:`${uniq}@example.test`,password:"G10.52!Passw0rd"}); assert.equal(lg.status,200,JSON.stringify(lg.body)); return {id,H:{Authorization:`Bearer ${lg.body.access_token}`}}; };
    const u1=await mk(1), u2=await mk(2);

    async function uploadRef(u, kind="market"){
      const r = await putBytes(base, `/api/market/uploads?kind=${kind}`, img, {...u.H, "content-type":"image/png"});
      assert.equal(r.status,201,`upload ${r.status} ${JSON.stringify(r.body)}`);
      assert.ok(r.body?.data?.delivery_url, "delivery_url missing");
      assert.ok(String(r.body.data.delivery_url).startsWith("/api/market/images/mimg_"), `bad delivery_url ${r.body.data.delivery_url}`);
      assert.equal(hasRawObjectKeyLeak(JSON.stringify(r.body)), false, "raw object key leak in upload response");
      assert.equal(r.body.data.ref && r.body.data.ref.startsWith("mimg_"), true);
      created.refs.push(r.body.data.ref);
      return r.body.data;
    }

    // 1) Authenticated upload returns server-owned renderable delivery_url (no public_url/raw key) — exact Flutter contract: PUT, raw bytes, ?kind=, auth.
    const up1 = await uploadRef(u1,"market");
    const up2 = await uploadRef(u1,"market");
    assert.equal(up1.delivery_url !== up2.delivery_url, true);
    // Contract/compat: POST accepted (compat) with same auth+shape; unauthenticated rejected; invalid kind rejected; responses leak no public_url/signed/raw key/bucket.
    const postCompat = await postBytes(base, `/api/market/uploads?kind=market`, img, {...u1.H, "content-type":"image/png"});
    assert.equal(postCompat.status, 201, `POST compat ${postCompat.status}`);
    assert.ok(String(postCompat.body?.data?.delivery_url||"").startsWith("/api/market/images/mimg_"));
    assert.equal(hasRawObjectKeyLeak(JSON.stringify(postCompat.body)), false);
    assert.equal(JSON.stringify(postCompat.body).includes("public_url"), false);
    assert.equal(JSON.stringify(postCompat.body).includes("signed"), false);
    created.refs.push(postCompat.body.data.ref);
    const noAuth = await postBytes(base, `/api/market/uploads?kind=market`, img, {"content-type":"image/png"});
    assert.ok([401,403].includes(noAuth.status), `unauth upload ${noAuth.status}`);
    const badKind = await putBytes(base, `/api/market/uploads?kind=car`, img, {...u1.H, "content-type":"image/png"});
    assert.equal(badKind.status, 400, `bad kind ${badKind.status}`);

    // 2) Unbound draft owner can preview (private, no-store); other user denied; conditional headers never 304
    const ownPrev = await gj(base, up1.delivery_url, u1.H);
    assert.equal(ownPrev.status,200);
    assert.equal(String(ownPrev.headers.get("cache-control")||""), "private, no-store");
    const otherPrev = await gj(base, up1.delivery_url, u2.H);
    assert.equal(otherPrev.status,403);
    const condPrev = await gj(base, up1.delivery_url, {...u1.H,"If-None-Match":"\"stale\""});
    assert.notEqual(condPrev.status,304);

    // 3) Cross-user ref binding denied
    const foreign = await uploadRef(u2,"market");
    const itemBad = crypto.randomUUID(); created.items.push(itemBad);
    const badBind = await pj(base, "/api/market/items", { id:itemBad,title:"T",price:1,images:[up1.delivery_url, foreign.delivery_url] }, u1.H);
    assert.ok([400,403].includes(badBind.status), `cross-user bind should fail: ${badBind.status} ${JSON.stringify(badBind.body)}`);

    // 4) Create with mixed legacy retained/new refs in order preserved; legacy trusted URL compat
    const legacy = `https://legacy-storage.example/storage/v1/object/public/cars/${u1.id}/market_legacy/${crypto.randomUUID()}.png`;
    const item1 = crypto.randomUUID(); created.items.push(item1);
    const create = await pj(base, "/api/market/items", { id:item1,title:"Mixed",price:5,images:[legacy, up1.delivery_url, up2.delivery_url] }, u1.H);
    assert.ok([200,201].includes(create.status), `create ${create.status} ${JSON.stringify(create.body)}`);
    const row1 = (await q("select images,is_approved,user_id from public.market_items where id=$1",[item1])).rows[0];
    assert.equal(row1.is_approved,false);
    assert.equal(row1.images[0], legacy);
    assert.ok(String(row1.images[1]).startsWith("/api/market/images/mimg_"));
    assert.ok(String(row1.images[2]).startsWith("/api/market/images/mimg_"));
    // refs bound
    const brefs = await q("select status,bound_table,bound_id from public.market_image_upload_refs where ref=any($1::text[])",[[up1.ref,up2.ref]]);
    for(const r of brefs.rows){ assert.equal(r.status,"bound"); assert.equal(r.bound_table,"public.market_items"); assert.equal(String(r.bound_id),String(item1)); }

    // 5) Market visibility (read routes): unauthenticated/public + ordinary users see approved only; owner sees own unapproved; other user cannot; by-ids enforces same matrix.
    await q("update public.market_items set is_approved=false where id=$1",[item1]);
    const item2 = crypto.randomUUID(); created.items.push(item2);
    const c2 = await pj(base, "/api/market/items", { id:item2,title:"Approved",price:2,images:[(await uploadRef(u1,"market")).delivery_url,(await uploadRef(u1,"market")).delivery_url] }, u1.H);
    assert.ok([200,201].includes(c2.status), `create item2 ${c2.status}`);
    await q("update public.market_items set is_approved=true where id=$1",[item2]);
    const listPub = await gj(base, "/api/market/items?limit=100");
    assert.equal(listPub.status,200);
    const idsPub = new Set((listPub.body.data||[]).map(x=>x.id));
    assert.equal(idsPub.has(item1), false, "public/unauth must not see owner unapproved");
    assert.equal(idsPub.has(item2), true);
    const listOther = await gj(base, "/api/market/items?limit=100", u2.H);
    const idsOther = new Set((listOther.body.data||[]).map(x=>x.id));
    assert.equal(idsOther.has(item1), false);
    assert.equal(idsOther.has(item2), true);
    const listOwner = await gj(base, "/api/market/items?limit=100", u1.H);
    const idsOwner = new Set((listOwner.body.data||[]).map(x=>x.id));
    assert.equal(idsOwner.has(item1), true, "owner sees own unapproved");
    assert.equal(idsOwner.has(item2), true);
    const byPub = await gj(base, `/api/market/items/by-ids?ids=${item1},${item2}`);
    assert.equal(byPub.status,200);
    const byPubIds = new Set((byPub.body.data||[]).map(x=>x.id));
    assert.equal(byPubIds.has(item1), false);
    assert.equal(byPubIds.has(item2), true);
    const byOther = await gj(base, `/api/market/items/by-ids?ids=${item1},${item2}`, u2.H);
    assert.equal(byOther.status,200);
    const byOtherIds = new Set((byOther.body.data||[]).map(x=>x.id));
    assert.equal(byOtherIds.has(item1), false, "other user must not see unapproved");
    assert.equal(byOtherIds.has(item2), true);
    const byOwner = await gj(base, `/api/market/items/by-ids?ids=${item1},${item2}`, u1.H);
    const byOwnerIds = new Set((byOwner.body.data||[]).map(x=>x.id));
    assert.equal(byOwnerIds.has(item1), true);
    assert.equal(byOwnerIds.has(item2), true);

    // 6) Delivery: bound approved image publicly readable with revalidation-safe cache; unapproved only owner; other denied; no unsafe 304.
    await q("update public.market_items set is_approved=true where id=$1",[item1]);
    const pubImg = await gj(base, row1.images[1], {});
    assert.equal(pubImg.status,200);
    const pubCc = String(pubImg.headers.get("cache-control")||"");
    assert.ok(pubCc.includes("public") && pubCc.includes("max-age=0") && pubCc.includes("must-revalidate") && !pubCc.includes("immutable"), pubCc);
    assert.ok(Buffer.isBuffer(pubImg.body) && pubImg.body.length>0);
    const condPub = await gj(base, row1.images[1], {"If-None-Match":"\"stale\""});
    assert.notEqual(condPub.status,304);
    assert.ok([200,412].includes(condPub.status), `conditional public: ${condPub.status}`);
    await q("update public.market_items set is_approved=false where id=$1",[item1]);
    assert.equal((await gj(base, row1.images[1], u1.H)).status,200, "owner sees own unapproved bound image");
    assert.equal((await gj(base, row1.images[1], u2.H)).status,403, "other user denied unapproved bound image");
    assert.equal((await gj(base, row1.images[1], {})).status,403, "public denied unapproved bound image");
    await q("update public.market_items set is_approved=true where id=$1",[item1]);

    // 7) PATCH retains legacy + adds new owned ref; order preserved; foreign/car/A1/raw refs rejected
    const up3 = await uploadRef(u1,"market");
    const patchOk = await patch(base, `/api/market/items/${item1}/images`, { images:[legacy, row1.images[1], up3.delivery_url] }, u1.H);
    assert.equal(patchOk.status,200, JSON.stringify(patchOk.body));
    const row1b = (await q("select images from public.market_items where id=$1",[item1])).rows[0];
    assert.deepEqual(row1b.images, [legacy, row1.images[1], `/api/market/images/${up3.ref}`]);
    const carRef = `/api/cars/${crypto.randomUUID()}/images/0`;
    const rawKey = `${u1.id}/${crypto.randomUUID()}/${crypto.randomUUID()}.jpg`;
    for (const bad of [carRef, rawKey, "https://evil.example/x.jpg"]) {
      const pr = await patch(base, `/api/market/items/${item1}/images`, { images:[legacy, bad] }, u1.H);
      assert.ok([400,403].includes(pr.status), `bad ref ${bad} should be rejected: ${pr.status}`);
    }

    // 8) Draft expiry cannot bind/deliver
    const exp = await uploadRef(u1,"market");
    await q("update public.market_image_upload_refs set expires_at = now() - interval '5 min' where ref=$1",[exp.ref]);
    const expItem = crypto.randomUUID(); created.items.push(expItem);
    const expBind = await pj(base, "/api/market/items", { id:expItem,title:"E",price:1,images:[legacy, exp.delivery_url] }, u1.H);
    assert.ok([400,403].includes(expBind.status), `expired bind ${expBind.status}`);
    const expDel = await gj(base, exp.delivery_url, u1.H);
    assert.ok([404,410].includes(expDel.status), `expired delivery ${expDel.status}`);

    // TASK A — Admin runtime (real verified independent-session auth, no req.user mocking/middleware bypass).
    // Admin identity comes only from trusted DB authorization (public.app_admins/profiles) resolved by middleware from verified session JWT.
    const adm = await mk("admin_runtime", true);
    const itemPriv = crypto.randomUUID(); created.items.push(itemPriv);
    const privUp1 = await uploadRef(u1,"market");
    const privUp2 = await uploadRef(u1,"market");
    const privCreate = await pj(base, "/api/market/items", { id:itemPriv,title:"PrivAdmin",price:3,images:[privUp1.delivery_url, privUp2.delivery_url] }, u1.H);
    assert.ok([200,201].includes(privCreate.status), `priv create ${privCreate.status} ${JSON.stringify(privCreate.body)}`);
    await q("update public.market_items set is_approved=false where id=$1",[itemPriv]);
    // Admin (verified session) can read owner-unapproved listing via list/by-ids and bound image delivery.
    const admList = await gj(base, `/api/market/items?limit=200`, adm.H);
    assert.equal(admList.status,200);
    assert.equal((admList.body.data||[]).some(x=>x.id===itemPriv), true, "verified admin sees unapproved listing in list");
    const admBy = await gj(base, `/api/market/items/by-ids?ids=${itemPriv}`, adm.H);
    assert.equal(admBy.status,200);
    assert.equal((admBy.body.data||[]).some(x=>x.id===itemPriv), true, "verified admin sees unapproved listing in by-ids");
    const admImg = await gj(base, privUp1.delivery_url, adm.H);
    assert.equal(admImg.status,200, "verified admin can view unapproved bound image");
    // Ordinary authenticated user cannot obtain same unapproved access.
    assert.equal((await gj(base, `/api/market/items/by-ids?ids=${itemPriv}`, u2.H)).body?.data?.some(x=>x.id===itemPriv) || false, false, "ordinary user cannot see unapproved in by-ids");
    assert.equal((await gj(base, privUp1.delivery_url, u2.H)).status,403, "ordinary user cannot view unapproved image");
    // Client-supplied is_admin fields cannot elevate privileges (middleware derives req.user.is_admin from DB; routes never read body/query is_admin).
    const fakeAdminList = await gj(base, `/api/market/items?limit=200&is_admin=true`, u2.H);
    assert.equal((fakeAdminList.body.data||[]).some(x=>x.id===itemPriv), false, "client is_admin query cannot elevate list");
    const fakeAdminBy = await gj(base, `/api/market/items/by-ids?ids=${itemPriv}&is_admin=true&admin=1&role=admin`, u2.H);
    assert.equal((fakeAdminBy.body.data||[]).some(x=>x.id===itemPriv), false, "client is_admin query cannot elevate by-ids");
    // Body is_admin on a JSON GET is ignored by these handlers; verify no elevation via create-style body field cannot grant admin on reads (reads take no body). Confirm ordinary token still cannot see privileged image even with spoof headers.
    const fakeHeaderImg = await gj(base, privUp1.delivery_url, {...u2.H, "x-is-admin":"true", "x-admin":"1"});
    assert.equal(fakeHeaderImg.status,403, "spoofed headers cannot elevate delivery access");
    await q("update public.market_items set is_approved=true where id=$1",[itemPriv]);
    const jrefs=[]; for(let i=0;i<5;i++) jrefs.push((await uploadRef(u1,"job")).delivery_url);
    const job1 = crypto.randomUUID(); created.jobs.push(job1);
    const jobCreate = await pj(base, "/api/market/jobs", { id:job1,title:"J",governorate:"G",job_type:"full_time",images:jrefs }, u1.H);
    assert.ok([200,201].includes(jobCreate.status), `job create ${jobCreate.status} ${JSON.stringify(jobCreate.body)}`);
    const j6=(await uploadRef(u1,"job")).delivery_url;
    const jobBad = crypto.randomUUID(); created.jobs.push(jobBad);
    const jobOver = await pj(base, "/api/market/jobs", { id:jobBad,title:"J2",governorate:"G",job_type:"full_time",images:[...jrefs,j6] }, u1.H);
    assert.equal(jobOver.status,400);

    // 10) Unapproved bound job image: owner/admin model - owner can view; other cannot (job listing not publicly listed by current route, delivery checks bound listing approval)
    await q("update public.jobs set is_approved=false where id=$1",[job1]);
    const jobRow=(await q("select images from public.jobs where id=$1",[job1])).rows[0];
    const jobImg = String(jobRow.images[0]);
    assert.equal((await gj(base, jobImg, u1.H)).status,200);
    assert.equal((await gj(base, jobImg, u2.H)).status,403);

  } finally {
    try { await dbId("cleanup");
      if(created.items.length) await pool.query("delete from public.market_items where id = any($1::uuid[])",[created.items]);
      if(created.jobs.length) await pool.query("delete from public.jobs where id = any($1::uuid[])",[created.jobs]);
      if(created.refs.length) await pool.query("delete from public.market_image_upload_refs where ref = any($1::text[])",[created.refs]);
      if(created.users.length){ await pool.query("delete from public.app_sessions where user_id = any($1::uuid[])",[created.users]).catch(()=>{}); await pool.query("delete from public.app_admins where user_id = any($1::uuid[])",[created.users]).catch(()=>{}); await pool.query("delete from public.profiles where id = any($1::uuid[])",[created.users]).catch(()=>{}); await pool.query("delete from public.app_users where id = any($1::uuid[])",[created.users]).catch(()=>{}); }
    } catch {}
    try { server.close(); } catch {}
    try { await pool.end(); } catch {}
  }
});
