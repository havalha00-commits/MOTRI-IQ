# Data safety — source-based worksheet, not a submitted declaration

Review every answer against the deployed backend and current SDK disclosures. The publisher must certify actual practice in Play Console; this file is not proof of backend security or policy compliance.

| Google data category | Source evidence | Draft treatment / purpose |
|---|---|---|
| Name, email, phone, user IDs | Supabase Auth; profiles, usernames, seller/showroom forms | Collected for account management and app functionality; public listing contact details are user-selected and visible to other users |
| Photos | Cars/market/business/showroom image uploads; legacy wallet receipt images for admins | Collected for app functionality; public ad images shared with viewers; receipts should be private under reviewed RLS/storage policy |
| Approximate / precise location | Business location selection; optional coordinates in listings; network address processed by hosting services | Optional location collection when selected, app functionality; no ad SDK is packaged in version code 5 |
| Other in-app messages | car_offer_messages, offers, requests, seller reviews and reports | Collected, stored server-side; messages shared with conversation participants and moderation as applicable |
| App interactions / search history | saved_searches; business_ad_events (impression/click/contact), seller_response_tracking | Functionality and analytics as applicable; paid business feed is suppressed in the Play build, but backend records remain |
| Device or other IDs, diagnostics | Google Mobile Ads and UMP removed from version code 5; ad ID permissions explicitly excluded | Do not declare advertising collection solely from the removed SDK. Review remaining plugins and actual backend logging for any other identifiers or diagnostics |
| Purchase history / financial information | Legacy wallet_transactions and wallet_receipts accessible to authorized staff | Paid entry points disabled in this Play build. Review whether the remaining staff/legacy flows still mean these categories must be declared; never claim the entire backend has no financial data |

Version code 5 is ad-free: select Contains ads = No for this replacement build after verifying its manifest. Google Mobile Ads/UMP are removed; AD_ID and AdServices permissions are absent. Paid business-ad feeds and paid placement/top-up entry points are disabled in the Play build. User-created car and marketplace listings remain normal app content. Do not use the old version-code-4 bundle for this declaration.

HTTPS endpoints are used by the client. Do not assert encryption-at-rest, audited RLS correctness or automatic account deletion without verifying the actual services. No service-role key belongs in the app.

Deletion URL: https://motri-iq-account-deletion.me-0eca.chatgpt.site/
In-app path: Account → Settings → Delete account and data (Settings is also available to guests).
The portal receives requests. The operator still needs a tested backend deletion procedure and precise processing/retention periods. The portal privacy notice is for the portal, not a substitute for the full mobile-app privacy policy.

Sources:
- https://support.google.com/googleplay/android-developer/answer/10787469
- https://developers.google.com/admob/android/privacy/play-data-disclosure
- https://support.google.com/googleplay/android-developer/answer/13327111

## Play Console draft saved — 25 October 2026

All 12 selected data types have completed handling answers. Saved with **Save as draft**; not sent for review. Exact choices and remaining review items are recorded in play-console-data-safety-draft.json. Precise location is declared collected and shared with Nominatim, optional and not ephemeral; OSMF states its public API use does not establish a controller/processor relationship and its privacy policy describes service records. This updates the earlier generic location worksheet guidance. Favorites/follows are included under Other actions, with app functionality and personalization. The final declaration still needs publisher review of actual operations and deletion/retention implementation.
