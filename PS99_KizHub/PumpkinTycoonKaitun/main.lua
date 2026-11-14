-- =========================================================================
-- PS99_KizHub/PumpkinTycoonKaitun/main.lua
-- Trình điều phối chính (Orchestrator) cho Suite tự động hóa Pumpkin Patch Tycoon
-- Tác giả: VANTA [JHON369] | KizHub Automation Engine
-- =========================================================================

repeat task.wait(0.2) until game:IsLoaded()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local GITHUB_REPO_BASE = "https://raw.githubusercontent.com/lamhoc/speed_jump_autoclick_tele/refs/heads/main/PS99_KizHub/"

local function readFileSafe(path)
    if type(readfile) == "function" then
        local ok, content = pcall(readfile, path)
        if ok and content and #content > 0 then
            return content
        end
    end
    return nil
end

local function import(relativePath)
    local localCandidates = {
        relativePath,
        "PS99_KizHub/" .. relativePath,
        "scripts/PS99_KizHub/" .. relativePath,
    }
    for _, path in ipairs(localCandidates) do
        local content = readFileSafe(path)
        if content then
            local fn, err = loadstring(content, "=" .. relativePath)
            if fn then return fn() else error("[KizHub Import] Lỗi nạp local " .. relativePath .. ": " .. tostring(err)) end
        end
    end

    local url = GITHUB_REPO_BASE .. relativePath
    local okG, webContent = pcall(function() return game:HttpGet(url) end)
    if okG and webContent and #webContent > 0 then
        local fn, err = loadstring(webContent, "=" .. relativePath)
        if fn then return fn() else error("[KizHub Import] Lỗi nạp online " .. url .. ": " .. tostring(err)) end
    end

    error("[KizHub Import] Không tìm thấy file: " .. relativePath)
end

-- =========================================================================
-- 1. NẠP MODULES & CẤU HÌNH HỆ THỐNG
-- =========================================================================

local Modules        = import("Shared/Modules.lua")
local Network        = import("Shared/Network.lua")
local EngineOptim    = import("Shared/EngineOptim.lua")
local AntiAFK        = import("Shared/AntiAFK.lua")
local Webhook        = import("Shared/Webhook.lua")
local DashboardGui   = import("Shared/DashboardGui.lua")

local Daycare        = import("HalloweenKaitun/Daycare.lua")
local AutoMail       = import("HalloweenKaitun/AutoMail.lua")
local BuffsAndGifts  = import("HalloweenKaitun/BuffsAndGifts.lua")

local ConfigModule   = import("PumpkinTycoonKaitun/Config.lua")
local Config         = ConfigModule.Config
local K              = ConfigModule.K

local TycoonFarm     = import("PumpkinTycoonKaitun/TycoonFarm.lua")
local EggHatch       = import("PumpkinTycoonKaitun/EggHatch.lua")
local TycoonMachines = import("PumpkinTycoonKaitun/TycoonMachines.lua")

-- Ràng buộc Network với môi trường game
Network.bindModules(Modules.G)

-- Trạng thái điều phối phiên chạy
local state = {
    alive = true,
    startTime = os.clock(),
    sessionStartCoins = 0,
    totalEggsHatched = 0,
    currentZoneNumber = 1,
    currentEggName = "Cocoa Cabin Egg",
    excursion = nil,
    daycareStatus = "Chờ",
    mailStatus = "Rảnh",
}

-- Khởi tạo Dependencies dùng chung
local sharedDeps = {
    Modules = Modules,
    Network = Network,
    Config = Config,
    K = K,
    Webhook = Webhook,
    inEvent = function()
        local s = Network.getSave()
        local inst = s and s.Instancing and s.Instancing.InstanceId
        return inst == K.INSTANCE_ID
    end,
    instanceModel = function()
        if Modules and Modules.G and Modules.G.Instancing and Network.isfn(Modules.G.Instancing, "GetModel") then
            local m = Network.gval(Modules.G.Instancing.GetModel)
            if typeof(m) == "Instance" then return m end
        end
        local things = workspace:FindFirstChild("__THINGS")
        local cont = things and things:FindFirstChild("__INSTANCE_CONTAINER")
        local act = cont and cont:FindFirstChild("Active")
        return act and act:FindFirstChild(K.INSTANCE_ID)
    end,
    petEuids = TycoonFarm.petEuids,
    DashboardGui = DashboardGui,
}

TycoonFarm.init(sharedDeps)
EggHatch.init(sharedDeps)
TycoonMachines.init(sharedDeps)
Daycare.init(sharedDeps)
AutoMail.init(sharedDeps)
BuffsAndGifts.init(sharedDeps)

-- =========================================================================
-- 2. TỐI ƯU HIỆU NĂNG & CHỐNG AFK KICK
-- =========================================================================

EngineOptim.applyAll(Config.TargetFPS or 5, Config.Blackout ~= false)
if Config.HidePlayers then
    EngineOptim.hideOtherPlayers()
end

AntiAFK.installGodModeAntiAfk(Network.netFire, Config.AfkPulseInterval or 35)

-- =========================================================================
-- 3. ĐẢM BẢO NGƯỜI CHƠI ĐÃ VÀO INSTANCE PUMPKIN TYCOON
-- =========================================================================

local function ensureInPumpkinTycoon()
    local s = Network.getSave()
    local currentInst = s and s.Instancing and s.Instancing.InstanceId
    if currentInst == K.INSTANCE_ID and TycoonFarm.getPlot() then
        return true
    end

    print("[KizHub Tycoon] Đang tiến vào thế giới Pumpkin Tycoon...")
    pcall(function()
        if Modules and Modules.G and Modules.G.Instancing and Network.isfn(Modules.G.Instancing, "Enter") then
            Network.gcall(Modules.G.Instancing.Enter, K.INSTANCE_ID)
        else
            Network.netInvoke("Instancing_PlayerEnterInstance", K.INSTANCE_ID)
        end
    end)

    local t0 = os.clock()
    while state.alive and os.clock() - t0 < 15 do
        if TycoonFarm.getPlot() then
            task.wait(1.5)
            -- Đặt cấu hình AutoBreak về 0 ngay khi vào đảo
            TycoonFarm.ensureAutoBreakZero()
            return true
        end
        task.wait(0.5)
    end

    return TycoonFarm.getPlot() ~= nil
end

-- =========================================================================
-- 4. KHỞI TẠO DASHBOARD GUI THEO DÕI THỜI GIAN THỰC
-- =========================================================================

local ui = DashboardGui.create({
    BadgeTitle = "🎃 Kiz Hub | Pumpkin Patch Tycoon",
    OnClose = function()
        state.alive = false
    end,
})

task.spawn(function()
    while state.alive do
        pcall(function()
            local now = os.clock()
            local uptime = now - state.startTime
            local hrs = math.floor(uptime / 3600)
            local mins = math.floor((uptime % 3600) / 60)
            local secs = math.floor(uptime % 60)

            local prog = TycoonFarm.getTycoonProgress()
            local mach = TycoonMachines.getMachineSummary()
            local coins = Network.currency(K.CURRENCY) or 0
            local tokens = Network.currency(K.TOKENS) or 0

            if state.sessionStartCoins == 0 and coins > 0 then
                state.sessionStartCoins = coins
            end
            local earnedCoins = math.max(0, coins - state.sessionStartCoins)

            -- Cập nhật Header
            if ui.UptimeLabel then
                ui.UptimeLabel.Text = string.format("Uptime: %02d:%02d:%02d", hrs, mins, secs)
            end
            if ui.ZoneLabel then
                local zoneData = K.ZONES[prog.bestZone or 1]
                ui.ZoneLabel.Text = string.format("Zone %d of 5 • %s", prog.bestZone or 1, zoneData and zoneData.DisplayName or "Cocoa Cabin")
            end
            if ui.CoinsLabel then
                ui.CoinsLabel.Text = string.format("Patch Coins: %s (+%s) | Tokens: %s", Network.shorten(coins), Network.shorten(earnedCoins), Network.shorten(tokens))
            end
            if ui.CombineLabel then
                ui.CombineLabel.Text = string.format("Hatched: %d | Big Pumpkins: %d", state.totalEggsHatched, prog.activeBigPumpkins)
            end
            if ui.MailLabel then
                ui.MailLabel.Text = string.format("Doing: %s", state.excursion or "Cày quặng bãi cao nhất & Mua nút...")
            end

            -- Cập nhật 4 Hàng Tiến Độ (QuestRows)
            if ui.QuestRows then
                -- Hàng 1: Tiến độ xây đảo (Island Buttons & Reward)
                local r1 = ui.QuestRows[1]
                if r1 then
                    r1.Row.Visible = true
                    r1.Stars.Text = "[🏝️ Đảo]"
                    r1.Stars.TextColor3 = Color3.fromRGB(56, 189, 248)
                    r1.Name.Text = "Tiến Độ Xây Đảo"
                    local isDone = prog.completed or (prog.percent >= 1)
                    r1.ProgText.Text = string.format("%d / %d (%.0f%%) • %s", prog.ownedButtons, prog.totalButtons, prog.percent * 100, isDone and "HOÀN THÀNH" or "ĐANG XÂY")
                    r1.ProgText.TextColor3 = isDone and Color3.fromRGB(52, 211, 153) or Color3.fromRGB(248, 113, 113)
                    r1.BarFill.Size = UDim2.new(math.clamp(prog.percent, 0, 1), 0, 1, 0)
                    r1.BarFill.BackgroundColor3 = isDone and Color3.fromRGB(52, 211, 153) or Color3.fromRGB(56, 189, 248)
                end

                -- Hàng 2: Bí Ngô Khổng Lồ & Bệ Pedestal
                local r2 = ui.QuestRows[2]
                if r2 then
                    r2.Row.Visible = true
                    r2.Stars.Text = "[🎃 Bệ]"
                    r2.Stars.TextColor3 = Color3.fromRGB(251, 146, 60)
                    r2.Name.Text = "Bệ & Bí Ngô Khổng Lồ"
                    r2.ProgText.Text = string.format("Bí Ngô: %d (Bậc %d) | Bệ mở: %d/8 | Stock: %d", prog.activeBigPumpkins, prog.activeBigPumpkinRung or 0, prog.unlockedPedestals, mach.stockCount or 0)
                    r2.ProgText.TextColor3 = (prog.activeBigPumpkins > 0) and Color3.fromRGB(251, 146, 60) or Color3.fromRGB(52, 211, 153)
                    local pedFrac = math.clamp(prog.unlockedPedestals / 8, 0, 1)
                    r2.BarFill.Size = UDim2.new(pedFrac, 0, 1, 0)
                    r2.BarFill.BackgroundColor3 = Color3.fromRGB(251, 146, 60)
                end

                -- Hàng 3: Máy Nâng Cấp Upgrade Machine
                local r3 = ui.QuestRows[3]
                if r3 then
                    r3.Row.Visible = true
                    r3.Stars.Text = "[⚡ Máy]"
                    r3.Stars.TextColor3 = Color3.fromRGB(168, 85, 247)
                    r3.Name.Text = "Upgrade Machine"
                    r3.ProgText.Text = string.format("Tổng cấp: %d | Tokens: %s", mach.totalTiers or 0, Network.shorten(tokens))
                    r3.ProgText.TextColor3 = Color3.fromRGB(168, 85, 247)
                    r3.BarFill.Size = UDim2.new(math.clamp((mach.totalTiers or 0) / 100, 0, 1), 0, 1, 0)
                    r3.BarFill.BackgroundColor3 = Color3.fromRGB(168, 85, 247)
                end

                -- Hàng 4: Hot Cocoa & Trứng Đang Mở
                local r4 = ui.QuestRows[4]
                if r4 then
                    r4.Row.Visible = true
                    r4.Stars.Text = "[☕ Cocoa]"
                    r4.Stars.TextColor3 = Color3.fromRGB(250, 204, 21)
                    r4.Name.Text = "Hot Cocoa & Trứng"
                    r4.ProgText.Text = string.format("Cocoa: %dp | Mở: %s", mach.activeCocoaMin or 0, state.currentEggName or "None")
                    r4.ProgText.TextColor3 = (mach.activeCocoaMin > 0) and Color3.fromRGB(52, 211, 153) or Color3.fromRGB(248, 113, 113)
                    r4.BarFill.Size = UDim2.new(math.clamp(mach.activeCocoaMin / 60, 0, 1), 0, 1, 0)
                    r4.BarFill.BackgroundColor3 = Color3.fromRGB(250, 204, 21)
                end
            end
        end)
        task.wait(1.0)
    end
end)

-- =========================================================================
-- 5. CÁC TIẾN TRÌNH VẬN HÀNH ĐỒNG THỜI (CONCURRENT WORKERS)
-- =========================================================================

-- LUỒNG 1: Farm bãi patch cao nhất + Ưu tiên diệt Bí Ngô Khổng Lồ + Mở trứng Custom
task.spawn(function()
    while state.alive do
        pcall(function()
            if not Config.Enabled or not ensureInPumpkinTycoon() then
                task.wait(1.0)
                return
            end

            -- 1. Ưu tiên cao nhất: Kiểm tra và đánh Bí Ngô Khổng Lồ nếu xuất hiện trên bệ
            local isFightingBigPumpkin = TycoonFarm.breakBigPumpkinTick(state)

            -- 2. Nếu không có Bí Ngô Khổng Lồ, tập trung farm bãi Patch tốt nhất
            if not isFightingBigPumpkin then
                TycoonFarm.farmBestPatchTick(state)
            end

            -- 3. Mở trứng Custom cao nhất từ xa (không xáo trộn vị trí farm)
            EggHatch.hatchBestEggTick(state)
        end)
        task.wait(0.1)
    end
end)

-- LUỒNG 2: Mua nút Tycoon (Cheapest First) & Hút Orbs / Lootbags
task.spawn(function()
    while state.alive do
        pcall(function()
            if not Config.Enabled or not ensureInPumpkinTycoon() then
                task.wait(1.0)
                return
            end

            -- Tự động mua nút rẻ nhất khi đủ Patch Coins
            TycoonFarm.checkAndBuyButtons(state)
            TycoonFarm.collectOrbsTick()
        end)
        task.wait(Config.ButtonBuyInterval or 1.5)
    end
end)

-- LUỒNG 3: Auto-Tap gõ quặng xung quanh
task.spawn(function()
    while state.alive do
        pcall(function()
            if Config.Enabled and ensureInPumpkinTycoon() then
                TycoonFarm.runAutoTapTick()
            end
        end)
        task.wait(Config.AutoTap and Config.AutoTap.TapDelay or 0.2)
    end
end)

-- LUỒNG 4: Quản lý toàn bộ máy trạm (Upgrades, Merchant, Cocoa, Roster Pets, Gifts)
task.spawn(function()
    while state.alive do
        pcall(function()
            if Config.Enabled and ensureInPumpkinTycoon() then
                TycoonMachines.runAllMachinesTick(state)
                TycoonFarm.ensureAutoBreakZero()
            end
        end)
        task.wait(3.0)
    end
end)

-- LUỒNG 5: Quản lý Daycare, AutoMail Huge & Buffs phụ trợ
task.spawn(function()
    while state.alive do
        pcall(function()
            if Config.Enabled then
                if Config.AutoDaycare and Daycare and type(Daycare.checkAndEnroll) == "function" then
                    Daycare.checkAndEnroll(state)
                end
                if Config.AutoMailHuge and AutoMail and type(AutoMail.checkAndSendHuge) == "function" then
                    AutoMail.checkAndSendHuge(state)
                end
                if BuffsAndGifts and type(BuffsAndGifts.runBuffsAndGiftsTick) == "function" then
                    BuffsAndGifts.runBuffsAndGiftsTick(state)
                end
            end
        end)
        task.wait(15.0)
    end
end)

-- LUỒNG 6: Bắt Huge / Titanic mới nở từ Trứng & Gửi Báo Cáo Discord Webhook Định Kỳ
task.spawn(function()
    local lastStatusReport = os.clock()
    while state.alive do
        pcall(function()
            -- 1. Quét tìm Huge / Titanic vừa nở
            local eventsUrl = Config.Webhook and Config.Webhook.EventsUrl
            if eventsUrl and eventsUrl ~= "" and Webhook and type(Webhook.checkNewHugeHatched) == "function" then
                Webhook.checkNewHugeHatched(Network.getSave, eventsUrl)
            end

            -- 2. Gửi báo cáo trạng thái định kỳ 30 phút
            local statusUrl = Config.Webhook and Config.Webhook.StatusUrl
            local interval = (Config.Webhook and Config.Webhook.StatusInterval) or 1800
            if statusUrl and statusUrl ~= "" and os.clock() - lastStatusReport >= interval then
                lastStatusReport = os.clock()
                local prog = TycoonFarm.getTycoonProgress()
                local coins = Network.currency(K.CURRENCY) or 0
                local tokens = Network.currency(K.TOKENS) or 0
                local uptimeHours = (os.clock() - state.startTime) / 3600

                local title = "📊 [BÁO CÁO PUMPKIN TYCOON] THỐNG KÊ ĐỊNH KỲ"
                local desc = string.format(
                    "Tài khoản: **%s**\nThời gian chạy: **%.1f giờ**\nTiến độ Đảo: **%d/%d (%.1f%%)**\nKhu vực cao nhất: **Zone %d (%s)**\nPatch Coins: **%s**\nPumpkin Tokens: **%s**\nTrứng đã mở: **%d**\nBệ Pedestal: **%d/8**",
                    LocalPlayer.Name,
                    uptimeHours,
                    prog.ownedButtons,
                    prog.totalButtons,
                    prog.percent * 100,
                    prog.bestZone,
                    K.ZONES[prog.bestZone] and K.ZONES[prog.bestZone].DisplayName or "None",
                    Network.shorten(coins),
                    Network.shorten(tokens),
                    state.totalEggsHatched,
                    prog.unlockedPedestals
                )
                Webhook.sendWebhook(title, desc, 0xf59e0b, statusUrl)
            end
        end)
        task.wait(5.0)
    end
end)

print("[KizHub Tycoon] 🚀 Khởi chạy hoàn tất Suite tự động hóa Pumpkin Patch Tycoon!")
