import dotenv from "dotenv";
import pg from "pg";

dotenv.config({ path: "./source.env" });

const db = new pg.Pool({
  connectionString: process.env.SOURCE_DATABASE_URL,
  max: 1
});

try {
  const result = await db.query(`
    SELECT
      n.nspname AS schema_name,
      c.relname AS table_name,
      t.tgname AS trigger_name,
      p.proname AS function_name,
      t.tgenabled AS enabled,
      pg_get_triggerdef(t.oid, true) AS definition
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_proc p ON p.oid = t.tgfoid
    WHERE n.nspname IN ('public', 'auth')
      AND NOT t.tgisinternal
    ORDER BY n.nspname, c.relname, t.tgname;
  `);

  console.log("TOTAL TRIGGERS:", result.rows.length);
  console.table(result.rows);

} catch (e) {
  console.error("ERROR:", e.message);
} finally {
  await db.end();
}
