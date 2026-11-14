-- =========================================================
-- KizHub - Tool Lưu & Lấy Tọa Độ (Position & Relative Plot Logger)
-- Dành cho dj: Chạy script, đứng tại bãi farm / trứng và bấm Copy
-- Hỗ trợ tự động tính Relative Offset chuẩn cho mọi Plot Tycoon!
-- =========================================================

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local function getRoot()
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    return char and char:WaitForChild("HumanoidRootPart", 5)
end

local function copyToClipboard(text)
    local fn = setclipboard or toclipboard or set_clipboard or (Clipboard and Clipboard.set)
    if type(fn) == "function" then
        pcall(fn, text)
        return true
    end
    return false
end

-- Tìm Plot của người chơi để tính Relative Coordinate
local function getMyPlotPivot()
    local ok, islandCmds = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Client"):WaitForChild("PumpkinTycoonCmds"):WaitForChild("Island"))
    end)
    if ok and islandCmds and type(islandCmds.Plot) == "function" then
        local okP, plot = pcall(islandCmds.Plot)
        if okP and plot then
            local okM, model = pcall(function() return plot:GetModel() end)
            if okM and model and model:IsA("Model") then
                return model:GetPivot()
            end
        end
    end

    local things = workspace:FindFirstChild("__THINGS")
    local plots = things and things:FindFirstChild("Plots")
    if plots then
        local hrp = getRoot()
        local myPos = hrp and hrp.Position or Vector3.zero
        local closestDist = 1000
        local closestModel = nil
        for _, pModel in ipairs(plots:GetChildren()) do
            if pModel:IsA("Model") then
                local dist = (pModel:GetPivot().Position - myPos).Magnitude
                if dist < closestDist then
                    closestDist = dist
                    closestModel = pModel
                end
            end
        end
        if closestModel then
            return closestModel:GetPivot()
        end
    end
    return nil
end

-- Tạo ScreenGui
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "KizHub_PosLogger"
screenGui.ResetOnSpawn = false

local parentTarget = (type(gethui) == "function" and gethui()) or CoreGui:FindFirstChild("RobloxGui") or LocalPlayer:FindFirstChildOfClass("PlayerGui")
screenGui.Parent = parentTarget

local frame = Instance.new("Frame")
frame.Name = "MainFrame"
frame.Size = UDim2.new(0, 420, 0, 240)
frame.Position = UDim2.new(0.5, -210, 0.2, 0)
frame.BackgroundColor3 = Color3.fromRGB(15, 17, 23)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = frame

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(56, 189, 248)
stroke.Thickness = 1.5
stroke.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -40, 0, 35)
title.Position = UDim2.new(0, 15, 0, 5)
title.BackgroundTransparency = 1
title.Text = "👑 Kiz Hub | Position & Plot Relative Logger"
title.TextColor3 = Color3.fromRGB(248, 250, 252)
title.TextSize = 15
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = frame

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 28, 0, 28)
closeBtn.Position = UDim2.new(1, -36, 0, 8)
closeBtn.BackgroundColor3 = Color3.fromRGB(239, 68, 68)
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
closeBtn.Parent = frame
local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 6)
closeCorner.Parent = closeBtn
closeBtn.MouseButton1Click:Connect(function()
    screenGui:Destroy()
end)

local posLabel = Instance.new("TextLabel")
posLabel.Size = UDim2.new(1, -30, 0, 75)
posLabel.Position = UDim2.new(0, 15, 0, 42)
posLabel.BackgroundColor3 = Color3.fromRGB(24, 27, 36)
posLabel.TextColor3 = Color3.fromRGB(148, 163, 184)
posLabel.TextSize = 11
posLabel.Font = Enum.Font.Code
posLabel.TextWrapped = true
posLabel.Text = "Đang lấy tọa độ..."
posLabel.Parent = frame
local posCorner = Instance.new("UICorner")
posCorner.CornerRadius = UDim.new(0, 6)
posCorner.Parent = posLabel

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -30, 0, 18)
statusLabel.Position = UDim2.new(0, 15, 0, 122)
statusLabel.BackgroundTransparency = 1
statusLabel.TextColor3 = Color3.fromRGB(34, 197, 94)
statusLabel.TextSize = 12
statusLabel.Font = Enum.Font.Gotham
statusLabel.Text = ""
statusLabel.Parent = frame

-- 3 Nút Copy: Relative Offset, World CFrame, World Vector3
local copyRelBtn = Instance.new("TextButton")
copyRelBtn.Size = UDim2.new(1, -30, 0, 34)
copyRelBtn.Position = UDim2.new(0, 15, 0, 146)
copyRelBtn.BackgroundColor3 = Color3.fromRGB(16, 185, 129)
copyRelBtn.Text = "🌟 COPY RELATIVE OFFSET (Dùng Cho Code Tycoon)"
copyRelBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
copyRelBtn.Font = Enum.Font.GothamBold
copyRelBtn.TextSize = 12
copyRelBtn.Parent = frame
local btnCorner0 = Instance.new("UICorner")
btnCorner0.CornerRadius = UDim.new(0, 6)
btnCorner0.Parent = copyRelBtn

local copyCfBtn = Instance.new("TextButton")
copyCfBtn.Size = UDim2.new(0.48, -10, 0, 34)
copyCfBtn.Position = UDim2.new(0, 15, 0, 188)
copyCfBtn.BackgroundColor3 = Color3.fromRGB(14, 165, 233)
copyCfBtn.Text = "📋 Copy World CFrame"
copyCfBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
copyCfBtn.Font = Enum.Font.GothamBold
copyCfBtn.TextSize = 12
copyCfBtn.Parent = frame
local btnCorner1 = Instance.new("UICorner")
btnCorner1.CornerRadius = UDim.new(0, 6)
btnCorner1.Parent = copyCfBtn

local copyVecBtn = Instance.new("TextButton")
copyVecBtn.Size = UDim2.new(0.48, -10, 0, 34)
copyVecBtn.Position = UDim2.new(0.52, 5, 0, 188)
copyVecBtn.BackgroundColor3 = Color3.fromRGB(99, 102, 241)
copyVecBtn.Text = "📋 Copy World Vector3"
copyVecBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
copyVecBtn.Font = Enum.Font.GothamBold
copyVecBtn.TextSize = 12
copyVecBtn.Parent = frame
local btnCorner2 = Instance.new("UICorner")
btnCorner2.CornerRadius = UDim.new(0, 6)
btnCorner2.Parent = copyVecBtn

local lastPosStr = ""
local lastCfStr = ""
local lastRelStr = ""

RunService.RenderStepped:Connect(function()
    pcall(function()
        local hrp = getRoot()
        if hrp then
            local p = hrp.Position
            lastPosStr = string.format("Vector3.new(%.2f, %.2f, %.2f)", p.X, p.Y, p.Z)
            lastCfStr = string.format("CFrame.new(%.2f, %.2f, %.2f)", p.X, p.Y, p.Z)

            local plotPivot = getMyPlotPivot()
            if plotPivot then
                local rel = plotPivot:PointToObjectSpace(p)
                lastRelStr = string.format("Vector3.new(%.2f, %.2f, %.2f)", rel.X, rel.Y, rel.Z)
                posLabel.Text = string.format("⭐ Relative Offset (Chuẩn mọi Plot):\n%s\n\n🌍 World: Pos(%.1f, %.1f, %.1f)", lastRelStr, p.X, p.Y, p.Z)
            else
                lastRelStr = lastPosStr
                posLabel.Text = string.format("🌍 World Pos: %.1f, %.1f, %.1f\n%s", p.X, p.Y, p.Z, lastCfStr)
            end
        end
    end)
end)

copyRelBtn.MouseButton1Click:Connect(function()
    if lastRelStr ~= "" then
        copyToClipboard(lastRelStr)
        print("[Kiz Hub Relative Offset] " .. lastRelStr)
        statusLabel.Text = "✓ Đã copy RELATIVE OFFSET vào Clipboard & Console!"
        task.delay(3, function() statusLabel.Text = "" end)
    end
end)

copyCfBtn.MouseButton1Click:Connect(function()
    if lastCfStr ~= "" then
        copyToClipboard(lastCfStr)
        print("[Kiz Hub World CFrame] " .. lastCfStr)
        statusLabel.Text = "✓ Đã copy World CFrame vào Clipboard & Console!"
        task.delay(3, function() statusLabel.Text = "" end)
    end
end)

copyVecBtn.MouseButton1Click:Connect(function()
    if lastPosStr ~= "" then
        copyToClipboard(lastPosStr)
        print("[Kiz Hub World Vector3] " .. lastPosStr)
        statusLabel.Text = "✓ Đã copy World Vector3 vào Clipboard & Console!"
        task.delay(3, function() statusLabel.Text = "" end)
    end
end)
