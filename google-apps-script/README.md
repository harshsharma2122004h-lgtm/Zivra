# ZIVRA Gmail relay setup

This sends ZIVRA's six order emails through the Google account that owns the Apps Script project. The sender display name is **ZIVRA Support** and replies go to **Zivrasupport@gmail.com**.

## Important: keep your existing Apps Script project

Do **not** delete your project or deployment. Open the same Apps Script project you already created. Replace the contents of `Code.gs` with the complete current source in [ZIVRA-Email.gs](./ZIVRA-Email.gs), then Save. Existing Script Properties are kept when you replace the code.

## One-time Gmail authorization

1. In the Apps Script editor, choose `authorizeGmail` in the function dropdown.
2. Click **Run**.
3. Google will show an authorization prompt. Review it and allow Gmail access for the account that owns this script.
4. This helper only checks Gmail's daily sending quota; it does not send a message.

If Google does not show the prompt, check the function dropdown and confirm that the latest code is saved, then run `authorizeGmail` again.

## Keep or create the private token

In **Project Settings → Script Properties**, make sure this property exists:

- Name: `ZIVRA_RELAY_TOKEN`
- Value: a long random secret (at least 32 characters)

If you already created it, keep the same value. Do not share it in chat or commit it to GitHub. The exact same value is needed as the Supabase secret `GMAIL_SCRIPT_TOKEN`.

## Update the existing Web App deployment

1. Open **Deploy → Manage deployments**.
2. Select your existing Web App deployment and click the pencil (**Edit**).
3. For Version, choose **New version**.
4. Keep **Execute as: Me** and **Who has access: Anyone**.
5. Click **Deploy**. Approve any Google prompt that appears.
6. Keep/copy the Web app URL ending in `/exec`. If the URL changes, update the Supabase secret `GMAIL_SCRIPT_URL`.

Only create a **New deployment** if there is no Web App deployment listed. Do not delete the old deployment while updating it.

## Supabase configuration

In [Supabase Function Secrets](https://supabase.com/dashboard/project/pkraituxrivliqavzwgsm/settings/functions), set:

- `GMAIL_SCRIPT_URL` = the Apps Script Web App URL ending in `/exec`
- `GMAIL_SCRIPT_TOKEN` = the same private token saved in Script Properties

Then deploy the Supabase Edge Function from the repository root:

```bash
supabase functions deploy send-order-email --project-ref pkraituxrivliqavzwgsm
```

Run the complete `supabase-email-logs.sql` file once in the [Supabase SQL Editor](https://supabase.com/dashboard/project/pkraituxrivliqavzwgsm/sql).

## Email behavior

- Order Received: sent automatically after successful checkout.
- Confirmed, Processing, Shipped, Out for Delivery, Delivered: sent only when an admin manually chooses and clicks **Send Email**.
- For Shipped and Out for Delivery, save courier, AWB/tracking number, and tracking URL before sending.

Do not treat the system as live until a test order email and one admin-triggered status email have both been received successfully.
