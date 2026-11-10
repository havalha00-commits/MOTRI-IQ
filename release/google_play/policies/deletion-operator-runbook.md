# MOTRI IQ deletion-request operations

The public form records requests in this Site’s D1 database. It does not have app-backend administrator credentials and cannot itself delete a Supabase user. Never describe a recorded request as completed deletion.

The /admin route requires ChatGPT sign-in and a server-side ADMIN_EMAILS match. The supplied support address and the Site owner are configured. Public API calls cannot list requests or change their statuses. No automatic email notifications are configured; check the queue regularly.

1. Contact the requester using their registered account channel. Never request a password or login OTP. A contact address submitted in the form is not proof of account ownership.
2. Verify the identity against the app account using an approved, documented procedure. Record Ownership verified only after that check.
3. In a backed-up, authorized Supabase environment, inventory linked data before executing deletion. Include auth user/profile/username, cars and market items, business/showroom records, media/storage objects, favorites/follows, saved searches/alerts, requests/offers/messages, reviews/reports, activity and legacy wallet/receipt records. Retention requirements and third-party participants’ records need a deliberate decision; deleting auth.users alone may fail foreign keys or leave orphaned objects.
4. Complete account/data deletion in the actual backend using a reviewed procedure. Inform the requester of completion and explain any narrowly retained records and exact duration.
5. Only then mark Completed outside this portal. This status change does not perform backend deletion. Never use the dashboard to simulate completing a real request.

Before Google Play submission, the operator must adopt and test an actual deletion procedure, set processing/retention periods, and test administrative access. This site does not establish those operational facts. Public policy text must be reviewed against actual practices. Request records contain personal data: decide and implement a retention/cleanup schedule rather than keeping them indefinitely. No public request lookup endpoint is provided.

Local QA uses disposable example.invalid request records in the local database only. No real account deletion was performed.
