import dotenv from "dotenv";
import pg from "pg";
import { pool as neon } from "./config/database.js";

dotenv.config({ path: "./source.env" });

const source = new pg.Pool({
  connectionString: process.env.SOURCE_DATABASE_URL,
  max: 1
});

const checks = {
  VIEWS: `
    SELECT table_name AS name
    FROM information_schema.views
    WHERE table_schema='public'
    ORDER BY name
  `,
  FUNCTIONS: `
    SELECT routine_name AS name
    FROM information_schema.routines
    WHERE specific_schema='public'
    ORDER BY name
  `,
  TRIGGERS: `
    SELECT trigger_name AS name
    FROM information_schema.triggers
    WHERE trigger_schema='public'
    ORDER BY name
  `,
  POLICIES: `
    SELECT tablename || '.' || policyname AS name
    FROM pg_policies
    WHERE schemaname='public'
    ORDER BY name
  `,
  INDEXES: `
    SELECT tablename || '.' || indexname AS name
    FROM pg_indexes
    WHERE schemaname='public'
    ORDER BY name
  `
};

try {
  for (const [label, sql] of Object.entries(checks)) {
    const [s, n] = await Promise.all([
      source.query(sql),
      neon.query(sql)
    ]);

    const a = s.rows.map(x => x.name);
    const b = n.rows.map(x => x.name);

    console.log(`\n========== ${label} ==========`);
    console.log(`Supabase: ${a.length} | Neon: ${b.length}`);

    const missing = a.filter(x => !b.includes(x));
    const extra = b.filter(x => !a.includes(x));

    console.log("MISSING IN NEON:");
    console.log(missing.length ? missing.join("\n") : "None");

    console.log("EXTRA IN NEON:");
    console.log(extra.length ? extra.join("\n") : "None");
  }

  console.log("\nREAD-ONLY OBJECT AUDIT COMPLETED");
} catch (e) {
  console.log("AUDIT ERROR:", e.message);
} finally {
  await source.end();
  await neon.end();
}
