import dotenv from "dotenv";
import pg from "pg";

dotenv.config({ path: "./source.env" });

const db = new pg.Pool({
  connectionString: process.env.SOURCE_DATABASE_URL,
  max: 1
});

try {
  const schemas = await db.query(`
    SELECT
      n.nspname AS schema_name,
      COUNT(*) FILTER (WHERE c.relkind IN ('r','p')) AS tables,
      COUNT(*) FILTER (WHERE c.relkind = 'v') AS views,
      COUNT(*) FILTER (WHERE c.relkind = 'm') AS materialized_views,
      COUNT(*) FILTER (WHERE c.relkind = 'S') AS sequences,
      COUNT(*) FILTER (WHERE c.relkind = 'f') AS foreign_tables
    FROM pg_namespace n
    LEFT JOIN pg_class c ON c.relnamespace = n.oid
    WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
      AND n.nspname NOT LIKE 'pg_toast%'
      AND n.nspname NOT LIKE 'pg_temp_%'
    GROUP BY n.nspname
    ORDER BY n.nspname;
  `);

  console.log("========== SCHEMA INVENTORY ==========");
  console.table(schemas.rows);

  const functions = await db.query(`
    SELECT
      n.nspname AS schema_name,
      COUNT(*) AS function_count
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
    GROUP BY n.nspname
    ORDER BY n.nspname;
  `);

  console.log("========== FUNCTIONS BY SCHEMA ==========");
  console.table(functions.rows);

  const extensions = await db.query(`
    SELECT extname, extversion, n.nspname AS schema_name
    FROM pg_extension e
    JOIN pg_namespace n ON n.oid = e.extnamespace
    ORDER BY extname;
  `);

  console.log("========== EXTENSIONS ==========");
  console.table(extensions.rows);

  const customTypes = await db.query(`
    SELECT
      n.nspname AS schema_name,
      t.typname AS type_name,
      t.typtype AS type_kind
    FROM pg_type t
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
      AND t.typtype IN ('e', 'd', 'c')
      AND NOT EXISTS (
        SELECT 1 FROM pg_class c WHERE c.reltype = t.oid
      )
    ORDER BY n.nspname, t.typname;
  `);

  console.log("========== CUSTOM TYPES ==========");
  console.table(customTypes.rows);

  const publications = await db.query(`
    SELECT
      pubname,
      schemaname,
      tablename
    FROM pg_publication_tables
    ORDER BY pubname, schemaname, tablename;
  `);

  console.log("========== PUBLICATION TABLES ==========");
  console.table(publications.rows);

} catch (e) {
  console.error("ERROR:", e.message);
} finally {
  await db.end();
}
