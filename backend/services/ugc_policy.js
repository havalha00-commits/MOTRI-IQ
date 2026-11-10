import { pool } from "../config/database.js";

// G10.62 P3.4E: isolated local-test bootstrap must not implicitly load backend/.env.
// Normal non-local startup preserves dotenv loading.
if (process.env.MOTRI_LOCAL_TEST_ISOLATED !== "1") {
  const dotenv = await import("dotenv");
  dotenv.default?.config?.();
}

export const UGC_POLICY_VERSION = "2026-11-05";
let ensured = false;

async function ensureTable(database) {
  if (ensured) return;
  await database.query(`
    CREATE TABLE IF NOT EXISTS public.ugc_policy_acceptances (
      user_id uuid NOT NULL,
      policy_version text NOT NULL,
      accepted_at timestamptz NOT NULL DEFAULT now(),
      PRIMARY KEY (user_id, policy_version)
    )`);
  ensured = true;
}

export function createUgcPolicyService({ database = pool } = {}) {
  return {
    async hasAccepted(req) {
      await ensureTable(database);
      const userId = req?.user?.id;
      if (!userId) throw new Error("Verified user identity is unavailable");
      const r = await database.query(
        `SELECT 1 FROM public.ugc_policy_acceptances WHERE user_id=$1 AND policy_version=$2 LIMIT 1`,
        [userId, UGC_POLICY_VERSION]
      );
      return r.rowCount > 0;
    },
    async accept(req) {
      await ensureTable(database);
      const userId = req?.user?.id;
      if (!userId) throw new Error("Verified user identity is unavailable");
      const r = await database.query(
        `INSERT INTO public.ugc_policy_acceptances (user_id, policy_version, accepted_at)
         VALUES ($1,$2,now())
         ON CONFLICT (user_id, policy_version) DO UPDATE SET accepted_at=EXCLUDED.accepted_at
         RETURNING user_id`,
        [userId, UGC_POLICY_VERSION]
      );
      return r.rowCount > 0;
    },
  };
}

export const ugcPolicy = createUgcPolicyService();
