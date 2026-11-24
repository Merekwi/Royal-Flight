-- ИЖАВИА | StarterPlayer/StarterPlayerScripts/IzhaviaPurchaseClient.client.lua
-- This interface collects the one-time purchase code from the Royal Alliance Mini App.
-- All Game Pass prompting and purchase verification run in the server Script.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local requestRemote = ReplicatedStorage:WaitForChild("IzhaviaPurchaseRequest")
local statusRemote = ReplicatedStorage:WaitForChild("IzhaviaPurchaseStatus")

local gui = Instance.new("ScreenGui")
gui.Name = "IzhaviaPurchaseGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.Parent = player:WaitForChild("PlayerGui")

local open = Instance.new("TextButton")
open.Name = "OpenPurchasePanel"
open.Size = UDim2.fromOffset(154, 42)
open.Position = UDim2.new(1, -170, 1, -62)
open.BackgroundColor3 = Color3.fromRGB(224, 37, 67)
open.TextColor3 = Color3.fromRGB(255, 255, 255)
open.Text = "ИЖАВИА · УСЛУГИ"
open.Font = Enum.Font.GothamBold
open.TextSize = 12
open.Parent = gui
Instance.new("UICorner", open).CornerRadius = UDim.new(0, 11)

local panel = Instance.new("Frame")
panel.Name = "PurchasePanel"
panel.Size = UDim2.fromOffset(320, 226)
panel.Position = UDim2.new(0.5, -160, 0.5, -113)
panel.BackgroundColor3 = Color3.fromRGB(25, 23, 37)
panel.Visible = false
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 16)

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(225, 48, 79)
stroke.Transparency = 0.35
stroke.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -28, 0, 34)
title.Position = UDim2.fromOffset(14, 12)
title.BackgroundTransparency = 1
title.Text = "Оплата услуг Ижавиа"
title.TextColor3 = Color3.fromRGB(255, 237, 240)
title.Font = Enum.Font.GothamBold
title.TextSize = 17
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = panel

local subtitle = Instance.new("TextLabel")
subtitle.Size = UDim2.new(1, -28, 0, 34)
subtitle.Position = UDim2.fromOffset(14, 47)
subtitle.BackgroundTransparency = 1
subtitle.Text = "Введите одноразовый код из Royal Alliance Mini App."
subtitle.TextColor3 = Color3.fromRGB(190, 184, 198)
subtitle.Font = Enum.Font.Gotham
subtitle.TextSize = 10
subtitle.TextWrapped = true
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Parent = panel

local input = Instance.new("TextBox")
input.Size = UDim2.new(1, -28, 0, 44)
input.Position = UDim2.fromOffset(14, 88)
input.BackgroundColor3 = Color3.fromRGB(43, 39, 54)
input.TextColor3 = Color3.fromRGB(255, 255, 255)
input.PlaceholderText = "8-значный код"
input.PlaceholderColor3 = Color3.fromRGB(161, 154, 174)
input.Text = ""
input.ClearTextOnFocus = false
input.Font = Enum.Font.GothamBold
input.TextSize = 18
input.TextXAlignment = Enum.TextXAlignment.Center
input.Parent = panel
Instance.new("UICorner", input).CornerRadius = UDim.new(0, 9)

local submit = Instance.new("TextButton")
submit.Size = UDim2.new(1, -28, 0, 40)
submit.Position = UDim2.fromOffset(14, 141)
submit.BackgroundColor3 = Color3.fromRGB(233, 44, 73)
submit.TextColor3 = Color3.fromRGB(255, 255, 255)
submit.Text = "Проверить код и оплатить"
submit.Font = Enum.Font.GothamBold
submit.TextSize = 12
submit.Parent = panel
Instance.new("UICorner", submit).CornerRadius = UDim.new(0, 9)

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -28, 0, 34)
status.Position = UDim2.fromOffset(14, 186)
status.BackgroundTransparency = 1
status.Text = "После покупки окно можно закрыть."
status.TextColor3 = Color3.fromRGB(193, 184, 197)
status.Font = Enum.Font.Gotham
status.TextWrapped = true
status.TextSize = 9
status.Parent = panel

open.Activated:Connect(function()
    panel.Visible = not panel.Visible
end)

submit.Activated:Connect(function()
    submit.Active = false
    submit.Text = "Проверяем..."
    status.Text = "Проверяем код и готовим окно оплаты..."
    local ok, result = pcall(function()
        return requestRemote:InvokeServer(input.Text)
    end)

    if not ok or not result then
        status.Text = "Не удалось связаться с сервером. Попробуйте ещё раз."
    elseif result.ok then
        status.Text = result.message or "Окно покупки открыто."
    else
        status.Text = result.message or "Проверьте код и повторите попытку."
    end

    submit.Active = true
    submit.Text = "Проверить код и оплатить"
end)

statusRemote.OnClientEvent:Connect(function(kind, message)
    status.Text = tostring(message or "")
    if kind == "success" then
        input.Text = ""
        task.delay(3, function()
            if panel.Parent then panel.Visible = false end
        end)
    end
end)
