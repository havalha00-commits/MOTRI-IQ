import dotenv from "dotenv";
import pg from "pg";

dotenv.config({ path: "./source.env" });

const source = new pg.Pool({
  connectionString: process.env.SOURCE_DATABASE_URL,
  max: 1
});

try {
  const result = await source.query(`
    SELECT
      n.nspname AS schemaname,
      c.relname AS tablename,
      c.relrowsecurity AS rowsecurity,
      c.relforcerowsecurity AS forcerowsecurity
    FROM pg_class c
    JOIN pg_namespace n
      ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind IN ('r', 'p')
    ORDER BY c.relname
  `);

  console.table(result.rows);

  console.log("TOTAL TABLES:", result.rows.length);
  console.log("RLS ENABLED:",
    result.rows.filter(r => r.rowsecurity).length);
  console.log("FORCE RLS:",
    result.rows.filter(r => r.forcerowsecurity).length);

} catch (e) {
  console.error("ERROR:", e.message);
} finally {
  await source.end();
}
