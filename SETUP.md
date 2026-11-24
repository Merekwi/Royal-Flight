# Royal Alliance Mini App — deployment checklist

The source is in this repository and the backend Edge Functions are deployed to Supabase project `iotwbzzlwltjfddrmhvg`.

## 1. Configure Supabase Edge Function secrets

In Supabase → Project Settings → Edge Functions → Secrets, add:

- `TELEGRAM_BOT_TOKEN` — token from BotFather for the Telegram bot that hosts the Royal Alliance Mini App. Required by `telegram-auth` and `rf-api`.
- `ROBLOX_SERVER_SECRET` — a long random value used only by the Royal Alliance lobby server script and the `roblox-api` function.
- `IZHAVIA_ROBLOX_SERVER_SECRET` — a separate long random value used only by the Ижавиа purchase server script. Do not reuse or share `ROBLOX_SERVER_SECRET` with the Ижавиа team.
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

Every Telegram account has one Royal Alliance member profile and one common miles balance. Selecting Royal Flight, AZAL or Ижавиа changes the carrier's schedule, catalogue, payment methods, orders, subscriptions and announcements, but never creates a second mileage wallet.

Each portal has its own staff assignments. A carrier administrator can manage only that carrier's flights, services, payments, orders and notifications. The alliance owner can oversee all three portals and adjust the shared miles balance.

## 4. Configure scheduled notifications

In GitHub repository Settings → Secrets and variables → Actions, add a repository secret named `NOTIFICATION_CRON_SECRET` with the exact same value configured in Supabase.

The workflow `.github/workflows/dispatch-notifications.yml` checks for due notifications every five minutes. GitHub Actions must be enabled for the repository. You can also run the workflow manually from the Actions tab.

## 5. Connect the Royal Alliance Roblox lobby

Follow [roblox/README.md](roblox/README.md). Use the [Royal Alliance lobby](https://www.roblox.com/games/101826857818257) (Place ID: `101826857818257`) and add its Place ID to the approved list in the Mini App under **Настройки → Серверы Roblox**. Enable HTTP requests in Roblox Studio and insert the two scripts from the `roblox` folder into the specified services.

## 6. Connect Ижавиа's separate Roblox purchase Experience

Ижавиа's Robux payments are not sent through the Royal Alliance lobby. They are prompted inside the Roblox Experience that belongs to Ижавиа, so the Game Pass must also be created under Ижавиа's Roblox account/group and belong to that same Experience.

1. In the Mini App, open the **Ижавиа** portal → **Управление → Настройки → Roblox-сервис Ижавиа** and save the Place ID of Ижавиа's own published Roblox Experience.
2. In Supabase → Project Settings → Edge Functions → Secrets, add `IZHAVIA_ROBLOX_SERVER_SECRET` with a new, independent random value of at least 32 characters.
3. Paste exactly that value into `IZHAVIA_ROBLOX_SERVER_SECRET` in `roblox/IzhaviaPurchaseServer.server.lua`. Never put it in the LocalScript or share it in a public channel.
4. Install `IzhaviaPurchaseServer.server.lua` in **ServerScriptService** and `IzhaviaPurchaseClient.client.lua` in **StarterPlayer → StarterPlayerScripts** of the Ижавиа Experience.
5. Create Ижавиа's Game Passes under its own Roblox account/group, in the same Experience, and place their Game Pass IDs and Robux prices in the Ижавиа service catalogue in the Mini App.
6. Users first link their Roblox account to their Royal Alliance Telegram profile through the Royal Alliance lobby. When they choose an Ижавиа Robux service, the Mini App creates a 15-minute code and opens Ижавиа's Experience. The server prompts the pass there, verifies ownership on the server and activates the service in the shared Alliance profile.

The Izhavia Place ID is intentionally not pre-filled: it has to be the real published Place ID supplied by Ижавиа. Until it is saved in the Izhavia portal, Robux purchase-code generation remains disabled.

## 7. Verify before launch

- Open the Mini App through the Telegram bot, not as a plain website.
- Switch between Royal Flight, AZAL and Ижавиа and confirm the account, miles balance and miles history remain identical.
- Confirm the flight schedule, catalogue, orders and payment methods change with the selected airline.
- Register a test passenger for a future flight, verify the seat limit and confirm the passenger cannot register on another airline's flight.
- Check that your Telegram account appears as `owner` in the profile record.
- Create a test service and add payment details. Place a test order, press **Я оплатил**, and approve it from the admin panel.
- Confirm that approval activates the subscription and a later purchase extends its expiry.
- Test a scheduled notification with a short future time.
- Link a test Roblox account through the Royal Alliance lobby. Test mileage only in published Places where the mileage tracker is installed (the lobby itself is excluded).
- In Ижавиа, test a Game Pass purchase in Ижавиа's own published Experience and confirm the resulting order and subscription appear under the Ижавиа portal.

## Current implementation notes

- Payment is manually reviewed by an admin; the unique order number is shown as the transfer comment.
- Scheduled messages use GitHub Actions, so delivery can be delayed by several minutes.
- Roblox presence is credited from server-side heartbeats only; client-side scripts do not award miles.
- The Mini App does not receive or store Roblox passwords.
