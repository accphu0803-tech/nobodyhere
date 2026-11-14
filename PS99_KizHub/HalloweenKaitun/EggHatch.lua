-- =========================================================================
-- PS99_KizHub/HalloweenKaitun/EggHatch.lua
-- Module tự động mở trứng sự kiện Halloween (Custom Eggs Hatch)
-- Tích hợp: Bỏ qua Animation mở trứng, Quét Trứng thông minh, Watchdog chống kẹt
-- =========================================================================

local RS = game:GetService("ReplicatedStorage")
local EggHatch = {}

-- Dependencies
local G = nil
local Net = nil
local Config = nil
local K = nil

function EggHatch.init(deps)
    G = deps.Modules.G
    Net = deps.Network
    Config = deps.Config
    K = deps.K
end

local isNoEggAnimInstalled = false

-- Vô hiệu hóa toàn diện hoạt ảnh (Animation) mở trứng
-- Xử lý: Hook Egg Opening Frontend, Tắt Remote OnClientEvent, Xóa EggOpenAnimation GUI, Ngắt Mouse Click
function EggHatch.installNoHatchAnimation()
    if isNoEggAnimInstalled then return end
    isNoEggAnimInstalled = true

    task.spawn(function()
        local Players = game:GetService("Players")
        local LocalPlayer = Players.LocalPlayer
        local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 10)

        -- 1. Quét và triệt tiêu UI animation "EggOpenAnimation" trong PlayerGui
        local function cleanEggGuis()
            if not PlayerGui then return end
            for _, name in ipairs({ "EggOpenAnimation", "EggOpeningAnimation", "EggOpening", "EggsOpening" }) do
                local g = PlayerGui:FindFirstChild(name)
                if g then
                    pcall(function()
                        if g:IsA("ScreenGui") then g.Enabled = false end
                        g:Destroy()
                    end)
                end
            end
        end
        cleanEggGuis()
        pcall(function()
            PlayerGui.ChildAdded:Connect(function(child)
                local n = child.Name:lower()
                if n:find("eggopen") or n:find("eggopening") or n:find("egg_open") then
                    task.defer(function()
                        pcall(function()
                            if child:IsA("ScreenGui") then child.Enabled = false end
                            child:Destroy()
                        end)
                    end)
                end
            end)
        end)

        -- 2. Hook liên tục LocalScript "Egg Opening Frontend" trong PlayerScripts
        for attempt = 1, 30 do
            local hookedFrontend = false
            pcall(function()
                local ps = LocalPlayer:FindFirstChild("PlayerScripts")
                local scripts = ps and ps:FindFirstChild("Scripts")
                local gameFolder = scripts and scripts:FindFirstChild("Game")
                local eggScript = (gameFolder and gameFolder:FindFirstChild("Egg Opening Frontend"))
                    or (ps and ps:FindFirstChild("Egg Opening Frontend", true))

                if eggScript and type(getsenv) == "function" then
                    local env = getsenv(eggScript)
                    if type(env) == "table" and type(env.PlayEggAnimation) == "function" then
                        if type(hookfunction) == "function" then
                            hookfunction(env.PlayEggAnimation, function(...) return end)
                        end
                        env.PlayEggAnimation = function(...) return end
                        if type(env.PlayAnimation) == "function" then
                            if type(hookfunction) == "function" then
                                hookfunction(env.PlayAnimation, function(...) return end)
                            end
                            env.PlayAnimation = function(...) return end
                        end
                        hookedFrontend = true
                    end
                end
            end)

            -- 3. Tắt RemoteEvent OnClientEvent của "Eggs_PlayOpenAnimation"
            pcall(function()
                local netFolder = RS:FindFirstChild("Network")
                local remote = netFolder and netFolder:FindFirstChild("Eggs_PlayOpenAnimation")
                if remote and type(getconnections) == "function" then
                    for _, conn in ipairs(getconnections(remote.OnClientEvent)) do
                        pcall(function() conn:Disable() end)
                    end
                end
            end)

            -- 4. Hook fallback trên ModuleScript EggCmds nếu có
            pcall(function()
                local eggCmds = RS:FindFirstChild("Library")
                    and RS.Library:FindFirstChild("Client")
                    and RS.Library.Client:FindFirstChild("EggCmds")
                if eggCmds and type(getsenv) == "function" then
                    local env = getsenv(eggCmds)
                    if type(env) == "table" and type(env.PlayEggAnimation) == "function" then
                        if type(hookfunction) == "function" then
                            hookfunction(env.PlayEggAnimation, function(...) return end)
                        end
                        env.PlayEggAnimation = function(...) return end
                    end
                end
            end)

            -- 5. Tắt animation click listener trên mouse
            pcall(function()
                local ps = LocalPlayer:FindFirstChild("PlayerScripts")
                local frontend = ps and ps:FindFirstChild("Egg Opening Frontend", true)
                if frontend and type(getconnections) == "function" then
                    local source = frontend:GetFullName()
                    for _, conn in ipairs(getconnections(LocalPlayer:GetMouse().Button1Down)) do
                        if conn.Function and debug.info(conn.Function, "s") == source then
                            pcall(function() conn:Disable() end)
                        end
                    end
                end
            end)

            if hookedFrontend then
                print("[KizHub EggHatch] Đã disable Egg Animation thành công!")
                break
            end
            task.wait(1.0)
        end
    end)

    pcall(function()
        if G and type(G.PlayerPet) == "table" and type(G.PlayerPet.CalculateSpeedMultiplier) == "function" then
            G.PlayerPet.CalculateSpeedMultiplier = function(...)
                return 10
            end
        end
    end)
end

-- Tìm đối tượng trứng trong sự kiện theo ID
function EggHatch.findCustomEggById(eggId)
    if Net.isfn(G.CustomEggs, "All") then
        local all = Net.gval(G.CustomEggs.All)
        if type(all) == "table" then
            for uid, e in pairs(all) do
                if type(e) == "table" and (e._id == eggId or uid == eggId) then
                    local pos = e._position
                    if typeof(pos) ~= "Vector3" and e._model and e._model.Parent then
                        pcall(function() pos = e._model:GetPivot().Position end)
                    end
                    return {
                        uid = e._uid or uid,
                        id = e._id,
                        dir = e._dir or (G.Eggs and G.Eggs[e._id]) or nil,
                        pos = pos,
                        maxCount = e._maxEggCount,
                    }
                end
            end
        end
    end

    local things = workspace:FindFirstChild("__THINGS")
    local customEggsFolder = things and things:FindFirstChild("CustomEggs")
    if customEggsFolder then
        for _, eggModel in ipairs(customEggsFolder:GetChildren()) do
            if eggModel:IsA("Model") and (eggModel.Name:find(eggId) or eggModel:GetAttribute("EggId") == eggId) then
                local realUid = eggModel:GetAttribute("UID") or eggModel.Name
                return {
                    uid = realUid,
                    id = eggId,
                    dir = G.Eggs and G.Eggs[eggId] or nil,
                    pos = eggModel:GetPivot().Position,
                    maxCount = 99
                }
            end
        end
    end
    return nil
end

-- Lấy số lượng trứng tối đa có thể mở cùng lúc của tài khoản
function EggHatch.getAccountMaxHatch(egg)
    local bestMax = 1
    if Net.isfn(G.EggCmds, "GetMaxHatch") then
        local n = Net.gval(G.EggCmds.GetMaxHatch, egg and egg.dir or nil)
        if type(n) == "number" and n > bestMax then
            bestMax = math.floor(n)
        end
    end
    if egg and type(egg.maxCount) == "number" and egg.maxCount > bestMax then
        bestMax = math.floor(egg.maxCount)
    end
    return math.max(1, bestMax)
end

-- Thực hiện hatch trứng khu vực
function EggHatch.hatchZoneEgg(egg, state)
    if not egg then return false, 0 end
    local now = os.clock()
    if now < (state.nextHatchAttemptAt or 0) then return false, 0 end

    -- Kiểm tra số dư coin trước khi gửi Remote! Chống spam request khi hết tiền
    local curBal = Net.currency(K.CURRENCY) or 0
    if curBal <= 0 then
        state.nextHatchAttemptAt = now + 3.0 -- Nghỉ 3s chờ farm thêm coins
        return false, 0
    end

    local maxAmount = EggHatch.getAccountMaxHatch(egg)
    local target = egg.uid or egg.id
    if not target then return false, 0 end

    local ok, res = Net.netInvoke("CustomEggs_Hatch", target, maxAmount)
    if ok and res == true then
        state.totalEggsHatched = (state.totalEggsHatched or 0) + maxAmount
        state.lastSuccessfulHatch = os.clock()
        return true, maxAmount
    else
        -- Nếu mở bulk thất bại: Thử mở 1 quả
        if maxAmount > 1 then
            local ok1, res1 = Net.netInvoke("CustomEggs_Hatch", target, 1)
            if ok1 and res1 == true then
                state.totalEggsHatched = (state.totalEggsHatched or 0) + 1
                state.lastSuccessfulHatch = os.clock()
                return true, 1
            end
        end
        -- Thất bại do hết coin hoặc server cooldown -> giãn nhịp 3.5 giây
        state.nextHatchAttemptAt = now + 3.5
        return false, 0
    end
end

-- Kiểm tra Watchdog chống kẹt map khi mở trứng
function EggHatch.runWatchdogCheck(state, hasBreakablesFn, forceRejoinFn)
    local wCfg = Config.Watchdog
    if not (wCfg and wCfg.Enabled) then return end
    if state.excursion ~= nil or state.isRejoining then return end

    -- Nếu nhân vật đang farm hoặc còn coin -> Không kích hoạt Watchdog
    local char = game:GetService("Players").LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health > 0 then
        local currentZone = state.currentZoneNumber or 1
        if (hasBreakablesFn and hasBreakablesFn(currentZone)) or (Net.currency(K.CURRENCY) or 0) > 0 then
            state.lastSuccessfulHatch = os.clock()
            return
        end
    end

    local maxIdleSec = (wCfg.MaxIdleHatchMinutes or 30) * 60
    if (os.clock() - (state.lastSuccessfulHatch or os.clock())) >= maxIdleSec then
        if type(forceRejoinFn) == "function" then
            forceRejoinFn(string.format("Kẹt cứng không hatch/farm được quá %d phút.", math.floor(maxIdleSec / 60)))
        end
    end
end

return EggHatch
