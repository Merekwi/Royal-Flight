# Royal Alliance Roblox integrations — account linking, miles and Ижавиа purchases

## What this adds
- A one-time code generated in the Telegram Mini App and entered in the [Royal Alliance Roblox lobby](https://www.roblox.com/games/101826857818257).
- Roblox identity is taken from the server-side `Player.UserId` and `Player.Name`, not from a user-submitted username.
- The server sends a heartbeat every 60 seconds while the player remains in a Roblox server where the trusted ServerScript is installed.
- The backend credits complete minutes only. The current database rate is 1 Royal Alliance mile per credited minute; a Royal Flight portal admin can change the rate in that portal.
- The [Royal Alliance lobby](https://www.roblox.com/games/101826857818257) (Place ID `101826857818257`) is the menu Place and is excluded from mileage. Other Places earn miles when the trusted ServerScript is installed. The mileage path does not use the approved Place ID allow-list.
- Roblox mileage is credited to the one shared Royal Alliance wallet and is visible in every member airline portal.
- The shared account-linking lobby is Royal Alliance. The existing online-minute mileage tracker is installed only in Places where you explicitly put its server script; the Ижавиа purchase script below handles Robux purchases and does not itself award online-time miles.

## Required one-time configuration
1. In Roblox Studio, enable **Game Settings → Security → Allow HTTP Requests**.
2. Choose a long random secret (at least 32 random characters). Do not put it in a LocalScript or publish it in chat.
3. In Supabase project `iotwbzzlwltjfddrmhvg`, add the Edge Function secret `ROBLOX_SERVER_SECRET` with that value. The secret-management UI/CLI is required; it is not stored in this repository.
4. Paste the same value into the `SERVER_SECRET` constant in `RoyalFlightLinkServer.server.lua`. This is a server Script in ServerScriptService, so it is not replicated to clients.
5. Publish the [Royal Alliance lobby](https://www.roblox.com/games/101826857818257) and copy its **Place ID** (`101826857818257`).
6. Open the Mini App as the owner/admin → **Настройки** → **Серверы Roblox** and add the [Royal Alliance lobby](https://www.roblox.com/games/101826857818257) where users will link their account or use Game Pass features. This allow-list is for linking and other Roblox portal actions, not mileage heartbeats. The API rejects any Place ID not on this list.
7. Put `RoyalAllianceLobbyServer.server.lua` in **ServerScriptService** and `RoyalAllianceLobbyClient.client.lua` in **StarterPlayer → StarterPlayerScripts**. Remove the older `RoyalFlightLinkServer.server.lua` / `RoyalFlightLinkClient.client.lua` pair before installing these renamed files; do not keep two copies of the same lobby scripts running.
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

- catalog — additionally pass airlineCode: "royal", "azal" or "izavia". Returns enabled services with current gamePassId, robuxPrice, durationDays, and the official Game Pass URL.
- entitlements — returns the linked passenger's currently active privileges and their individual endsAt timestamps. This is the source of truth for access control.
- activate_gamepass — pass serviceId, gamePassId, and ownershipVerified: true only after the server has independently confirmed ownership using MarketplaceService. The backend checks that the pass ID is still the current ID configured for that service and performs idempotent activation/renewal.
- Existing link, heartbeat, and leave actions remain unchanged.

Never grant Business Class merely because UserOwnsGamePassAsync returns true for an old pass. Never derive entitlement from the current Game Pass ID. Never reset all passenger expiries when the ID changes.

**Experience limitation:** Roblox only allows prompting purchases for Game Passes belonging to the current Roblox Experience. Each airline that receives its own Robux revenue must own/configure its passes in its own Experience. A Royal Flight or Royal Alliance lobby script cannot prompt an Ижавиа Game Pass, even if the pass ID is known.


## Per-service payment channel settings

Each service has its own payment mode, independent of the airline portal:
- `manual_only` — only the existing non-Robux payment flow (for example, bank transfer/card details).
- `roblox_only` — only payment through Roblox Game Pass. The Mini App hides the manual order flow, and the backend rejects direct attempts to create a manual order.
- `both` — passengers may use either the manual payment flow or Roblox Game Pass.

The mode is configured on the existing service record in Admin → Services. Existing services default to `manual_only`, so current payment behaviour remains unchanged until an admin edits the mode.

For `roblox_only` or `both`, a valid current Game Pass ID and positive Robux price are required. The Roblox in-game catalog only returns services whose mode permits Roblox payment. Server-side purchase activation also checks the mode and current Game Pass ID.

Changing the mode affects only future payment options. Existing orders, completed purchases, and each passenger's individual subscription expiry remain unchanged. A `roblox_only` service does not require an ordinary-payment price; its normal price is stored as zero when left blank.


## Ижавиа: покупки в отдельном Roblox Experience

Ижавиа получает отдельный purchase flow so that Game Pass purchases are prompted inside Ижавиа's own published Roblox Experience and credited to the account/group that owns those passes. The Alliance lobby is used only for linking the player's Roblox identity to the common Telegram profile.

### One-time setup
1. In Supabase Edge Function Secrets, create `IZHAVIA_ROBLOX_SERVER_SECRET` with a new random secret (32+ characters). Keep it separate from `ROBLOX_SERVER_SECRET`.
2. In the Mini App, open **Ижавиа → Управление → Настройки → Roblox-сервис Ижавиа** and save Ижавиа's real published Place ID. `roblox_place_ids_izavia` is a separate allow-list; do not add the Ижавиа Place ID to the Royal Alliance lobby allow-list.
3. Paste the same `IZHAVIA_ROBLOX_SERVER_SECRET` into the constant in `IzhaviaPurchaseServer.server.lua`.
4. Install `IzhaviaPurchaseServer.server.lua` in **ServerScriptService** and `IzhaviaPurchaseClient.client.lua` in **StarterPlayer → StarterPlayerScripts** inside Ижавиа's own Experience.
5. Create each Game Pass under Ижавиа's Roblox account/group and make sure the pass belongs to that exact Experience. Enter the IDs and Robux prices into the Ижавиа portal's service catalogue.

### Purchase flow
1. The user links their Roblox account once through the Royal Alliance lobby.
2. In the Ижавиа portal, the user chooses a service and presses **Перейти в сервис Ижавиа для оплаты**.
3. The Mini App asks `rf-api` for an 8-character, 15-minute purchase code and opens Ижавиа's Place ID.
4. The player enters the code into the in-game Ижавиа purchase panel.
5. The Ижавиа server calls `roblox-api` with the separate Izhavia secret, checks the code and current service/Game Pass configuration, then prompts the Game Pass inside Ижавиа's Experience.
6. `PromptGamePassPurchaseFinished` is handled on the server. The server independently checks `UserOwnsGamePassAsync` and calls `izavia_purchase_confirm`.
7. Supabase consumes the one-time code and creates the paid order, entitlement and subscription in the shared Royal Alliance profile, scoped to `airline_code = 'izavia'`.

The Izhavia server secret authorizes only the two Izhavia purchase actions. It is not valid for account linking, miles heartbeats or the other Roblox API actions. The Mini App's purchase code is bound to the linked Roblox account, the selected Izhavia service and that service's current Game Pass ID. A code cannot be transferred to another Roblox user or reused.

**Important:** the Izhavia server script does not itself award mileage heartbeats. Mileage is credited only in Places where a trusted mileage-tracker server script is installed and configured.

## Important limitations
- Do not use the secret in a LocalScript, a RemoteEvent payload, or any client-visible asset.
- Install the trusted ServerScript in every Roblox Experience/Place where players should earn miles. Only the configured excluded menu Place is ignored for mileage; ordinary heartbeat requests do not need to be allow-listed.
- The initial Roblox linking action and Game Pass/catalog actions still use the separate approved Place ID allow-list. Add the [Royal Alliance lobby](https://www.roblox.com/games/101826857818257) there so players can link their accounts.
- The excluded mileage Place is stored in `rf_settings.roblox_miles_excluded_place_ids`; for this project it must contain `101826857818257` as a string ([Royal Alliance lobby](https://www.roblox.com/games/101826857818257)).
- Roblox HTTP calls can fail temporarily; those gaps are not retroactively credited.
- Do not paste `IZHAVIA_ROBLOX_SERVER_SECRET` into the Royal Alliance lobby scripts. Those scripts use the separate `ROBLOX_SERVER_SECRET`.
- Before public launch, configure the owner's numeric Telegram ID in `rf_settings.owner_telegram_id`, set the Edge Function secret above, and add the [Royal Alliance lobby](https://www.roblox.com/games/101826857818257) to the approved-place list. An empty allow-list blocks linking and other portal actions, but it does not block mileage heartbeats.
