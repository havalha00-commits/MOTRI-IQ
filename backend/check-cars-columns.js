import { pool } from "./config/database.js";

try {
  const result = await pool.query(`
    SELECT column_name, data_type, is_nullable
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'cars'
    ORDER BY ordinal_position
  `);

  console.table(result.rows);
} catch (error) {
  console.error(error.message);
} finally {
  await pool.end();
}
