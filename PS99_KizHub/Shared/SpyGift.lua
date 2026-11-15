-- =========================================================================
-- PS99_KizHub/Shared/SpyGift.lua (V3 - PRODUCER-CONSUMER QUEUE & ZERO PERMISSION ERROR)
-- Tác giả: VANTA [JHON369] | Dành riêng cho dj
-- Khắc phục triệt để lỗi:
--   "The current thread cannot access 'Instance' (lacking capability Plugin)"
-- Cơ chế:
--   - Luồng Hook (Producer) chạy ở game identity 2: CHỈ ghi dữ liệu vào bảng Lua thuần (EventQueue),
--     tuyệt đối KHÔNG chạm vào CoreGui / UI.
--   - Luồng Xử lý (Consumer) chạy ở executor identity 7/8: Lấy dữ liệu từ Queue, an toàn tuần tự hóa,
--     hiển thị lên UI và tự động copy vào Clipboard.
-- =========================================================================

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 10)

local setclip = setclipboard or toclipboard or (Clipboard and Clipboard.set) or function(...) end
local getgenvFn = (type(getgenv) == "function" and getgenv) or function() return _G end

-- Gỡ bỏ GUI cũ nếu có
if getgenvFn()._GiftSpyGui then
    pcall(function() getgenvFn()._GiftSpyGui:Destroy() end)
    getgenvFn()._GiftSpyGui = nil
end

-- =========================================================================
-- 1. HÀM CHUYỂN ĐỔI THAM SỐ AN TOÀN TRÊN LUỒNG EXECUTOR
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
        local fullName = nil
        pcall(function() fullName = val:GetFullName() end)
        return fullName and string.format("game.%s", fullName) or string.format("<Instance: %s>", tostring(val))
    elseif t == "Vector3" then
        return string.format("Vector3.new(%.1f, %.1f, %.1f)", val.X, val.Y, val.Z)
    elseif t == "CFrame" then
        local p = val.Position
        return string.format("CFrame.new(%.1f, %.1f, %.1f)", p.X, p.Y, p.Z)
    elseif t == "table" then
        if visited[val] then return "<CircularTable>" end
        visited[val] = true

        local parts = {}
        local count = 0
        local isArray = true
        for k, _ in pairs(val) do
            count = count + 1
            if type(k) ~= "number" or k ~= count then isArray = false end
            if count > 15 then table.insert(parts, "..."); break end
        end

        local cur = 0
        for k, v in pairs(val) do
            cur = cur + 1
            if cur > 15 then break end
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
-- 2. GIAO DIỆN SPY TRÊN MÀN HÌNH (KHỞI TẠO TRÊN EXECUTOR THREAD)
-- =========================================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "KizHub_GiftSpy_V3"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

pcall(function()
    if gethui then ScreenGui.Parent = gethui()
    elseif syn and syn.protect_gui then syn.protect_gui(ScreenGui); ScreenGui.Parent = CoreGui
    else ScreenGui.Parent = CoreGui end
end)
if not ScreenGui.Parent then ScreenGui.Parent = PlayerGui end
getgenvFn()._GiftSpyGui = ScreenGui

local MainFrame = Instance.new("Frame", ScreenGui)
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 580, 0, 420)
MainFrame.Position = UDim2.new(0.5, -290, 0.5, -210)
MainFrame.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true

Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 10)
local Stroke = Instance.new("UIStroke", MainFrame)
Stroke.Color = Color3.fromRGB(168, 85, 247)
Stroke.Thickness = 1.5

local Header = Instance.new("Frame", MainFrame)
Header.Name = "Header"
Header.Size = UDim2.new(1, 0, 0, 38)
Header.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
Header.BorderSizePixel = 0
Instance.new("UICorner", Header).CornerRadius = UDim.new(0, 10)

local Title = Instance.new("TextLabel", Header)
Title.Text = "🎁 KizHub Gift Spy V3 (TRIPLE HOOK - NO LAG - NO ERROR)"
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

local StatusLabel = Instance.new("TextLabel", MainFrame)
StatusLabel.Name = "StatusLabel"
StatusLabel.Text = "⚡ Đang lắng nghe 100% lệnh mạng... Hãy mở hộp quà trong túi đồ!"
StatusLabel.Font = Enum.Font.GothamMedium
StatusLabel.TextSize = 11
StatusLabel.TextColor3 = Color3.fromRGB(52, 211, 153)
StatusLabel.Position = UDim2.new(0, 12, 0, 42)
StatusLabel.Size = UDim2.new(1, -24, 0, 20)
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.BackgroundTransparency = 1

local LogScroll = Instance.new("ScrollingFrame", MainFrame)
LogScroll.Name = "LogScroll"
LogScroll.Position = UDim2.new(0, 12, 0, 66)
LogScroll.Size = UDim2.new(1, -24, 1, -118)
LogScroll.BackgroundColor3 = Color3.fromRGB(10, 14, 26)
LogScroll.BorderSizePixel = 0
LogScroll.ScrollBarThickness = 5
LogScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
LogScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
Instance.new("UICorner", LogScroll).CornerRadius = UDim.new(0, 6)

local LogListLayout = Instance.new("UIListLayout", LogScroll)
LogListLayout.SortOrder = Enum.SortOrder.LayoutOrder
LogListLayout.Padding = UDim.new(0, 3)

local LogPadding = Instance.new("UIPadding", LogScroll)
LogPadding.PaddingTop = UDim.new(0, 6)
LogPadding.PaddingBottom = UDim.new(0, 6)
LogPadding.PaddingLeft = UDim.new(0, 8)
LogPadding.PaddingRight = UDim.new(0, 8)

local BtnContainer = Instance.new("Frame", MainFrame)
BtnContainer.Position = UDim2.new(0, 12, 1, -44)
BtnContainer.Size = UDim2.new(1, -24, 0, 34)
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

local IGNORED_REMOTES = {
    ["Ping"] = true,
    ["GetPing"] = true,
    ["Framework: Ping"] = true,
    ["Idle Tracking: Heartbeat"] = true,
    ["Orbs: Collect"] = true,
    ["Breakables_PlayerDealDamage"] = true,
    ["AutoFarm_LogPosition"] = true,
    ["Breakables_JoinPetBulk"] = true,
}

-- =========================================================================
-- 3. HÀNG ĐỢI SỰ KIỆN (PRODUCER-CONSUMER QUEUE)
-- =========================================================================
local EventQueue = {}

local function pushEvent(src, rName, method, args)
    if IGNORED_REMOTES[rName] then return end
    table.insert(EventQueue, {
        source = src,
        name = rName,
        method = method,
        args = args,
        time = os.date("%H:%M:%S"),
    })
end

-- =========================================================================
-- 4. LUỒNG XỬ LÝ SỰ KIỆN (CONSUMER - CHẠY NỀN TRÊN EXECUTOR CONTEXT)
-- =========================================================================
task.spawn(function()
    while ScreenGui.Parent do
        while #EventQueue > 0 do
            local ev = table.remove(EventQueue, 1)
            if ev then
                local formatted = {}
                for i = 1, ev.args.n do
                    table.insert(formatted, safeSerialize(ev.args[i]))
                end
                local argsJoined = table.concat(formatted, ", ")
                local codePayload = string.format("game:GetService(\"ReplicatedStorage\").Network[%q]:%s(%s)", ev.name, ev.method, argsJoined)
                local displayLine = string.format("[%s] %s %s:%s(%s)", ev.time, ev.source, ev.name, ev.method, argsJoined)

                print("[GiftSpy] " .. displayLine)
                table.insert(allLogs, displayLine .. "\n  --> " .. codePayload)

                local fullStr = (ev.name .. " " .. argsJoined):lower()
                local isGift = fullStr:find("gift") or fullStr:find("box") or fullStr:find("flannel") or fullStr:find("open") or fullStr:find("loot") or fullStr:find("item") or fullStr:find("consume")

                local row = Instance.new("TextButton", LogScroll)
                row.Text = displayLine
                row.Font = Enum.Font.Code
                row.TextSize = 10
                row.TextXAlignment = Enum.TextXAlignment.Left
                row.TextWrapped = true
                row.Size = UDim2.new(1, 0, 0, 0)
                row.AutomaticSize = Enum.AutomaticSize.Y
                row.BackgroundTransparency = 1

                if isGift then
                    row.TextColor3 = Color3.fromRGB(250, 204, 21) -- Vàng sáng nổi bật
                    StatusLabel.Text = "🎯 ĐÃ BẮT ĐƯỢC GIFT: " .. ev.name .. " (Đã auto-copy!)"
                    lastCapturedCommand = codePayload
                    pcall(function() setclip(codePayload) end)
                else
                    row.TextColor3 = Color3.fromRGB(148, 163, 184) -- Xám nhạt
                end

                row.MouseButton1Click:Connect(function()
                    setclip(codePayload)
                    StatusLabel.Text = "📋 Đã copy: " .. ev.name
                end)

                local children = LogScroll:GetChildren()
                if #children > 200 then children[3]:Destroy() end
                task.defer(function() LogScroll.CanvasPosition = Vector2.new(0, 999999) end)
            end
        end
        task.wait(0.05)
    end
end)

-- =========================================================================
-- 5. CÁC HOOK PRODUCER (TUYỆT ĐỐI KHÔNG CHẠM COREGUI)
-- =========================================================================

-- Hook 1: __namecall
pcall(function()
    if type(hookmetamethod) ~= "function" then return end
    local oldNamecall = nil
    oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local method = getnamecallmethod()
        if (method == "InvokeServer" or method == "FireServer") and typeof(self) == "Instance" then
            local rName = tostring(self.Name)
            local args = table.pack(...)
            pushEvent("[Namecall]", rName, method, args)
        end
        return oldNamecall(self, ...)
    end))
end)

-- Hook 2: hookfunction trên InvokeServer / FireServer
pcall(function()
    if type(hookfunction) ~= "function" then return end

    local dummyFunc = Instance.new("RemoteFunction")
    local oldInv = nil
    oldInv = hookfunction(dummyFunc.InvokeServer, newcclosure(function(self, ...)
        if typeof(self) == "Instance" then
            local rName = tostring(self.Name)
            local args = table.pack(...)
            pushEvent("[FuncInvoke]", rName, "InvokeServer", args)
        end
        return oldInv(self, ...)
    end))

    local dummyEv = Instance.new("RemoteEvent")
    local oldFire = nil
    oldFire = hookfunction(dummyEv.FireServer, newcclosure(function(self, ...)
        if typeof(self) == "Instance" then
            local rName = tostring(self.Name)
            local args = table.pack(...)
            pushEvent("[FuncFire]", rName, "FireServer", args)
        end
        return oldFire(self, ...)
    end))
end)

-- Hook 3: Hook vào Client.Network nếu có
pcall(function()
    local NetModule = RS:FindFirstChild("Network", true) or (RS:FindFirstChild("Library") and RS.Library:FindFirstChild("Client") and RS.Library.Client:FindFirstChild("Network"))
    if NetModule and type(require) == "function" then
        local netObj = require(NetModule)
        if type(netObj) == "table" and hookfunction then
            if type(netObj.Invoke) == "function" then
                local origInv = netObj.Invoke
                netObj.Invoke = function(name, ...)
                    local args = table.pack(...)
                    pushEvent("[Net.Invoke]", tostring(name), "Invoke", args)
                    return origInv(name, ...)
                end
            end
            if type(netObj.Fire) == "function" then
                local origFire = netObj.Fire
                netObj.Fire = function(name, ...)
                    local args = table.pack(...)
                    pushEvent("[Net.Fire]", tostring(name), "Fire", args)
                    return origFire(name, ...)
                end
            end
        end
    end
end)

-- Hook 4: Click Tracker an toàn
pcall(function()
    UserInputService.InputBegan:Connect(function(input, processed)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            local mousePos = UserInputService:GetMouseLocation()
            task.defer(function()
                pcall(function()
                    for _, gui in ipairs(PlayerGui:GetChildren()) do
                        if gui:IsA("ScreenGui") and gui.Enabled and gui.Name ~= "KizHub_GiftSpy_V3" then
                            for _, desc in ipairs(gui:GetDescendants()) do
                                if (desc:IsA("TextButton") or desc:IsA("ImageButton")) and desc.Visible then
                                    local ap = desc.AbsolutePosition
                                    local as = desc.AbsoluteSize
                                    if mousePos.X >= ap.X and mousePos.X <= ap.X + as.X
                                       and mousePos.Y >= ap.Y and mousePos.Y <= ap.Y + as.Y then
                                        
                                        local bText = (desc:IsA("TextButton") and desc.Text) or "(ImageButton)"
                                        local pName = desc.Parent and desc.Parent.Name or ""
                                        local line = string.format("[%s] [CLICK] Nút: %q (Text: %q) | Cha: %q", os.date("%H:%M:%S"), desc.Name, bText, pName)
                                        print("[GiftSpy] " .. line)
                                        local row = Instance.new("TextButton", LogScroll)
                                        row.Text = line
                                        row.Font = Enum.Font.Code
                                        row.TextSize = 10
                                        row.TextColor3 = Color3.fromRGB(56, 189, 248)
                                        row.TextXAlignment = Enum.TextXAlignment.Left
                                        row.TextWrapped = true
                                        row.Size = UDim2.new(1, 0, 0, 0)
                                        row.AutomaticSize = Enum.AutomaticSize.Y
                                        row.BackgroundTransparency = 1
                                        table.insert(allLogs, line)
                                    end
                                end
                            end
                        end
                    end
                end)
            end)
        end
    end)
end)

-- Nút điều khiển footer
createBtn("📋 Copy Lệnh Vàng", 0, 140, Color3.fromRGB(37, 99, 235), function()
    if lastCapturedCommand ~= "" then
        setclip(lastCapturedCommand)
        StatusLabel.Text = "📋 Đã copy lệnh màu vàng vào Clipboard!"
    else
        StatusLabel.Text = "⚠️ Chưa có lệnh quà (màu vàng) nào!"
    end
end)

createBtn("📑 Copy Toàn Bộ Log", 148, 140, Color3.fromRGB(147, 51, 234), function()
    if #allLogs > 0 then
        local fullText = table.concat(allLogs, "\n")
        setclip(fullText)
        StatusLabel.Text = string.format("📑 Đã copy toàn bộ %d dòng log vào Clipboard!", #allLogs)
    else
        StatusLabel.Text = "⚠️ Danh sách log trống!"
    end
end)

createBtn("🗑️ Xóa Log", 296, 90, Color3.fromRGB(71, 85, 105), function()
    allLogs = {}
    for _, child in ipairs(LogScroll:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end
    StatusLabel.Text = "📡 Đã xóa sạch log."
end)

print("[GiftSpy] V3 Producer-Consumer sẵn sàng! Không lỗi capability.")
