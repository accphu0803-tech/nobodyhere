-- =========================================================================
-- PS99_KizHub/PumpkinTycoonKaitun/TycoonMachines.lua
-- Module tự động hóa các máy trạm & tính năng phụ trợ trên đảo Pumpkin Tycoon
-- Bao gồm:
--   1. Auto Nâng cấp máy Upgrade Machine (Tokens)
--   2. Auto Merchant & Auto Đặt hàng vào Pedestal (Stock Allocation)
--   3. Auto Mua & Duy trì Hot Cocoa Boosts (VB_Extend)
--   4. Auto Chế tạo Pet Vàng & Cầu Vồng (Roster Rung)
--   5. Auto Mở Quà Flannel Gift & Quà miễn phí
-- Tác giả: VANTA [JHON369] | KizHub Automation Engine
-- =========================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local TycoonMachines = {}

-- Dependencies
local Modules = nil
local Network = nil
local Config = nil
local K = nil
local Webhook = nil
local inEventFn = nil
local instanceModelFn = nil

-- Cache Client Modules
local IslandCmds = nil
local PTButtons = nil
local UpgradesCmds = nil
local UpgradesTypes = nil
local MerchantCmds = nil
local StockCmds = nil
local MerchantTypes = nil
local PTCocoa = nil
local CocoaCmds = nil

local function safeRequire(pathTbl)
    local cur = ReplicatedStorage
    for _, part in ipairs(pathTbl) do
        cur = cur and cur:FindFirstChild(part)
        if not cur then return nil end
    end
    local ok, res = pcall(require, cur)
    return ok and res or nil
end

local function initMachineLibs()
    if not IslandCmds then
        IslandCmds = safeRequire({ "Library", "Client", "PumpkinTycoonCmds", "Island" })
    end
    if not PTButtons then
        PTButtons = safeRequire({ "Library", "Util", "PumpkinTycoonButtons" })
    end
    if not UpgradesCmds then
        UpgradesCmds = safeRequire({ "Library", "Client", "PumpkinTycoonCmds", "Upgrades" })
    end
    if not UpgradesTypes then
        UpgradesTypes = safeRequire({ "Library", "Types", "PumpkinTycoon", "Upgrades" })
    end
    if not MerchantCmds then
        MerchantCmds = safeRequire({ "Library", "Client", "PumpkinTycoonCmds", "Merchant" })
    end
    if not StockCmds then
        StockCmds = safeRequire({ "Library", "Client", "PumpkinTycoonCmds", "Stock" })
    end
    if not MerchantTypes then
        MerchantTypes = safeRequire({ "Library", "Types", "PumpkinTycoon", "Merchant" })
    end
    if not PTCocoa then
        PTCocoa = safeRequire({ "Library", "Util", "PumpkinTycoonCocoa" })
    end
    if not CocoaCmds then
        CocoaCmds = safeRequire({ "Library", "Client", "PumpkinTycoonCmds", "Cocoa" })
    end
end

function TycoonMachines.init(deps)
    Modules = deps.Modules
    Network = deps.Network
    Config = deps.Config
    K = deps.K
    Webhook = deps.Webhook
    inEventFn = deps.inEvent
    instanceModelFn = deps.instanceModel
    initMachineLibs()
end

local function getPlot()
    initMachineLibs()
    if IslandCmds and type(IslandCmds.Plot) == "function" then
        local ok, p = pcall(IslandCmds.Plot)
        if ok and p then return p end
    end
    return nil
end

-- =========================================================================
-- 1. AUTO NÂNG CẤP MÁY UPGRADE MACHINE (SỬ DỤNG PUMPKIN TOKENS)
-- =========================================================================

local lastUpgradeCheck = 0
local function runUpgrades(plot, buttonsState)
    if not Config.AutoUpgrades then return end
    local now = os.clock()
    if now - lastUpgradeCheck < (Config.UpgradeInterval or 10) then return end
    lastUpgradeCheck = now

    local hasMachine = false
    if PTButtons and type(PTButtons.Owned) == "function" then
        hasMachine = PTButtons.Owned(buttonsState, "UpgradeMachine")
    else
        hasMachine = (buttonsState["UpgradeMachine"] == true or buttonsState["UpgradeMachine"] == 1)
    end
    if not hasMachine then return end

    local tokens = Network.currency(K.TOKENS) or 0
    if tokens <= 0 then return end

    local order = Config.UpgradeOrder or K.UPGRADE_TRACKS
    for _, track in ipairs(order) do
        local curTier = 0
        local cost = 999999999

        pcall(function()
            if UpgradesCmds and type(UpgradesCmds.Tier) == "function" then
                curTier = UpgradesCmds.Tier(track) or 0
            end
            if UpgradesTypes and type(UpgradesTypes.Cost) == "function" then
                cost = UpgradesTypes.Cost(track, curTier + 1) or 999999999
            elseif UpgradesCmds and type(UpgradesCmds.Cost) == "function" then
                cost = UpgradesCmds.Cost(track, curTier + 1) or 999999999
            end
        end)

        if tokens >= cost then
            local okU = pcall(function()
                plot:Invoke(K.VERBS.Upgrade, track)
            end)
            if okU then
                print(string.format("[KizHub Tycoon] ⚡ Nâng cấp thành công %s lên bậc %d (Chi phí: %d Tokens)", track, curTier + 1, cost))
                tokens = tokens - cost
                task.wait(0.2)
            end
        end
    end
end

-- =========================================================================
-- 2. AUTO MERCHANT & AUTO PLACE STOCK VÀO BỆ PEDESTAL
-- =========================================================================

local lastMerchantCheck = 0
local function runMerchantAndStock(plot, buttonsState)
    if not (Config.AutoMerchant or Config.AutoPlaceStock) then return end
    local now = os.clock()
    if now - lastMerchantCheck < (Config.MerchantInterval or 5) then return end
    lastMerchantCheck = now

    local hasMerchant = false
    if PTButtons and type(PTButtons.Owned) == "function" then
        hasMerchant = PTButtons.Owned(buttonsState, "Merchant")
    else
        hasMerchant = (buttonsState["Merchant"] == true or buttonsState["Merchant"] == 1)
    end
    if not hasMerchant then return end

    -- 1. Bật cờ Server Auto-Merchant nếu chưa bật
    pcall(function()
        local mAuto = plot:Save("MerchantAuto")
        if mAuto == false then
            plot:Invoke(K.VERBS.AutoMerchant, true)
        end
    end)

    -- 2. Mua hàng Merchant theo thứ tự Rarity Band nếu kho Stock còn slot
    if Config.AutoMerchant then
        pcall(function()
            local stockData = plot:Save("Stock")
            local stockList = (MerchantTypes and type(MerchantTypes.CleanStock) == "function" and MerchantTypes.CleanStock(stockData)) or stockData or {}
            local maxSlots = (MerchantCmds and type(MerchantCmds.Slots) == "function" and MerchantCmds.Slots()) or 8

            if #stockList < maxSlots then
                local bands = Config.MerchantBandOrder or { "ExoticPlus", "MythicalPlus", "LegendaryPlus", "EpicPlus", "RarePlus" }
                for _, band in ipairs(bands) do
                    local okB = pcall(function()
                        plot:Invoke(K.VERBS.BuyStock, band)
                    end)
                    if okB then
                        task.wait(0.1)
                        break
                    end
                end
            end
        end)
    end

    -- 3. Bật cờ Server Auto-Place Stock nếu chưa bật
    if Config.AutoPlaceStock then
        pcall(function()
            local spAuto = plot:Save("StockAutoPlace")
            if spAuto == false then
                plot:Invoke(K.VERBS.AutoPlaceStock, true)
            end
        end)

        -- 4. Phân phối hàng tồn kho vào các bệ Pedestal còn trống
        pcall(function()
            local peds = (StockCmds and type(StockCmds.Pedestals) == "function" and StockCmds.Pedestals()) or plot:Save("Pedestals") or {}
            local stock = (StockCmds and type(StockCmds.Stock) == "function" and StockCmds.Stock()) or plot:Save("Stock") or {}

            if #stock > 0 then
                for idx, ped in pairs(peds) do
                    local pIdx = tonumber(idx) or (type(ped) == "table" and ped.index)
                    local isEmpty = (type(ped) == "table" and (ped.empty == true or ped.Band == nil or ped.Band == ""))
                    local isUnlocked = (type(ped) == "table" and ped.Locked ~= true)

                    if pIdx and isEmpty and isUnlocked then
                        -- Lấy band tốt nhất trong kho
                        local bestBand = stock[1]
                        if type(bestBand) == "table" and bestBand.Band then
                            bestBand = bestBand.Band
                        end
                        if bestBand then
                            plot:Invoke(K.VERBS.PlaceStock, pIdx, bestBand)
                            task.wait(0.15)
                        end
                    end
                end
            end
        end)
    end
end

-- =========================================================================
-- 3. AUTO MUA & DUY TRÌ HOT COCOA BOOSTS
-- =========================================================================

local lastCocoaCheck = 0
local function runHotCocoa(plot, buttonsState)
    if not Config.AutoHotCocoa then return end
    local now = os.clock()
    if now - lastCocoaCheck < (Config.CocoaInterval or 15) then return end
    lastCocoaCheck = now

    local hasStand = false
    if PTButtons and type(PTButtons.Owned) == "function" then
        hasStand = PTButtons.Owned(buttonsState, "CocoaStand")
    else
        hasStand = (buttonsState["CocoaStand"] == true or buttonsState["CocoaStand"] == 1)
    end

    if hasStand and PTCocoa and type(PTCocoa.OFFERS) == "table" then
        local minSec = Config.CocoaMinRemainingSeconds or 900
        for _, offer in ipairs(PTCocoa.OFFERS) do
            local rem = 0
            if CocoaCmds and type(CocoaCmds.Remaining) == "function" then
                rem = CocoaCmds.Remaining(offer.Id) or 0
            end

            if rem < minSec then
                pcall(function()
                    plot:Invoke(K.VERBS.ExtendCocoa, offer.Key, 15)
                end)
                task.wait(0.1)
            end
        end
    end

    -- Tự động sử dụng các bình Buff / Vật phẩm Hot Cocoa trong túi đồ
    if Config.AutoConsumeBoosts then
        pcall(function()
            local s = Network.getSave()
            local inv = s and s.Inventory
            if not inv then return end

            local itemsToConsume = { "Patch Coin Boost", "Pumpkin Damage Boost", "Island Luck Boost", "Hot Cocoa" }
            for _, cat in ipairs({ "Consumable", "Misc", "Item" }) do
                if type(inv[cat]) == "table" then
                    for uid, itemData in pairs(inv[cat]) do
                        if type(itemData) == "table" and type(itemData.id) == "string" then
                            for _, matchId in ipairs(itemsToConsume) do
                                if itemData.id == matchId or itemData.id:find(matchId) then
                                    Network.netFire("Consumables_Consume", uid, 1)
                                    task.wait(0.05)
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end)
    end
end

-- =========================================================================
-- 4. AUTO CHẾ TẠO PET VÀNG & CẦU VỒNG (ROSTER RUNG PETS)
-- =========================================================================

local lastGoldRainbowCheck = 0
local function runGoldRainbowPets(buttonsState)
    if not Config.AutoGoldRainbowPets then return end
    local now = os.clock()
    if now - lastGoldRainbowCheck < (Config.GoldRainbowInterval or 20) then return end
    lastGoldRainbowCheck = now

    local hasGold = false
    local hasRainbow = false
    if PTButtons and type(PTButtons.Owned) == "function" then
        hasGold = PTButtons.Owned(buttonsState, "GoldMachine")
        hasRainbow = PTButtons.Owned(buttonsState, "RainbowMachine")
    else
        hasGold = (buttonsState["GoldMachine"] == true or buttonsState["GoldMachine"] == 1)
        hasRainbow = (buttonsState["RainbowMachine"] == true or buttonsState["RainbowMachine"] == 1)
    end

    if not hasGold and not hasRainbow then return end

    local s = Network.getSave()
    local pets = s and s.Inventory and s.Inventory.Pet
    if type(pets) ~= "table" then return end

    -- Lấy danh sách UID pet đang trang bị để không động vào
    local equipped = {}
    pcall(function()
        if Modules and Modules.G and Modules.G.PetCmds and Network.isfn(Modules.G.PetCmds, "GetEquippedItems") then
            local ok, items = Network.gcall(Modules.G.PetCmds.GetEquippedItems)
            if ok and type(items) == "table" then
                for _, it in pairs(items) do
                    if type(it) == "string" then equipped[it] = true
                    elseif type(it) == "table" and type(it.GetUID) == "function" then
                        local okU, uid = pcall(it.GetUID, it)
                        if okU and uid then equipped[uid] = true end
                    end
                end
            end
        end
        if s.EquippedPets then
            for uid, _ in pairs(s.EquippedPets) do equipped[uid] = true end
        end
    end)

    for uid, p in pairs(pets) do
        if type(p) == "table" and type(p.id) == "string" and not equipped[uid] and p._lk ~= true and p.locked ~= true then
            local idLower = p.id:lower()
            -- Tuyệt đối bỏ qua Huge, Titanic, Gargantuan
            local isSpecial = idLower:find("huge") or idLower:find("titanic") or idLower:find("gargantuan")

            if not isSpecial and K.ROSTER_RUNG[p.id] then
                local am = tonumber(p._am) or 1
                local isGold = (p.pt == 1 or p.g == true)
                local isRainbow = (p.pt == 2 or p.r == true)

                -- 1. Nâng lên Vàng (cần ít nhất 10 con thường)
                if hasGold and not isGold and not isRainbow and am >= 10 then
                    local batches = math.floor(am / 10)
                    local okM = Network.netInvoke("GoldMachine_Activate", uid, batches)
                    if okM then
                        print(string.format("[KizHub Tycoon] 🌟 Đã nâng cấp %d mẻ Vàng cho %s", batches, p.id))
                        task.wait(0.3)
                    end
                end

                -- 2. Nâng lên Cầu Vồng (cần ít nhất 10 con vàng)
                if hasRainbow and isGold and not isRainbow and am >= 10 then
                    local batches = math.floor(am / 10)
                    local okR = Network.netInvoke("RainbowMachine_Activate", uid, batches)
                    if okR then
                        print(string.format("[KizHub Tycoon] 🌈 Đã nâng cấp %d mẻ Cầu Vồng cho %s", batches, p.id))
                        task.wait(0.3)
                    end
                end
            end
        end
    end
end

-- =========================================================================
-- 5. AUTO MỞ QUÀ FLANNEL GIFT & QUÀ MIỄN PHÍ
-- =========================================================================

local lastGiftCheck = 0
local function runFlannelGifts(plot)
    if not Config.AutoOpenFlannelGifts then return end
    local now = os.clock()
    if now - lastGiftCheck < (Config.GiftOpenInterval or 10) then return end
    lastGiftCheck = now

    pcall(function()
        local s = Network.getSave()
        local lootboxes = s and s.Inventory and s.Inventory.Lootbox
        if type(lootboxes) == "table" then
            for uid, item in pairs(lootboxes) do
                if type(item) == "table" and (item.id == "Flannel Gift" or tostring(item.id):find("Flannel")) then
                    local am = math.clamp(tonumber(item._am) or 1, 1, 10)
                    -- Thử gọi verb plot trước, sau đó fallback sang remote game
                    plot:Invoke(K.VERBS.OpenGift, am)
                    Network.netInvoke("PumpkinTycoon_GiftOpen", am)
                    Network.netInvoke("Lootbox: Open", uid, am)
                    print(string.format("[KizHub Tycoon] 🎁 Đã mở %d Quà Flannel Gift!", am))
                    task.wait(0.3)
                    break
                end
            end
        end
    end)

    if Config.AutoClaimFreeGifts then
        pcall(function()
            for i = 1, 12 do
                Network.netInvoke("Redeem Free Gift", i)
            end
        end)
    end
end

-- =========================================================================
-- 6. TỔNG HỢP VÒNG LẶP MÁY & TÓM TẮT DỮ LIỆU UI
-- =========================================================================

function TycoonMachines.runAllMachinesTick(state)
    local plot = getPlot()
    if not plot then return end

    local buttonsState = plot:Save("Buttons") or {}
    runUpgrades(plot, buttonsState)
    runMerchantAndStock(plot, buttonsState)
    runHotCocoa(plot, buttonsState)
    runGoldRainbowPets(buttonsState)
    runFlannelGifts(plot)
end

function TycoonMachines.getMachineSummary()
    local plot = getPlot()
    if not plot then
        return {
            tokens = 0,
            avgUpgradeLevel = 0,
            activeCocoaMin = 0,
            stockCount = 0,
        }
    end

    local tokens = Network.currency(K.TOKENS) or 0
    local totalTiers = 0
    local count = 0

    pcall(function()
        if UpgradesCmds and type(UpgradesCmds.Tier) == "function" then
            for _, t in ipairs(K.UPGRADE_TRACKS) do
                totalTiers = totalTiers + (UpgradesCmds.Tier(t) or 0)
                count = count + 1
            end
        end
    end)

    local activeCocoa = 0
    pcall(function()
        if CocoaCmds and type(CocoaCmds.Remaining) == "function" and PTCocoa and PTCocoa.OFFERS then
            for _, o in ipairs(PTCocoa.OFFERS) do
                local rem = CocoaCmds.Remaining(o.Id) or 0
                if rem > 0 then
                    activeCocoa = math.max(activeCocoa, math.floor(rem / 60))
                end
            end
        end
    end)

    local stockCount = 0
    pcall(function()
        local s = plot:Save("Stock")
        if type(s) == "table" then stockCount = #s end
    end)

    return {
        tokens = tokens,
        avgUpgradeLevel = count > 0 and math.floor(totalTiers / count) or 0,
        totalTiers = totalTiers,
        activeCocoaMin = activeCocoa,
        stockCount = stockCount,
    }
end

return TycoonMachines
