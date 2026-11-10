import dotenv from "dotenv";
import pg from "pg";
import { pool as neon } from "./config/database.js";

dotenv.config({ path: "./source.env" });

const source = new pg.Pool({
  connectionString: process.env.SOURCE_DATABASE_URL,
  max: 1,
  connectionTimeoutMillis: 15000
});

const quote = (name) => '"' + name.replace(/"/g, '""') + '"';

async function inspect(db) {
  const tables = await db.query(`
    SELECT table_name
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_type = 'BASE TABLE'
    ORDER BY table_name
  `);

  const result = {};

  for (const { table_name } of tables.rows) {
    const columns = await db.query(`
      SELECT column_name, data_type, udt_name,
             is_nullable, column_default
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = $1
      ORDER BY ordinal_position
    `, [table_name]);

    const count = await db.query(
      `SELECT count(*)::bigint AS total FROM public.${quote(table_name)}`
    );

    result[table_name] = {
      count: count.rows[0].total,
      columns: columns.rows
    };
  }

  return result;
}

try {
  console.log("Reading Supabase...");
  const src = await inspect(source);

  console.log("Reading Neon...");
  const dst = await inspect(neon);

  const srcNames = Object.keys(src);
  const dstNames = Object.keys(dst);

  console.log("\n========== TABLE COMPARISON ==========");
  console.log("Supabase:", srcNames.length, "| Neon:", dstNames.length);

  console.log("\n========== SOURCE ONLY ==========");
  const sourceOnly = srcNames.filter(t => !dst[t]);
  console.log(sourceOnly.length ? sourceOnly.join("\n") : "None");

  console.log("\n========== NEON ONLY ==========");
  const neonOnly = dstNames.filter(t => !src[t]);
  console.log(neonOnly.length ? neonOnly.join("\n") : "None");

  console.log("\n========== ROW COUNTS ==========");
  for (const name of srcNames) {
    console.log(
      `${name}: Supabase=${src[name].count}, Neon=${dst[name]?.count ?? "TABLE MISSING"}`
    );
  }

  console.log("\n========== COLUMN DIFFERENCES ==========");
  let differences = 0;

  for (const name of srcNames) {
    if (!dst[name]) continue;

    const sourceCols = src[name].columns;
    const targetCols = dst[name].columns;
    const targetMap = new Map(targetCols.map(c => [c.column_name, c]));

    for (const col of sourceCols) {
      const other = targetMap.get(col.column_name);

      if (!other) {
        console.log(`${name}.${col.column_name}: MISSING IN NEON`);
        differences++;
        continue;
      }

      for (const key of ["data_type", "udt_name", "is_nullable", "column_default"]) {
        if (col[key] !== other[key]) {
          console.log(
            `${name}.${col.column_name}: ${key} differs (Supabase=${col[key]}, Neon=${other[key]})`
          );
          differences++;
        }
      }
    }

    const sourceColNames = new Set(sourceCols.map(c => c.column_name));
    for (const col of targetCols) {
      if (!sourceColNames.has(col.column_name)) {
        console.log(`${name}.${col.column_name}: EXTRA IN NEON`);
        differences++;
      }
    }
  }

  console.log("\nTotal column differences:", differences);
  console.log("\nREAD-ONLY AUDIT COMPLETED");
} catch (error) {
  console.error("AUDIT ERROR:", error.message);
} finally {
  await source.end();
  await neon.end();
}
