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
