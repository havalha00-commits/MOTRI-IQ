import dotenv from "dotenv";
import pg from "pg";

dotenv.config({ path: "./source.env" });

const db = new pg.Pool({
  connectionString: process.env.SOURCE_DATABASE_URL,
  max: 1
});

try {
  const roles = await db.query(`
    SELECT
      rolname,
      rolsuper,
      rolbypassrls,
      rolinherit,
      rolcreaterole,
      rolcreatedb,
      rolcanlogin
    FROM pg_roles
    WHERE rolname IN (
      'anon',
      'authenticated',
      'service_role',
      'postgres',
      'authenticator'
    )
    ORDER BY rolname;
  `);

  console.log("ROLE SECURITY:");
  console.table(roles.rows);

  const memberships = await db.query(`
    SELECT
      member.rolname AS member,
      granted.rolname AS granted_role,
      m.admin_option
    FROM pg_auth_members m
    JOIN pg_roles member ON member.oid = m.member
    JOIN pg_roles granted ON granted.oid = m.roleid
    WHERE member.rolname IN (
      'anon',
      'authenticated',
      'service_role',
      'authenticator'
    )
    ORDER BY member.rolname, granted.rolname;
  `);

  console.log("ROLE MEMBERSHIPS:");
  console.table(memberships.rows);

} catch (e) {
  console.error("ERROR:", e.message);
} finally {
  await db.end();
}
