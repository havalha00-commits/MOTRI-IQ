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
      p.proname AS function_name,
      pg_get_function_identity_arguments(p.oid) AS arguments,
      pg_get_function_result(p.oid) AS return_type,
      l.lanname AS language,
      p.prosecdef AS security_definer,
      p.provolatile AS volatility,
      pg_get_functiondef(p.oid) AS definition
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    JOIN pg_language l ON l.oid = p.prolang
    WHERE n.nspname = 'public'
    ORDER BY p.proname;
  `);

  console.log("TOTAL FUNCTIONS:", result.rows.length);

  for (const f of result.rows) {
    console.log("\n================================");
    console.log("FUNCTION:", f.function_name);
    console.log("ARGUMENTS:", f.arguments);
    console.log("RETURN:", f.return_type);
    console.log("LANGUAGE:", f.language);
    console.log("SECURITY DEFINER:", f.security_definer);
    console.log("DEFINITION:\n", f.definition);
  }
} catch (e) {
  console.error("ERROR:", e.message);
} finally {
  await source.end();
}
