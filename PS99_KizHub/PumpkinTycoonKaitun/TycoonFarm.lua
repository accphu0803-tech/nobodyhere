-- =========================================================================
-- PS99_KizHub/PumpkinTycoonKaitun/TycoonFarm.lua
-- Module điều khiển Farm bãi, di chuyển né nước, phá Bí Ngô Khổng Lồ và mua nút
-- Tác giả: VANTA [JHON369] | KizHub Automation Engine
-- =========================================================================

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local TycoonFarm = {}

-- Dependencies
local Modules = nil
local Network = nil
local Config = nil
local K = nil
local Webhook = nil
local inEventFn = nil
local instanceModelFn = nil

-- Cache Client Modules của Tycoon
local IslandCmds = nil
local PTButtons = nil
local ButtonsCmds = nil
local BreakableFrontend = nil
local AutoFarmCmds = nil
local PlayerPet = nil

local function safeRequire(pathTbl)
    local cur = ReplicatedStorage
    for _, part in ipairs(pathTbl) do
        cur = cur and cur:FindFirstChild(part)
        if not cur then return nil end
    end
    local ok, res = pcall(require, cur)
    return ok and res or nil
end

local function initGameLibs()
    if not IslandCmds then
        IslandCmds = safeRequire({ "Library", "Client", "PumpkinTycoonCmds", "Island" })
    end
    if not PTButtons then
        PTButtons = safeRequire({ "Library", "Util", "PumpkinTycoonButtons" })
    end
    if not ButtonsCmds then
        ButtonsCmds = safeRequire({ "Library", "Client", "PumpkinTycoonCmds", "Buttons" })
    end
    if not BreakableFrontend then
        BreakableFrontend = safeRequire({ "Library", "Client", "BreakableFrontend" })
    end
    if not AutoFarmCmds then
        AutoFarmCmds = safeRequire({ "Library", "Client", "AutoFarmCmds" })
    end
    if not PlayerPet then
        PlayerPet = safeRequire({ "Library", "Client", "PlayerPet" })
    end
end

function TycoonFarm.init(deps)
    Modules = deps.Modules
    Network = deps.Network
    Config = deps.Config
    K = deps.K
    Webhook = deps.Webhook
    inEventFn = deps.inEvent
    instanceModelFn = deps.instanceModel
    initGameLibs()
end

-- =========================================================================
-- 1. TRUY VẤN PLOT VÀ MÔ HÌNH ĐẢO CỦA NGƯỜI CHƠI
-- =========================================================================

function TycoonFarm.getPlot()
    initGameLibs()
    if IslandCmds and type(IslandCmds.Plot) == "function" then
        local ok, plot = pcall(IslandCmds.Plot)
        if ok and plot then return plot end
    end
    -- Fallback: tìm trong workspace.__THINGS.Plots theo UserId hoặc Player
    local things = workspace:FindFirstChild("__THINGS")
    local plots = things and things:FindFirstChild("Plots")
    if plots and LocalPlayer then
        for _, p in ipairs(plots:GetChildren()) do
            local owner = p:GetAttribute("Owner") or p:GetAttribute("UserId") or p:GetAttribute("Player")
            if owner == LocalPlayer.UserId or owner == LocalPlayer.Name or tostring(owner) == tostring(LocalPlayer.UserId) then
                return p
            end
        end
    end
    return nil
end

function TycoonFarm.getPlotModel()
    local plot = TycoonFarm.getPlot()
    if not plot then return nil end
    if typeof(plot) == "Instance" and plot:IsA("Model") then
        return plot
    end
    local ok, model = pcall(function() return plot:GetModel() end)
    if ok and model then return model end

    if type(plot.GetId) == "function" then
        local plotId = tostring(plot:GetId())
        local things = workspace:FindFirstChild("__THINGS")
        local plots = things and things:FindFirstChild("Plots")
        if plots and plots:FindFirstChild(plotId) then
            return plots:FindFirstChild(plotId)
        end
    end
    return nil
end

-- =========================================================================
-- 2. HỆ THỐNG DI CHUYỂN NÉ NƯỚC & NHẢY CHƯỚNG NGẠI VẬT (RAGE & LEGIT)
-- =========================================================================

local function getCharacterParts()
    local char = LocalPlayer.Character
    if not char then return nil, nil, nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    return char, hrp, hum
end

function TycoonFarm.moveTo(targetPosOrCF)
    if not targetPosOrCF then return end
    local targetPos = typeof(targetPosOrCF) == "CFrame" and targetPosOrCF.Position or targetPosOrCF

    local char, hrp, hum = getCharacterParts()
    if not hrp or not hum then return end

    if hum.Sit then hum.Sit = false end
    if hum.PlatformStand then hum.PlatformStand = false end

    local cf = typeof(targetPosOrCF) == "CFrame" and targetPosOrCF or CFrame.new(targetPos + Vector3.new(0, 2.5, 0))

    -- Teleport tức thì, chống rơi rụng hoặc lag vật lý
    pcall(function()
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        char:PivotTo(cf)
        hrp.CFrame = cf
    end)
    pcall(function()
        Network.teleportTo(targetPos)
    end)
end

-- =========================================================================
-- 3. QUẢN LÝ QUY TẮC AUTOBREAK, PEDESTAL VÀ AUTO FARM SỰ KIỆN
-- =========================================================================

function TycoonFarm.getPlotPivot()
    local plotModel = TycoonFarm.getPlotModel()
    if plotModel and typeof(plotModel) == "Instance" then
        local okP, pcf = pcall(function() return plotModel:GetPivot() end)
        if okP and typeof(pcf) == "CFrame" then
            return pcf
        end
        if plotModel.PrimaryPart then
            return plotModel.PrimaryPart.CFrame
        end
    end
    local plot = TycoonFarm.getPlot()
    if plot and type(plot.GetCFrame) == "function" then
        local ok, cf = pcall(plot.GetCFrame, plot)
        if ok and typeof(cf) == "CFrame" then
            return cf
        end
    end
    return nil
end

function TycoonFarm.getPlotCFrame()
    return TycoonFarm.getPlotPivot()
end

local FARM_AREAS = {
    [5] = {
        name = "Area 5 (Golden Grove)",
        displayName = "Golden Grove",
        pathBtn = "Path_5",
        zoneBtn = "GoldenGrove_Zone",
        eggAttr = "GoldenGrove_Egg",
        eggBtn = "GoldenGrove_Egg",
        pedIndex = 5,
    },
    [4] = {
        name = "Area 4 (Cider Mill)",
        displayName = "Cider Mill",
        offset = Vector3.new(-70.41, 5.72, -300.74),
        pathBtn = "Path_4",
        zoneBtn = "CiderMill_Zone",
        eggAttr = "CiderMill_Egg",
        eggBtn = "CiderMill_Egg",
        pedIndex = 4,
    },
    [3] = {
        name = "Area 3 (Hayride Hill)",
        displayName = "Hayride Hill",
        offset = Vector3.new(-198.58, 0.08, -50.60),
        pathBtn = "Path_3",
        zoneBtn = "HayrideHill_Zone",
        eggAttr = "HayrideHill_Egg",
        eggBtn = "HayrideHill_Egg",
        pedIndex = 3,
    },
    [2] = {
        name = "Area 2 (Apple Orchard)",
        displayName = "Apple Orchard",
        offset = Vector3.new(-138.68, 4.63, 161.97),
        pathBtn = "Path_2",
        zoneBtn = "AppleOrchard_Zone",
        eggAttr = "AppleOrchard_Egg",
        eggBtn = "AppleOrchard_Egg",
        pedIndex = 2,
    },
    [1] = {
        name = "Area 1 (Cocoa Cabin)",
        displayName = "Cocoa Cabin",
        offset = Vector3.new(183.04, 3.86, 125.91),
        pathBtn = nil,
        zoneBtn = "CocoaCabin_Zone",
        eggAttr = "CocoaCabin_Egg",
        eggBtn = "CocoaCabin_Egg",
        pedIndex = 1,
    },
}

function TycoonFarm.getActiveAreaIndex()
    if Config and Config.ForceZone then
        return tonumber(Config.ForceZone) or 1
    end

    local plot = TycoonFarm.getPlot()
    if not plot then return 1 end

    initGameLibs()

    -- 1. Lấy trạng thái buttons từ IslandCmds.Get(nil, "Buttons") trước, fallback plot:Save("Buttons")
    local buttonsState = {}
    pcall(function()
        if IslandCmds and type(IslandCmds.Get) == "function" then
            buttonsState = IslandCmds.Get(nil, "Buttons") or {}
        end
    end)
    if not buttonsState or not next(buttonsState) then
        pcall(function()
            if plot and type(plot.Save) == "function" then
                buttonsState = plot:Save("Buttons") or {}
            end
        end)
    end
    if not buttonsState or not next(buttonsState) then
        pcall(function()
            local s = Network.getSave and Network.getSave()
            if s and s.PumpkinTycoon and type(s.PumpkinTycoon.Buttons) == "table" then
                buttonsState = s.PumpkinTycoon.Buttons
            end
        end)
    end

    local plotPivot = TycoonFarm.getPlotPivot()
    local plotModel = TycoonFarm.getPlotModel()
    local things = workspace:FindFirstChild("__THINGS")
    local customEggs = things and things:FindFirstChild("CustomEggs")
    local sectionsFolder = plotModel and plotModel:FindFirstChild("Sections")

    local function isButtonOwned(btnId)
        if not btnId then return false end
        if buttonsState[btnId] == true then return true end
        if PTButtons and type(PTButtons.Owned) == "function" and PTButtons.Owned(buttonsState, btnId) then
            return true
        end
        return false
    end

    -- Quét từ bãi cao nhất (Bãi 5) xuống bãi thấp nhất (Bãi 1)
    for zoneIdx = 5, 1, -1 do
        local area = FARM_AREAS[zoneIdx]

        -- A. Kiểm tra đã sở hữu nút mở Egg hoặc nút Zone hoặc nút Path dẫn đến bãi đó
        if isButtonOwned(area.eggBtn) or isButtonOwned(area.zoneBtn) or isButtonOwned(area.pathBtn) then
            return zoneIdx
        end

        -- B. Kiểm tra thư mục Plot.Sections (khi mua zone, khu vực sẽ xuất hiện trong Sections)
        if sectionsFolder then
            for _, sec in ipairs(sectionsFolder:GetChildren()) do
                local zn = sec:GetAttribute("ZoneNumber") or tonumber(sec.Name:match("^(%d+)"))
                local ts = sec:GetAttribute("TycoonSection") or ""
                if zn == zoneIdx or sec.Name:find(area.displayName) or (area.displayName and ts:lower():find(area.displayName:gsub("%s+", ""):lower())) then
                    return zoneIdx
                end
            end
        end

        -- C. Kiểm tra nếu có CustomEgg của bãi đó đã xuất hiện trên map
        local eggPos = nil
        if plotModel then
            local eggAttr = plotModel:GetAttribute(area.eggAttr)
            if typeof(eggAttr) == "CFrame" then
                eggPos = eggAttr.Position
            elseif typeof(eggAttr) == "Vector3" then
                eggPos = eggAttr
            end
        end
        if not eggPos and area.offset and plotPivot then
            eggPos = plotPivot:PointToWorldSpace(area.offset)
        end

        if eggPos and customEggs then
            for _, egg in ipairs(customEggs:GetChildren()) do
                if (egg:GetPivot().Position - eggPos).Magnitude < 65 then
                    return zoneIdx
                end
            end
        end
    end

    -- D. Fallback nếu nhân vật đang đứng gần vị trí của bãi nào (trong phạm vi 100 studs)
    local char, hrp = getCharacterParts()
    if hrp and plotPivot then
        for zoneIdx = 5, 2, -1 do
            local area = FARM_AREAS[zoneIdx]
            local targetPos = nil
            if area.offset then
                targetPos = plotPivot:PointToWorldSpace(area.offset)
            end
            if targetPos and (hrp.Position - targetPos).Magnitude <= 100 then
                return zoneIdx
            end
        end
    end

    return 1
end

function TycoonFarm.getSweetPos()
    local areaIdx = TycoonFarm.getActiveAreaIndex()
    local areaData = FARM_AREAS[areaIdx] or FARM_AREAS[1]

    local plotPivot = TycoonFarm.getPlotPivot()
    local plotModel = TycoonFarm.getPlotModel()

    -- 1. Chuẩn toán học đảo: Biến đổi Relative Offset qua ma trận xoay của Plot (giống chuẩn Bãi 1 & 2)
    local basePos = nil
    if areaData.offset and plotPivot then
        basePos = plotPivot:PointToWorldSpace(areaData.offset)
    elseif plotModel and areaData.eggAttr then
        local eggAttr = plotModel:GetAttribute(areaData.eggAttr)
        if typeof(eggAttr) == "CFrame" then
            basePos = eggAttr.Position + Vector3.new(0, 2.5, 8)
        elseif typeof(eggAttr) == "Vector3" then
            basePos = eggAttr + Vector3.new(0, 2.5, 8)
        end
    end

    if not basePos then return nil end

    -- 2. AUTO-SNAP: Kiểm tra mật độ quặng xung quanh basePos
    -- Nếu basePos rơi vào bãi đất trống (không có quặng nào trong vòng 35 studs),
    -- tự động tìm tâm của cụm quặng gần nhất của bãi hiện tại (trong cự ly 120 studs) để kéo nhân vật vào tâm farm!
    pcall(function()
        if BreakableFrontend and type(BreakableFrontend.AllByInstanceAndClass) == "function" then
            local ok, normals = pcall(BreakableFrontend.AllByInstanceAndClass, "Normal")
            if ok and type(normals) == "table" then
                local nearbyCount = 0
                local clusterSum = Vector3.zero
                local clusterCount = 0
                for k, v in pairs(normals) do
                    local brk = getBrkData(k, v)
                    local isTycoon = (brk.parentID == "PumpkinTycoon") or (brk.model and brk.model:GetAttribute("ParentID") == "PumpkinTycoon")
                    if isTycoon and brk.position then
                        local d = (brk.position - basePos).Magnitude
                        if d <= 35 then
                            nearbyCount = nearbyCount + 1
                        end
                        if d <= 120 then
                            clusterSum = clusterSum + brk.position
                            clusterCount = clusterCount + 1
                        end
                    end
                end
                -- Nếu vị trí đứng không có quặng nào nhưng gần đó có cụm quặng (>= 3 quặng)
                if nearbyCount == 0 and clusterCount >= 3 then
                    local avgCenter = clusterSum / clusterCount
                    basePos = Vector3.new(avgCenter.X, basePos.Y, avgCenter.Z)
                end
            end
        end
    end)

    return basePos
end

function TycoonFarm.ensureAutoFarmEnabled(state, sweetPos)
    pcall(function()
        if not AutoFarmCmds then
            AutoFarmCmds = safeRequire({ "Library", "Client", "AutoFarmCmds" })
        end
        if AutoFarmCmds and type(AutoFarmCmds.IsEnabled) == "function" then
            if not AutoFarmCmds.IsEnabled() then
                if type(AutoFarmCmds.Enable) == "function" then
                    AutoFarmCmds.Enable()
                end
                Network.netInvoke("AutoFarm_Enable", true)
                if sweetPos then
                    Network.netFire("AutoFarm_LogPosition", sweetPos)
                end
            end
            if state then
                state.autoFarmActive = AutoFarmCmds.IsEnabled()
            end
        end
    end)
end

function TycoonFarm.ensureAutoBreakZero()
    local plot = TycoonFarm.getPlot()
    if not plot then return end

    local sweetPos = TycoonFarm.getSweetPos()
    TycoonFarm.ensureAutoFarmEnabled(nil, sweetPos)

    pcall(function()
        local autoBreak = plot:Save("AutoBreak")
        if type(autoBreak) == "table" and autoBreak.Below ~= 0 then
            plot:Invoke(K.VERBS.AutoBreakPolicy, 0)
        end
    end)

    pcall(function()
        local pedestals = plot:Save("Pedestals")
        if type(pedestals) == "table" then
            for idx, ped in pairs(pedestals) do
                if type(ped) == "table" and ped.Locked == true then
                    plot:Invoke(K.VERBS.PedestalShelter, tonumber(idx) or idx, false)
                end
            end
        end
    end)
end

-- =========================================================================
-- 4. TRUY TÌM VÀ PHÁ BÍ NGÔ KHỔNG LỒ (BIG PUMPKIN) ƯU TIÊN CAO NHẤT
-- =========================================================================

local function getBrkData(k, v)
    local brkObj = (type(v) == "table" and v) or (type(k) == "table" and k) or {}
    local uid = brkObj.uid or (type(k) == "string" and k) or (type(v) == "string" and v) or (brkObj.model and brkObj.model.Name)
    local model = brkObj.model or (typeof(v) == "Instance" and v) or (typeof(k) == "Instance" and k)
    local parentID = brkObj.parentID or (model and model:GetAttribute("ParentID"))
    local pos = brkObj.position or (model and model:GetPivot().Position) or (brkObj.GetPosition and brkObj:GetPosition())
    local clientAttrs = brkObj.clientAttributes or (model and model:GetAttributes()) or {}
    return {
        uid = uid,
        model = model,
        parentID = parentID,
        position = pos,
        clientAttributes = clientAttrs,
    }
end

local function getPlayerPets()
    local pets = {}
    pcall(function()
        local pp = (Modules and Modules.G and Modules.G.PlayerPet) or PlayerPet or safeRequire({ "Library", "Client", "PlayerPet" })
        if pp and type(pp.GetByPlayer) == "function" then
            local pList = pp.GetByPlayer(LocalPlayer)
            if type(pList) == "table" then
                for _, p in pairs(pList) do
                    table.insert(pets, p)
                end
            end
        end
    end)
    return pets
end

function TycoonFarm.findActiveBigPumpkin()
    local plot = TycoonFarm.getPlot()
    if not plot then return nil end

    initGameLibs()
    local plotId = plot:GetId()
    local sweetPos = TycoonFarm.getSweetPos()
    if not sweetPos then return nil end

    local activeArea = TycoonFarm.getActiveAreaIndex()
    local bestPumpkin = nil
    local maxRung = -1

    local function checkChest(brk)
        if not brk or not brk.position then return end
        local isTycoon = (brk.parentID == "PumpkinTycoon") or (brk.model and brk.model:GetAttribute("ParentID") == "PumpkinTycoon")
        if not isTycoon then return end

        local distSweet = (brk.position - sweetPos).Magnitude

        -- CHỈ ĐÁNH BÍ NGÔ NẰM TRONG BÃI HIỆN TẠI (distSweet <= 110 studs)
        -- Tuyệt đối không nhắm vào Pedestal 1 (Cocoa Cabin Bậc 1) ở đầu đảo khi đang farm Bãi 2, 3, 4, 5
        if distSweet <= 110 then
            local rung = tonumber(brk.clientAttributes.Rung) or (brk.model and tonumber(brk.model:GetAttribute("Rung"))) or 1
            local petName = brk.clientAttributes.PetName or (brk.model and brk.model:GetAttribute("PetName")) or (brk.model and brk.model.Name)
            if K and K.ROSTER_RUNG and petName and K.ROSTER_RUNG[petName] then
                rung = math.max(rung, K.ROSTER_RUNG[petName])
            end
            local pedIndex = brk.clientAttributes.PumpkinPedestal or brk.clientAttributes.Pedestal or activeArea

            if rung > maxRung then
                maxRung = rung
                bestPumpkin = {
                    uid = brk.uid,
                    model = brk.model,
                    pos = brk.position,
                    pedestalIndex = pedIndex,
                    rung = rung,
                }
            end
        end
    end

    if BreakableFrontend and type(BreakableFrontend.AllByInstanceAndClass) == "function" then
        local ok, chests = pcall(BreakableFrontend.AllByInstanceAndClass, "Chest")
        if ok and type(chests) == "table" then
            for k, v in pairs(chests) do
                checkChest(getBrkData(k, v))
            end
        end
    end

    if not bestPumpkin then
        local things = workspace:FindFirstChild("__THINGS")
        local breakables = things and things:FindFirstChild("Breakables")
        if breakables then
            for _, child in ipairs(breakables:GetChildren()) do
                if child:IsA("Model") and (child:GetAttribute("Chest") or child.Name:find("Chest") or child:GetAttribute("PumpkinPedestal")) then
                    checkChest(getBrkData(child.Name, child))
                end
            end
        end
    end

    return bestPumpkin
end

function TycoonFarm.petEuids()
    local equipped = {}
    pcall(function()
        if Modules and Modules.G and Modules.G.PetCmds and Network.isfn(Modules.G.PetCmds, "GetEquippedItems") then
            local ok, items = Network.gcall(Modules.G.PetCmds.GetEquippedItems)
            if ok and type(items) == "table" then
                for _, it in pairs(items) do
                    if type(it) == "string" then
                        table.insert(equipped, it)
                    elseif type(it) == "table" and type(it.GetUID) == "function" then
                        local okU, uid = pcall(it.GetUID, it)
                        if okU and uid then table.insert(equipped, uid) end
                    elseif type(it) == "table" and it._uid then
                        table.insert(equipped, it._uid)
                    end
                end
            end
        end
        if #equipped == 0 then
            local s = Network.getSave()
            if s and type(s.EquippedPets) == "table" then
                for uid, _ in pairs(s.EquippedPets) do
                    table.insert(equipped, uid)
                end
            end
        end
    end)
    return equipped
end

function TycoonFarm.breakBigPumpkinTick(state)
    if state and state.excursion and state.excursion:find("Bí Ngô") then
        state.excursion = nil
    end
    -- Cơ chế game tự động cho pet đánh bí khổng lồ, script không can thiệp để tránh làm lệch vị trí farm
    return false
end

-- =========================================================================
-- 5. FARM BÃI PATCH ĐẢO ĐƠN NHẤT (SINGLE ISLAND SWEET SPOT)
-- =========================================================================

function TycoonFarm.farmBestPatchTick(state)
    if state and state.excursion and state.excursion:find("Bí Ngô") then
        state.excursion = nil
    end

    local plot = TycoonFarm.getPlot()
    if not plot then return end

    initGameLibs()
    local sweetPos = TycoonFarm.getSweetPos()
    if not sweetPos then return end

    -- Kích hoạt Auto Farm miễn phí của event
    TycoonFarm.ensureAutoFarmEnabled(state, sweetPos)

    -- Luôn đảm bảo nhân vật đứng tại sweetPos của bãi farm hiện tại (nếu lệch quá 8 studs -> Teleport ngay)
    local char, hrp = getCharacterParts()
    if hrp and (hrp.Position - sweetPos).Magnitude > 8 then
        TycoonFarm.moveTo(sweetPos)
    end

    -- Quét quặng Normal trên đảo từ BreakableFrontend (brk.parentID == "PumpkinTycoon" và cự ly <= 65)
    local targets = {}
    if BreakableFrontend and type(BreakableFrontend.AllByInstanceAndClass) == "function" then
        local ok, normals = pcall(BreakableFrontend.AllByInstanceAndClass, "Normal")
        if ok and type(normals) == "table" then
            for k, v in pairs(normals) do
                local brk = getBrkData(k, v)
                local isTycoon = (brk.parentID == "PumpkinTycoon") or (brk.model and brk.model:GetAttribute("ParentID") == "PumpkinTycoon")
                if isTycoon and brk.position and (brk.position - sweetPos).Magnitude <= 65 then
                    table.insert(targets, brk)
                end
            end
        end
    end

    -- Fallback quét thư mục __THINGS.Breakables
    if #targets == 0 then
        local things = workspace:FindFirstChild("__THINGS")
        local breakables = things and things:FindFirstChild("Breakables")
        if breakables then
            for _, b in ipairs(breakables:GetChildren()) do
                if b:IsA("Model") then
                    local bPos = b:GetPivot().Position
                    if (bPos - sweetPos).Magnitude <= 65 then
                        table.insert(targets, {
                            uid = b.Name,
                            model = b,
                            position = bPos,
                        })
                    end
                end
            end
        end
    end

    -- Điều phối pet: pet:SetTarget(brk.model), Breakables_JoinPetBulk, Breakables_PlayerDealDamage
    if #targets > 0 then
        local playerPets = getPlayerPets()
        local petUids = TycoonFarm.petEuids()

        if #playerPets > 0 then
            for idx, pet in ipairs(playerPets) do
                local t = targets[((idx - 1) % #targets) + 1]
                if pet.SetAnchored then pet:SetAnchored(false) end
                if pet.SetTarget and t.model then pet:SetTarget(t.model) end
            end
        end

        if #petUids > 0 then
            local joinMap = {}
            for idx, pUid in ipairs(petUids) do
                local t = targets[((idx - 1) % #targets) + 1]
                joinMap[pUid] = tostring(t.uid)
            end
            pcall(function()
                Network.netFire("Breakables_JoinPetBulk", joinMap)
            end)
        end

        local primary = targets[1]
        if primary and primary.uid then
            pcall(function()
                Network.netFire("Breakables_PlayerDealDamage", tonumber(primary.uid) or primary.uid)
            end)
        end
    end

    TycoonFarm.collectOrbsTick()
end

-- =========================================================================
-- 6. TỰ ĐỘNG MUA NÚT TYCOON (CÂN ĐỐI NGÂN SÁCH THÔNG MINH) & NHẬN THƯỞNG ĐẢO
-- =========================================================================

-- Xác định nút mục tiêu tiếp theo để phân bổ ngân sách với việc mở trứng
function TycoonFarm.getNextTargetButton(priceMult)
    local plot = TycoonFarm.getPlot()
    if not plot then return nil end

    initGameLibs()
    local buttonsState = plot:Save("Buttons") or {}
    if not (PTButtons and type(PTButtons.Available) == "function" and type(PTButtons.Price) == "function") then
        return nil
    end

    priceMult = priceMult or (ButtonsCmds and type(ButtonsCmds.PriceMult) == "function" and ButtonsCmds.PriceMult()) or 1
    local avail = PTButtons.Available(buttonsState, 5, false, priceMult)
    if not (type(avail) == "table" and #avail > 0) then
        return nil
    end

    -- 1. ƯU TIÊN CAO NHẤT: Nút mở Trứng (Egg) hoặc Nút mở Khu vực (Zone)
    for _, btn in ipairs(avail) do
        local id = tostring(btn.Id or "")
        if id:find("Egg") or id:find("Zone") or btn.Egg then
            local price = PTButtons.Price(btn, priceMult)
            return btn, price, true -- isMilestone = true
        end
    end

    -- 2. Nếu không có nút Egg/Zone: Chọn nút rẻ nhất hiện có để đẩy nhanh tiến độ
    local cheapestBtn = avail[1]
    local minPrice = PTButtons.Price(cheapestBtn, priceMult)
    for i = 2, #avail do
        local p = PTButtons.Price(avail[i], priceMult)
        if p < minPrice then
            cheapestBtn = avail[i]
            minPrice = p
        end
    end

    return cheapestBtn, minPrice, false
end

-- Quét tìm nút có giá rẻ nhất trong toàn bộ danh sách các nút hiện có thể mua
function TycoonFarm.getCheapestAvailableButton(priceMult)
    local plot = TycoonFarm.getPlot()
    if not plot then return nil end

    initGameLibs()
    local buttonsState = plot:Save("Buttons") or {}
    if not (PTButtons and type(PTButtons.Available) == "function" and type(PTButtons.Price) == "function") then
        return nil
    end

    priceMult = priceMult or (ButtonsCmds and type(ButtonsCmds.PriceMult) == "function" and ButtonsCmds.PriceMult()) or 1
    local avail = PTButtons.Available(buttonsState, 15, false, priceMult)
    if not (type(avail) == "table" and #avail > 0) then
        return nil
    end

    local cheapestBtn = avail[1]
    local minPrice = PTButtons.Price(cheapestBtn, priceMult) or math.huge
    for i = 2, #avail do
        local p = PTButtons.Price(avail[i], priceMult) or math.huge
        if p < minPrice then
            cheapestBtn = avail[i]
            minPrice = p
        end
    end

    return cheapestBtn, minPrice
end

function TycoonFarm.checkAndBuyButtons(state)
    if not Config.AutoBuyButtons then return end
    local plot = TycoonFarm.getPlot()
    local plotModel = TycoonFarm.getPlotModel()
    if not plot or not plotModel then return end

    initGameLibs()
    local buttonsState = plot:Save("Buttons") or {}
    local priceMult = (ButtonsCmds and type(ButtonsCmds.PriceMult) == "function" and ButtonsCmds.PriceMult()) or 1

    -- 1. Kiểm tra nhận thưởng hoàn thành đảo (Island Completion Reward)
    if Config.AutoClaimIslandReward and PTButtons and type(PTButtons.Progress) == "function" and type(PTButtons.Completed) == "function" then
        local _, _, frac = PTButtons.Progress(buttonsState, 1)
        if frac >= 1 and not PTButtons.Completed(buttonsState) then
            pcall(function()
                plot:Invoke(K.VERBS.ClaimReward)
                print("[KizHub Tycoon] 🎉 ĐÃ NHẬN THƯỞNG HOÀN THÀNH ĐẢO PUMPKIN TYCOON!")
            end)
        end
    end

    local coins = Network.currency(K.CURRENCY) or 0

    -- 2. ƯU TIÊN MUA NÚT MỐC QUAN TRỌNG (Egg / Zone button) NGAY KHI ĐỦ COIN
    local targetBtn, targetPrice, isMilestone = TycoonFarm.getNextTargetButton(priceMult)
    if targetBtn and isMilestone and coins >= targetPrice then
        local okB, resB = pcall(function()
            return plot:Invoke(K.VERBS.BuyButton, targetBtn.Id)
        end)
        if okB and resB == true then
            print(string.format("[KizHub Tycoon] 👑 ĐÃ MUA THÀNH CÔNG NÚT MỐC: %s (Giá: %s Coins)", tostring(targetBtn.Id), Network.shorten(targetPrice)))
            if Modules and Modules.EggHatch and type(Modules.EggHatch.onButtonBought) == "function" then
                Modules.EggHatch.onButtonBought(targetBtn.Id)
            end
            task.wait(0.3)
            return
        else
            -- Thử kích hoạt nút qua pad trong workspace.PumpkinTycoonPads
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local padFolder = workspace:FindFirstChild("PumpkinTycoonPads")
            local pad = padFolder and padFolder:FindFirstChild(targetBtn.Id)
            local touchPart = pad and (pad:FindFirstChild("Touch", true) or pad:FindFirstChild("Press", true) or pad:FindFirstChild("Base", true))
            
            if touchPart and typeof(firetouchinterest) == "function" and hrp then
                firetouchinterest(hrp, touchPart, 0)
                task.wait(0.05)
                firetouchinterest(hrp, touchPart, 1)
            end

            -- Dự phòng: Di chuyển tạm thời đến vị trí bệ nút để kích hoạt
            local padSpot = nil
            if PTButtons and type(PTButtons.PadSpot) == "function" then
                pcall(function() padSpot = PTButtons.PadSpot(plotModel, targetBtn) end)
            end
            if not padSpot and pad then
                padSpot = pad:GetPivot()
            end
            if padSpot and hrp then
                local padPos = (typeof(padSpot) == "CFrame" and padSpot.Position) or padSpot
                pcall(function()
                    hrp.AssemblyLinearVelocity = Vector3.zero
                    hrp.AssemblyAngularVelocity = Vector3.zero
                    char:PivotTo(CFrame.new(padPos + Vector3.new(0, 3, 0)))
                end)
                task.wait(0.2)
                pcall(function()
                    local buyOk, buyRes = plot:Invoke(K.VERBS.BuyButton, targetBtn.Id)
                    if buyOk and buyRes == true then
                        print(string.format("[KizHub Tycoon] 👑 ĐÃ MUA THÀNH CÔNG NÚT MỐC QUA BỆ PAD: %s", tostring(targetBtn.Id)))
                        if Modules and Modules.EggHatch and type(Modules.EggHatch.onButtonBought) == "function" then
                            Modules.EggHatch.onButtonBought(targetBtn.Id)
                        end
                    end
                end)
                task.wait(0.2)
                return
            end
        end
    end

    -- 3. Mua các nút có sẵn theo thứ tự Rẻ nhất trước (Cheapest First)
    if PTButtons and type(PTButtons.Available) == "function" and type(PTButtons.Price) == "function" then
        local avail = PTButtons.Available(buttonsState, 5, false, priceMult)
        if type(avail) == "table" and #avail > 0 then
            for _, btn in ipairs(avail) do
                local price = PTButtons.Price(btn, priceMult)
                if coins >= price then
                    local okB, resB = pcall(function()
                        return plot:Invoke(K.VERBS.BuyButton, btn.Id)
                    end)
                    if okB and resB == true then
                        print(string.format("[KizHub Tycoon] ✔ Đã mua nút: %s (Giá: %s Coins)", tostring(btn.Id), Network.shorten(price)))
                        if Modules and Modules.EggHatch and type(Modules.EggHatch.onButtonBought) == "function" then
                            Modules.EggHatch.onButtonBought(btn.Id)
                        end
                        task.wait(0.2)
                        break
                    else
                        local padFolder = workspace:FindFirstChild("PumpkinTycoonPads")
                        local pad = padFolder and padFolder:FindFirstChild(btn.Id)
                        local touchPart = pad and (pad:FindFirstChild("Touch", true) or pad:FindFirstChild("Press", true))
                        local char = LocalPlayer.Character
                        local hrp = char and char:FindFirstChild("HumanoidRootPart")
                        if touchPart and typeof(firetouchinterest) == "function" and hrp then
                            firetouchinterest(hrp, touchPart, 0)
                            task.wait(0.05)
                            firetouchinterest(hrp, touchPart, 1)
                        end
                    end
                end
            end
        end
    end
end

-- =========================================================================
-- 7. AUTO-TAP VÀ HÚT ORBS / LOOTBAGS
-- =========================================================================

local lastTapTime = 0
function TycoonFarm.runAutoTapTick()
    if not (Config.AutoTap and Config.AutoTap.Enabled) then return end
    local now = os.clock()
    if now - lastTapTime < (Config.AutoTap.TapDelay or 0.2) then return end
    lastTapTime = now

    local char, hrp = getCharacterParts()
    if not hrp then return end

    local things = workspace:FindFirstChild("__THINGS")
    local breakables = things and things:FindFirstChild("Breakables")
    if breakables then
        for _, b in ipairs(breakables:GetChildren()) do
            if b:IsA("Model") and (b:GetPivot().Position - hrp.Position).Magnitude < 35 then
                Network.netFire("Breakables_PlayerDealDamage", b.Name)
                break
            end
        end
    end
end

function TycoonFarm.collectOrbsTick()
    pcall(function()
        local things = workspace:FindFirstChild("__THINGS")
        local orbs = things and things:FindFirstChild("Orbs")
        if orbs and #orbs:GetChildren() > 0 then
            local ids = {}
            for _, orb in ipairs(orbs:GetChildren()) do
                table.insert(ids, tonumber(orb.Name) or orb.Name)
                if #ids >= 40 then break end
            end
            if #ids > 0 then
                Network.netFire("Orbs: Collect", ids)
            end
        end
        local lootbags = things and things:FindFirstChild("Lootbags")
        if lootbags and #lootbags:GetChildren() > 0 then
            local uids = {}
            for _, lb in ipairs(lootbags:GetChildren()) do
                table.insert(uids, lb.Name)
                if #uids >= 25 then break end
            end
            if #uids > 0 then
                Network.netFire("Lootbags_Claim", uids)
            end
        end
    end)
end

-- =========================================================================
-- 8. THỐNG KÊ TIẾN ĐỘ TYCOON CHO DASHBOARD GUI
-- =========================================================================

function TycoonFarm.getTycoonProgress()
    local plot = TycoonFarm.getPlot()
    if not plot then
        return {
            ownedButtons = 0,
            totalButtons = 0,
            percent = 0,
            activeBigPumpkins = 0,
            activeBigPumpkinRung = 0,
            unlockedPedestals = 0,
            completed = false,
        }
    end

    initGameLibs()
    local buttonsState = plot:Save("Buttons") or {}
    local ownedCount, totalCount, frac = 0, 0, 0
    local isCompleted = false

    if PTButtons and type(PTButtons.Progress) == "function" then
        ownedCount, totalCount, frac = PTButtons.Progress(buttonsState, 1)
        isCompleted = PTButtons.Completed(buttonsState)
    end

    local unlockedPedestals = 0
    pcall(function()
        local peds = plot:Save("Pedestals")
        if type(peds) == "table" then
            for _, p in pairs(peds) do
                if type(p) == "table" and p.Locked ~= true then
                    unlockedPedestals = unlockedPedestals + 1
                end
            end
        end
    end)

    local bigPumpkin = TycoonFarm.findActiveBigPumpkin()

    return {
        ownedButtons = ownedCount or 0,
        totalButtons = totalCount or 1,
        percent = frac or 0,
        activeBigPumpkins = bigPumpkin and 1 or 0,
        activeBigPumpkinRung = bigPumpkin and bigPumpkin.rung or 0,
        unlockedPedestals = unlockedPedestals,
        completed = isCompleted,
    }
end

return TycoonFarm
