# ZIVRA Gmail relay setup

This relay sends the six transactional email types through the Gmail account that owns the Apps Script project. The visible sender name is **ZIVRA Support**. Gmail controls the actual sender address and daily sending quota.

## 1. Create the Apps Script project

1. Sign in to the Google account `Zivrasupport@gmail.com`.
2. Open https://script.google.com/home/start and create a new project named `ZIVRA Email Relay`.
3. Replace the editor contents with the complete source from `google-apps-script/ZIVRA-Email.gs` in this repository.
4. Save the project.

## 2. Set a private relay token

1. In Apps Script, open **Project Settings** (gear icon).
2. Under **Script Properties**, click **Add script property**.
3. Property: `ZIVRA_RELAY_TOKEN`
4. Value: create a long random secret (at least 32 characters). Keep it private; do not paste it into chat or commit it to GitHub.
5. Save script properties.

You will enter the exact same value as the Supabase Edge Function secret `GMAIL_SCRIPT_TOKEN`.

## 3. Deploy as a Web App

1. Click **Deploy → New deployment**.
2. Select type **Web app**.
3. Description: `ZIVRA Gmail relay`.
4. Execute as: **Me**.
5. Who has access: **Anyone** (the endpoint validates the private relay token on every request).
6. Click **Deploy** and approve Google's authorization to send email.
7. Copy the Web app URL ending in `/exec`. Do not use the editor URL.

## 4. Add two Supabase Edge Function secrets

Open https://supabase.com/dashboard/project/pkraituxrivliqavzwgsm/settings/functions

Add:
- `GMAIL_SCRIPT_URL` = the deployed Apps Script Web app URL ending in `/exec`
- `GMAIL_SCRIPT_TOKEN` = the exact private token set in Script Properties

The old SMTP secrets are no longer used by the updated Edge Function; they can be left in place or removed later.

## 5. Deploy the Supabase Edge Function

From the repository root, deploy the function to project `pkraituxrivliqavzwgsm`:

```bash
supabase functions deploy send-order-email --project-ref pkraituxrivliqavzwgsm
```

The Supabase CLI must be logged in and linked to this project. Do not put the service-role key in frontend code or GitHub.

## 6. Create the email log table

Open https://supabase.com/dashboard/project/pkraituxrivliqavzwgsm/sql and run the complete contents of `supabase-email-logs.sql` once.

## 7. Test safely

Place a low-value test order using an email address you control. Confirm the received email arrives. Then use the admin panel to manually send a later status email. Status-change emails are not sent automatically. For shipment messages, save courier, AWB/tracking number, and tracking URL first.

If a deployment is updated later, use **Deploy → Manage deployments → Edit** in Apps Script and create a new version, then update Supabase if the Web app URL changes.
