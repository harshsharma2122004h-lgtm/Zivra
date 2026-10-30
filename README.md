# ZIVRA Fashion Store

This repository contains the ZIVRA website files prepared for GitHub upload.

## Files
- `index.html` — main storefront / shopping flow
- `admin.html` — admin and database studio preview
- `preview.html` — fixed storefront preview

## Publish with GitHub Pages
1. Create a new repository on GitHub.
2. Upload these files to the repository root.
3. Open **Settings → Pages**.
4. Under **Build and deployment**, select **Deploy from a branch**.
5. Choose the `main` branch and `/ (root)`, then save.
6. Wait for the published site link to appear in the Pages section.

## Supabase note
These files are the saved HTML versions of the website. This package does not include a verified live Supabase project connection or secret credentials. Before using Supabase for real data, configure the project URL and public anon key in the frontend and add the required database tables / Row Level Security policies. Never put a Supabase service-role key in browser code.

## Important
GitHub Pages can host this static HTML package. If the project later uses a build system or server-side functions, it will need the corresponding source files and deployment setup too.


## Supabase setup (ZIVRA)

The public project configuration is stored in `supabase-config.js`. It contains only the Supabase project URL and publishable browser key; never add a service-role/secret key to the repository.

1. Open the Supabase project linked to this repository.
2. Go to **SQL Editor → New query**.
3. Paste and run the contents of `supabase-schema.sql`.
4. Confirm that the `products`, `orders`, and `order_items` tables exist.
5. Before launch, connect admin sign-in and assign the approved administrator the server-managed `app_metadata.role = admin` claim. Do not grant admin access through user-editable metadata.

The schema includes public read access to active products, admin-only order access, and a database-side guest-order function that recalculates prices and stock. The existing HTML preview pages are not yet fully wired to these tables; online payments and order emails are also not activated. Do not accept real payments until a payment provider and verified server-side webhook are integrated.
