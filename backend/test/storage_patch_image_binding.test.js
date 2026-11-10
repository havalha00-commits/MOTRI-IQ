import assert from "node:assert/strict";
import test from "node:test";
import crypto from "node:crypto";
import net from "node:net";
import pg from "pg";
import dotenv from "dotenv";
import express from "express";
import { S3Client, CreateBucketCommand, HeadBucketCommand, DeleteObjectsCommand } from "@aws-sdk/client-s3";
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

function portReachable(url){ return new Promise(r=>{try{const u=new URL(url);const s=net.connect(+u.port||80,u.hostname);const t=setTimeout(()=>{s.destroy();r(false)},900);s.on('connect',()=>{clearTimeout(t);s.end();r(true)});s.on('error',()=>{clearTimeout(t);r(false)})}catch{r(false)}}); }
const png = ()=>Buffer.from([137,80,78,71,13,10,26,10,0,0,0,13,73,72,68,82,0,0,0,1,0,0,0,1,8,6,0,0,0,31,21,196,137,0,0,0,10,73,68,65,84,120,156,99,0,1,0,0,5,0,1,13,10,45,180,0,0,0,0,73,69,78,68,174,66,96,130]);
async function pj(base,path,body,h={}){const r=await fetch(base+path,{method:"POST",headers:{"content-type":"application/json",...h},body:JSON.stringify(body)});const t=await r.text();let j;try{j=JSON.parse(t)}catch{j={_raw:t}}return {status:r.status,body:j};}
async function patch(base,path,body,h={}){const r=await fetch(base+path,{method:"PATCH",headers:{"content-type":"application/json",...h},body:JSON.stringify(body)});const t=await r.text();let j;try{j=JSON.parse(t)}catch{j={_raw:t}}return {status:r.status,body:j};}
async function put(base,path,buf,h={}){const r=await fetch(base+path,{method:"PUT",headers:h,body:buf});const t=await r.text();let j;try{j=JSON.parse(t)}catch{j={_raw:t}}return {status:r.status,body:j};}

maybe("G10.42.29 PATCH /api/cars/my/:id image binding (motri_iq_test + local s3rver, opt-in)", async () => {
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
  app.use("/api/auth", createAuthRouter({ database: pool, jwtSecret: TEST_SECRET }));
  app.use("/api/cars", createCarsRouter({ database: pool, authenticate: authMw, storage }));
  app.use("/api/storage", createStorageRouter({ authenticate: authMw, storage, database: pool }));
  const server = app.listen(0,"127.0.0.1"); await new Promise(r=>server.once("listening",r));
  const base = `http://127.0.0.1:${server.address().port}`;
  const tag=`g104229_${Date.now()}`; const created={users:[],cars:[],keys:[]}; const img=png();

  try {
    const mk=async(n)=>{ await dbId("mk"); const uniq=`${tag}_${n}_${crypto.randomUUID().slice(0,8)}`; const reg=await pj(base,"/api/auth/register",{email:`${uniq}@example.test`,username:uniq.replace(/[^a-z0-9]/gi,'').slice(0,24),password:"G10.42.29!Disposable",full_name:"P"}); assert.equal(reg.status,201,JSON.stringify(reg.body)); created.users.push(reg.body.user.id); return {id:reg.body.user.id,H:{authorization:`Bearer ${reg.body.access_token}`}}; };
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
    async function createCar(u, carId, keys=[]){
      await dbId("createCar");
      const body={id:carId,brand:"B",model:"M",year:2024,price:1,title:"t"};
      if(keys.length){ body.image_url=keys[0]; body.images=keys; }
      const r=await pj(base,"/api/cars",body,u.H);
      assert.equal(r.status,201,`createCar ${r.status} ${JSON.stringify(r.body)}`);
      created.cars.push(carId);
      return r;
    }

    // 1) Valid new image on PATCH succeeds; reservation consumed; car updated
    { const carId=crypto.randomUUID(); await createCar(u1,carId,[]);
      const {key}=await reserveUpload(u1,carId);
      const r=await patch(base,`/api/cars/my/${carId}`,{image_url:key,images:[key]},u1.H);
      assert.equal(r.status,200,JSON.stringify(r.body));
      const car=(await q('select image_url,images from public.cars where id=$1',[carId])).rows[0];
      assert.equal(car.image_url,key);
      const cons=(await q('select consumed_at from public.car_image_upload_reservations where user_id=$1 and submission_id=$2 and object_key=$3',[u1.id,carId,key])).rows[0];
      assert.ok(cons?.consumed_at, 'reservation should be consumed');
    }

    // 2) Existing image preservation (re-save existing key without re-consumption failure)
    { const carId=crypto.randomUUID();
      const ex=await reserveUpload(u1,carId); await createCar(u1,carId,[ex.key]);
      const r=await patch(base,`/api/cars/my/${carId}`,{title:"t2",images:[ex.key],image_url:ex.key},u1.H);
      assert.equal(r.status,200,JSON.stringify(r.body));
      const car=(await q('select title,image_url from public.cars where id=$1',[carId])).rows[0];
      assert.equal(car.title,"t2"); assert.equal(car.image_url,ex.key);
    }

    // 3) Mixed existing and new images
    { const carId=crypto.randomUUID();
      const ex=await reserveUpload(u1,carId); await createCar(u1,carId,[ex.key]);
      const nw=await reserveUpload(u1,carId);
      const r=await patch(base,`/api/cars/my/${carId}`,{images:[ex.key,nw.key],image_url:ex.key},u1.H);
      assert.equal(r.status,200,JSON.stringify(r.body));
      const consN=(await q('select consumed_at from public.car_image_upload_reservations where user_id=$1 and submission_id=$2 and object_key=$3',[u1.id,carId,nw.key])).rows[0];
      assert.ok(consN?.consumed_at);
      const consE=(await q('select consumed_at from public.car_image_upload_reservations where user_id=$1 and submission_id=$2 and object_key=$3',[u1.id,carId,ex.key])).rows[0];
      assert.ok(consE?.consumed_at); // consumed at create; preserved
    }

    // 4) Foreign-user image rejection (403), no mutation, no consumption
    { const carId=crypto.randomUUID(); await createCar(u1,carId,[]);
      const u2car=crypto.randomUUID(); const fk=await reserveUpload(u2,u2car); created.cars.push(u2car);
      await createCar(u2,u2car,[fk.key]);
      // try to use u2's key on u1's car (wrong owner/submission shape) - patch u1 car
      const r=await patch(base,`/api/cars/my/${carId}`,{images:[fk.key]},u1.H);
      assert.equal(r.status,403,JSON.stringify(r.body));
      const car=(await q('select images,image_url from public.cars where id=$1',[carId])).rows[0];
      assert.ok(car.image_url==null && (car.images==null || car.images=='{}' || car.images=='null' || JSON.stringify(car.images)==='[]' || car.images==='' ), `mutated: ${JSON.stringify(car)}`);
    }

    // 5) Wrong submission ID rejection (403) - key belongs to different car of same user
    { const carId=crypto.randomUUID(), otherCar=crypto.randomUUID();
      await createCar(u1,carId,[]); const k=await reserveUpload(u1,otherCar); created.cars.push(otherCar); await createCar(u1,otherCar,[k.key]);
      const r=await patch(base,`/api/cars/my/${carId}`,{image_url:k.key},u1.H);
      assert.equal(r.status,403,JSON.stringify(r.body));
    }

    // 6) Missing storage object (400)
    { const carId=crypto.randomUUID(); await createCar(u1,carId,[]);
      const ph=crypto.randomUUID();
      const rv=await pj(base,"/api/cars/uploads/reserve",{submission_id:carId,photo_id:ph,extension:"png"},u1.H);
      assert.equal(rv.status,201); const key=rv.body.data.object_key; // not uploaded
      const r=await patch(base,`/api/cars/my/${carId}`,{image_url:key},u1.H);
      assert.equal(r.status,400,JSON.stringify(r.body));
      const cons=(await q('select consumed_at from public.car_image_upload_reservations where user_id=$1 and submission_id=$2 and object_key=$3',[u1.id,carId,key])).rows[0];
      assert.ok(cons?.consumed_at==null);
    }

    // 7a) Expired reservation (403)
    { const carId=crypto.randomUUID(); await createCar(u1,carId,[]);
      const {key}=await reserveUpload(u1,carId);
      await q('update public.car_image_upload_reservations set expires_at=now()-interval \'10 min\' where user_id=$1 and submission_id=$2 and object_key=$3',[u1.id,carId,key]);
      const r=await patch(base,`/api/cars/my/${carId}`,{image_url:key},u1.H);
      assert.equal(r.status,403,JSON.stringify(r.body));
      const cons=(await q('select consumed_at from public.car_image_upload_reservations where user_id=$1 and submission_id=$2 and object_key=$3',[u1.id,carId,key])).rows[0];
      assert.ok(cons?.consumed_at==null);
    }
    // 7b) Consumed reservation (403)
    { const carId=crypto.randomUUID(); await createCar(u1,carId,[]);
      const {key}=await reserveUpload(u1,carId);
      await q('update public.car_image_upload_reservations set consumed_at=now() where user_id=$1 and submission_id=$2 and object_key=$3',[u1.id,carId,key]);
      const r=await patch(base,`/api/cars/my/${carId}`,{image_url:key},u1.H);
      assert.equal(r.status,403,JSON.stringify(r.body));
    }
    // 7c) Missing reservation (403)
    { const carId=crypto.randomUUID(); await createCar(u1,carId,[]);
      const key=`${u1.id}/${carId}/${crypto.randomUUID()}.png`;
      await storage.upload({bucket:S3_BUCKET,key,body:img,contentType:'image/png'}); created.keys.push(key);
      const r=await patch(base,`/api/cars/my/${carId}`,{image_url:key},u1.H);
      assert.equal(r.status,403,JSON.stringify(r.body));
    }

    // 8) Atomic rollback (motri_iq_test asserted): inject failure on final cars UPDATE after consumption.
    { await dbId("rollback");
      const carId=crypto.randomUUID(); await createCar(u1,carId,[]);
      const rv=await pj(base,"/api/cars/uploads/reserve",{submission_id:carId,photo_id:crypto.randomUUID(),extension:"png"},u1.H);
      assert.equal(rv.status,201); const key=rv.body.data.object_key; created.keys.push(key);
      const up=await put(base,`/api/storage/object?bucket=cars&path=${encodeURIComponent(key)}`,img,{...u1.H,"content-type":"image/png"});
      assert.equal(up.status,201,JSON.stringify(up.body));
      const realClient=await pool.connect(); let injected=false;
      const wrapClient={ query: async (sql,params)=>{ if(!injected && /^UPDATE public\.cars/i.test(String(sql).trim()) && Array.isArray(params) && params[0]===carId){ injected=true; throw new Error('INJECTED_UPDATE_FAILURE_G104229'); } return realClient.query(sql,params); }, release: ()=>realClient.release() };
      const dbWrap={ query:(s,p)=>pool.query(s,p), connect: async()=>wrapClient };
      const app2=express(); app2.use(express.json());
      app2.use('/api/cars', createCarsRouter({database:dbWrap, authenticate:createCurrentUserAuthenticator({database:pool,supabaseUrl:null,publishableKey:null}), storage}));
      const srv2=app2.listen(0,'127.0.0.1'); await new Promise(r=>srv2.once('listening',r));
      const base2=`http://127.0.0.1:${srv2.address().port}`;
      const rr=await patch(base2,`/api/cars/my/${carId}`,{image_url:key,images:[key]},u1.H);
      assert.equal(rr.status,500,JSON.stringify(rr.body)); assert.ok(injected,'fault not injected');
      await new Promise(r=>srv2.close(r)); await dbId("rollback-check");
      const car=(await q('select image_url from public.cars where id=$1',[carId])).rows[0];
      assert.ok(car.image_url==null, `car mutated despite rollback: ${JSON.stringify(car)}`);
      const cons=(await q('select consumed_at from public.car_image_upload_reservations where user_id=$1 and submission_id=$2 and object_key=$3',[u1.id,carId,key])).rows[0];
      assert.ok(cons?.consumed_at==null, 'reservation consumed despite rollback');
    }

    // 9) Concurrent PATCH requests (same car, same new key): car row FOR UPDATE serializes;
    //    winner consumes/binds; follower re-reads committed row, treats key as existing-bound
    //    (preserve semantics) and performs no new consumption. No double-consume.
    { await dbId("concurrent");
      const carId=crypto.randomUUID(); await createCar(u1,carId,[]);
      const {key}=await reserveUpload(u1,carId);
      const [a,b]=await Promise.all([
        patch(base,`/api/cars/my/${carId}`,{image_url:key,images:[key]},u1.H),
        patch(base,`/api/cars/my/${carId}`,{image_url:key,images:[key]},u1.H),
      ]);
      const codes=[a.status,b.status].sort();
      assert.ok((codes[0]===200 && (codes[1]===200 || codes[1]===403)), `concurrent: ${JSON.stringify(codes)} A=${JSON.stringify(a.body)} B=${JSON.stringify(b.body)}`);
      const cons=(await q('select count(*)::int c from public.car_image_upload_reservations where user_id=$1 and submission_id=$2 and object_key=$3 and consumed_at is not null',[u1.id,carId,key])).rows[0];
      assert.equal(cons.c,1,'reservation consumed exactly once');
      const car=(await q('select image_url from public.cars where id=$1',[carId])).rows[0];
      assert.equal(car.image_url,key);
    }

    // 10) Non-owner update rejection (404)
    { await dbId("nonowner");
      const carId=crypto.randomUUID(); await createCar(u1,carId,[]);
      const r=await patch(base,`/api/cars/my/${carId}`,{title:"stolen"},u2.H);
      assert.equal(r.status,404,JSON.stringify(r.body));
      const car=(await q('select title from public.cars where id=$1',[carId])).rows[0];
      assert.notEqual(car.title,'stolen');
    }

  } finally {
    try { await s3.send(new DeleteObjectsCommand({Bucket:S3_BUCKET, Delete:{Objects:[...new Set(created.keys)].map(Key=>({Key})), Quiet:true}})); } catch {}
    await new Promise(r=>server.close(r));
    await dbId("cleanup");
    if(created.cars.length) await q('delete from public.cars where id=any($1::uuid[])',[created.cars]).catch(()=>{});
    if(created.users.length){
      await q('delete from public.cars where user_id=any($1::uuid[])',[created.users]).catch(()=>{});
      await q('delete from public.car_image_upload_reservations where user_id=any($1::uuid[])',[created.users]).catch(()=>{});
      await q('delete from public.app_sessions where user_id=any($1::uuid[])',[created.users]).catch(()=>{});
      await q('delete from public.profiles where id=any($1::uuid[])',[created.users]).catch(()=>{});
      await q('delete from public.app_admins where user_id=any($1::uuid[])',[created.users]).catch(()=>{});
      await q('delete from public.app_users where id=any($1::uuid[])',[created.users]).catch(()=>{});
      const left=(await q(`select (select count(*) from public.cars where user_id=any($1::uuid[])) c,(select count(*) from public.car_image_upload_reservations where user_id=any($1::uuid[])) r,(select count(*) from public.app_users where id=any($1::uuid[])) u`,[created.users])).rows[0];
      assert.equal(left.c,'0'); assert.equal(left.r,'0'); assert.equal(left.u,'0');
    }
    await pool.end(); s3.destroy();
  }
});
