import "dotenv/config";
import { pool } from "./config/database.js";
try {
  const r = await pool.query(`
    SELECT table_schema, table_name FROM information_schema.tables
     WHERE table_schema='public' AND table_name ILIKE '%ugc%policy%' OR table_name ILIKE '%policy%accept%'
     ORDER BY 1,2`);
  console.log(JSON.stringify(r.rows));
  const r2 = await pool.query(`SELECT routine_name FROM information_schema.routines WHERE routine_schema='public' AND (routine_name ILIKE '%ugc%' OR routine_name ILIKE '%policy%accept%')`);
  console.log(JSON.stringify(r2.rows));
} catch(e){ console.error(e.message); }
finally { await pool.end().catch(()=>{}); }
