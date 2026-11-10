import dotenv from "dotenv";
import pg from "pg";
import { pool as neon } from "./config/database.js";

dotenv.config({ path: "./source.env" });

const { Pool } = pg;
const sourceUrl = process.env.SOURCE_DATABASE_URL;

if (!sourceUrl || !/^postgres(ql)?:\/\//i.test(sourceUrl)) {
  console.log("SOURCE ERROR: رابط الاتصال غير موجود أو صيغته غير صحيحة.");
  await neon.end();
  process.exit(1);
}

const source = new Pool({
  connectionString: sourceUrl,
  connectionTimeoutMillis: 15000,
  max: 1
});

try {
  const src = await source.query(`
    SELECT current_database() AS db,
           (SELECT count(*) FROM information_schema.tables
            WHERE table_schema = 'public'
              AND table_type = 'BASE TABLE') AS tables
  `);
  console.log("SUPABASE SOURCE: CONNECTED");
  console.log("Database:", src.rows[0].db);
  console.log("Public tables:", src.rows[0].tables);

  const dst = await neon.query(`
    SELECT current_database() AS db,
           (SELECT count(*) FROM information_schema.tables
            WHERE table_schema = 'public'
              AND table_type = 'BASE TABLE') AS tables
  `);
  console.log("NEON TARGET: CONNECTED");
  console.log("Database:", dst.rows[0].db);
  console.log("Public tables:", dst.rows[0].tables);
} catch (error) {
  console.log("CONNECTION CHECK FAILED:", error.message);
} finally {
  await source.end();
  await neon.end();
}
