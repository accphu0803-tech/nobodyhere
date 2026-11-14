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
-- 3. QUẢN LÝ QUY TẮC AUTOBREAK, PEDESTAL VÀ AUTO FARM SỰ KIỆN
-- =========================================================================

function TycoonFarm.getPlotCFrame()
    local plot = TycoonFarm.getPlot()
    if plot and type(plot.GetCFrame) == "function" then
        local ok, cf = pcall(plot.GetCFrame, plot)
        if ok and typeof(cf) == "CFrame" then
            return cf
        end
    end
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
    return nil
end

function TycoonFarm.getSweetPos()
    local plotCF = TycoonFarm.getPlotCFrame()
    if plotCF then
        return plotCF:PointToWorldSpace(Vector3.new(181.27, 3.86, 124.00))
    end

    local plotModel = TycoonFarm.getPlotModel()
    if plotModel then
        if PTButtons and type(PTButtons.ZoneSlab) == "function" then
            local okSlab, slab = pcall(PTButtons.ZoneSlab, plotModel, 1)
            if okSlab and slab and slab:IsA("BasePart") then
                return slab.Position + Vector3.new(0, 3, 0)
            end
        end

        local eggAttr = plotModel:GetAttribute("CocoaCabin_Egg") or plotModel:GetAttribute("CocoaCabinEgg")
        if typeof(eggAttr) == "CFrame" then
            return eggAttr.Position + Vector3.new(0, 2, 12)
        elseif typeof(eggAttr) == "Vector3" then
            return eggAttr + Vector3.new(0, 2, 12)
        end
    end

    return nil
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
    local bestPumpkin = nil
    local maxRung = -1

    local function checkChest(brk)
        if not brk or not brk.position then return end
        local isTycoon = (brk.parentID == "PumpkinTycoon") or (brk.model and brk.model:GetAttribute("ParentID") == "PumpkinTycoon")
        if not isTycoon then return end

        local brkPlot = brk.clientAttributes.Plot or (brk.model and brk.model:GetAttribute("Plot"))
        local distSweet = sweetPos and (brk.position - sweetPos).Magnitude or 9999
        local isMyPlot = (brkPlot == plotId) or (distSweet < 350)

        if isMyPlot then
            local rung = tonumber(brk.clientAttributes.Rung) or (brk.model and tonumber(brk.model:GetAttribute("Rung"))) or 1
            local petName = brk.clientAttributes.PetName or (brk.model and brk.model:GetAttribute("PetName")) or (brk.model and brk.model.Name)
            if K and K.ROSTER_RUNG and petName and K.ROSTER_RUNG[petName] then
                rung = math.max(rung, K.ROSTER_RUNG[petName])
            end
            local pedIndex = brk.clientAttributes.PumpkinPedestal or brk.clientAttributes.Pedestal or 1

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
    if not Config.BreakBigPumpkins then return false end
    local bp = TycoonFarm.findActiveBigPumpkin()
    if not bp then
        if state.excursion and state.excursion:find("Bí Ngô") then
            state.excursion = nil
        end
        return false
    end

    state.excursion = "Phá Bí Ngô Khổng Lồ (Bậc " .. tostring(bp.rung) .. ")"

    -- Di chuyển lại gần Bí Ngô nếu khoảng cách > 15 studs
    local char, hrp = getCharacterParts()
    if hrp and (hrp.Position - bp.pos).Magnitude > 15 then
        TycoonFarm.moveTo(CFrame.new(bp.pos + Vector3.new(0, 3, 8), bp.pos))
    end

    -- Gửi toàn bộ Pet trang bị vào tấn công Bí Ngô Khổng Lồ (PlayerPet.GetByPlayer -> SetAnchored, SetTarget)
    local playerPets = getPlayerPets()
    for _, pet in ipairs(playerPets) do
        if pet.SetAnchored then pet:SetAnchored(false) end
        if pet.SetTarget and bp.model then pet:SetTarget(bp.model) end
    end

    local pets = TycoonFarm.petEuids()
    if #pets > 0 then
        local targetBulk = {}
        for _, uid in ipairs(pets) do
            targetBulk[uid] = tostring(bp.uid)
        end
        pcall(function()
            Network.netFire("Breakables_JoinPetBulk", targetBulk)
            Network.netFire("Pets_SetTargetBulk", targetBulk)
        end)
    end

    -- Đánh tay (Player Deal Damage)
    pcall(function()
        Network.netFire("Breakables_PlayerDealDamage", tonumber(bp.uid) or bp.uid)
    end)

    return true
end

-- =========================================================================
-- 5. FARM BÃI PATCH ĐẢO ĐƠN NHẤT (SINGLE ISLAND SWEET SPOT)
-- =========================================================================

function TycoonFarm.farmBestPatchTick(state)
    local plot = TycoonFarm.getPlot()
    if not plot then return end

    initGameLibs()
    local sweetPos = TycoonFarm.getSweetPos()
    if not sweetPos then return end

    -- Kích hoạt Auto Farm miễn phí của event
    TycoonFarm.ensureAutoFarmEnabled(state, sweetPos)

    -- Nếu không có excursion (không đi phá bí ngô ở bệ xa) và cách sweetPos > 8 studs -> Di chuyển về sweetPos
    local char, hrp = getCharacterParts()
    if state and state.excursion == nil and hrp and (hrp.Position - sweetPos).Magnitude > 8 then
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
