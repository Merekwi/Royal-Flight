# Royal Flight Mini App — deployment checklist

The source is in this repository and the backend Edge Functions are deployed to Supabase project `iotwbzzlwltjfddrmhvg`.

## 1. Configure Supabase Edge Function secrets

In Supabase → Project Settings → Edge Functions → Secrets, add:

- `TELEGRAM_BOT_TOKEN` — token from BotFather for the Royal Flight bot. Required by `telegram-auth` and `rf-api`.
- `ROBLOX_SERVER_SECRET` — a long random value used only by the Roblox server script and the `roblox-api` function.
- `NOTIFICATION_CRON_SECRET` — another independent long random value used by the scheduled-notification workflow and `notification-dispatcher`.

Do not commit any of these values to GitHub. The Supabase service-role key must remain server-side and must never be placed in website JavaScript or Roblox LocalScripts.

## 2. Set the owner Telegram ID

The first owner is configured explicitly to prevent a random first visitor from claiming admin access. Obtain the numeric Telegram ID of the owner, then run this query in Supabase SQL Editor, replacing the example number:

```sql
update public.rf_settings
set value = '123456789'::jsonb, updated_at = now()
where key = 'owner_telegram_id';
```

When that Telegram account opens the Mini App, `telegram-auth` assigns it the `owner` role. The owner can then appoint admins from **Админ-панель → Участники**.

## 3. Configure scheduled notifications

In GitHub repository Settings → Secrets and variables → Actions, add a repository secret named `NOTIFICATION_CRON_SECRET` with the exact same value configured in Supabase.

The workflow `.github/workflows/dispatch-notifications.yml` checks for due notifications every five minutes. GitHub Actions must be enabled for the repository. You can also run the workflow manually from the Actions tab.

## 4. Connect the Roblox game

Follow [roblox/README.md](roblox/README.md). Add the approved game Place ID in the Mini App under **Настройки → option 3**. Enable HTTP requests in Roblox Studio and insert the two scripts from the `roblox` folder into the specified services.

## 5. Verify before launch

- Open the Mini App through the Telegram bot, not as a plain website.
- Check that your Telegram account appears as `owner` in the profile record.
- Create a test service and add payment details. Place a test order, press **Я оплатил**, and approve it from the admin panel.
- Confirm that approval activates the subscription and a later purchase extends its expiry.
- Test a scheduled notification with a short future time.
- Link a test Roblox account and confirm miles appear after a full minute in the approved published Place.

## Current implementation notes

- Payment is manually reviewed by an admin; the unique order number is shown as the transfer comment.
- Scheduled messages use GitHub Actions, so delivery can be delayed by several minutes.
- Roblox presence is credited from server-side heartbeats only; client-side scripts do not award miles.
- The Mini App does not receive or store Roblox passwords.
