import dotenv from "dotenv";
import pg from "pg";
import { pool as neon } from "./config/database.js";

dotenv.config({ path: "./source.env" });

const source = new pg.Pool({
  connectionString: process.env.SOURCE_DATABASE_URL,
  max: 1
});

try {
  console.log("========== CARS_PUBLIC DEFINITION ==========");
  const view = await source.query(`
    SELECT pg_get_viewdef('public.cars_public'::regclass, true) AS definition
  `);
  console.log(view.rows[0]?.definition ?? "NOT FOUND");

  console.log("\n========== FUNCTION DEFINITIONS ==========");
  const funcs = await source.query(`
    SELECT p.oid::regprocedure::text AS signature,
           pg_get_functiondef(p.oid) AS definition
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prokind = 'f'
    ORDER BY p.proname
  `);

  for (const f of funcs.rows) {
    console.log("\n--- " + f.signature + " ---");
    console.log(f.definition);
  }

  console.log("\n========== TRIGGER DEFINITIONS ==========");
  const triggers = await source.query(`
    SELECT c.relname AS table_name,
           t.tgname AS trigger_name,
           pg_get_triggerdef(t.oid, true) AS definition
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND NOT t.tgisinternal
    ORDER BY c.relname, t.tgname
  `);

  for (const t of triggers.rows) {
    console.log(`\n--- ${t.table_name}.${t.trigger_name} ---`);
    console.log(t.definition);
  }

  console.log("\n========== RLS TABLE STATUS ==========");
  const [s, n] = await Promise.all([
    source.query(`
      SELECT c.relname AS table_name,
             c.relrowsecurity AS rls_enabled,
             c.relforcerowsecurity AS force_rls
      FROM pg_class c
      JOIN pg_namespace ns ON ns.oid = c.relnamespace
      WHERE ns.nspname = 'public' AND c.relkind = 'r'
      ORDER BY c.relname
    `),
    neon.query(`
      SELECT c.relname AS table_name,
             c.relrowsecurity AS rls_enabled,
             c.relforcerowsecurity AS force_rls
      FROM pg_class c
      JOIN pg_namespace ns ON ns.oid = c.relnamespace
      WHERE ns.nspname = 'public' AND c.relkind = 'r'
      ORDER BY c.relname
    `)
  ]);

  console.log("SUPABASE:", JSON.stringify(s.rows));
  console.log("NEON:", JSON.stringify(n.rows));

  console.log("\nREAD-ONLY DEFINITIONS AUDIT COMPLETED");
} catch (e) {
  console.error("AUDIT ERROR:", e.message);
} finally {
  await source.end();
  await neon.end();
}
