# Public web app hosting

Live app: https://motri-iq-app.me-0eca.chatgpt.site/

Published using Sites hosting. No paid plan, domain purchase, or billing configuration was added. The public app was opened in Chrome and verified with loaded live listing photos and navigation.

The static hosting checkout is sites/motri-iq-web; it has its own source repository. To update, build the current Flutter release, replace that checkout's dist/ with build/web/, package using the Sites source workflow, then save and deploy the returned source commit/archive. Preserve its .openai/hosting.json identity. See web_hosting_deployment.json for the successful version and deployment.

The Supabase backend remains the existing backend and has its own usage/plan limits. Configure the new HTTPS origin in authentication redirect allowlists before using email/OAuth recovery flows. Hosting success does not certify every authenticated workflow or close the mobile release blockers.

The earlier Codemagic address remains a testing preview; this is the new client-facing address.
