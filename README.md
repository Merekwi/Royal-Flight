# Royal Flight Platform

Telegram Mini App and operations platform for the Royal Flight virtual airline.

## Included
- Responsive Russian-language Mini App shell with Telegram WebApp SDK.
- Navigation for home, flights, miles, services, profile and admin modules.
- Initial Supabase schema for profiles, flights, services, manual-payment orders, timed subscriptions, mile ledger, Roblox online sessions, notifications, settings and admin audit.
- Browser roles are locked out of direct table access. Trusted server functions must validate Telegram initData and enforce roles.

## Deployment
GitHub Pages workflow is included in .github/workflows/pages.yml. Enable Pages in repository Settings if needed.

## Required before production
1. Create the Telegram bot with BotFather and configure its Web App URL.
2. Add a server-side function to validate Telegram WebApp initData with the bot token. Never trust initDataUnsafe for authorization.
3. Configure Supabase Edge Function secrets for the bot token and server-side Supabase key. Do not commit secrets or expose them in frontend code.
4. Set the owner Telegram ID through a protected setup path.
5. Implement and test admin APIs, payment review, order idempotency, service activation/expiry, notification delivery and Roblox session reporting.
6. Configure approved Roblox place IDs and add Roblox server scripts.
7. Review Supabase Security Advisor before launch.

## Local preview
Open index.html through a static server. Telegram user identity appears when opened inside Telegram. Until the trusted backend is connected, balances and transactional features intentionally show placeholders instead of fabricated account data.