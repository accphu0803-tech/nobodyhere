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
    return nil
end

function TycoonFarm.getPlotModel()
    local plot = TycoonFarm.getPlot()
    if not plot then return nil end
    local ok, model = pcall(function() return plot:GetModel() end)
    if ok and model then return model end

    local plotId = tostring(plot:GetId())
    local things = workspace:FindFirstChild("__THINGS")
    local plots = things and things:FindFirstChild("Plots")
    return plots and plots:FindFirstChild(plotId)
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

    local mode = Config.MovementMode or "Rage"
    if mode == "Rage" then
        Network.teleportTo(typeof(targetPosOrCF) == "CFrame" and targetPosOrCF or CFrame.new(targetPos + Vector3.new(0, 2, 0)))
        return
    end

    -- Chế độ Legit: Dùng PathfindingService, kiểm tra raycast chướng ngại và né rơi xuống nước (Y < 1998.5)
    local path = PathfindingService:CreatePath({
        AgentRadius = 2.5,
        AgentHeight = 5,
        AgentCanJump = true,
        AgentCanClimb = false,
        WaypointSpacing = 4,
    })

    local startPos = hrp.Position
    local okP, _ = pcall(function() path:ComputeAsync(startPos, targetPos) end)

    if not okP or path.Status ~= Enum.PathStatus.Success then
        -- Pathfinding không tìm được đường an toàn -> Fallback teleport an toàn
        Network.teleportTo(CFrame.new(targetPos + Vector3.new(0, 2, 0)))
        return
    end

    local waypoints = path:GetWaypoints()
    for i, wp in ipairs(waypoints) do
        if not char.Parent or hum.Health <= 0 then break end

        -- Cảnh báo rơi xuống nước: Mực nước là Y=1995. Nếu tọa độ bước đi < 1998.5 -> Teleport thẳng đến đích
        if wp.Position.Y < 1998.5 then
            Network.teleportTo(CFrame.new(targetPos + Vector3.new(0, 2, 0)))
            return
        end

        -- Nhảy chướng ngại vật
        if wp.Action == Enum.PathWaypointAction.Jump then
            hum.Jump = true
        else
            -- Raycast kiểm tra chướng ngại trước mặt để chủ động nhảy
            local forwardDir = (wp.Position - hrp.Position).Unit
            local rayParams = RaycastParams.new()
            rayParams.FilterDescendantsInstances = { char }
            rayParams.FilterType = EnumRaycastFilterType.Exclude

            local hit = workspace:Raycast(hrp.Position, forwardDir * 3, rayParams)
            if hit and hit.Instance and hit.Instance.CanCollide then
                hum.Jump = true
            end
        end

        hum:MoveTo(wp.Position)

        -- Chờ nhân vật tới gần waypoint
        local t0 = os.clock()
        while (hrp.Position - wp.Position).Magnitude > 3.5 do
            if os.clock() - t0 > 1.2 then
                -- Bị kẹt -> Nhảy
                hum.Jump = true
                break
            end
            task.wait(0.05)
        end
    end

    if (hrp.Position - targetPos).Magnitude > 4 then
        hum:MoveTo(targetPos)
    end
end

-- =========================================================================
-- 3. QUẢN LÝ QUY TẮC AUTOBREAK VÀ MỞ KHÓA PEDESTAL
-- =========================================================================

function TycoonFarm.ensureAutoBreakZero()
    local plot = TycoonFarm.getPlot()
    if not plot then return end

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

function TycoonFarm.findActiveBigPumpkin()
    local plot = TycoonFarm.getPlot()
    if not plot then return nil end

    local plotId = plot:GetId()
    local plotModel = TycoonFarm.getPlotModel()
    local bestPumpkin = nil
    local maxRung = -1

    local function inspectBreakable(chest, uid)
        local cf = chest:GetPivot()
        local pos = cf.Position
        local clientAttrs = chest:GetAttributes()

        local isMyPlot = (clientAttrs.Plot == plotId)
        local pedIndex = clientAttrs.PumpkinPedestal or clientAttrs.Pedestal

        if not isMyPlot and plotModel then
            -- Fallback kiểm tra khoảng cách với các bệ Pedestal trên đảo của mình
            for i = 1, 8 do
                local pedPart = plotModel:FindFirstChild("Pedestal_" .. i, true)
                local spawnPart = pedPart and (pedPart:FindFirstChild("PumpkinSpawn") or pedPart:FindFirstChild("Spawn"))
                if spawnPart and (spawnPart.Position - pos).Magnitude < 25 then
                    isMyPlot = true
                    pedIndex = i
                    break
                end
            end
        end

        if isMyPlot then
            local rung = tonumber(clientAttrs.Rung) or 1
            local petName = clientAttrs.PetName or chest.Name
            if K.ROSTER_RUNG[petName] then
                rung = math.max(rung, K.ROSTER_RUNG[petName])
            end

            if rung > maxRung then
                maxRung = rung
                bestPumpkin = {
                    uid = uid or chest.Name,
                    model = chest,
                    pos = pos,
                    pedestalIndex = pedIndex or 1,
                    rung = rung,
                }
            end
        end
    end

    -- 1. Tìm qua BreakableFrontend (Thư viện Client PS99)
    if BreakableFrontend and type(BreakableFrontend.AllByInstanceAndClass) == "function" then
        local ok, chests = pcall(BreakableFrontend.AllByInstanceAndClass, "Chest")
        if ok and type(chests) == "table" then
            for uid, chest in pairs(chests) do
                if typeof(chest) == "Instance" then
                    inspectBreakable(chest, uid)
                end
            end
        end
    end

    -- 2. Fallback quét thư mục __THINGS.Breakables
    if not bestPumpkin then
        local things = workspace:FindFirstChild("__THINGS")
        local breakables = things and things:FindFirstChild("Breakables")
        if breakables then
            for _, child in ipairs(breakables:GetChildren()) do
                if child:IsA("Model") and (child:GetAttribute("Chest") or child.Name:find("Chest") or child:GetAttribute("PumpkinPedestal")) then
                    inspectBreakable(child, child.Name)
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
    if not Config.BreakBigPumpkins then return false end
    local bp = TycoonFarm.findActiveBigPumpkin()
    if not bp then
        if state.excursion and state.excursion:find("Bí Ngô") then
            state.excursion = nil
        end
        return false
    end

    state.excursion = string.format("Phá Bí Ngô Khổng Lồ (Bệ #%d - Bậc %d)", bp.pedestalIndex, bp.rung)

    -- Di chuyển lại gần Bí Ngô nếu khoảng cách > 15 studs
    local char, hrp = getCharacterParts()
    if hrp and (hrp.Position - bp.pos).Magnitude > 15 then
        TycoonFarm.moveTo(CFrame.new(bp.pos + Vector3.new(0, 3, 8), bp.pos))
    end

    -- Gửi toàn bộ Pet vào tấn công Bí Ngô Khổng Lồ
    local pets = TycoonFarm.petEuids()
    if #pets > 0 then
        local targetBulk = {}
        for _, uid in ipairs(pets) do
            targetBulk[uid] = bp.uid
        end
        pcall(function()
            Network.netFire("Breakables_JoinPetBulk", targetBulk)
            Network.netFire("Pets_SetTargetBulk", targetBulk)
        end)
    end

    -- Đánh tay (Player Deal Damage)
    pcall(function()
        Network.netFire("Breakables_PlayerDealDamage", bp.uid)
    end)

    return true
end

-- =========================================================================
-- 5. FARM BÃI PATCH CỦA KHU VỰC CAO NHẤT (BEST ZONE SLAB)
-- =========================================================================

function TycoonFarm.farmBestPatchTick(state)
    local plot = TycoonFarm.getPlot()
    local plotModel = TycoonFarm.getPlotModel()
    if not plot or not plotModel then return end

    initGameLibs()
    local buttonsState = plot:Save("Buttons") or {}
    local bestZone = 1
    if PTButtons and type(PTButtons.FarmZone) == "function" then
        bestZone = PTButtons.FarmZone(buttonsState, 5) or 1
    end

    -- Tìm vị trí tâm bãi Patch của khu vực
    local patchPos = nil
    if PTButtons and type(PTButtons.ZoneSlab) == "function" then
        local slab = PTButtons.ZoneSlab(plotModel, bestZone)
        if slab and slab:IsA("BasePart") then
            patchPos = slab.Position + Vector3.new(0, 3, 0)
        end
    end

    if not patchPos then
        local secFolder = plotModel:FindFirstChild("Sections")
        local zoneData = K.ZONES[bestZone]
        local sec = secFolder and zoneData and secFolder:FindFirstChild(zoneData.Section)
        local slab = sec and (sec:FindFirstChild("ZoneSlab", true) or sec:FindFirstChild("Slab", true))
        if slab and slab:IsA("BasePart") then
            patchPos = slab.Position + Vector3.new(0, 3, 0)
        elseif sec then
            patchPos = sec:GetPivot().Position + Vector3.new(0, 3, 0)
        end
    end

    if not patchPos then return end

    local char, hrp = getCharacterParts()
    if hrp and (hrp.Position - patchPos).Magnitude > 22 then
        TycoonFarm.moveTo(patchPos)
    end

    -- Quét quặng trong bãi và điều phối pet
    local pets = TycoonFarm.petEuids()
    if #pets > 0 then
        local things = workspace:FindFirstChild("__THINGS")
        local breakables = things and things:FindFirstChild("Breakables")
        if breakables then
            local targets = {}
            for _, b in ipairs(breakables:GetChildren()) do
                if b:IsA("Model") and (b:GetPivot().Position - patchPos).Magnitude < 35 then
                    table.insert(targets, b.Name)
                end
            end
            if #targets > 0 then
                local joinMap = {}
                for idx, pUid in ipairs(pets) do
                    local tUid = targets[((idx - 1) % #targets) + 1]
                    joinMap[pUid] = tUid
                end
                pcall(function()
                    Network.netFire("Breakables_JoinPetBulk", joinMap)
                end)
            end
        end
    end

    TycoonFarm.collectOrbsTick()
end

-- =========================================================================
-- 6. TỰ ĐỘNG MUA NÚT TYCOON (CHEAPEST FIRST) VÀ NHẬN THƯỞNG ĐẢO
-- =========================================================================

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

    -- 2. Quét các nút có sẵn theo thứ tự Rẻ nhất trước (Cheapest First)
    if PTButtons and type(PTButtons.Available) == "function" and type(PTButtons.Price) == "function" then
        local avail = PTButtons.Available(buttonsState, 5, false, priceMult)
        if type(avail) == "table" and #avail > 0 then
            local coins = Network.currency(K.CURRENCY) or 0
            for _, btn in ipairs(avail) do
                local price = PTButtons.Price(btn, priceMult)
                if coins >= price then
                    -- Nếu chạy chế độ Legit, bước lên bệ pad của nút
                    if Config.MovementMode == "Legit" and type(PTButtons.PadSpot) == "function" then
                        local padSpot = PTButtons.PadSpot(plotModel, btn)
                        if padSpot then
                            TycoonFarm.moveTo(padSpot)
                            task.wait(0.1)
                        end
                    end

                    local okB, resB = pcall(function()
                        return plot:Invoke(K.VERBS.BuyButton, btn.Id)
                    end)

                    if okB then
                        print(string.format("[KizHub Tycoon] ✔ Đã mua nút: %s (Giá: %s Coins)", tostring(btn.Id), Network.shorten(price)))
                        task.wait(0.2)
                        break
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
    local plotModel = TycoonFarm.getPlotModel()
    if not plot then
        return {
            ownedButtons = 0,
            totalButtons = 0,
            percent = 0,
            activeBigPumpkins = 0,
            unlockedPedestals = 0,
            bestZone = 1,
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

    local bestZone = 1
    if PTButtons and type(PTButtons.FarmZone) == "function" then
        bestZone = PTButtons.FarmZone(buttonsState, 5) or 1
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
        bestZone = bestZone,
        completed = isCompleted,
    }
end

return TycoonFarm
