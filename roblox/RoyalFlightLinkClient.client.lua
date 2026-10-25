-- Royal Flight | StarterPlayer/StarterPlayerScripts/RoyalFlightLinkClient.client.lua
-- This creates a small in-game panel for entering the one-time code from the Telegram Mini App.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("RFLinkRequest")

local gui = Instance.new("ScreenGui")
gui.Name = "RoyalFlightLinkGui"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local open = Instance.new("TextButton")
open.Name = "OpenLinkPanel"
open.Size = UDim2.fromOffset(150, 38)
open.Position = UDim2.new(1, -166, 1, -58)
open.BackgroundColor3 = Color3.fromRGB(176, 82, 96)
open.TextColor3 = Color3.fromRGB(255, 255, 255)
open.Text = "ROYAL FLIGHT"
open.Font = Enum.Font.GothamBold
open.TextSize = 13
open.Parent = gui
Instance.new("UICorner", open).CornerRadius = UDim.new(0, 10)

local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(300, 190)
panel.Position = UDim2.new(0.5, -150, 0.5, -95)
panel.BackgroundColor3 = Color3.fromRGB(13, 27, 44)
panel.Visible = false
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -24, 0, 34)
title.Position = UDim2.fromOffset(12, 10)
title.BackgroundTransparency = 1
title.Text = "Привязка аккаунта"
title.TextColor3 = Color3.fromRGB(245, 239, 230)
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.Parent = panel

local input = Instance.new("TextBox")
input.Size = UDim2.new(1, -24, 0, 40)
input.Position = UDim2.fromOffset(12, 52)
input.BackgroundColor3 = Color3.fromRGB(25, 43, 62)
input.TextColor3 = Color3.fromRGB(255, 255, 255)
input.PlaceholderText = "Код из Telegram"
input.PlaceholderColor3 = Color3.fromRGB(160, 173, 190)
input.Text = ""
input.ClearTextOnFocus = false
input.Font = Enum.Font.Gotham
input.TextSize = 16
input.Parent = panel
Instance.new("UICorner", input).CornerRadius = UDim.new(0, 8)

local submit = Instance.new("TextButton")
submit.Size = UDim2.new(1, -24, 0, 38)
submit.Position = UDim2.fromOffset(12, 100)
submit.BackgroundColor3 = Color3.fromRGB(211, 179, 116)
submit.TextColor3 = Color3.fromRGB(15, 28, 44)
submit.Text = "Привязать"
submit.Font = Enum.Font.GothamBold
submit.TextSize = 14
submit.Parent = panel
Instance.new("UICorner", submit).CornerRadius = UDim.new(0, 8)

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -24, 0, 34)
status.Position = UDim2.fromOffset(12, 143)
status.BackgroundTransparency = 1
status.Text = "Получите код в Telegram Mini App."
status.TextColor3 = Color3.fromRGB(190, 203, 218)
status.Font = Enum.Font.Gotham
status.TextWrapped = true
status.TextSize = 11
status.Parent = panel

open.Activated:Connect(function() panel.Visible = not panel.Visible end)
submit.Activated:Connect(function()
    submit.Active = false
    submit.Text = "Проверка..."
    status.Text = "Проверяем код..."
    local ok, result = pcall(function() return remote:InvokeServer(input.Text) end)
    if not ok or not result then
        status.Text = "Не удалось связаться с сервером. Попробуйте ещё раз."
    else
        status.Text = result.message or "Готово."
        if result.ok then
            input.Text = ""
            task.wait(2)
            panel.Visible = false
        end
    end
    submit.Active = true
    submit.Text = "Привязать"
end)
