# Royal Alliance Platform

Telegram Mini App and shared operations platform for Royal Flight, AZAL and Ижавиа.

## Included
- Responsive Russian-language Telegram Mini App with separate Royal Flight, AZAL and Ижавиа portals.
- One Royal Alliance member profile and shared miles wallet across every airline portal; carrier schedules, catalogues, orders, payments and announcements remain separated.
- Airline-scoped admin assignments; alliance-wide owner controls and audited common-mile adjustments.
- Passenger flight registration with server-side departure, registration deadline, carrier and seat-capacity checks.
- Supabase Edge Functions for Telegram WebApp signature validation and trusted API actions.
- Admin flight creation, service catalogue, payment method management, manual order review, timed subscriptions and renewal by repeat purchase.
- Airline-scoped Career Centre with a no-code conditional form builder, candidate inbox, status workflow and Telegram status notifications.
- Unique order numbers for payment comments; users submit “Я оплатил”, and admins approve/reject with a note.
- Telegram notification delivery plus scheduled messages via GitHub Actions.
- Roblox account linking through one-time codes entered in the [Royal Alliance lobby](https://www.roblox.com/games/101826857818257), server-validated Roblox identity, miles earned in connected Places and Ижавиа Game Pass purchases processed in Ижавиа's own Roblox Experience.
- Participant management, carrier-specific admin roles and owner-only audited alliance-mile adjustments.
- Supabase RLS enabled with direct access revoked from browser roles; privileged operations run through server functions.

## Deployment
GitHub Pages workflow is included in `.github/workflows/pages.yml`. Enable Pages in repository Settings if needed.

## Required before production
1. Create the Telegram bot with BotFather and configure its Web App URL.
2. Configure Edge Function secrets and the owner Telegram ID by following [SETUP.md](SETUP.md).
3. Add `NOTIFICATION_CRON_SECRET` to both Supabase Edge Function secrets and GitHub Actions repository secrets.
4. Follow [roblox/README.md](roblox/README.md) to install the Royal Alliance lobby scripts and the separate Ижавиа purchase scripts, configure HTTP requests and allow-list each published Place ID.
5. Run end-to-end tests for payment review, service expiry/renewal, scheduled notifications and Roblox mileage before inviting users.

## Local preview
Open `index.html` through a static server. Telegram identity is only available when opened inside Telegram. Transactional features require the configured Supabase backend and server-side secrets.
