# G10.45 — Backblaze B2 Isolated Integration (PREPARATION ONLY)

**Status:** Backblaze B2 = **NOT VERIFIED**. This document prepares configuration and fail-closed test scaffolding only. **No live Backblaze B2 requests were performed.**

## Target (exact, isolated)
- Endpoint (exact): `https://s3.eu-central-003.backblazeb2.com`
- Region (exact): `eu-central-003`
- Bucket (exact, isolated only): `motri-iq-isolated-test-2026`
- Database for any future DB-touching tests: `motri_iq_test` only (assert `current_database()`).
- Credentials: **read from local environment only** (`B2_KEY_ID`, `B2_APPLICATION_KEY`). **Never hardcode. Never commit. Never use a Master Application Key.** Use a restricted, non-master application key scoped only to `motri-iq-isolated-test-2026`.

## Environment variables (placeholders; values provided locally at runtime only)
Set only in a non-committed local env/session (never `backend/.env` committed, never Git):
- `B2_ENDPOINT=https://s3.eu-central-003.backblazeb2.com`
- `B2_REGION=eu-central-003`
- `B2_BUCKET=motri-iq-isolated-test-2026`
- `B2_KEY_ID=<local env only>`
- `B2_APPLICATION_KEY=<local env only>`
- Optional: `B2_PUBLIC_BASE` (verify before use; `wallet_receipts`/private buckets never public)

`backend/services/objectStorage.js` resolves S3-compatible config from `R2_*` or `B2_*` env vars (B2 fallbacks added) and accepts explicit constructor args. Existing AWS SDK deps (`@aws-sdk/client-s3`, `@aws-sdk/s3-request-presigner`) are reused. **No Flutter/API contract changes.**

## Fail-closed gates (must all pass before any future live B2 test runs)
Enforced by `backend/test/helpers/b2_readiness.js` / `storage_b2_integration.test.js`:
1. Explicit opt-in: `B2_LIVE_INTEGRATION=1`
2. Explicit bucket acknowledgement: `B2_LIVE_ACK=motri-iq-isolated-test-2026`
3. Exact endpoint: `https://s3.eu-central-003.backblazeb2.com`
4. Exact region: `eu-central-003`
5. Exact bucket: `motri-iq-isolated-test-2026` (rejects any production/other bucket)
6. Credentials present in env (presence only; values never inspected/printed)
7. Database identity: `current_database() == motri_iq_test` before DB operations
`NODE_ENV` is **not** used as a safety proof.

## Test scaffolding (disabled by default)
- `backend/test/storage_b2_integration.test.js` — opt-in (`B2_LIVE_INTEGRATION=1`) and **fail-closed**; the live path asserts guards + DB isolation then intentionally fails with NOT VERIFIED until an explicitly approved live flow is implemented. **No PUT/GET/DELETE/HEAD/sign network calls to Backblaze are executed in preparation.**
- Safe unit/guard tests in the same file run with normal local tests (no network).

## Prohibited
- No connection to Backblaze during preparation. No real B2 requests. No secret printing. No changes to `backend/.env`. No master application key. No `motri_iq_migrated`/`neondb`/Supabase/production. No Flutter/API contract changes. Do not treat `s3rver` as Backblaze R2/B2 evidence.
