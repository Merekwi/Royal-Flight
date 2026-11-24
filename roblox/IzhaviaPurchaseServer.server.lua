-- ИЖАВИА | ServerScriptService/IzhaviaPurchaseServer.server.lua
-- Install this Script only in the official IZhAVIA Roblox Experience.
-- Set the same secret in Supabase Edge Function secrets as IZHAVIA_ROBLOX_SERVER_SECRET.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local HttpService = game:GetService("HttpService")

local API_URL = "https://iotwbzzlwltjfddrmhvg.supabase.co/functions/v1/roblox-api"
local IZHAVIA_ROBLOX_SERVER_SECRET = "PASTE_IZHAVIA_ROBLOX_SERVER_SECRET_HERE"
local JOB_ID = (game.JobId ~= "" and game.JobId) or ("studio-" .. tostring(game.PlaceId) .. "-" .. tostring(game.PlaceVersion))

local requestRemote = ReplicatedStorage:FindFirstChild("IzhaviaPurchaseRequest")
if not requestRemote then
    requestRemote = Instance.new("RemoteFunction")
    requestRemote.Name = "IzhaviaPurchaseRequest"
    requestRemote.Parent = ReplicatedStorage
end

local statusRemote = ReplicatedStorage:FindFirstChild("IzhaviaPurchaseStatus")
if not statusRemote then
    statusRemote = Instance.new("RemoteEvent")
    statusRemote.Name = "IzhaviaPurchaseStatus"
    statusRemote.Parent = ReplicatedStorage
end

local pending = {}
local lastRequest = {}

local function apiRequest(action, player, extra)
    local payload = extra or {}
    payload.action = action
    payload.robloxUserId = player.UserId
    payload.placeId = game.PlaceId
    payload.jobId = JOB_ID

    local ok, response = pcall(function()
        return HttpService:RequestAsync({
            Url = API_URL,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
                ["x-rf-server-secret"] = IZHAVIA_ROBLOX_SERVER_SECRET
            },
            Body = HttpService:JSONEncode(payload)
        })
    end)

    if not ok then
        warn("[Ижавиа] API request failed:", response)
        return false, "Не удалось связаться с сервером Royal Alliance. Попробуйте ещё раз."
    end

    local decodedOk, data = pcall(function()
        return HttpService:JSONDecode(response.Body)
    end)
    if not decodedOk then
        return false, "Сервер вернул некорректный ответ."
    end
    if not response.Success or data.error then
        local messages = {
            izavia_place_not_allowed = "Этот Roblox-сервис ещё не подключён администратором Ижавиа.",
            izavia_purchase_code_not_found = "Код не найден. Создайте новый код в Mini App.",
            izavia_purchase_code_used = "Этот код уже использован.",
            izavia_purchase_code_expired = "Срок действия кода истёк. Создайте новый код.",
            izavia_purchase_code_other_player = "Этот код создан для другого Roblox-аккаунта.",
            izavia_service_or_gamepass_changed = "Услуга изменилась. Создайте новый код в Mini App.",
            roblox_account_not_linked = "Сначала привяжите Roblox-аккаунт в Mini App через лобби Royal Alliance."
        }
        local reason = data.error or ("HTTP_" .. tostring(response.StatusCode))
        warn("[Ижавиа] API rejected request:", reason)
        return false, messages[reason] or "Не удалось подтвердить покупку: " .. tostring(reason)
    end

    return true, data
end

requestRemote.OnServerInvoke = function(player, purchaseCode)
    if typeof(purchaseCode) ~= "string" or #purchaseCode > 16 then
        return { ok = false, message = "Введите одноразовый код из Mini App." }
    end

    local now = os.clock()
    if lastRequest[player.UserId] and now - lastRequest[player.UserId] < 3 then
        return { ok = false, message = "Подождите несколько секунд перед повторной попыткой." }
    end
    lastRequest[player.UserId] = now

    if pending[player.UserId] then
        return { ok = false, message = "Сначала завершите или закройте предыдущее окно покупки." }
    end

    purchaseCode = string.upper(string.gsub(purchaseCode, "%s+", ""))
    if not string.match(purchaseCode, "^[A-HJ-NP-Z2-9][A-HJ-NP-Z2-9][A-HJ-NP-Z2-9][A-HJ-NP-Z2-9][A-HJ-NP-Z2-9][A-HJ-NP-Z2-9][A-HJ-NP-Z2-9][A-HJ-NP-Z2-9]$") then
        return { ok = false, message = "Код должен состоять из 8 символов." }
    end

    local ok, data = apiRequest("izavia_purchase_start", player, { purchaseCode = purchaseCode })
    if not ok then
        return { ok = false, message = data }
    end

    local gamePassId = tonumber(data.gamePassId)
    if not gamePassId or gamePassId <= 0 or gamePassId % 1 ~= 0 then
        return { ok = false, message = "Для услуги Ижавиа некорректно настроен Game Pass." }
    end

    pending[player.UserId] = {
        purchaseCode = purchaseCode,
        gamePassId = gamePassId,
        serviceName = tostring(data.serviceName or "Услуга Ижавиа")
    }

    local promptOk, promptError = pcall(function()
        MarketplaceService:PromptGamePassPurchase(player, gamePassId)
    end)
    if not promptOk then
        pending[player.UserId] = nil
        warn("[Ижавиа] Could not open Game Pass prompt:", promptError)
        return { ok = false, message = "Roblox не смог открыть окно покупки. Проверьте, что Game Pass принадлежит этому Experience." }
    end

    return { ok = true, message = "Открылось окно оплаты Roblox. После покупки услуга активируется автоматически." }
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
    if not player or not player.Parent then return end
    local current = pending[player.UserId]
    if not current or current.gamePassId ~= gamePassId then return end

    if not wasPurchased then
        pending[player.UserId] = nil
        statusRemote:FireClient(player, "cancelled", "Покупка отменена. Код можно использовать повторно до окончания срока действия.")
        return
    end

    task.spawn(function()
        local ownsPass = false
        local checked = false

        -- Roblox updates the ownership cache when PromptGamePassPurchaseFinished fires.
        -- Recheck on the server; never trust a LocalScript purchase result.
        for attempt = 1, 3 do
            local checkOk, result = pcall(function()
                return MarketplaceService:UserOwnsGamePassAsync(player.UserId, current.gamePassId)
            end)
            if checkOk then
                checked = true
                ownsPass = result == true
                if ownsPass then break end
            end
            task.wait(1)
        end

        if not checked or not ownsPass then
            pending[player.UserId] = nil
            statusRemote:FireClient(player, "error", "Roblox пока не подтвердил владение Game Pass. Проверьте покупку и создайте новый код, если услуга не появилась.")
            return
        end

        local ok, result = apiRequest("izavia_purchase_confirm", player, {
            purchaseCode = current.purchaseCode,
            gamePassId = tostring(current.gamePassId),
            ownershipVerified = true
        })
        pending[player.UserId] = nil

        if not ok then
            statusRemote:FireClient(player, "error", result)
            return
        end

        statusRemote:FireClient(player, "success", "Оплата подтверждена! Услуга «" .. current.serviceName .. "» активирована в Royal Alliance.")
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    pending[player.UserId] = nil
    lastRequest[player.UserId] = nil
end)
