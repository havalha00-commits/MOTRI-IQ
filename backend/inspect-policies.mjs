import dotenv from "dotenv";
import pg from "pg";

dotenv.config({ path: "./source.env" });

const source = new pg.Pool({
  connectionString: process.env.SOURCE_DATABASE_URL,
  max: 1
});

try {
  const result = await source.query(`
    SELECT tablename, policyname, permissive,
           roles, cmd, qual, with_check
    FROM pg_policies
    WHERE schemaname = 'public'
    ORDER BY tablename, policyname
  `);

  console.log("TOTAL POLICIES:", result.rows.length);

  for (const p of result.rows) {
    console.log("\n================================");
    console.log("TABLE:", p.tablename);
    console.log("POLICY:", p.policyname);
    console.log("COMMAND:", p.cmd);
    console.log("ROLES:", p.roles);
    console.log("USING:", p.qual);
    console.log("WITH CHECK:", p.with_check);
  }
} catch (e) {
  console.log("ERROR:", e.message);
} finally {
  await source.end();
}
