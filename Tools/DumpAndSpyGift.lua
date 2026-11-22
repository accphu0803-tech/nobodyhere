-- =========================================================================
-- KIZHUB COMPREHENSIVE INVENTORY DUMPER & GIFT SPY (PS99 TYCOON)
-- Tự động Dump toàn bộ Inventory (UID, ID, Số lượng, Mục)
-- Bắt trọn Remote khi mở Gift (Tham số + Giá trị Server trả về)
-- Tích hợp bộ Test mở quà tự động kiểm tra 6 phương thức mở quà
-- =========================================================================

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local RS = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local function Notify(title, msg, dur)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title or "KizHub Spy",
            Text = msg or "",
            Duration = dur or 6
        })
    end)
end

print("=========================================================================")
print("          [KIZHUB] INVENTORY DUMPER & GIFT REMOTE SPY STARTED           ")
print("=========================================================================")
Notify("KizHub Spy Loaded", "Đang phân tích túi đồ & kích hoạt bộ lắng nghe...")

-- -------------------------------------------------------------------------
-- 1. TÌM VÀ TRÍCH XUẤT SAVE / INVENTORY
-- -------------------------------------------------------------------------
local SaveGet = nil
pcall(function()
    local lib = RS:FindFirstChild("Library")
    if lib then
        local client = lib:FindFirstChild("Client")
        if client and client:FindFirstChild("Save") then
            local saveMod = require(client.Save)
            if saveMod and saveMod.Get then SaveGet = saveMod.Get end
        end
        if not SaveGet then
            local mainLib = require(lib)
            if mainLib and mainLib.Save and mainLib.Save.Get then
                SaveGet = mainLib.Save.Get
            end
        end
    end
end)

local inventory = nil
if SaveGet then
    local ok, s = pcall(SaveGet)
    if ok and type(s) == "table" then
        inventory = s.Inventory
    end
end

-- -------------------------------------------------------------------------
-- 2. DUMP TOÀN BỘ INVENTORY RA CONSOLE & FILE
-- -------------------------------------------------------------------------
local dumpLines = {}
local function AddDump(line)
    table.insert(dumpLines, line)
    print(line)
end

AddDump("\n--- [1. TỔNG QUAN TÚI ĐỒ (INVENTORY CATEGORIES)] ---")
local targetGiftsFound = {}

if type(inventory) == "table" then
    local categoryCounts = {}
    for catName, catTable in pairs(inventory) do
        if type(catTable) == "table" then
            local count = 0
            for uid, item in pairs(catTable) do
                count = count + 1
                if type(item) == "table" then
                    local idStr = tostring(item.id or item._id or item.Name or "")
                    local lower = (catName .. " " .. idStr):lower()
                    if lower:find("gift") or lower:find("flannel") or lower:find("loot") or lower:find("box") or lower:find("bag") or lower:find("pumpkin") then
                        table.insert(targetGiftsFound, {
                            Category = catName,
                            UID = tostring(uid or item._uid or item.uid or ""),
                            ID = idStr,
                            Amount = tonumber(item._am or item.amount or item.Count) or 1,
                            Locked = (item.lk == true or item._lk == true),
                            Soulbound = (item.sb == true or item._sb == true)
                        })
                    end
                end
            end
            categoryCounts[catName] = count
        end
    end

    for catName, count in pairs(categoryCounts) do
        AddDump(string.format("  Mục [%s]: %d vật phẩm", catName, count))
    end

    AddDump("\n--- [2. DANH SÁCH GIFT / LOOTBOX / HỘP QUÀ TÌM THẤY TRONG TÚI] ---")
    if #targetGiftsFound > 0 then
        for idx, g in ipairs(targetGiftsFound) do
            AddDump(string.format("  #%d [%s] ID: \"%s\" | UID: \"%s\" | Số lượng: %d | Khóa: %s | Soulbound: %s",
                idx, g.Category, g.ID, g.UID, g.Amount, tostring(g.Locked), tostring(g.Soulbound)))
        end
    else
        AddDump("  ⚠️ Không tìm thấy vật phẩm nào có tên chứa 'gift', 'flannel', 'lootbox' trong túi đồ!")
        AddDump("  -> Vui lòng kiểm tra lại xem acc đã mở hòm/nhận được Flannel Gift chưa.")
    end
else
    AddDump("  ⚠️ Không đọc được Inventory từ Save.Get()!")
end

if type(writefile) == "function" then
    pcall(writefile, "kizhub_inventory_dump.txt", table.concat(dumpLines, "\n"))
end

-- -------------------------------------------------------------------------
-- 3. HÀM SERIALIZE & LẮNG NGHE REMOTE (HOOK METAMETHOD SPY)
-- -------------------------------------------------------------------------
local function Serialize(val, depth)
    depth = depth or 0
    if depth > 4 then return '"<max_depth>"' end
    local t = typeof(val)
    if t == "string" then
        return string.format("%q", val)
    elseif t == "number" or t == "boolean" then
        return tostring(val)
    elseif t == "table" then
        local parts = {}
        for k, v in pairs(val) do
            local kStr = type(k) == "string" and string.format("[%q]", k) or string.format("[%s]", tostring(k))
            table.insert(parts, string.rep("  ", depth + 1) .. kStr .. " = " .. Serialize(v, depth + 1))
        end
        if #parts == 0 then return "{}" end
        return "{\n" .. table.concat(parts, ",\n") .. "\n" .. string.rep("  ", depth) .. "}"
    elseif t == "Vector3" then
        return string.format("Vector3.new(%.2f, %.2f, %.2f)", val.X, val.Y, val.Z)
    elseif t == "CFrame" then
        return string.format("CFrame.new(%.2f, %.2f, %.2f)", val.Position.X, val.Position.Y, val.Position.Z)
    elseif t == "Instance" then
        return val:GetFullName()
    else
        return tostring(val)
    end
end

local ignored = {
    ["Ping"] = true, ["Idle"] = true, ["Touch"] = true, ["Move"] = true,
    ["Replicate"] = true, ["Update"] = true, ["Step"] = true, ["Physics"] = true,
    ["ClientLoaded"] = true, ["Heartbeat"] = true, ["Sound"] = true
}

local function LogCapturedRemote(remote, method, args, result)
    local name = remote.Name
    if ignored[name] then return end

    local path = remote:GetFullName()
    local argStrings = {}
    for _, v in ipairs(args) do
        table.insert(argStrings, Serialize(v))
    end
    local argFormatted = table.concat(argStrings, ", ")
    local codeSnippet = string.format("%s:%s(%s)", path, method, argFormatted)

    local resStr = "N/A (FireServer / Chờ kết quả)"
    if result ~= nil then
        resStr = Serialize(result)
    end

    local logEntry = string.format([[
-------------------------------------------------------------------------
[BẮT ĐƯỢC REMOTE GỌI SERVER]
Tên Remote:    %s (%s)
Phương thức:   %s
Đường dẫn:     %s
Kết quả Server trả về: %s
Mã gọi (Code Snippet):
%s
-------------------------------------------------------------------------]], name, remote.ClassName, method, path, resStr, codeSnippet)

    print(logEntry)

    -- Bộ lọc nhận diện Gift / Lootbox / Hydrate / Open
    local lower = (name .. " " .. path .. " " .. argFormatted):lower()
    if lower:find("gift") or lower:find("lootbox") or lower:find("hydrate") or lower:find("open") or lower:find("flannel") or lower:find("box") then
        if type(setclipboard) == "function" then
            setclipboard(codeSnippet)
            Notify("ĐÃ BẮT ĐƯỢC REMOTE MỞ QUÀ!", "Đã copy vào Clipboard. Server trả về: " .. tostring(resStr), 7)
        end
        if type(writefile) == "function" then
            pcall(writefile, "kizhub_gift_captured.txt", logEntry)
        end
    end
end

-- Hook metamethod __namecall
local rawNamecall
rawNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
    local method = getnamecallmethod()
    if (method == "FireServer" or method == "InvokeServer") and typeof(self) == "Instance" and (self:IsA("RemoteEvent") or self:IsA("RemoteFunction")) then
        local args = { ... }
        task.spawn(LogCapturedRemote, self, method, args, nil)
    end
    return rawNamecall(self, ...)
end))

-- -------------------------------------------------------------------------
-- 4. BỘ TEST MỞ QUÀ TRỰC TIẾP (DIRECT TEST OPENER)
-- -------------------------------------------------------------------------
_G.TestOpenGift = function()
    print("\n>>> [KIZHUB] BẮT ĐẦU TEST CÁC PHƯƠNG THỨC MỞ QUÀ...")
    if #targetGiftsFound == 0 then
        print("❌ Không có hộp quà nào trong túi đồ để test!")
        return
    end

    local sampleGift = targetGiftsFound[1]
    local uid = sampleGift.UID
    local id = sampleGift.ID
    print(string.format("🎯 Mục tiêu test: %s (UID: %s)", id, uid))

    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local pos = hrp and hrp.Position or Vector3.new(0, 10, 0)
    local posArr = { [1] = pos }

    local yrHydrate = (RS:FindFirstChild("Network") and RS.Network:FindFirstChild("YR_Hydrate"))

    -- Test 1: YR_Hydrate (uid, 1, posArr, false)
    if yrHydrate and yrHydrate:IsA("RemoteFunction") then
        print("\n--- Test 1: YR_Hydrate:InvokeServer(uid, 1, posArr, false) ---")
        local ok1, res1 = pcall(function() return yrHydrate:InvokeServer(uid, 1, posArr, false) end)
        print(string.format("Kết quả: ok=%s, return=%s", tostring(ok1), tostring(res1)))

        -- Test 2: YR_Hydrate (uid, 1, posArr, true) [Instant Open]
        print("\n--- Test 2: YR_Hydrate:InvokeServer(uid, 1, posArr, true) [Instant Open] ---")
        local ok2, res2 = pcall(function() return yrHydrate:InvokeServer(uid, 1, posArr, true) end)
        print(string.format("Kết quả: ok=%s, return=%s", tostring(ok2), tostring(res2)))

        -- Test 3: YR_Hydrate (uid, 1, {}, true) [Skip placement]
        print("\n--- Test 3: YR_Hydrate:InvokeServer(uid, 1, {}, true) [Skip Placement] ---")
        local ok3, res3 = pcall(function() return yrHydrate:InvokeServer(uid, 1, {}, true) end)
        print(string.format("Kết quả: ok=%s, return=%s", tostring(ok3), tostring(res3)))
    else
        print("⚠️ Không tìm thấy RemoteFunction YR_Hydrate trong ReplicatedStorage.Network!")
    end

    -- Test 4: Network.Invoke("Lootbox: Open", id, 1)
    print("\n--- Test 4: Network.Invoke(\"Lootbox: Open\", id, 1) ---")
    pcall(function()
        local lib = require(RS.Library)
        local ok4, res4 = pcall(lib.Network.Invoke, "Lootbox: Open", id, 1)
        print(string.format("Kết quả: ok=%s, return=%s", tostring(ok4), tostring(res4)))
    end)

    -- Test 5: Network.Invoke("Gift: Open", uid, 1)
    print("\n--- Test 5: Network.Invoke(\"Gift: Open\", uid, 1) ---")
    pcall(function()
        local lib = require(RS.Library)
        local ok5, res5 = pcall(lib.Network.Invoke, "Gift: Open", uid, 1)
        print(string.format("Kết quả: ok=%s, return=%s", tostring(ok5), tostring(res5)))
    end)

    print("\n>>> HOÀN TẤT BỘ TEST! Vui lòng chụp lại Console F9 hoặc kiểm tra kết quả ở trên.")
end

-- Tự động chạy bộ test nếu có quà trong túi
if #targetGiftsFound > 0 then
    task.spawn(function()
        task.wait(2)
        print("\n[KIZHUB] Tự động kích hoạt Test mở hộp quà đầu tiên tìm thấy...")
        _G.TestOpenGift()
    end)
end

print("\n[KIZHUB SPY ĐÃ SẴN SÀNG]")
print("1. Hãy mở hòm thư hoặc mở quà thủ công trong game nếu muốn spy remote.")
print("2. Để chạy lại bộ test mở quà bất kỳ lúc nào, gõ lệnh: _G.TestOpenGift()")
print("3. Kết quả dump túi đồ đã lưu vào: kizhub_inventory_dump.txt")
