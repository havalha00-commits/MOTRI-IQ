import dotenv from "dotenv";
import pg from "pg";

dotenv.config({ path: "./source.env" });

const db = new pg.Pool({
  connectionString: process.env.SOURCE_DATABASE_URL,
  max: 1
});

try {
  const users = await db.query(`
    SELECT COUNT(*)::bigint AS auth_users_count
    FROM auth.users;
  `);
  console.log("========== AUTH USERS ==========");
  console.table(users.rows);

  const buckets = await db.query(`
    SELECT
      id,
      name,
      public,
      to_jsonb(b)->>'file_size_limit' AS file_size_limit,
      to_jsonb(b)->'allowed_mime_types' AS allowed_mime_types
    FROM storage.buckets b
    ORDER BY name;
  `);
  console.log("========== STORAGE BUCKETS ==========");
  console.table(buckets.rows);

  const objects = await db.query(`
    SELECT
      bucket_id,
      COUNT(*)::bigint AS object_count,
      COALESCE(SUM((metadata->>'size')::bigint), 0)::bigint AS total_bytes
    FROM storage.objects
    GROUP BY bucket_id
    ORDER BY bucket_id;
  `);
  console.log("========== STORAGE OBJECT COUNTS ==========");
  console.table(objects.rows);

  const views = await db.query(`
    SELECT
      schemaname,
      viewname,
      definition
    FROM pg_views
    WHERE schemaname = 'public';
  `);
  console.log("========== PUBLIC VIEWS ==========");
  console.table(views.rows);

} catch (e) {
  console.error("ERROR:", e.message);
} finally {
  await db.end();
}
