-- =========================================================================
-- PS99_KizHub/Shared/SpyGift.lua
-- REMOTE SPY CHUYÊN DỤNG BẮT HÀNH ĐỘNG MỞ GIFT & LOOTBOX TRONG PET SIMULATOR 99
-- Tác giả: VANTA [JHON369] | Thiết kế riêng cho dj
-- Hướng dẫn:
--   1. Chạy script này trên executor (Volt, Wave, Delta, Hydrogen, Solara...)
--   2. Một bảng GUI tím nổi sẽ xuất hiện trên màn hình.
--   3. Mở túi đồ (Inventory) và tự tay click mở 1 hộp quà Flannel Gift hoặc Gift bất kỳ.
--   4. Remote và toàn bộ tham số sẽ được bắt tức thì, tự động copy vào Clipboard
--      và hiển thị trên GUI + Console (F9).
--   5. Gửi lại kết quả copy cho VANTA để map vào script chính!
-- =========================================================================

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 10)

-- Multi-executor clipboard support
local setclip = setclipboard or toclipboard or (Clipboard and Clipboard.set) or function(...) end
local getgenvFn = (type(getgenv) == "function" and getgenv) or function() return _G end

-- Gỡ bỏ GUI cũ nếu đang chạy
if getgenvFn()._GiftSpyGui then
    pcall(function() getgenvFn()._GiftSpyGui:Destroy() end)
    getgenvFn()._GiftSpyGui = nil
end

-- =========================================================================
-- 1. HÀM CHUYỂN ĐỔI THAM SỐ AN TOÀN TUYỆT ĐỐI (KHÔNG CRASH)
-- =========================================================================
local function safeSerialize(val, depth, visited)
    depth = depth or 0
    visited = visited or {}
    if depth > 4 then return "..." end

    local t = typeof(val)
    if t == "string" then
        return string.format("%q", val)
    elseif t == "number" or t == "boolean" then
        return tostring(val)
    elseif t == "nil" then
        return "nil"
    elseif t == "Instance" then
        local fullName = pcall(function() return val:GetFullName() end) and val:GetFullName() or tostring(val)
        return string.format("game.%s", fullName)
    elseif t == "Vector3" then
        return string.format("Vector3.new(%.2f, %.2f, %.2f)", val.X, val.Y, val.Z)
    elseif t == "CFrame" then
        local p = val.Position
        return string.format("CFrame.new(%.2f, %.2f, %.2f)", p.X, p.Y, p.Z)
    elseif t == "table" then
        if visited[val] then return "<CircularTable>" end
        visited[val] = true

        local parts = {}
        local count = 0
        local isArray = true
        for k, _ in pairs(val) do
            count = count + 1
            if type(k) ~= "number" or k ~= count then isArray = false end
            if count > 12 then table.insert(parts, "..."); break end
        end

        local cur = 0
        for k, v in pairs(val) do
            cur = cur + 1
            if cur > 12 then break end
            local vStr = safeSerialize(v, depth + 1, visited)
            if isArray then
                table.insert(parts, vStr)
            else
                local kStr = (type(k) == "string" and k:match("^[%a_][%w_]*$")) and k or string.format("[%s]", safeSerialize(k, depth + 1, visited))
                table.insert(parts, string.format("%s = %s", kStr, vStr))
            end
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    else
        return string.format("<%s: %s>", t, tostring(val))
    end
end

-- =========================================================================
-- 2. TẠO GIAO DIỆN SPY UI NỔI TRÊN MÀN HÌNH
-- =========================================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "KizHub_GiftSpy_Safe"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

pcall(function()
    if gethui then
        ScreenGui.Parent = gethui()
    elseif syn and syn.protect_gui then
        syn.protect_gui(ScreenGui)
        ScreenGui.Parent = CoreGui
    else
        ScreenGui.Parent = CoreGui
    end
end)
if not ScreenGui.Parent then ScreenGui.Parent = PlayerGui end
getgenvFn()._GiftSpyGui = ScreenGui

local MainFrame = Instance.new("Frame", ScreenGui)
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 560, 0, 420)
MainFrame.Position = UDim2.new(0.5, -280, 0.5, -210)
MainFrame.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true

Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 10)
local Stroke = Instance.new("UIStroke", MainFrame)
Stroke.Color = Color3.fromRGB(168, 85, 247)
Stroke.Thickness = 1.5

-- Header
local Header = Instance.new("Frame", MainFrame)
Header.Name = "Header"
Header.Size = UDim2.new(1, 0, 0, 38)
Header.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
Header.BorderSizePixel = 0
Instance.new("UICorner", Header).CornerRadius = UDim.new(0, 10)

local Title = Instance.new("TextLabel", Header)
Title.Text = "🎁 KizHub | Gift & Lootbox Remote Spy (VANTA)"
Title.Font = Enum.Font.GothamBold
Title.TextSize = 13
Title.TextColor3 = Color3.fromRGB(216, 180, 254)
Title.Position = UDim2.new(0, 12, 0, 0)
Title.Size = UDim2.new(1, -50, 1, 0)
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.BackgroundTransparency = 1

local CloseBtn = Instance.new("TextButton", Header)
CloseBtn.Text = "✕"
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 14
CloseBtn.TextColor3 = Color3.fromRGB(248, 113, 113)
CloseBtn.Position = UDim2.new(1, -32, 0, 6)
CloseBtn.Size = UDim2.new(0, 26, 0, 26)
CloseBtn.BackgroundColor3 = Color3.fromRGB(51, 25, 35)
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 6)
CloseBtn.MouseButton1Click:Connect(function() ScreenGui:Destroy() end)

-- Status Box
local StatusLabel = Instance.new("TextLabel", MainFrame)
StatusLabel.Name = "StatusLabel"
StatusLabel.Text = "📡 Đang lắng nghe... Hãy vào Inventory và mở 1 hộp quà Flannel Gift!"
StatusLabel.Font = Enum.Font.GothamMedium
StatusLabel.TextSize = 11
StatusLabel.TextColor3 = Color3.fromRGB(52, 211, 153)
StatusLabel.Position = UDim2.new(0, 12, 0, 42)
StatusLabel.Size = UDim2.new(1, -24, 0, 20)
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.BackgroundTransparency = 1

-- Filter Settings Bar
local FilterBar = Instance.new("Frame", MainFrame)
FilterBar.Name = "FilterBar"
FilterBar.Size = UDim2.new(1, -24, 0, 26)
FilterBar.Position = UDim2.new(0, 12, 0, 64)
FilterBar.BackgroundColor3 = Color3.fromRGB(20, 29, 47)
Instance.new("UICorner", FilterBar).CornerRadius = UDim.new(0, 6)

local FilterLabel = Instance.new("TextLabel", FilterBar)
FilterLabel.Text = "Bộ lọc từ khóa:"
FilterLabel.Font = Enum.Font.GothamBold
FilterLabel.TextSize = 10
FilterLabel.TextColor3 = Color3.fromRGB(148, 163, 184)
FilterLabel.Position = UDim2.new(0, 8, 0, 0)
FilterLabel.Size = UDim2.new(0, 85, 1, 0)
FilterLabel.TextXAlignment = Enum.TextXAlignment.Left
FilterLabel.BackgroundTransparency = 1

local FilterInput = Instance.new("TextBox", FilterBar)
FilterInput.Text = "gift,lootbox,box,open,flannel,use,consume,item,redeem,reward,tycoon"
FilterInput.ClearTextOnFocus = false
FilterInput.Font = Enum.Font.Code
FilterInput.TextSize = 10
FilterInput.TextColor3 = Color3.fromRGB(56, 189, 248)
FilterInput.Position = UDim2.new(0, 95, 0, 2)
FilterInput.Size = UDim2.new(1, -100, 1, -4)
FilterInput.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
Instance.new("UICorner", FilterInput).CornerRadius = UDim.new(0, 4)

-- Log Scroll Area
local LogScroll = Instance.new("ScrollingFrame", MainFrame)
LogScroll.Name = "LogScroll"
LogScroll.Position = UDim2.new(0, 12, 0, 96)
LogScroll.Size = UDim2.new(1, -24, 1, -150)
LogScroll.BackgroundColor3 = Color3.fromRGB(10, 14, 26)
LogScroll.BorderSizePixel = 0
LogScroll.ScrollBarThickness = 5
LogScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
LogScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
Instance.new("UICorner", LogScroll).CornerRadius = UDim.new(0, 6)

local LogListLayout = Instance.new("UIListLayout", LogScroll)
LogListLayout.SortOrder = Enum.SortOrder.LayoutOrder
LogListLayout.Padding = UDim.new(0, 4)

local LogPadding = Instance.new("UIPadding", LogScroll)
LogPadding.PaddingTop = UDim.new(0, 6)
LogPadding.PaddingBottom = UDim.new(0, 6)
LogPadding.PaddingLeft = UDim.new(0, 8)
LogPadding.PaddingRight = UDim.new(0, 8)

-- Footer Controls
local BtnContainer = Instance.new("Frame", MainFrame)
BtnContainer.Position = UDim2.new(0, 12, 1, -46)
BtnContainer.Size = UDim2.new(1, -24, 0, 36)
BtnContainer.BackgroundTransparency = 1

local function createBtn(text, xPos, width, color, callback)
    local btn = Instance.new("TextButton", BtnContainer)
    btn.Text = text
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 11
    btn.TextColor3 = Color3.fromRGB(248, 250, 252)
    btn.BackgroundColor3 = color
    btn.Position = UDim2.new(0, xPos, 0, 0)
    btn.Size = UDim2.new(0, width, 1, 0)
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    btn.MouseButton1Click:Connect(callback)
    return btn
end

local lastCapturedCommand = ""
local allLogs = {}
local captureModeAll = false

local function addLog(text, codeToCopy, color)
    local line = string.format("[%s] %s", os.date("%H:%M:%S"), text)
    print("[GiftSpy] " .. line)
    table.insert(allLogs, line .. (codeToCopy and ("\n  --> " .. codeToCopy) or ""))

    local row = Instance.new("TextButton", LogScroll)
    row.Text = line
    row.Font = Enum.Font.Code
    row.TextSize = 10
    row.TextColor3 = color or Color3.fromRGB(224, 231, 255)
    row.TextXAlignment = Enum.TextXAlignment.Left
    row.TextWrapped = true
    row.Size = UDim2.new(1, 0, 0, 0)
    row.AutomaticSize = Enum.AutomaticSize.Y
    row.BackgroundTransparency = 1

    if codeToCopy then
        row.MouseButton1Click:Connect(function()
            setclip(codeToCopy)
            StatusLabel.Text = "📋 Đã copy lệnh này vào Clipboard!"
        end)
    end

    local children = LogScroll:GetChildren()
    if #children > 150 then
        children[3]:Destroy()
    end
    task.defer(function()
        LogScroll.CanvasPosition = Vector2.new(0, 999999)
    end)
end

-- =========================================================================
-- 3. HOOK __NAMECALL & TÌM REMOTE THÔNG MINH
-- =========================================================================
local function isMatchFilter(name, argsStr)
    if captureModeAll then return true end
    local query = FilterInput.Text:lower()
    local target = (name .. " " .. argsStr):lower()
    for word in query:gmatch("[^,;|%s]+") do
        if word ~= "" and target:find(word, 1, true) then
            return true
        end
    end
    return false
end

pcall(function()
    if type(hookmetamethod) ~= "function" then
        addLog("⚠️ Executor không hỗ trợ hookmetamethod! Hãy thử dùng Volt / Wave / Delta.", nil, Color3.fromRGB(239, 68, 68))
        return
    end

    local oldNamecall = nil
    oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local method = getnamecallmethod()
        
        if (method == "InvokeServer" or method == "FireServer") and typeof(self) == "Instance" then
            local rName = self.Name
            local rawArgs = { ... }

            task.spawn(function()
                local formatted = {}
                for _, a in ipairs(rawArgs) do
                    table.insert(formatted, safeSerialize(a))
                end
                local argsJoined = table.concat(formatted, ", ")

                if isMatchFilter(rName, argsJoined) then
                    local codePayload = string.format("game:GetService(\"ReplicatedStorage\").Network[%q]:%s(%s)", rName, method, argsJoined)
                    local displayLine = string.format("[%s] %s(%s)", method, rName, argsJoined)

                    lastCapturedCommand = codePayload
                    addLog(displayLine, codePayload, Color3.fromRGB(244, 114, 182))
                    StatusLabel.Text = "🎯 ĐÃ BẮT ĐƯỢC REMOTE: " .. rName .. " (Đã auto-copy!)"
                    pcall(function() setclip(codePayload) end)
                end
            end)
        end

        return oldNamecall(self, ...)
    end))

    addLog("✓ Đã cài đặt Safe Hook __namecall (Bảo toàn 100% dữ liệu game)", nil, Color3.fromRGB(56, 189, 248))
end)

-- Hook phụ vào Network module nếu có thể (để bắt kể cả khi game dùng custom wrapper)
pcall(function()
    local NetModule = RS:FindFirstChild("Network", true) or (RS:FindFirstChild("Library") and RS.Library:FindFirstChild("Client") and RS.Library.Client:FindFirstChild("Network"))
    if NetModule and type(require) == "function" then
        local netObj = require(NetModule)
        if type(netObj) == "table" then
            if type(netObj.Invoke) == "function" and hookfunction then
                local oldInv = netObj.Invoke
                netObj.Invoke = function(name, ...)
                    local rawArgs = { ... }
                    task.spawn(function()
                        local formatted = {}
                        for _, a in ipairs(rawArgs) do table.insert(formatted, safeSerialize(a)) end
                        local argsJoined = table.concat(formatted, ", ")
                        if isMatchFilter(tostring(name), argsJoined) then
                            local code = string.format("Network.Invoke(%q, %s)", tostring(name), argsJoined)
                            lastCapturedCommand = code
                            addLog("[Network.Invoke] " .. tostring(name) .. "(" .. argsJoined .. ")", code, Color3.fromRGB(52, 211, 153))
                            pcall(function() setclip(code) end)
                        end
                    end)
                    return oldInv(name, ...)
                end
            end
            if type(netObj.Fire) == "function" and hookfunction then
                local oldFire = netObj.Fire
                netObj.Fire = function(name, ...)
                    local rawArgs = { ... }
                    task.spawn(function()
                        local formatted = {}
                        for _, a in ipairs(rawArgs) do table.insert(formatted, safeSerialize(a)) end
                        local argsJoined = table.concat(formatted, ", ")
                        if isMatchFilter(tostring(name), argsJoined) then
                            local code = string.format("Network.Fire(%q, %s)", tostring(name), argsJoined)
                            lastCapturedCommand = code
                            addLog("[Network.Fire] " .. tostring(name) .. "(" .. argsJoined .. ")", code, Color3.fromRGB(52, 211, 153))
                            pcall(function() setclip(code) end)
                        end
                    end)
                    return oldFire(name, ...)
                end
            end
        end
    end
end)

-- =========================================================================
-- 4. CÁC NÚT ĐIỀU KHIỂN DƯỚI FOOTER
-- =========================================================================
-- Nút 1: Copy Remote mới nhất
createBtn("📋 Copy Lệnh Mới", 0, 130, Color3.fromRGB(37, 99, 235), function()
    if lastCapturedCommand ~= "" then
        setclip(lastCapturedCommand)
        StatusLabel.Text = "📋 Đã copy lệnh mới nhất vào Clipboard!"
    else
        StatusLabel.Text = "⚠️ Chưa bắt được lệnh nào!"
    end
end)

-- Nút 2: Copy Toàn Bộ Log
createBtn("📑 Copy All Logs", 136, 120, Color3.fromRGB(147, 51, 234), function()
    if #allLogs > 0 then
        local fullText = table.concat(allLogs, "\n")
        setclip(fullText)
        StatusLabel.Text = string.format("📑 Đã copy toàn bộ %d logs vào Clipboard!", #allLogs)
    else
        StatusLabel.Text = "⚠️ Danh sách log trống!"
    end
end)

-- Nút 3: Toggle Bắt Tất Cả (All vs Filtered)
local toggleModeBtn = createBtn("🔍 Chế Độ: Lọc", 262, 125, Color3.fromRGB(16, 185, 129), function() end)
toggleModeBtn.MouseButton1Click:Connect(function()
    captureModeAll = not captureModeAll
    if captureModeAll then
        toggleModeBtn.Text = "⚡ Chế Độ: BẮT TẤT CẢ"
        toggleModeBtn.BackgroundColor3 = Color3.fromRGB(239, 68, 68)
        StatusLabel.Text = "⚡ Đang bắt TẤT CẢ remote (không lọc từ khóa)"
    else
        toggleModeBtn.Text = "🔍 Chế Độ: LỌC"
        toggleModeBtn.BackgroundColor3 = Color3.fromRGB(16, 185, 129)
        StatusLabel.Text = "🔍 Đang lọc theo từ khóa: " .. FilterInput.Text
    end
end)

-- Nút 4: Xóa Log
createBtn("🗑️ Xóa Log", 393, 80, Color3.fromRGB(71, 85, 105), function()
    allLogs = {}
    for _, child in ipairs(LogScroll:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end
    StatusLabel.Text = "📡 Đã xóa sạch log. Sẵn sàng bắt tiếp!"
end)

addLog("SẴN SÀNG! Remote Spy đã kích hoạt.", nil, Color3.fromRGB(52, 211, 153))
addLog("Bây giờ bạn mở túi đồ và mở Flannel Gift, remote sẽ tự động hiện ở đây và copy vào Clipboard!", nil, Color3.fromRGB(224, 231, 255))
