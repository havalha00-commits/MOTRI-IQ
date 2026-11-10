# Google Play reviewer access

Account label: Google Play review account

Email / sign-in identifier: Alijasimuhammed+playreview@gmail.com
Display name: Google Play Reviewer

Use **email and password**, not username or phone sign-in. The backend username-login function currently returns no session; that path is not verified.

The generated password is intentionally excluded from project source and release ZIPs. Supply it privately in Play Console → Sign in details.

Paste these reviewer instructions:

> Open MOTRI IQ and select Profile (حسابي in Arabic). Enter the supplied email address in the Account field and the supplied password, then tap Log in. This reviewer account uses email/password authentication; no OTP, phone verification or email confirmation is required by the current backend configuration. Guest browsing is also available. Once signed in, use Profile to reach account features. Paid business placements and wallet top-ups are disabled in the Google Play build. This is a regular reviewer account, not an administrator account.

Do not expire, delete or change the account credentials while Google review is pending. Recheck the exact uploaded Android build before submission. No real-user data or staff/admin privileges were added to this account.

Verification: email/password backend login passed; own profile/favorites/listings reads passed; no admin membership. Native Android integration test passed through the actual login form and opened Favorites on the isolated API 35 emulator with PLAY_STORE_BUILD=true. The test signed out afterward. This used current app source with a debug test entrypoint, not the signed upload AAB.
