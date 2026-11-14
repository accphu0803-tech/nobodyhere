-- =========================================================================
-- PS99_KizHub/PumpkinTycoonKaitun/EggHatch.lua
-- Module tự động mở Trứng Custom cao nhất trên đảo Pumpkin Patch Tycoon
-- Tác giả: VANTA [JHON369] | KizHub Automation Engine
-- =========================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local EggHatch = {}

-- Dependencies
local Modules = nil
local Network = nil
local Config = nil
local K = nil
local Webhook = nil
local inEventFn = nil
local instanceModelFn = nil

local EggCmds = nil
local CustomEggsCmds = nil
local PTButtons = nil

local function safeRequire(pathTbl)
    local cur = ReplicatedStorage
    for _, part in ipairs(pathTbl) do
        cur = cur and cur:FindFirstChild(part)
        if not cur then return nil end
    end
    local ok, res = pcall(require, cur)
    return ok and res or nil
end

local function initEggLibs()
    if not EggCmds then
        EggCmds = safeRequire({ "Library", "Client", "EggCmds" })
    end
    if not CustomEggsCmds then
        CustomEggsCmds = safeRequire({ "Library", "Client", "CustomEggsCmds" })
    end
    if not PTButtons then
        PTButtons = safeRequire({ "Library", "Util", "PumpkinTycoonButtons" })
    end
end

function EggHatch.init(deps)
    Modules = deps.Modules
    Network = deps.Network
    Config = deps.Config
    K = deps.K
    Webhook = deps.Webhook
    inEventFn = deps.inEvent
    instanceModelFn = deps.instanceModel
    initEggLibs()
end

-- =========================================================================
-- 1. CHẶN CUTSCENE ANIMATION MỞ TRỨNG (ZERO-LAG HATCHING)
-- =========================================================================

function EggHatch.installNoHatchAnimation()
    pcall(function()
        initEggLibs()
        if EggCmds and type(EggCmds.PlayEggAnimation) == "function" then
            EggCmds.PlayEggAnimation = function() end
        end
    end)

    pcall(function()
        if type(getsenv) ~= "function" then return end
        local ps = LocalPlayer and LocalPlayer:FindFirstChild("PlayerScripts")
        local scripts = ps and ps:FindFirstChild("Scripts")
        local gameFolder = scripts and scripts:FindFirstChild("Game")
        local eggScript = gameFolder and gameFolder:FindFirstChild("Egg Opening Frontend")
        if eggScript then
            local env = getsenv(eggScript)
            if type(env) == "table" and type(env.PlayEggAnimation) == "function" then
                env.PlayEggAnimation = function() end
            end
        end
    end)
end

-- =========================================================================
-- 2. TÌM TRỨNG CUSTOM ĐÃ MỞ KHÓA TỐT NHẤT TRÊN ĐẢO
-- =========================================================================

local function getPlot()
    local islandCmds = safeRequire({ "Library", "Client", "PumpkinTycoonCmds", "Island" })
    if islandCmds and type(islandCmds.Plot) == "function" then
        local ok, plot = pcall(islandCmds.Plot)
        if ok and plot then return plot end
    end
    return nil
end

local function getPlotModel()
    local plot = getPlot()
    if not plot then return nil end
    local ok, m = pcall(function() return plot:GetModel() end)
    if ok and m then return m end

    local plotId = tostring(plot:GetId())
    local things = workspace:FindFirstChild("__THINGS")
    local plots = things and things:FindFirstChild("Plots")
    return plots and plots:FindFirstChild(plotId)
end

function EggHatch.getBestUnlockedEgg()
    local plot = getPlot()
    local plotModel = getPlotModel()
    if not plot then return nil end

    initEggLibs()
    local buttonsState = plot:Save("Buttons") or {}

    -- Quét từ Zone 5 (Golden Grove) xuống Zone 1 (Cocoa Cabin)
    for zoneIdx = 5, 1, -1 do
        local zoneInfo = K.ZONES[zoneIdx]
        local isUnlocked = false

        if PTButtons and type(PTButtons.Owned) == "function" then
            isUnlocked = PTButtons.Owned(buttonsState, zoneInfo.EggBtn)
        else
            isUnlocked = (buttonsState[zoneInfo.EggBtn] == true or buttonsState[zoneInfo.EggBtn] == 1)
        end

        if isUnlocked then
            -- Tìm Instance CustomEgg tương ứng trên workspace hoặc qua thư viện CustomEggs
            local eggInstance = nil
            local eggUid = nil

            -- 1. Tìm trong workspace.__THINGS.CustomEggs
            local things = workspace:FindFirstChild("__THINGS")
            local customEggs = things and things:FindFirstChild("CustomEggs")
            if customEggs then
                local bestDist = 80
                local plotPos = plotModel and plotModel:GetPivot().Position
                for _, egg in ipairs(customEggs:GetChildren()) do
                    local name = egg.Name:lower()
                    local searchName = zoneInfo.Egg:lower()
                    local matchName = name:find(searchName) or searchName:find(name)
                    if matchName or egg:GetAttribute("Egg") == zoneInfo.Egg then
                        eggInstance = egg
                        eggUid = egg.Name
                        break
                    elseif plotPos and (egg:GetPivot().Position - plotPos).Magnitude < bestDist then
                        bestDist = (egg:GetPivot().Position - plotPos).Magnitude
                        eggInstance = egg
                        eggUid = egg.Name
                    end
                end
            end

            -- 2. Fallback tìm qua CustomEggsCmds
            if not eggUid and CustomEggsCmds and type(CustomEggsCmds.All) == "function" then
                local ok, all = pcall(CustomEggsCmds.All)
                if ok and type(all) == "table" then
                    for uid, data in pairs(all) do
                        if type(data) == "table" and (data.Name == zoneInfo.Egg or data._id == zoneInfo.Egg) then
                            eggUid = uid
                            break
                        end
                    end
                end
            end

            return {
                zoneIndex = zoneIdx,
                eggName = zoneInfo.Egg,
                eggBtnId = zoneInfo.EggBtn,
                displayName = zoneInfo.DisplayName,
                eggInstance = eggInstance,
                eggUid = eggUid or zoneInfo.Egg,
            }
        end
    end

    return nil
end

-- =========================================================================
-- 3. THỰC THI MỞ TRỨNG TỪ XA KHÔNG LỆCH VỊ TRÍ FARM
-- =========================================================================

local lastHatchAttempt = 0

function EggHatch.hatchBestEggTick(state)
    if not Config.AutoHatchBestEgg then return end

    local now = os.clock()
    if now - lastHatchAttempt < (Config.HatchDelay or 1.0) then return end
    lastHatchAttempt = now

    local coins = Network.currency(K.CURRENCY) or 0
    if coins <= 0 then return end

    local targetEgg = EggHatch.getBestUnlockedEgg()
    if not targetEgg or not targetEgg.eggUid then return end

    state.currentEggName = targetEgg.displayName .. " Egg"

    -- Tính toán số lượng trứng tối đa có thể mở mỗi lần
    initEggLibs()
    local maxHatch = 1
    pcall(function()
        if EggCmds and type(EggCmds.GetMaxHatch) == "function" then
            maxHatch = math.clamp(tonumber(EggCmds.GetMaxHatch()) or 1, 1, 99)
        elseif Modules and Modules.G and Modules.G.EggCmds and Network.isfn(Modules.G.EggCmds, "GetMaxHatch") then
            maxHatch = math.clamp(tonumber(Network.gval(Modules.G.EggCmds.GetMaxHatch)) or 1, 1, 99)
        end
    end)

    -- Đảm bảo cutscene bị triệt tiêu
    EggHatch.installNoHatchAnimation()

    -- Gọi Remote mở trứng Custom từ xa (CustomEggs_Hatch)
    local okH, resH = Network.netInvoke("CustomEggs_Hatch", targetEgg.eggUid, maxHatch)
    if okH and (resH == true or type(resH) == "table") then
        state.totalEggsHatched = (state.totalEggsHatched or 0) + maxHatch
    else
        -- Fallback với 1 quả nếu không đủ tiền mở full lượt
        if maxHatch > 1 then
            local ok1, res1 = Network.netInvoke("CustomEggs_Hatch", targetEgg.eggUid, 1)
            if ok1 and (res1 == true or type(res1) == "table") then
                state.totalEggsHatched = (state.totalEggsHatched or 0) + 1
            end
        end
    end
end

return EggHatch
