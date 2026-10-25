# Royal Flight Platform

Telegram Mini App and operations platform for the Royal Flight virtual airline.

## Included
- Responsive Russian-language Telegram Mini App: home, flights, miles, services, profile and admin panel.
- Supabase Edge Functions for Telegram WebApp signature validation and trusted API actions.
- Admin flight creation, service catalogue, payment method management, manual order review, timed subscriptions and renewal by repeat purchase.
- Unique order numbers for payment comments; users submit “Я оплатил”, and admins approve/reject with a note.
- Telegram notification delivery plus scheduled messages via GitHub Actions.
- Roblox account linking through one-time codes, server-validated Roblox identity and miles earned for online minutes in approved game Places.
- Participant management, admin roles and audited mileage adjustments.
- Supabase RLS enabled with direct access revoked from browser roles; privileged operations run through server functions.

## Deployment
GitHub Pages workflow is included in `.github/workflows/pages.yml`. Enable Pages in repository Settings if needed.

## Required before production
1. Create the Telegram bot with BotFather and configure its Web App URL.
2. Configure Edge Function secrets and the owner Telegram ID by following [SETUP.md](SETUP.md).
3. Add `NOTIFICATION_CRON_SECRET` to both Supabase Edge Function secrets and GitHub Actions repository secrets.
4. Follow [roblox/README.md](roblox/README.md) to install the Roblox server/client scripts, configure HTTP requests and allow-list the published Place ID.
5. Run end-to-end tests for payment review, service expiry/renewal, scheduled notifications and Roblox mileage before inviting users.

## Local preview
Open `index.html` through a static server. Telegram identity is only available when opened inside Telegram. Transactional features require the configured Supabase backend and server-side secrets.
