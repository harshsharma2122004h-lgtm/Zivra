# ZIVRA Premium Redesign — Safe Implementation Branch

Branch: `zivra/premium-redesign-safe`

## Added in this branch
- `admin-content-studio.html`: separate authenticated owner workspace for theme-specific homepage copy, hero campaign, poster JSON, ordered section JSON, marquee and brand story. Uses the existing Supabase admin role claim and saves drafts/published records to `zivra_site_content`; it does not alter the existing admin dashboard.
- `zivra-premium-preview.html`: isolated, responsive dual-theme editorial homepage preview. It does not replace `index.html` and its collection links intentionally return to the current storefront until the integration is tested.
- `supabase/migrations/20261104_zivra_premium_foundation.sql`: additive schema foundation for customer profiles, saved addresses, wishlist, customer-linked orders, product media/variant metadata and editable published site content.

## Safety decisions
- The existing `index.html`, `admin.html`, checkout RPCs and payment functions have not been modified.
- No live Supabase migration has been run from this branch.
- No payment method has been enabled or changed. Do not accept live online payments until payment intent reconciliation, webhook verification and end-to-end order creation are tested.
- Existing guest orders are not automatically attached to customer accounts based only on matching email/phone.
- Admin authorization continues to rely on the server-managed `app_metadata.role = 'admin'` claim.

## Not yet complete
This is a first implementation slice, not a completed launch. Remaining work includes the authenticated content editor and media upload flow, product variant stock transactions, customer OTP UI/provider configuration, customer account pages and wishlist integration, order tracking UI, full admin integration, and end-to-end regression tests for COD and payment reconciliation.

## Verification required before merge
1. Apply the migration to a staging Supabase project first and inspect RLS behavior using anon, customer and admin accounts.
2. Confirm OTP providers/templates and rate limits in Supabase Auth.
3. Test a guest COD order, authenticated COD order, duplicate submit, out-of-stock cart, and order history.
4. Verify existing admin sign-in and all current admin operations still work.
5. Keep online payment disabled until the verified webhook and payment ledger reconciliation pass.
6. Only merge after review and staging tests; this branch is not a production deployment.
