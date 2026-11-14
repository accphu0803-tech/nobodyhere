-- =========================================================================
-- PS99_KizHub/PumpkinTycoonKaitun/Config.lua
-- Cấu hình trung tâm cho Suite tự động hóa Pumpkin Patch Tycoon Pet Simulator 99
-- Tác giả: VANTA [JHON369] | KizHub Automation Engine
-- =========================================================================

local genv = (type(getgenv) == "function" and getgenv()) or _G

local Config = {
    -- Cài đặt chung & Hiệu năng
    Enabled = true,
    TargetFPS = 5,
    Blackout = true,
    HidePlayers = true,
    AfkPulseInterval = 35,

    -- Chế độ di chuyển: "Rage" = Teleport tức thì; "Legit" = Pathfinding né nước & nhảy chướng ngại
    MovementMode = "Rage",

    -- Farm đảo & Quái Bí Ngô
    AutoFarmTycoon = true,
    ForceZone = nil, -- Đặt 1, 2, 3, 4, 5 nếu muốn cố định bãi farm; để nil để tự động theo tiến độ đảo
    BreakBigPumpkins = false,
    BigPumpkinMaxDistance = 400,

    -- Mua nút Tycoon & Nhận thưởng đảo
    AutoBuyButtons = true,
    ButtonBuyInterval = 1.5,
    AutoClaimIslandReward = true,

    -- Mở Trứng Custom tốt nhất
    AutoHatchBestEgg = true,
    HatchDelay = 1.0,

    -- Auto Click / Gõ quặng
    AutoTap = {
        Enabled = true,
        TapDelay = 0.2,
    },

    -- Nâng cấp máy Upgrade Machine
    AutoUpgrades = true,
    UpgradeInterval = 10,
    UpgradeOrder = {
        "SpawnLuck",
        "PumpkinCoins",
        "PumpkinDamage",
        "RespawnSpeed",
        "StockSlots",
        "ChaseOdds",
        "EggLuck",
        "MerchantLuck",
        "AutoBreakRules",
    },

    -- Trạm Hot Cocoa Boost
    AutoHotCocoa = true,
    CocoaInterval = 15,
    CocoaMinRemainingSeconds = 900, -- Mua thêm khi còn dưới 15 phút
    AutoConsumeBoosts = true,

    -- Chế tạo Pet Vàng / Cầu Vồng Tycoon
    AutoGoldRainbowPets = true,
    GoldRainbowInterval = 20,
    GoldRainbowBatchSize = 10,

    -- Merchant & Quầy hàng Pedestal
    AutoMerchant = true,
    AutoPlaceStock = true,
    MerchantInterval = 5,
    MerchantBandOrder = {
        "ExoticPlus",
        "MythicalPlus",
        "LegendaryPlus",
        "EpicPlus",
        "RarePlus",
    },

    -- Quà Flannel & Quà miễn phí
    AutoOpenFlannelGifts = true,
    GiftOpenInterval = 10,
    AutoClaimFreeGifts = true,

    -- Tính năng phụ trợ
    AutoDaycare = false,
    AutoMailHuge = true,
    MailRecipient = genv.MailRecipient or "Kizmoii_VNG",
    MailRetryInterval = 1800,
    MailCooldownSec = 61,

    -- Cân đối ngân sách Tycoon thông minh (Mua Button vs Mở Egg)
    Economy = {
        HatchCyclesBeforeButtonCheck = 3, -- Cứ mở egg 3 lần sẽ check nút rẻ nhất tiếp theo và ngưng mở egg cho tới khi mua xong nút
        PrioritizeEggButtons = true,    -- Luôn gom 100% tiền mua ngay nút Egg & Zone khi xuất hiện
        ReserveRatioForExpensive = 0.6, -- Với nút giá cao: Giữ 60% tiền làm quỹ tích lũy, dùng thặng dư hatch
    },

    -- Discord Webhook
    Webhook = {
        Enabled = true,
        EventsUrl = "",
        StatusUrl = "",
        StatusInterval = 1800,
    },
}

-- Bảng hằng số & API Game Pumpkin Tycoon
local K = {
    INSTANCE_ID = "PumpkinTycoon",
    CURRENCY    = "PumpkinTycoonCoins",
    TOKENS      = "PumpkinTokens",

    -- Verbs gọi Server Plot: plot:Invoke(verb, ...)
    VERBS = {
        BuyButton       = "NZ_Commit",
        ClaimReward     = "BT_Settle",
        AutoBreakPolicy = "QW_Policy",
        PedestalShelter = "KT_Shelter",
        AutoMerchant    = "HM_Sustain",
        BuyStock        = "FZ_Reserve",
        AutoPlaceStock  = "JD_Prefer",
        PlaceStock      = "XC_Allocate",
        Upgrade         = "OQ_Advance",
        ExtendCocoa     = "VB_Extend",
        OpenGift        = "YR_Hydrate",
    },

    -- 5 Khu vực bãi cày & Trứng tương ứng
    ZONES = {
        [1] = { Egg = "Cocoa Cabin Egg",   EggBtn = "CocoaCabin_Egg",   Section = "CocoaCabin",   DisplayName = "Cocoa Cabin" },
        [2] = { Egg = "Apple Orchard Egg", EggBtn = "AppleOrchard_Egg", Section = "AppleOrchard", DisplayName = "Apple Orchard" },
        [3] = { Egg = "Hayride Hill Egg",  EggBtn = "HayrideHill_Egg",  Section = "HayrideHill",  DisplayName = "Hayride Hill" },
        [4] = { Egg = "Cider Mill Egg",    EggBtn = "CiderMill_Egg",    Section = "CiderMill",    DisplayName = "Cider Mill" },
        [5] = { Egg = "Golden Grove Egg",  EggBtn = "GoldenGrove_Egg",  Section = "GoldenGrove",  DisplayName = "Golden Grove" },
    },

    -- Phân hạng bậc Roster Pet của Pumpkin Tycoon
    ROSTER_RUNG = {
        ["Gourd Toad"]      = 1,
        ["Toasty Monkey"]   = 2,
        ["Toasty Otter"]    = 3,
        ["Toasty Capybara"] = 3,
        ["Gourd Piggy"]     = 4,
        ["Gourd Koala"]     = 4,
        ["Orchard Hedgehog"]= 5,
        ["Orchard Moose"]   = 5,
        ["Orchard Pony"]    = 6,
        ["Maple Lion"]      = 6,
        ["Maple Kitsune"]   = 7,
        ["Pumpkin Dragon"]  = 8,
    },

    UPGRADE_TRACKS = {
        "SpawnLuck",
        "PumpkinCoins",
        "PumpkinDamage",
        "RespawnSpeed",
        "StockSlots",
        "ChaseOdds",
        "EggLuck",
        "MerchantLuck",
        "AutoBreakRules",
    },
}

-- Đồng bộ cấu hình từ genv nếu đã tồn tại
if type(genv.KaitunConfig) == "table" then
    for k, v in pairs(genv.KaitunConfig) do
        Config[k] = v
    end
else
    genv.KaitunConfig = Config
end

return {
    Config = Config,
    K = K,
}
