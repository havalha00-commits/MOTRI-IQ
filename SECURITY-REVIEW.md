# Security Review: UGC Migration and Neon Compatibility

**Review date:** 2026-11-05  
**Scope:** Static review of `supabase/migrations/20261105_ugc_safety.sql` and repository authentication, database, chat, and reporting paths. No live database was contacted and no SQL was executed.

## Finding

| Severity | Confidence | Finding |
|---|---:|---|
| Medium | 9/10 | The proposed migration is written for Supabase Auth and PostgREST, not for a confirmed Neon authentication and authorization setup. It assumes `auth.users`, `auth.uid()`, `auth.role()`, and Supabase roles including `authenticated` and `service_role`. The repository does not establish that these objects exist in production Neon or that Neon requests receive a trusted database identity. |

If those Supabase-specific objects are absent, the migration will fail. If chat and reports are handled through the Neon backend instead, these policies alone do not prove that the backend supplies verified identity or enforces the block/report authorization rules.

## Repository evidence

- `backend/config/database.js` connects to PostgreSQL using `pg` and `DATABASE_URL`.
- `backend/middleware/auth.js` verifies tokens against a configured issuer/JWKS and derives `req.user.id` from the verified JWT subject (`sub`).
- The inspected backend connection code does not show a trusted mechanism for setting that verified actor identity in the database session. The inspected server routes do not show Neon-backed chat or user-report endpoints.
- The Flutter client accesses Supabase directly for chat, block status, user reports, and policy consent. Existing chat and admin migrations also use Supabase Auth identity and roles.
- The repository therefore shows both a Neon-backed API and Supabase-backed chat/report paths; it does not establish which production path is authoritative for chat and reports or provide the live Neon schema and policies.

## Security impact and limits

The proposed RLS rules cannot be relied on to prevent message reads or sends after a block through a Neon API unless that API executes equivalent authorization checks against a trusted server-derived identity. Client-supplied actor IDs must not be trusted. Admin access to reports likewise must be checked server-side using the actual production admin-membership source; the repository's `app_admins` references do not establish that this table exists in production Neon.

The review cannot confirm the live schema, existing policies, Neon role grants, or deployed routes from repository files alone. Consequently, a Neon-compatible migration cannot safely be authored from the available evidence without inventing schema or identity assumptions.

## Recommended next steps

1. Confirm the production chat/report API path, token issuer and verification configuration, and how authenticated identity is conveyed to Neon.
2. Obtain the authoritative Neon schema, grants, existing row-level security policies, and admin-membership model through a reviewed schema export or deployment artifacts.
3. Implement blocking, message read/send checks, reports, and admin review on the authoritative backend path. Derive actor identity from verified credentials, never request payload identity fields.
4. Produce a migration against the confirmed schema, then review and test it against a disposable/staging database before considering production deployment.
5. Take and verify a production backup before any approved database change.

## Database state

No SQL was executed. No live Neon or Supabase database was accessed or changed, and no data was deleted. `supabase/migrations/20261105_ugc_safety.sql` remains a proposed Supabase-specific migration and is not approved for Neon deployment.
