# Screen-state inventory

All 38 active screens are listed below. “Inline” means that state belongs to a subsection, action, media loader, or session gate rather than replacing the entire page. This inventory is not a claim that every state has completed current visual acceptance.

| Screen | Loading | Empty | Error | Populated | State model |
|---|---|---|---|---|---|
| HomePage | Inline / N/A | Inline / N/A | Inline / N/A | Yes | Navigation shell; asynchronous discovery belongs to HomeTab and each destination. |
| HomeTab | Yes | Yes | Yes | Yes | Required car feed and selected market feed; optional empty sections collapse. Each feed has independent state. |
| CarRequestsPage | Yes | Yes | Yes | Yes | Asynchronous list/query with loading, failed read, successful empty and populated response. Search also has an idle state; role/session gates are additional states. |
| CompareCarsPage | Inline / N/A | Yes | Inline / N/A | Yes | Synchronous comparison snapshot; empty, one and two selected vehicles. No asynchronous page loader or query-error state. |
| CarDetailsPage | Inline / N/A | Inline / N/A | Inline / N/A | Yes | Receives car data from the caller. Optional market estimate, seller reputation, image loading/error and admin checks are independent; their failures must not replace the listing. |
| SectionPage | Yes | Yes | Yes | Yes | Asynchronous list/query with loading, failed read, successful empty and populated response. Search also has an idle state; role/session gates are additional states. |
| FavoritesPage | Yes | Yes | Yes | Yes | Asynchronous list/query with loading, failed read, successful empty and populated response. Search also has an idle state; role/session gates are additional states. |
| SearchTab | Yes | Yes | Yes | Yes | Asynchronous list/query with loading, failed read, successful empty and populated response. Search also has an idle state; role/session gates are additional states. |
| AddCarTab | Inline / N/A | Inline / N/A | Inline / N/A | Yes | Immediately usable local draft form. Empty photos, validation, location lookup, picker/preview, upload/publish pending/failure/success and optional price estimates are independent inline/action states. |
| MyAdsPage | Yes | Yes | Yes | Yes | Asynchronous list/query with loading, failed read, successful empty and populated response. Search also has an idle state; role/session gates are additional states. |
| ManageShowroomPage | Yes | Inline / N/A | Yes | Yes | Editor loads an existing or new showroom draft. Missing row means a usable blank form; save validation/pending/error/success are action states. |
| SellerProfilePage | Yes | Inline / N/A | Yes | Yes | Profile loads asynchronously; missing showroom, no cars, no offers and no reviews are independent empty subsections rather than a blank entire profile. |
| MySentOffersPage | Yes | Yes | Yes | Yes | Asynchronous list/query with loading, failed read, successful empty and populated response. Search also has an idle state; role/session gates are additional states. |
| CarOfferChatPage | Yes | Yes | Yes | Yes | Asynchronous list/query with loading, failed read, successful empty and populated response. Search also has an idle state; role/session gates are additional states. |
| AdminAdsManagementPage | Yes | Yes | Yes | Yes | Asynchronous list/query with loading, failed read, successful empty and populated response. Search also has an idle state; role/session gates are additional states. |
| AdminDashboardPage | Yes | Yes | Yes | Yes | Asynchronous list/query with loading, failed read, successful empty and populated response. Search also has an idle state; role/session gates are additional states. |
| AdminBusinessAdsPage | Yes | Yes | Yes | Yes | Asynchronous list/query with loading, failed read, successful empty and populated response. Search also has an idle state; role/session gates are additional states. |
| ActivityNotificationsPage | Yes | Yes | Yes | Yes | Asynchronous list/query with loading, failed read, successful empty and populated response. Search also has an idle state; role/session gates are additional states. |
| AlertsPage | Yes | Yes | Yes | Yes | Asynchronous list/query with loading, failed read, successful empty and populated response. Search also has an idle state; role/session gates are additional states. |
| UserProfilePage | Yes | Inline / N/A | Yes | Yes | Authenticated profile read; no username row uses metadata/email/default-name fallback. Guest has a sign-in state, not an empty profile list. |
| MyFollowsPage | Yes | Yes | Yes | Yes | Asynchronous list/query with loading, failed read, successful empty and populated response. Search also has an idle state; role/session gates are additional states. |
| MyMessagesPage | Yes | Yes | Yes | Yes | Asynchronous list/query with loading, failed read, successful empty and populated response. Search also has an idle state; role/session gates are additional states. |
| MyReviewsPage | Yes | Yes | Yes | Yes | Asynchronous list/query with loading, failed read, successful empty and populated response. Search also has an idle state; role/session gates are additional states. |
| SettingsPage | Yes | Inline / N/A | Yes | Yes | Preferences read is asynchronous; defaults represent missing values. Pending writes are per-switch action states; there is no empty-settings page. |
| AboutPage | Inline / N/A | Inline / N/A | Inline / N/A | Yes | Static app information is immediately available. PackageInfo metadata loads independently; missing/failed metadata uses an explicit unavailable value. |
| SupportCenterPage | Inline / N/A | Inline / N/A | Inline / N/A | Yes | Static localized FAQ and contact/report entry points. Contact sheet, report editor, share failure and external-app handoff belong to action states. |
| AccountTab | Inline / N/A | Inline / N/A | Inline / N/A | Yes | Guest sign-in/signup and signed-in account are primary states. Auth-option preparation, verification, username editing, message counts and auth failures are inline/modal actions, not a page-level feed empty state. |
| FinesPage | Inline / N/A | Inline / N/A | Inline / N/A | Yes | Static external-service choices. Link-launch failure is action feedback; the app does not load traffic-fine records. |
| WalletTopUpPage | Yes | Yes | Yes | Yes | Wallet configuration read; empty means no configured payment account. Receipt picker/upload and transaction submission have separate action states; guest state precedes loading. |
| WalletAdminReviewPage | Yes | Yes | Yes | Yes | Asynchronous list/query with loading, failed read, successful empty and populated response. Search also has an idle state; role/session gates are additional states. |
| SearchHistoryPage | Yes | Yes | Yes | Yes | Asynchronous list/query with loading, failed read, successful empty and populated response. Search also has an idle state; role/session gates are additional states. |
| PrivacyPolicyPage | Inline / N/A | Inline / N/A | Inline / N/A | Yes | Bundled localized PolicyDocument; no remote query, asynchronous loader or empty collection. |
| TermsOfUsePage | Inline / N/A | Inline / N/A | Inline / N/A | Yes | Bundled localized PolicyDocument; no remote query, asynchronous loader or empty collection. |
| BusinessAdsPage | Yes | Yes | Yes | Yes | Asynchronous list/query with loading, failed read, successful empty and populated response. Search also has an idle state; role/session gates are additional states. |
| BusinessAdDetailsPage | Inline / N/A | Inline / N/A | Inline / N/A | Yes | Receives BusinessAdData from the caller; missing media/contact/hours use local fallback. View counters and share/contact actions are independent side effects. |
| CreateBusinessAdPage | Yes | Yes | Yes | Yes | Draft remains visible while package selector loads; selector may fail, contain no packages, or contain selectable packages. Picker/upload/submission and acknowledgement states are additional. |
| PaymentPage | Inline / N/A | Inline / N/A | Inline / N/A | Yes | Receives selected ad/package/price from caller and renders a local summary. Support/contact handoff is an action, not a page-level data fetch. |
| MarketItemDetailsPage | Inline / N/A | Inline / N/A | Inline / N/A | Yes | Receives item data from the caller; missing media/specs use local fallback. Admin lookup, image editor and delete actions are independent session-scoped states. |

Detailed source locations, component hashes, test locators and scoped revision references: [ui_screen_state_matrix.json](ui_screen_state_matrix.json).

Modal flow register: [ui_modal_flow_crosswalk.json](ui_modal_flow_crosswalk.json). Completion and staging limits: [ui_completion_audit.json](ui_completion_audit.json).

The current normal-build source/font manifest matches the application source. This pass changed audit documentation only.
