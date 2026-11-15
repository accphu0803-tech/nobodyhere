-- =========================================================================
-- Run_PumpkinTycoon.lua
-- Launcher chạy Suite Kaitun Pumpkin Tycoon (PS99)
-- Tác giả: VANTA [JHON369] | KizHub Automation Suite
-- =========================================================================

-- 1. Cấu hình thông số tài khoản
getgenv().MailRecipient = "Kizmoii_VNG"     -- Tên nick chính nhận Huge & Boost Tier 2
getgenv().EventsUrl = ""                   -- Link Webhook Discord (nếu có)
getgenv().StatusUrl = ""                   -- Link Webhook báo cáo định kỳ (nếu có)

-- 2. Tải và khởi chạy Suite
loadstring(game:HttpGet("https://raw.githubusercontent.com/accphu0803-tech/nobodyhere/main/PS99_KizHub/PumpkinTycoonKaitun/main.lua"))()
