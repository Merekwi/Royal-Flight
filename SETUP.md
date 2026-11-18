# Royal Alliance Mini App — deployment checklist

The source is in this repository and the backend Edge Functions are deployed to Supabase project `iotwbzzlwltjfddrmhvg`.

## 1. Configure Supabase Edge Function secrets

In Supabase → Project Settings → Edge Functions → Secrets, add:

- `TELEGRAM_BOT_TOKEN` — token from BotFather for the Telegram bot that hosts the Royal Alliance Mini App. Required by `telegram-auth` and `rf-api`.
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

When that Telegram account opens the Mini App, `telegram-auth` assigns it the `owner` role. The owner can appoint admins for the airline currently selected in the portal from **Админ-панель → Участники**. Admin assignments are stored per airline; an AZAL admin does not automatically become a Royal Flight admin. The owner role remains alliance-wide.

## 3. Alliance membership and airline portals

Every Telegram account has one Royal Alliance member profile and one common miles balance. Selecting Royal Flight or AZAL changes the carrier's schedule, catalogue, payment methods, orders, subscriptions and announcements, but never creates a second mileage wallet.

Each portal has its own staff assignments. A carrier administrator can manage only that carrier's flights, services, payments, orders and notifications. The alliance owner can oversee both portals and adjust the shared miles balance.

## 4. Configure scheduled notifications

In GitHub repository Settings → Secrets and variables → Actions, add a repository secret named `NOTIFICATION_CRON_SECRET` with the exact same value configured in Supabase.

The workflow `.github/workflows/dispatch-notifications.yml` checks for due notifications every five minutes. GitHub Actions must be enabled for the repository. You can also run the workflow manually from the Actions tab.

## 5. Connect the Royal Alliance Roblox lobby

Follow [roblox/README.md](roblox/README.md). Use the [Royal Alliance lobby](https://www.roblox.com/games/101826857818257) (Place ID: `101826857818257`) and add its Place ID to the approved list in the Mini App under **Настройки → Серверы Roblox**. Enable HTTP requests in Roblox Studio and insert the two scripts from the `roblox` folder into the specified services.

## 6. Verify before launch

- Open the Mini App through the Telegram bot, not as a plain website.
- Switch between Royal Flight and AZAL and confirm the account, miles balance and miles history remain identical.
- Confirm the flight schedule, catalogue, orders and payment methods change with the selected airline.
- Register a test passenger for a future flight, verify the seat limit and confirm the passenger cannot register on another airline's flight.
- Check that your Telegram account appears as `owner` in the profile record.
- Create a test service and add payment details. Place a test order, press **Я оплатил**, and approve it from the admin panel.
- Confirm that approval activates the subscription and a later purchase extends its expiry.
- Test a scheduled notification with a short future time.
- Link a test Roblox account through the Royal Alliance lobby and confirm miles appear after a full minute in a published Place where the mileage tracker is installed (the lobby itself is excluded).

## Current implementation notes

- Payment is manually reviewed by an admin; the unique order number is shown as the transfer comment.
- Scheduled messages use GitHub Actions, so delivery can be delayed by several minutes.
- Roblox presence is credited from server-side heartbeats only; client-side scripts do not award miles.
- The Mini App does not receive or store Roblox passwords.
