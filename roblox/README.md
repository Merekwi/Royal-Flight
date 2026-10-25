# Royal Flight — Roblox bridge

## What this adds
- A one-time code generated in the Telegram Mini App and entered in the Royal Flight Roblox game.
- Roblox identity is taken from the server-side `Player.UserId` and `Player.Name`, not from a user-submitted username.
- The server sends a heartbeat every 60 seconds while the player remains in the approved game Place.
- The backend credits complete minutes only. Current default: 10 miles per credited minute; an admin can change the rate in the Mini App.
- The Mini App shows the current balance and mileage ledger.

## Required one-time configuration
1. In Roblox Studio, enable **Game Settings → Security → Allow HTTP Requests**.
2. Choose a long random secret (at least 32 random characters). Do not put it in a LocalScript or publish it in chat.
3. In Supabase project `iotwbzzlwltjfddrmhvg`, add the Edge Function secret `ROBLOX_SERVER_SECRET` with that value. The secret-management UI/CLI is required; it is not stored in this repository.
4. Paste the same value into the `SERVER_SECRET` constant in `RoyalFlightLinkServer.server.lua`. This is a server Script in ServerScriptService, so it is not replicated to clients.
5. Publish the game and copy the **Place ID** of the place where players actually spend time.
6. Open the Mini App as the owner/admin → **Настройки** → option **3** and save the approved Place ID. The API rejects any Place ID not on this list.
7. Put `RoyalFlightLinkServer.server.lua` in **ServerScriptService** and `RoyalFlightLinkClient.client.lua` in **StarterPlayer → StarterPlayerScripts**.
8. Test in a published server. Studio local sessions will not earn miles unless the published Place ID is allow-listed and HTTP requests work.

## Link flow
1. Player opens Mini App → Profile → **Привязать Roblox**.
2. The Mini App shows a one-time code valid for 10 minutes.
3. Player joins the approved Royal Flight place, opens the in-game **ROYAL FLIGHT** panel and enters the code.
4. The server submits the code with the actual Roblox UserId and username. The code can only be used once, and a Roblox account cannot be linked to two Telegram profiles.
5. After linking, each 60-second heartbeat confirms presence. The server caps a delayed heartbeat to 90 seconds to prevent large offline credit jumps.

## Important limitations
- Do not use the secret in a LocalScript, a RemoteEvent payload, or any client-visible asset.
- Only the listed Place IDs count. Add every legitimate Royal Flight place where players should earn miles.
- Roblox HTTP calls can fail temporarily; those gaps are not retroactively credited.
- Before public launch, configure the owner's numeric Telegram ID in `rf_settings.owner_telegram_id` / `rf_profiles.role`, and set the Edge Function secret above.
