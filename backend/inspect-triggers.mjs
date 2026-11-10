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
      n.nspname AS schema_name,
      c.relname AS table_name,
      t.tgname AS trigger_name,
      pg_get_triggerdef(t.oid, true) AS trigger_definition,
      p.proname AS function_name,
      t.tgenabled AS enabled_status
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_proc p ON p.oid = t.tgfoid
    WHERE n.nspname = 'public'
      AND NOT t.tgisinternal
    ORDER BY c.relname, t.tgname;
  `);

  console.log("TOTAL TRIGGERS:", result.rows.length);

  for (const t of result.rows) {
    console.log("\n================================");
    console.log("TABLE:", t.table_name);
    console.log("TRIGGER:", t.trigger_name);
    console.log("FUNCTION:", t.function_name);
    console.log("ENABLED:", t.enabled_status);
    console.log("DEFINITION:", t.trigger_definition);
  }

} catch (e) {
  console.error("ERROR:", e.message);
} finally {
  await source.end();
}
