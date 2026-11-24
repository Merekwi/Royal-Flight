-- Royal Alliance Lobby | ServerScriptService/RoyalAllianceLobbyServer.server.lua
-- Enable Game Settings > Security > Allow HTTP Requests.
-- Set the same long random secret in this script and Supabase Edge Function secret ROBLOX_SERVER_SECRET.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local API_URL = "https://iotwbzzlwltjfddrmhvg.supabase.co/functions/v1/roblox-api"
local SERVER_SECRET = "PASTE_THE_SAME_RANDOM_SECRET_HERE"
local JOB_ID = (game.JobId ~= "" and game.JobId) or ("studio-" .. tostring(game.PlaceId) .. "-" .. tostring(game.PlaceVersion))

local remote = ReplicatedStorage:FindFirstChild("RFLinkRequest")
if not remote then
    remote = Instance.new("RemoteFunction")
    remote.Name = "RFLinkRequest"
    remote.Parent = ReplicatedStorage
end

local function apiRequest(payload)
    local ok, response = pcall(function()
        return HttpService:RequestAsync({
            Url = API_URL,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
                ["x-rf-server-secret"] = SERVER_SECRET
            },
            Body = HttpService:JSONEncode(payload)
        })
    end)
    if not ok or not response.Success then
        warn("[Royal Alliance] API request failed", ok and response.StatusCode or response)
        return false, "Не удалось связаться с Royal Alliance. Попробуйте позже."
    end
    local decodedOk, data = pcall(function() return HttpService:JSONDecode(response.Body) end)
    if not decodedOk then return false, "Сервер вернул неверный ответ." end
    if data.error then
        local messages = {
            link_code_expired = "Код истёк или неверен. Получите новый код в Telegram.",
            roblox_account_already_linked = "Этот Roblox-аккаунт уже привязан к другому профилю.",
            place_not_allowed = "Это лобби ещё не подключено к системе Royal Alliance."
        }
        return false, messages[data.error] or "Не удалось выполнить действие."
    end
    return true, data
end

remote.OnServerInvoke = function(player, code)
    if typeof(code) ~= "string" or #code > 16 then
        return { ok = false, message = "Введите код из Telegram." }
    end
    local ok, result = apiRequest({
        action = "link",
        code = string.upper(string.gsub(code, "%s+", "")),
        robloxUserId = player.UserId,
        robloxUsername = player.Name,
        placeId = game.PlaceId,
        jobId = JOB_ID
    })
    if not ok then return { ok = false, message = result } end
    return { ok = true, message = "Roblox успешно привязан к Royal Alliance!" }
end

local function apiRequestBatch(players)
    if #players == 0 then return end
    local ids = {}
    for _, player in ipairs(players) do table.insert(ids, player.UserId) end
    local ok, response = pcall(function()
        return HttpService:RequestAsync({
            Url = API_URL,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
                ["x-rf-server-secret"] = SERVER_SECRET
            },
            Body = HttpService:JSONEncode({
                action = "heartbeat_batch",
                players = ids,
                placeId = game.PlaceId,
                jobId = JOB_ID
            })
        })
    end)
    if not ok or not response.Success then
        warn("[Royal Alliance] Mileage batch failed", ok and response.StatusCode or response)
    end
end

local heartbeatBusy = false
local function sendOnlineSnapshot()
    if heartbeatBusy then return end
    heartbeatBusy = true
    apiRequestBatch(Players:GetPlayers())
    heartbeatBusy = false
end

Players.PlayerAdded:Connect(function()
    task.delay(2, sendOnlineSnapshot)
end)
Players.PlayerRemoving:Connect(function(player)
    apiRequest({
        action = "heartbeat",
        robloxUserId = player.UserId,
        placeId = game.PlaceId,
        jobId = JOB_ID
    })
    apiRequest({
        action = "leave",
        robloxUserId = player.UserId,
        placeId = game.PlaceId,
        jobId = JOB_ID
    })
end)

task.spawn(function()
    task.wait(2)
    sendOnlineSnapshot()
    while true do
        task.wait(60)
        sendOnlineSnapshot()
    end
end)
