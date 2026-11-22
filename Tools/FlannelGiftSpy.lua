-- =========================================================================
-- KIZHUB CLEAN REMOTE SPY (FLANNEL GIFT / LOOTBOX SNIFFER)
-- Chế độ thụ động: Không can thiệp, không sửa đổi dữ liệu
-- Tự động lọc & Tự động Copy lệnh Remote vào Clipboard khi mở Gift
-- =========================================================================

local StarterGui = game:GetService("StarterGui")

local function Notify(msg)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "KizHub Gift Spy",
            Text = msg,
            Duration = 5
        })
    end)
end

local function Serialize(val, depth)
    depth = depth or 0
    if depth > 5 then return '"<max_depth>"' end
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

local function LogRemote(remote, method, args)
    local name = remote.Name
    if ignored[name] then return end

    local path = remote:GetFullName()
    local argStrings = {}
    for _, v in ipairs(args) do
        table.insert(argStrings, Serialize(v))
    end
    local argFormatted = table.concat(argStrings, ", ")
    local codeSnippet = string.format("%s:%s(%s)", path, method, argFormatted)

    local logEntry = string.format([[
-------------------------------------------------------------------------
[CAPTURED REMOTE]
Remote Name: %s (%s)
Method:      %s
Path:        %s
Code Snippet:
%s
-------------------------------------------------------------------------]], name, remote.ClassName, method, path, codeSnippet)

    print(logEntry)

    -- Bộ lọc nhận diện Gift / Lootbox / Open / Hydrate
    local lower = (name .. " " .. path .. " " .. argFormatted):lower()
    if lower:find("gift") or lower:find("lootbox") or lower:find("hydrate") or lower:find("open") or lower:find("flannel") or lower:find("box") then
        if type(setclipboard) == "function" then
            setclipboard(codeSnippet)
            Notify("Đã BẮT ĐƯỢC Remote mở Gift!\nĐã tự động Copy vào Clipboard (Chỉ cần Ctrl+V).")
        else
            Notify("Đã bắt được: " .. name .. "\n(Mở F9 Console để xem)")
        end
        if type(writefile) == "function" then
            pcall(writefile, "flannel_gift_spy.txt", logEntry)
        end
    end
end

-- Hook Namecall (Không sửa đổi bất kỳ tham số nào, chỉ đọc và ghi log)
local rawNamecall
rawNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
    local method = getnamecallmethod()
    if (method == "FireServer" or method == "InvokeServer") and (typeof(self) == "Instance" and (self:IsA("RemoteEvent") or self:IsA("RemoteFunction"))) then
        local args = { ... }
        task.spawn(LogRemote, self, method, args)
    end
    return rawNamecall(self, ...)
end))

Notify("KizHub Spy đã kích hoạt!\nHãy vào túi đồ mở 1 túi Flannel Gift thủ công.")
print("=== KIZHUB REMOTE SPY ĐÃ SẴN SÀNG - HÃY MỞ FLANNEL GIFT THỦ CÔNG ===")
