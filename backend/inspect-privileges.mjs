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
      p.proname AS function_name,
      pg_get_function_identity_arguments(p.oid) AS arguments,
      pg_get_userbyid(p.proowner) AS owner,
      p.prosecdef AS security_definer,
      p.proacl AS privileges
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
    ORDER BY p.proname;
  `);

  console.log("FUNCTION PRIVILEGES:");
  console.table(result.rows);

  const grants = await db.query(`
    SELECT grantee, table_name, privilege_type
    FROM information_schema.role_table_grants
    WHERE table_schema = 'public'
    ORDER BY table_name, grantee, privilege_type;
  `);

  console.log("TABLE GRANTS:", grants.rows.length);
  console.table(grants.rows);

} catch (e) {
  console.error("ERROR:", e.message);
} finally {
  await db.end();
}
