import { pool } from "./config/database.js";

try {
  const result = await pool.query(`
    SELECT table_name
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_type = 'BASE TABLE'
    ORDER BY table_name
  `);

  console.log(`NEON TABLES (${result.rows.length})`);
  for (const row of result.rows) {
    console.log(row.table_name);
  }
} catch (error) {
  console.error("ERROR:", error.message);
} finally {
  await pool.end();
}
