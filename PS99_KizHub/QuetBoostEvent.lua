-- =========================================================================
-- QUET_BOOST_EVENT.lua
-- Tool quét tự động toàn bộ Boost Event trong túi đồ Pet Simulator 99
-- Tác giả: VANTA [JHON369] | Dành riêng cho dj
-- =========================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

print("\n==================================================")
print("🔍 [VANTA] ĐANG QUÉT TÚI ĐỒ TÌM BOOST EVENT...")
print("==================================================")

local outputLines = {}
local function logLine(txt)
    print(txt)
    table.insert(outputLines, txt)
end

logLine("🎮 TÀI KHOẢN: " .. tostring(LocalPlayer.Name))
logLine("⏰ THỜI GIAN: " .. os.date("%H:%M:%S"))
logLine("--------------------------------------------------")

-- 1. LẤY DỮ LIỆU TÚI ĐỒ (SAVE DATA)
local save = nil
pcall(function()
    local SaveModule = require(ReplicatedStorage.Library.Client.Save)
    if SaveModule and type(SaveModule.Get) == "function" then
        save = SaveModule.Get()
    end
end)

if not save or not save.Inventory then
    logLine("❌ Không đọc được save.Inventory từ client module!")
else
    local inv = save.Inventory
    local foundCount = 0

    -- Danh mục cần quét
    local categories = { "Consumable", "Potion", "Misc", "Item", "Box", "Lootbox" }
    local eventKeywords = { "boost", "cocoa", "pumpkin", "patch", "island", "luck", "tycoon" }

    for _, catName in ipairs(categories) do
        local catTable = inv[catName]
        if type(catTable) == "table" then
            for uid, itemData in pairs(catTable) do
                if type(itemData) == "table" and type(itemData.id) == "string" then
                    local lowerId = string.lower(itemData.id)
                    local isMatch = false
                    for _, kw in ipairs(eventKeywords) do
                        if lowerId:find(kw) then
                            isMatch = true
                            break
                        end
                    end

                    if isMatch then
                        foundCount = foundCount + 1
                        local amt = tonumber(itemData._am) or 1
                        local tier = itemData.tn or itemData.tier or 1
                        local line = string.format("📌 [%s] Tên: \"%s\" | Số lượng: %d | Cấp/Tier: %s | UID: %s", catName, itemData.id, amt, tostring(tier), tostring(uid))
                        logLine(line)
                    end
                end
            end
        end
    end

    if foundCount == 0 then
        logLine("⚠️ Chưa tìm thấy item nào có từ khóa Event/Boost trong túi.")
        logLine("👉 Hãy thử mở túi đồ lên, xem các item đang có.")
    else
        logLine(string.format("✅ TÌM THẤY TỔNG CỘNG: %d LOẠI BOOST / VẬT PHẨM EVENT!", foundCount))
    end
end

-- 2. TỰ ĐỘNG BẬT BỘ BẮT REMOTE KHI BẤM CẮN THỬ BẰNG TAY
logLine("--------------------------------------------------")
logLine("🎯 [CHẾ ĐỘ THEO DÕI TỰ ĐỘNG KÍCH HOẠT]")
logLine("👉 Bạn chỉ cần mở túi đồ và BẤM CẮN 1 CÁI BOOST BẤT KỲ BẰNG TAY.")
logLine("👉 Script sẽ tự động in chính xác tên Remote & lệnh mà game gửi đi!")
logLine("==================================================\n")

local clipboardText = table.concat(outputLines, "\n")
if type(setclipboard) == "function" then
    pcall(function()
        setclipboard(clipboardText)
        print("📋 ĐÃ TỰ ĐỘNG COPY TOÀN BỘ KẾT QUẢ VÀO CLIPBOARD (BẤM CTRL + V ĐỂ GỬI)!")
    end)
end

if type(writefile) == "function" then
    pcall(function()
        writefile("PS99_Event_Boost_Scan.txt", clipboardText)
    end)
end

-- Bộ Hook bắt remote khi cắn boost bằng tay
pcall(function()
    local mt = getrawmetatable(game)
    setreadonly(mt, false)
    local oldNamecall = mt.__namecall

    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        local args = { ... }

        if (method == "FireServer" or method == "InvokeServer") then
            local rName = tostring(self.Name)
            local lowerRName = string.lower(rName)
            if lowerRName:find("consume") or lowerRName:find("boost") or lowerRName:find("cocoa") or lowerRName:find("potion") then
                print(string.format("\n🎯 [ĐÃ BẮT ĐƯỢC LỆNH CẮN BOOST: %s]", rName))
                for i, v in ipairs(args) do
                    print(string.format("   Arg[%d]: %s (%s)", i, tostring(v), type(v)))
                end
                print("--------------------------------------------------\n")
            end
        end

        return oldNamecall(self, ...)
    end)
    setreadonly(mt, true)
end)
