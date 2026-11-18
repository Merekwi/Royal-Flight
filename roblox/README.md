# Royal Alliance Lobby — Roblox integration for the Royal Flight portal

## What this adds
- A one-time code generated in the Telegram Mini App and entered in the [Royal Alliance Roblox lobby](https://www.roblox.com/games/101826857818257).
- Roblox identity is taken from the server-side `Player.UserId` and `Player.Name`, not from a user-submitted username.
- The server sends a heartbeat every 60 seconds while the player remains in a Roblox server where the trusted ServerScript is installed.
- The backend credits complete minutes only. The current database rate is 1 Royal Alliance mile per credited minute; a Royal Flight portal admin can change the rate in that portal.
- Mileage heartbeats work in every Place ID except the explicitly excluded menu Place. The mileage path does not use the approved Place ID allow-list.
- Roblox mileage is credited to the one shared Royal Alliance wallet and is visible in every member airline portal.
- Roblox is currently a Royal Flight integration, not an AZAL feature.

## Required one-time configuration
1. In Roblox Studio, enable **Game Settings → Security → Allow HTTP Requests**.
2. Choose a long random secret (at least 32 random characters). Do not put it in a LocalScript or publish it in chat.
3. In Supabase project `iotwbzzlwltjfddrmhvg`, add the Edge Function secret `ROBLOX_SERVER_SECRET` with that value. The secret-management UI/CLI is required; it is not stored in this repository.
4. Paste the same value into the `SERVER_SECRET` constant in `RoyalFlightLinkServer.server.lua`. This is a server Script in ServerScriptService, so it is not replicated to clients.
5. Publish the [Royal Alliance lobby](https://www.roblox.com/games/101826857818257) and copy its **Place ID** (`101826857818257`).
6. Open the Mini App as the owner/admin → **Настройки** → **Серверы Roblox** and add the [Royal Alliance lobby](https://www.roblox.com/games/101826857818257) where users will link their account or use Game Pass features. This allow-list is for linking and other Roblox portal actions, not mileage heartbeats. The API rejects any Place ID not on this list.
7. Put `RoyalFlightLinkServer.server.lua` in **ServerScriptService** and `RoyalFlightLinkClient.client.lua` in **StarterPlayer → StarterPlayerScripts**.
8. Test in a published server. Studio local sessions will not earn miles unless the published Place ID is allow-listed and HTTP requests work.

## Link flow
1. Player opens Mini App → Profile → **Привязать Roblox**.
2. The Mini App shows a one-time code valid for 10 minutes.
3. Player joins the approved **Royal Alliance lobby**, opens the in-game **ROYAL ALLIANCE** panel and enters the code.
4. The server submits the code with the actual Roblox UserId and username. The code can only be used once, and a Roblox account cannot be linked to two Telegram profiles.
5. After linking, each 60-second heartbeat confirms presence. The server caps a delayed heartbeat to 90 seconds to prevent large offline credit jumps.

## Roblox Game Pass subscription renewals

The Roblox catalog is configured per airline in the Mini App admin panel. A linked Roblox account can use the shared alliance profile while service catalogs remain airline-scoped.

### Monthly renewal model
- Each service keeps one stable service record (for example, Business Class).
- Admin creates a new Game Pass in the Roblox Creator Dashboard once per renewal cycle, then updates that service's **Current Game Pass ID** and **Base price in Robux** in Mini App → Admin → Services.
- The new Game Pass is only the next available renewal method. Changing the ID does **not** delete, shorten, deactivate, or replace anyone's existing rf_subscriptions row.
- Every passenger keeps an independent starts_at / ends_at. The active service remains available until that passenger's own ends_at, regardless of when the admin rotates the Game Pass ID.
- When a passenger buys the current Game Pass, the Roblox server verifies ownership with MarketplaceService:UserOwnsGamePassAsync() and calls roblox-api action activate_gamepass.
- The database records one activation per (profile_id, service_id, gamepass_id). Rechecking the same pass is idempotent and cannot grant another month.
- The new subscription period starts at max(now(), passenger's latest active ends_at) and adds the service's configured duration_days (normally 30). Early renewals therefore add time after the existing expiry instead of wasting the remaining days.
- If the passenger's old period has already expired, the new period starts immediately.
- Old Game Pass ownership is never used as proof of a currently active Business Class subscription. Only the database subscription expiry grants access.

### Admin fields
- roblox_enabled: allow new in-game Game Pass renewals for the service.
- roblox_gamepass_id: current pass ID. It is replaced each renewal cycle.
- robux_price: configured base price used to detect a stale or incorrectly configured pass.
- duration_days: length of each new subscription period. Changing this affects future purchases only.

The Roblox server should retrieve pass details with MarketplaceService:GetProductInfoAsync(passId, Enum.InfoType.GamePass), verify that the pass is for sale, and compare UserBasePriceInRobux with the app's configured robux_price. It should display the user's actual PriceInRobux, then prompt purchase. On the server-only PromptGamePassPurchaseFinished event, re-check ownership with UserOwnsGamePassAsync before activating anything.

### Backend API contract
All calls below are server-to-server POST requests to the Supabase roblox-api Edge Function, with x-rf-server-secret. Every request must include the actual server-derived robloxUserId, the current placeId, and jobId.

- catalog — additionally pass airlineCode: "royal" or "azal". Returns enabled services with current gamePassId, robuxPrice, durationDays, and the official Game Pass URL.
- entitlements — returns the linked passenger's currently active privileges and their individual endsAt timestamps. This is the source of truth for access control.
- activate_gamepass — pass serviceId, gamePassId, and ownershipVerified: true only after the server has independently confirmed ownership using MarketplaceService. The backend checks that the pass ID is still the current ID configured for that service and performs idempotent activation/renewal.
- Existing link, heartbeat, and leave actions remain unchanged.

Never grant Business Class merely because UserOwnsGamePassAsync returns true for an old pass. Never derive entitlement from the current Game Pass ID. Never reset all passenger expiries when the ID changes.

**Experience limitation:** Roblox only allows prompting purchases for Game Passes belonging to the current Roblox Experience. If Royal Flight and AZAL are implemented as separate Roblox Experiences, each experience needs its own pass configured for that experience; a Game Pass from one experience cannot be prompted from the other.


## Per-service payment channel settings

Each service has its own payment mode, independent of the airline portal:
- `manual_only` — only the existing non-Robux payment flow (for example, bank transfer/card details).
- `roblox_only` — only payment through Roblox Game Pass. The Mini App hides the manual order flow, and the backend rejects direct attempts to create a manual order.
- `both` — passengers may use either the manual payment flow or Roblox Game Pass.

The mode is configured on the existing service record in Admin → Services. Existing services default to `manual_only`, so current payment behaviour remains unchanged until an admin edits the mode.

For `roblox_only` or `both`, a valid current Game Pass ID and positive Robux price are required. The Roblox in-game catalog only returns services whose mode permits Roblox payment. Server-side purchase activation also checks the mode and current Game Pass ID.

Changing the mode affects only future payment options. Existing orders, completed purchases, and each passenger's individual subscription expiry remain unchanged. A `roblox_only` service does not require an ordinary-payment price; its normal price is stored as zero when left blank.

## Important limitations
- Do not use the secret in a LocalScript, a RemoteEvent payload, or any client-visible asset.
- Install the trusted ServerScript in every Roblox Experience/Place where players should earn miles. Only the configured excluded menu Place is ignored for mileage; ordinary heartbeat requests do not need to be allow-listed.
- The initial Roblox linking action and Game Pass/catalog actions still use the separate approved Place ID allow-list. Add the [Royal Alliance lobby](https://www.roblox.com/games/101826857818257) there so players can link their accounts.
- The excluded mileage Place is stored in `rf_settings.roblox_miles_excluded_place_ids`; it must contain the menu Place ID as a string.
- Roblox HTTP calls can fail temporarily; those gaps are not retroactively credited.
- Before public launch, configure the owner's numeric Telegram ID in `rf_settings.owner_telegram_id`, set the Edge Function secret above, and add the [Royal Alliance lobby](https://www.roblox.com/games/101826857818257) to the approved-place list. An empty allow-list blocks linking and other portal actions, but it does not block mileage heartbeats.
