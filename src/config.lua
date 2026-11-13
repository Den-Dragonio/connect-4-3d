local I18N           = require("src.i18n")
local FirebaseClient = require("src.firebase_client")

local Config = {
    GameMode = {
        LOCAL_PVP = "local_pvp",
        VS_BOT    = "vs_bot",
        LAN       = "lan",
        ONLINE    = "online"
    },
    BotDifficulty = {
        EASY   = 1,
        MEDIUM = 2,
        HARD   = 3
    },

    currentMode = "local_pvp",
    ruleMode = "standard",      -- "standard" or "free"
    eloGraphMode = "std_blitz", -- "std_bullet", "std_blitz", "free_bullet", "free_blitz"
    botDifficulty = 2,          -- Default: Medium (2 on 1..3 slider)
    botColorChoice = "white",   -- "white", "black", "random"
    humanPlayer = 1,            -- 1 = White, 2 = Black
    onlineTimeMinutes = 5,      -- 5 minutes (300s) or 1 minute (60s)
    onlinePlayersCount = 1,     -- Real active online players count
    onlineActiveGames = 0,      -- Real active online games count

    cameraSensitivity = 1.0,
    animateDrops = true,
    useOwnSkins = true,

    -- Display settings
    fullscreen = false,
    resolutions = {
        { w = 1280, h = 800,  label = "1280x800"  },
        { w = 1366, h = 768,  label = "1366x768"  },
        { w = 1600, h = 900,  label = "1600x900"  },
        { w = 1920, h = 1080, label = "1920x1080" }
    },
    currentResIndex = 1,

    -- Registered accounts database (persisted locally)
    registeredAccounts = {},

    -- Active Player Profile
    profile = {
        username = "Guest_" .. tostring(math.random(1000, 9999)),
        email = "",
        password = "",
        bio = "",
        avatarPreset = 1,
        customAvatarFile = nil,
        isRegistered = false,
        userNumber = 9999,
        rating = 800,
        ratingHistory = { 800 },
        ratings = {
            std_bullet  = 800,
            std_blitz   = 800,
            free_bullet = 800,
            free_blitz  = 800
        },
        ratingHistories = {
            std_bullet  = { 800 },
            std_blitz   = { 800 },
            free_bullet = { 800 },
            free_blitz  = { 800 }
        },
        gamesPlayed = 0,
        wins = 0,
        losses = 0,
        draws = 0,
        winStreak = 0,
        skinWins = {},
        boardWins = {},
        recentMatches = {},
        friends = {},
        incomingRequests = {},
        sentRequests = {},
        blockedUsers = {},
        tournamentHistory = {},
        achievements = {
            bot_easy       = false,
            bot_medium     = false,
            bot_hard       = false,
            wins_10        = false,
            wins_100       = false,
            wins_1000      = false,
            first_friend   = false,
            pioneer_1000   = false,
            tournament_win = false
        }
    },

    coins = 100,
    DAILY_COIN_LIMIT = 100,
    dailyProgress = {
        dateStr     = os.date("%Y-%m-%d"),
        coinsEarned = 0,
        pvpWins     = 0
    },
    adsRemoved = false,

    boardShape = "round",
    activePieceSkin = "classic_bw",
    activeBoardSkin = "dark_wood",
    activeUITheme   = "minimal_gray",

    uiThemeOrder = {
        "minimal_gray",
        "white_clean",
        "black_oled",
        "new_year",
        "halloween",
        "wood_vibe",
        "carbon_dark"
    },

    uiThemes = {
        minimal_gray = {
            id = "minimal_gray",
            nameKey = "ui_theme_gray",
            splitPreview = true,
            adaptiveDayNight = true,
            -- Night / Dark Gray palette (19:00 - 07:00)
            bgClear        = { 0.14, 0.15, 0.17, 1.0 },
            panelBg        = { 0.18, 0.19, 0.22, 0.95 },
            panelBorder    = { 0.36, 0.38, 0.43, 0.92 },
            btnDefault     = { 0.23, 0.25, 0.29, 0.95 },
            btnPrimary     = { 0.34, 0.38, 0.45, 0.98 },
            btnActive      = { 0.26, 0.52, 0.42, 0.96 },
            btnAccent      = { 0.42, 0.45, 0.52, 0.96 },
            btnBorder      = { 0.45, 0.48, 0.54, 0.90 },
            btnHoverBorder = { 0.82, 0.85, 0.90, 1.0 },
            textMain       = { 0.95, 0.96, 0.98, 1.0 },
            textSub        = { 0.68, 0.71, 0.76, 1.0 },
            accentText     = { 0.86, 0.89, 0.94, 1.0 },
            dayPalette = {
                id             = "minimal_gray",
                nameKey        = "ui_theme_gray",
                bgClear        = { 0.78, 0.80, 0.84, 1.0 },
                panelBg        = { 0.86, 0.88, 0.91, 0.96 },
                panelBorder    = { 0.56, 0.60, 0.66, 0.95 },
                btnDefault     = { 0.74, 0.77, 0.82, 0.96 },
                btnPrimary     = { 0.28, 0.48, 0.78, 0.98 },
                btnActive      = { 0.20, 0.58, 0.42, 0.96 },
                btnAccent      = { 0.50, 0.55, 0.64, 0.96 },
                btnBorder      = { 0.52, 0.56, 0.62, 0.94 },
                btnHoverBorder = { 0.20, 0.38, 0.68, 1.0 },
                textMain       = { 0.12, 0.14, 0.18, 1.0 },
                textSub        = { 0.34, 0.38, 0.44, 1.0 },
                accentText     = { 0.16, 0.34, 0.64, 1.0 },
                unlocked       = true,
                unlockType     = "free",
                price          = 0
            },
            nightPalette = {
                id             = "minimal_gray",
                nameKey        = "ui_theme_gray",
                bgClear        = { 0.14, 0.15, 0.17, 1.0 },
                panelBg        = { 0.18, 0.19, 0.22, 0.95 },
                panelBorder    = { 0.36, 0.38, 0.43, 0.92 },
                btnDefault     = { 0.23, 0.25, 0.29, 0.95 },
                btnPrimary     = { 0.34, 0.38, 0.45, 0.98 },
                btnActive      = { 0.26, 0.52, 0.42, 0.96 },
                btnAccent      = { 0.42, 0.45, 0.52, 0.96 },
                btnBorder      = { 0.45, 0.48, 0.54, 0.90 },
                btnHoverBorder = { 0.82, 0.85, 0.90, 1.0 },
                textMain       = { 0.95, 0.96, 0.98, 1.0 },
                textSub        = { 0.68, 0.71, 0.76, 1.0 },
                accentText     = { 0.86, 0.89, 0.94, 1.0 },
                unlocked       = true,
                unlockType     = "free",
                price          = 0
            },
            unlocked       = true,
            unlockType     = "free",
            price          = 0
        },
        wood_vibe = {
            id = "wood_vibe",
            nameKey = "ui_theme_wood",
            bgClear        = { 0.09, 0.08, 0.07, 1.0 },
            panelBg        = { 0.11, 0.09, 0.08, 0.95 },
            panelBorder    = { 0.48, 0.36, 0.24, 0.92 },
            btnDefault     = { 0.17, 0.14, 0.12, 0.94 },
            btnPrimary     = { 0.56, 0.36, 0.20, 0.96 },
            btnActive      = { 0.22, 0.54, 0.36, 0.96 },
            btnAccent      = { 0.72, 0.50, 0.16, 0.96 },
            btnBorder      = { 0.45, 0.36, 0.26, 0.90 },
            btnHoverBorder = { 0.92, 0.76, 0.46, 1.0 },
            textMain       = { 0.98, 0.92, 0.80, 1.0 },
            textSub        = { 0.78, 0.70, 0.58, 1.0 },
            accentText     = { 0.95, 0.78, 0.35, 1.0 },
            unlocked       = true,
            unlockType     = "free",
            price          = 0
        },
        carbon_dark = {
            id = "carbon_dark",
            nameKey = "ui_theme_obsidian",
            bgClear        = { 0.07, 0.08, 0.10, 1.0 },
            panelBg        = { 0.11, 0.12, 0.15, 0.95 },
            panelBorder    = { 0.26, 0.30, 0.38, 0.92 },
            btnDefault     = { 0.15, 0.17, 0.21, 0.95 },
            btnPrimary     = { 0.22, 0.38, 0.62, 0.96 },
            btnActive      = { 0.20, 0.52, 0.44, 0.96 },
            btnAccent      = { 0.30, 0.46, 0.72, 0.96 },
            btnBorder      = { 0.32, 0.36, 0.46, 0.90 },
            btnHoverBorder = { 0.65, 0.78, 0.98, 1.0 },
            textMain       = { 0.94, 0.96, 1.00, 1.0 },
            textSub        = { 0.62, 0.67, 0.76, 1.0 },
            accentText     = { 0.58, 0.78, 0.98, 1.0 },
            unlocked       = false,
            unlockType     = "coins",
            price          = 100
        },
        white_clean = {
            id = "white_clean",
            nameKey = "ui_theme_white",
            bgClear        = { 0.94, 0.95, 0.97, 1.0 },
            panelBg        = { 0.98, 0.99, 1.00, 0.96 },
            panelBorder    = { 0.78, 0.81, 0.86, 0.95 },
            btnDefault     = { 0.90, 0.92, 0.95, 0.96 },
            btnPrimary     = { 0.24, 0.46, 0.84, 0.98 },
            btnActive      = { 0.18, 0.62, 0.44, 0.96 },
            btnAccent      = { 0.35, 0.42, 0.52, 0.96 },
            btnBorder      = { 0.72, 0.76, 0.82, 0.95 },
            btnHoverBorder = { 0.20, 0.42, 0.78, 1.0 },
            textMain       = { 0.12, 0.14, 0.18, 1.0 },
            textSub        = { 0.38, 0.42, 0.48, 1.0 },
            accentText     = { 0.16, 0.36, 0.72, 1.0 },
            unlocked       = true,
            unlockType     = "free",
            price          = 0
        },
        black_oled = {
            id = "black_oled",
            nameKey = "ui_theme_black",
            bgClear        = { 0.02, 0.02, 0.03, 1.0 },
            panelBg        = { 0.05, 0.05, 0.07, 0.97 },
            panelBorder    = { 0.22, 0.23, 0.27, 0.95 },
            btnDefault     = { 0.09, 0.10, 0.12, 0.96 },
            btnPrimary     = { 0.20, 0.36, 0.60, 0.98 },
            btnActive      = { 0.16, 0.54, 0.40, 0.96 },
            btnAccent      = { 0.28, 0.30, 0.36, 0.96 },
            btnBorder      = { 0.26, 0.28, 0.33, 0.92 },
            btnHoverBorder = { 0.85, 0.88, 0.95, 1.0 },
            textMain       = { 0.96, 0.97, 0.99, 1.0 },
            textSub        = { 0.60, 0.63, 0.69, 1.0 },
            accentText     = { 0.72, 0.84, 1.00, 1.0 },
            unlocked       = true,
            unlockType     = "free",
            price          = 0
        },
        new_year = {
            id = "new_year",
            nameKey = "ui_theme_new_year",
            effect         = "snow",
            bgClear        = { 0.08, 0.14, 0.22, 1.0 },
            panelBg        = { 0.11, 0.18, 0.28, 0.95 },
            panelBorder    = { 0.60, 0.84, 0.98, 0.92 },
            btnDefault     = { 0.16, 0.25, 0.38, 0.95 },
            btnPrimary     = { 0.22, 0.52, 0.78, 0.98 },
            btnActive      = { 0.18, 0.62, 0.44, 0.96 },
            btnAccent      = { 0.78, 0.24, 0.28, 0.96 },
            btnBorder      = { 0.48, 0.72, 0.90, 0.90 },
            btnHoverBorder = { 0.90, 0.97, 1.00, 1.0 },
            textMain       = { 0.96, 0.99, 1.00, 1.0 },
            textSub        = { 0.74, 0.86, 0.96, 1.0 },
            accentText     = { 0.70, 0.92, 1.00, 1.0 },
            unlocked       = true,
            unlockType     = "free",
            price          = 0
        },
        halloween = {
            id = "halloween",
            nameKey = "ui_theme_halloween",
            effect         = "halloween",
            bgClear        = { 0.08, 0.05, 0.12, 1.0 },
            panelBg        = { 0.12, 0.08, 0.17, 0.96 },
            panelBorder    = { 0.88, 0.44, 0.12, 0.92 },
            btnDefault     = { 0.18, 0.12, 0.25, 0.95 },
            btnPrimary     = { 0.82, 0.38, 0.10, 0.98 },
            btnActive      = { 0.54, 0.24, 0.72, 0.96 },
            btnAccent      = { 0.92, 0.52, 0.14, 0.96 },
            btnBorder      = { 0.62, 0.32, 0.14, 0.90 },
            btnHoverBorder = { 1.00, 0.70, 0.24, 1.0 },
            textMain       = { 0.98, 0.94, 0.88, 1.0 },
            textSub        = { 0.78, 0.68, 0.84, 1.0 },
            accentText     = { 1.00, 0.62, 0.20, 1.0 },
            unlocked       = true,
            unlockType     = "free",
            price          = 0
        }
    },

    pieceSkinOrder = {
        "classic_bw",
        "crimson_cobalt",
        "emerald_gold",
        "neon_ad",
        "ivory_ach",
        "gold_silver_rings",
        "iron_blocks",
        "pumpkin_halloween",
        "nuclear_core",
        "glazed_donuts",
        "skyscraper_blocks",
        "billiard_balls",
        "pine_tree",
        "snowman",
        "thin_rings",
        "amber_obsidian"
    },

    pieceSkins = {
        classic_bw = {
            id = "classic_bw",
            nameKey = "skin_bw",
            style = "wood",
            rarity = "common",
            player1Color = { 0.88, 0.82, 0.72, 1.0 },
            player2Color = { 0.19, 0.14, 0.11, 1.0 },
            woodStrength = 0.85,
            specular = 0.32,
            unlocked = true,
            unlockType = "free",
            price = 0
        },
        crimson_cobalt = {
            id = "crimson_cobalt",
            nameKey = "skin_rb",
            style = "wood",
            rarity = "common",
            player1Color = { 0.86, 0.20, 0.22, 1.0 },
            player2Color = { 0.16, 0.36, 0.82, 1.0 },
            woodStrength = 0.75,
            specular = 0.38,
            unlocked = false,
            unlockType = "coins",
            price = 100
        },
        emerald_gold = {
            id = "emerald_gold",
            nameKey = "skin_emerald",
            style = "wood",
            rarity = "common",
            player1Color = { 0.95, 0.56, 0.12, 1.0 }, -- Rich Warm Amber
            player2Color = { 0.12, 0.52, 0.34, 1.0 }, -- Emerald Green
            woodStrength = 0.60,
            specular = 0.50,
            unlocked = false,
            unlockType = "coins",
            price = 100
        },
        gold_silver_rings = {
            id = "gold_silver_rings",
            nameKey = "skin_gold_silver",
            style = "metal_ring",
            rarity = "rare",
            player1Color = { 0.96, 0.78, 0.24, 1.0 }, -- Polished Gold
            player2Color = { 0.82, 0.86, 0.92, 1.0 }, -- Mirror Silver
            woodStrength = 0.08,
            specular = 0.95,
            unlocked = false,
            unlockType = "coins",
            price = 250
        },
        iron_blocks = {
            id = "iron_blocks",
            nameKey = "skin_iron_blocks",
            style = "iron_block",
            rarity = "rare",
            player1Color = { 0.66, 0.70, 0.76, 1.0 }, -- Brushed Grey Steel Metal
            player2Color = { 0.44, 0.29, 0.16, 1.0 }, -- Dark Smoked Bronze Metal
            woodStrength = 0.06,
            specular = 0.94,
            unlocked = false,
            unlockType = "coins",
            price = 250
        },
        nuclear_core = {
            id = "nuclear_core",
            nameKey = "skin_nuclear",
            style = "nuclear",
            rarity = "epic",
            player1Color = { 0.28, 1.00, 0.22, 1.0 }, -- Uranium-235 (glowing & pulsing radiation)
            player2Color = { 0.21, 0.23, 0.26, 1.0 }, -- Reactor Graphite (dark carbon moderator)
            woodStrength = 0.45,
            specular = 0.62,
            unlocked = false,
            unlockType = "coins",
            price = 250
        },
        pumpkin_halloween = {
            id = "pumpkin_halloween",
            nameKey = "skin_pumpkin",
            style = "pumpkin",
            rarity = "super_rare",
            player1Color = { 0.96, 0.44, 0.08, 1.0 }, -- Classic Jack-o-Lantern Orange
            player2Color = { 0.34, 0.18, 0.46, 1.0 }, -- Midnight Witch Pumpkin
            woodStrength = 0.35,
            specular = 0.45,
            unlocked = false,
            unlockType = "coins",
            price = 250
        },
        glazed_donuts = {
            id = "glazed_donuts",
            nameKey = "skin_donut",
            style = "donut",
            rarity = "epic",
            player1Color = { 0.98, 0.95, 0.92, 1.0 }, -- White icing glaze on golden donut
            player2Color = { 0.24, 0.12, 0.06, 1.0 }, -- Dark chocolate glaze on pastry donut
            woodStrength = 0.25,
            specular = 0.78,
            unlocked = false,
            unlockType = "coins",
            price = 500
        },
        skyscraper_blocks = {
            id = "skyscraper_blocks",
            nameKey = "skin_skyscraper_blocks",
            style = "skyscraper_block",
            rarity = "epic",
            player1Color = { 0.82, 0.86, 0.94, 1.0 }, -- Lit Skyscraper Blocks (lights ON)
            player2Color = { 0.22, 0.26, 0.34, 1.0 }, -- Unlit Skyscraper Blocks (same building style, lights OFF)
            woodStrength = 0.0,
            specular = 0.88,
            unlocked = false,
            unlockType = "coins",
            price = 500
        },
        billiard_balls = {
            id = "billiard_balls",
            nameKey = "skin_billiard_balls",
            style = "billiard_ball",
            rarity = "epic",
            player1Color = { 0.90, 0.14, 0.12, 1.0 }, -- Solid colored pool balls (1..7, no black/white)
            player2Color = { 0.10, 0.36, 0.90, 1.0 }, -- Striped colored pool balls (9..15, ivory shell + colored band)
            woodStrength = 0.0,
            specular = 0.98,
            unlocked = false,
            unlockType = "coins",
            price = 500
        },
        pine_tree = {
            id = "pine_tree",
            nameKey = "skin_pine",
            style = "pine",
            rarity = "legendary",
            taperByHeight = true, -- Снизу шире, сверху уже -> складывается в 3D-ёлку
            player1Color = { 0.05, 0.85, 0.28, 1.0 }, -- Яркий насыщенный изумрудно-зеленый
            player2Color = { 0.08, 0.55, 1.00, 1.0 }, -- Яркий насыщенный королевский синий
            woodStrength = 0.40,
            specular = 0.35,
            unlocked = false,
            unlockType = "coins",
            price = 1000
        },
        snowman = {
            id = "snowman",
            nameKey = "skin_snowman",
            style = "snowman",
            rarity = "legendary",
            player1Color = { 0.99, 0.99, 1.00, 1.0 }, -- Pure Snow White
            player2Color = { 0.56, 0.60, 0.66, 1.0 }, -- Cool Grey Snowman
            woodStrength = 0.20,
            specular = 0.38,
            unlocked = false,
            unlockType = "coins",
            price = 1000
        },
        thin_rings = {
            id = "thin_rings",
            nameKey = "skin_thin_rings",
            style = "thin_ring",
            underRework = true,
            player1Color = { 0.92, 0.94, 0.96, 1.0 },
            player2Color = { 0.18, 0.20, 0.24, 1.0 },
            woodStrength = 0.15,
            specular = 0.72,
            unlocked = false,
            unlockType = "rework",
            price = 0
        },
        amber_obsidian = {
            id = "amber_obsidian",
            nameKey = "skin_amber",
            style = "wood",
            underRework = true,
            player1Color = { 0.92, 0.62, 0.16, 1.0 },
            player2Color = { 0.16, 0.13, 0.22, 1.0 },
            woodStrength = 0.65,
            specular = 0.45,
            unlocked = false,
            unlockType = "rework",
            price = 0
        },
        neon_ad = {
            id = "neon_ad",
            nameKey = "skin_ad",
            player1Color = { 0.20, 0.86, 0.96, 1.0 },
            player2Color = { 0.94, 0.22, 0.56, 1.0 },
            woodStrength = 0.20,
            specular = 0.65,
            unlocked = false,
            unlockType = "ad",
            price = 0
        },
        ivory_ach = {
            id = "ivory_ach",
            nameKey = "skin_ach",
            player1Color = { 0.96, 0.94, 0.88, 1.0 },
            player2Color = { 0.28, 0.22, 0.18, 1.0 },
            woodStrength = 0.50,
            specular = 0.55,
            unlocked = false,
            unlockType = "ach",
            price = 0
        }
    },

    boardSkinOrder = {
        "dark_wood",
        "white_wood",
        "metal_steel",
        "obsidian_stub",
        "forest_glade",
        "gold_ach",
        "snowy_winter",
        "sweet_cake",
        "chernobyl",
        "billiard_table",
        "manhattan",
        "japanese_roof",
        "skyscraper"
    },

    boardSkins = {
        dark_wood = {
            id = "dark_wood",
            nameKey = "board_dark_wood",
            style = "wood",
            rarity = "common",
            soundType = "wood",
            baseColor = { 0.30, 0.19, 0.12, 1.0 },
            pegColor  = { 0.38, 0.25, 0.16, 1.0 },
            pegHover  = { 0.88, 0.68, 0.32, 1.0 },
            woodStrength = 1.0,
            unlocked = true,
            unlockType = "free",
            price = 0
        },
        white_wood = {
            id = "white_wood",
            nameKey = "board_white_wood",
            style = "wood",
            rarity = "common",
            soundType = "light_wood",
            baseColor = { 0.88, 0.85, 0.79, 1.0 },
            pegColor  = { 0.82, 0.78, 0.71, 1.0 },
            pegHover  = { 0.95, 0.74, 0.30, 1.0 },
            woodStrength = 0.85,
            unlocked = false,
            unlockType = "coins",
            price = 100
        },
        metal_steel = {
            id = "metal_steel",
            nameKey = "board_metal",
            style = "metal",
            rarity = "common",
            soundType = "metal",
            baseColor = { 0.44, 0.48, 0.54, 1.0 }, -- Brushed industrial steel base
            pegColor  = { 0.68, 0.73, 0.80, 1.0 }, -- Polished chrome/steel rods
            pegHover  = { 0.45, 0.86, 1.00, 1.0 },
            woodStrength = 0.12,
            unlocked = false,
            unlockType = "coins",
            price = 200
        },
        gold_ach = {
            id = "gold_ach",
            nameKey = "board_gold",
            style = "metal",
            soundType = "metal",
            rarity = "super_rare",
            baseColor = { 0.96, 0.80, 0.22, 1.0 }, -- Чистое сияющее золото 24K
            pegColor  = { 0.98, 0.86, 0.36, 1.0 }, -- Золотые полированные штыри
            pegHover  = { 1.00, 0.96, 0.65, 1.0 },
            woodStrength = 0.02,
            unlocked = false,
            unlockType = "coins",
            price = 300
        },
        sweet_cake = {
            id = "sweet_cake",
            nameKey = "board_cake",
            style = "cake",
            rarity = "epic",
            soundType = "cake",
            baseColor = { 0.96, 0.74, 0.82, 1.0 }, -- Strawberry-vanilla cake frosting & sponge layers
            pegColor  = { 0.84, 0.60, 0.34, 1.0 }, -- Crispy chocolate-striped wafer roll sticks
            pegHover  = { 1.00, 0.50, 0.74, 1.0 },
            woodStrength = 0.20,
            unlocked = false,
            unlockType = "coins",
            price = 400
        },
        chernobyl = {
            id = "chernobyl",
            nameKey = "board_chernobyl",
            style = "chernobyl",
            rarity = "epic",
            soundType = "metal",
            forceSquare = true,
            baseColor = { 0.31, 0.33, 0.35, 1.0 }, -- Weathered Chernobyl Unit 4 concrete roof
            pegColor  = { 0.48, 0.50, 0.52, 1.0 }, -- Wide industrial smoking chimneys
            pegHover  = { 0.98, 0.80, 0.16, 1.0 },
            woodStrength = 0.06,
            unlocked = false,
            unlockType = "coins",
            price = 600
        },
        billiard_table = {
            id = "billiard_table",
            nameKey = "board_billiard",
            style = "billiard",
            rarity = "epic",
            soundType = "billiard",
            forceSquare = true,
            baseColor = { 0.06, 0.44, 0.24, 1.0 }, -- Emerald green billiard cloth + mahogany rails
            pegColor  = { 0.88, 0.78, 0.58, 1.0 }, -- Tapered pool cues with chalked tips
            pegHover  = { 0.98, 0.84, 0.28, 1.0 },
            woodStrength = 0.08,
            unlocked = false,
            unlockType = "coins",
            price = 550
        },
        snowy_winter = {
            id = "snowy_winter",
            nameKey = "board_snow",
            style = "snow",
            rarity = "super_rare",
            soundType = "forest",
            baseColor = { 0.94, 0.97, 1.00, 1.0 },
            pegColor  = { 0.80, 0.88, 0.96, 1.0 },
            pegHover  = { 0.42, 0.78, 1.00, 1.0 },
            woodStrength = 0.15,
            unlocked = false,
            unlockType = "coins",
            price = 500
        },
        forest_glade = {
            id = "forest_glade",
            nameKey = "board_forest",
            style = "forest",
            rarity = "rare",
            upgradeable = true,
            winsRequired = 10,
            soundType = "forest",
            baseColor = { 0.20, 0.46, 0.17, 1.0 }, -- Forest grass & moss around trunks
            pegColor  = { 0.35, 0.22, 0.12, 1.0 }, -- Tree trunk bark
            pegHover  = { 0.62, 0.90, 0.32, 1.0 },
            woodStrength = 0.95,
            unlocked = false,
            unlockType = "coins",
            price = 1000
        },
        obsidian_stub = {
            id = "obsidian_stub",
            nameKey = "board_obsidian",
            style = "stone",
            rarity = "rare",
            soundType = "stone",
            baseColor = { 0.16, 0.17, 0.21, 1.0 },
            pegColor  = { 0.32, 0.34, 0.40, 1.0 },
            pegHover  = { 0.55, 0.78, 0.98, 1.0 },
            woodStrength = 0.35,
            unlocked = false,
            unlockType = "coins",
            price = 200
        },
        japanese_roof = {
            id = "japanese_roof",
            nameKey = "board_japanese",
            style = "japanese_roof",
            soundType = "wood",
            hasMist = true,
            underRework = true,
            baseColor = { 0.20, 0.23, 0.28, 1.0 }, -- Slate ceramic roof tiles
            pegColor  = { 0.74, 0.18, 0.16, 1.0 }, -- Vermilion torii-red wooden pillars
            pegHover  = { 1.00, 0.56, 0.24, 1.0 },
            woodStrength = 0.45,
            unlocked = false,
            unlockType = "rework",
            price = 0
        },
        skyscraper = {
            id = "skyscraper",
            nameKey = "board_skyscraper",
            style = "skyscraper",
            soundType = "metal",
            hasMist = true,
            underRework = true,
            baseColor = { 0.36, 0.46, 0.58, 1.0 }, -- Trade tower glass & steel roof
            pegColor  = { 0.78, 0.84, 0.90, 1.0 }, -- Radio/spire antennas
            pegHover  = { 0.40, 0.88, 1.00, 1.0 },
            woodStrength = 0.15,
            unlocked = false,
            unlockType = "rework",
            price = 0
        },
        manhattan = {
            id = "manhattan",
            nameKey = "board_manhattan",
            style = "manhattan",
            soundType = "metal",
            rarity = "legendary",
            hasMist = false,
            baseColor = { 0.08, 0.09, 0.13, 1.0 }, -- Night Manhattan glass towers
            pegColor  = { 0.65, 0.70, 0.78, 1.0 }, -- Slender spire antennas with blinking red beacons
            pegHover  = { 1.00, 0.45, 0.38, 1.0 },
            woodStrength = 0.08,
            unlocked = true,
            unlockType = "free",
            price = 0
        }
    },

    currencyPacks = {
        { id = "p1", coins = 100,   price = "$0.99",  bonus = "1 Skin"      },
        { id = "p2", coins = 330,   price = "$2.99",  bonus = "+10% Bonus"  },
        { id = "p3", coins = 600,   price = "$4.99",  bonus = "+20% Bonus"  },
        { id = "p4", coins = 1300,  price = "$9.99",  bonus = "+30% Bonus"  },
        { id = "p5", coins = 2800,  price = "$19.99", bonus = "+40% Bonus"  },
        { id = "p6", coins = 7500,  price = "$49.99", bonus = "+50% Value"  },
        { id = "p7", coins = 16000, price = "$99.99", bonus = "+60% VIP"    }
    }
}

function Config.getPieceSkin()
    return Config.pieceSkins[Config.activePieceSkin] or Config.pieceSkins.classic_bw
end

function Config.getBoardSkin()
    return Config.boardSkins[Config.activeBoardSkin] or Config.boardSkins.dark_wood
end

function Config.getUITheme(hourOverride)
    local th = Config.uiThemes[Config.activeUITheme] or Config.uiThemes.minimal_gray
    if th.adaptiveDayNight and th.dayPalette and th.nightPalette then
        local hour = hourOverride
        if hour == nil then
            local dt = os.date("*t")
            hour = (dt and dt.hour) or 12
        end
        if hour >= 7 and hour < 19 then
            return th.dayPalette
        end
        return th.nightPalette
    end
    return th
end

-- Strict Validation Rules:
-- Username: 3..12 chars, English letters & digits ONLY (no spaces, hyphens, underscores, or special symbols)
function Config.validateUsername(u)
    if type(u) ~= "string" then return false end
    if #u < 3 or #u > 12 then return false end
    return u:match("^[A-Za-z0-9]+$") ~= nil
end

-- Email: standard email pattern
function Config.validateEmail(e)
    if type(e) ~= "string" then return false end
    return e:match("^[A-Za-z0-9._%%+%-]+@[A-Za-z0-9.%-]+%.[A-Za-z][A-Za-z]+$") ~= nil
end

-- Password: min 10 chars, must contain at least 1 letter, 1 digit, and 1 special character
function Config.validatePassword(pw)
    if type(pw) ~= "string" then return false end
    if #pw < 10 then return false end
    local hasLetter  = pw:match("[A-Za-z]") ~= nil
    local hasDigit   = pw:match("[0-9]") ~= nil
    local hasSpecial = pw:match("[^A-Za-z0-9%s]") ~= nil
    return hasLetter and hasDigit and hasSpecial
end

function Config.registerAccount(username, password, confirmPassword)
    if not Config.validateUsername(username) then
        return false, "err_username"
    end
    local lowerU = username:lower()
    for existingU, acc in pairs(Config.registeredAccounts) do
        if existingU:lower() == lowerU then
            return false, "err_username_taken"
        end
    end
    if not Config.validatePassword(password) then
        return false, "err_password"
    end
    if password ~= confirmPassword then
        return false, "err_password_mismatch"
    end

    local userNum = FirebaseClient.claimNextUserNumber()
    local nowTs = os.time()
    local newAcc = {
        username               = username,
        password               = password,
        bio                    = "",
        avatarPreset           = 1,
        customAvatarFile       = nil,
        isRegistered           = true,
        userNumber             = userNum,
        createdAt              = nowTs,
        createdAtStr           = os.date("%d.%m.%Y", nowTs),
        lastUsernameChangeTime = nowTs,
        rating                 = 800,
        ratingHistory          = { 800 },
        ratings                = { std_bullet = 800, std_blitz = 800, free_bullet = 800, free_blitz = 800 },
        ratingHistories        = { std_bullet = { 800 }, std_blitz = { 800 }, free_bullet = { 800 }, free_blitz = { 800 } },
        gamesPlayed            = 0,
        wins                   = 0,
        losses                 = 0,
        draws                  = 0,
        winStreak              = 0,
        skinWins               = {},
        boardWins              = {},
        recentMatches          = {},
        friends                = {},
        incomingRequests       = {},
        sentRequests           = {},
        blockedUsers           = {},
        tournamentHistory      = {},
        achievements           = {
            bot_easy       = false,
            bot_medium     = false,
            bot_hard       = false,
            wins_10        = false,
            wins_100       = false,
            wins_1000      = false,
            first_friend   = false,
            pioneer_1000   = (userNum <= 1000),
            tournament_win = false
        }
    }
    Config.registeredAccounts[username] = newAcc
    Config.profile = newAcc
    FirebaseClient.registerUser(username, username .. "@connect4.local", password, newAcc)
    return true, nil
end

function Config.loginAccount(username, password)
    for _, acc in pairs(Config.registeredAccounts) do
        if acc.username:lower() == username:lower() and acc.password == password then
            Config.ensureProfileFields(acc)
            Config.profile = acc
            Config.profile.isRegistered = true
            FirebaseClient.signInUser(acc.username .. "@connect4.local", password)
            return true, nil
        end
    end

    -- Fallback: try cross-device login from Firebase Realtime Database
    local remoteProf = FirebaseClient.fetchUserProfile(username)
    if remoteProf then
        local restoredAcc = {
            username               = remoteProf.username,
            password               = password,
            bio                    = remoteProf.bio or "",
            avatarPreset           = 1,
            customAvatarFile       = nil,
            isRegistered           = true,
            userNumber             = remoteProf.userNumber or 9999,
            createdAt              = (remoteProf.createdAt and remoteProf.createdAt > 0) and remoteProf.createdAt or os.time(),
            createdAtStr           = (remoteProf.createdAtStr and #remoteProf.createdAtStr > 0) and remoteProf.createdAtStr or os.date("%d.%m.%Y"),
            lastUsernameChangeTime = remoteProf.lastUsernameChangeTime or 0,
            rating                 = remoteProf.rating or 800,
            ratingHistory          = { 800, remoteProf.rating or 800 },
            ratings                = remoteProf.ratings or { std_bullet = 800, std_blitz = remoteProf.rating or 800, free_bullet = 800, free_blitz = 800 },
            ratingHistories        = { std_bullet = { 800 }, std_blitz = { 800, remoteProf.rating or 800 }, free_bullet = { 800 }, free_blitz = { 800 } },
            gamesPlayed            = remoteProf.gamesPlayed or 0,
            wins                   = remoteProf.wins or 0,
            losses                 = remoteProf.losses or 0,
            draws                  = remoteProf.draws or 0,
            winStreak              = 0,
            skinWins               = {},
            boardWins              = {},
            recentMatches          = {},
            friends                = {},
            incomingRequests       = {},
            sentRequests           = {},
            blockedUsers           = {},
            tournamentHistory      = {},
            achievements           = {
                bot_easy       = false,
                bot_medium     = false,
                bot_hard       = false,
                wins_10        = (remoteProf.wins or 0) >= 10,
                wins_100       = (remoteProf.wins or 0) >= 100,
                wins_1000      = (remoteProf.wins or 0) >= 1000,
                first_friend   = false,
                pioneer_1000   = (remoteProf.userNumber or 9999) <= 1000,
                tournament_win = false
            }
        }
        Config.registeredAccounts[restoredAcc.username] = restoredAcc
        Config.profile = restoredAcc
        return true, nil
    end

    return false, "err_login_failed"
end

function Config.updateRegisteredProfile(newUsername, newPassword, newBio, newAvatarPreset, newCustomAvatarFile)
    local cur = Config.profile
    if newUsername ~= cur.username then
        if not Config.validateUsername(newUsername) then
            return false, "err_username"
        end
        local lowerU = newUsername:lower()
        for existingU, acc in pairs(Config.registeredAccounts) do
            if acc ~= cur and existingU:lower() == lowerU then
                return false, "err_username_taken"
            end
        end

        local now = os.time()
        local lastChange = cur.lastUsernameChangeTime or 0
        local cooldown = 7 * 86400
        if (now - lastChange) < cooldown and lastChange > 0 then
            local remDays = math.ceil((cooldown - (now - lastChange)) / 86400)
            return false, "err_username_cooldown", remDays
        end
        cur.lastUsernameChangeTime = now
        Config.registeredAccounts[cur.username] = nil
        cur.username = newUsername
        Config.registeredAccounts[newUsername] = cur
    end

    if newPassword and #newPassword > 0 and newPassword ~= cur.password then
        if not Config.validatePassword(newPassword) then
            return false, "err_password"
        end
        cur.password = newPassword
    end
    cur.bio = newBio or ""
    if newAvatarPreset then
        cur.avatarPreset = newAvatarPreset
    end
    if newCustomAvatarFile ~= nil then
        cur.customAvatarFile = newCustomAvatarFile
    end
    FirebaseClient.syncProfile(cur.username, cur)
    return true, nil
end

function Config.ensureProfileFields(p)
    if not p then return end
    p.ratings = p.ratings or {
        std_bullet  = 800,
        std_blitz   = p.rating or 800,
        free_bullet = 800,
        free_blitz  = 800
    }
    p.ratings.std_bullet  = p.ratings.std_bullet  or 800
    p.ratings.std_blitz   = p.ratings.std_blitz   or (p.rating or 800)
    p.ratings.free_bullet = p.ratings.free_bullet or 800
    p.ratings.free_blitz  = p.ratings.free_blitz  or 800

    p.ratingHistories = p.ratingHistories or {
        std_bullet  = { 800 },
        std_blitz   = p.ratingHistory or { 800 },
        free_bullet = { 800 },
        free_blitz  = { 800 }
    }
    p.ratingHistories.std_bullet  = p.ratingHistories.std_bullet  or { 800 }
    p.ratingHistories.std_blitz   = p.ratingHistories.std_blitz   or { 800 }
    p.ratingHistories.free_bullet = p.ratingHistories.free_bullet or { 800 }
    p.ratingHistories.free_blitz  = p.ratingHistories.free_blitz  or { 800 }

    p.winStreak         = p.winStreak or 0
    p.skinWins          = p.skinWins or {}
    p.boardWins         = p.boardWins or {}
    p.recentMatches     = p.recentMatches or {}
    p.friends           = p.friends or {}
    p.incomingRequests  = p.incomingRequests or {}
    p.sentRequests      = p.sentRequests or {}
    p.blockedUsers      = p.blockedUsers or {}
    p.tournamentHistory = p.tournamentHistory or {}
    p.achievements      = p.achievements or {}
    if p.isRegistered then
        if not p.createdAt or p.createdAt <= 0 then
            p.createdAt = os.time()
        end
        if not p.createdAtStr or p.createdAtStr == "" then
            p.createdAtStr = os.date("%d.%m.%Y", p.createdAt)
        end
    end
end

function Config.getEloKey(ruleMode, timeMinutes)
    local prefix = (ruleMode == "free") and "free" or "std"
    local suffix = (timeMinutes == 1) and "bullet" or "blitz"
    return prefix .. "_" .. suffix
end

function Config.logoutAccount()
    Config.profile = {
        username         = "Guest_" .. tostring(math.random(1000, 9999)),
        email            = "",
        password         = "",
        bio              = "",
        avatarPreset     = 1,
        customAvatarFile = nil,
        isRegistered     = false,
        userNumber       = 9999,
        rating           = 800,
        ratingHistory    = { 800 },
        ratings          = { std_bullet = 800, std_blitz = 800, free_bullet = 800, free_blitz = 800 },
        ratingHistories  = { std_bullet = { 800 }, std_blitz = { 800 }, free_bullet = { 800 }, free_blitz = { 800 } },
        gamesPlayed      = 0,
        wins             = 0,
        losses           = 0,
        draws            = 0,
        winStreak        = 0,
        skinWins         = {},
        boardWins        = {},
        recentMatches    = {},
        friends          = {},
        incomingRequests = {},
        sentRequests     = {},
        blockedUsers     = {},
        tournamentHistory = {},
        achievements     = {
            bot_easy       = false,
            bot_medium     = false,
            bot_hard       = false,
            wins_10        = false,
            wins_100       = false,
            wins_1000      = false,
            first_friend   = false,
            pioneer_1000   = false,
            tournament_win = false
        }
    }
end

Config.RARITY_RANK = {
    common     = 1,
    rare       = 2,
    super_rare = 3,
    epic       = 4,
    legendary  = 5
}

function Config.getSortedOrder(orderList, lookupMap, sortMode)
    local out = {}
    local idxMap = {}
    for i, id in ipairs(orderList) do
        table.insert(out, id)
        idxMap[id] = i
    end
    local isDesc = (sortMode == "rarity_desc")
    table.sort(out, function(a, b)
        local sa, sb = lookupMap[a], lookupMap[b]
        local wa = (sa and sa.underRework) and 1 or 0
        local wb = (sb and sb.underRework) and 1 or 0
        if wa ~= wb then return wa < wb end
        local ra = Config.RARITY_RANK[sa and sa.rarity or "common"] or 1
        local rb = Config.RARITY_RANK[sb and sb.rarity or "common"] or 1
        if ra ~= rb then
            if isDesc then return ra > rb else return ra < rb end
        end
        return (idxMap[a] or 0) < (idxMap[b] or 0)
    end)
    return out
end

function Config.ensureDailyProgress(todayOverride)
    local today = todayOverride or os.date("%Y-%m-%d")
    if type(Config.dailyProgress) ~= "table" or Config.dailyProgress.dateStr ~= today then
        Config.dailyProgress = {
            dateStr     = today,
            coinsEarned = 0,
            pvpWins     = 0
        }
    end
    Config.dailyProgress.coinsEarned = math.max(0, math.floor(Config.dailyProgress.coinsEarned or 0))
    Config.dailyProgress.pvpWins     = math.max(0, math.floor(Config.dailyProgress.pvpWins or 0))
    return Config.dailyProgress
end

function Config.earnDailyCoins(requestedAmount, isPvpWin, todayOverride)
    local dp = Config.ensureDailyProgress(todayOverride)
    local cap = Config.DAILY_COIN_LIMIT or 100
    local remaining = math.max(0, cap - dp.coinsEarned)
    local amount = math.max(0, math.floor(requestedAmount or 0))
    if isPvpWin then
        if dp.pvpWins >= 10 then
            amount = 0
        else
            dp.pvpWins = dp.pvpWins + 1
        end
    end
    local granted = math.min(amount, remaining)
    if granted > 0 then
        Config.coins = Config.coins + granted
        dp.coinsEarned = dp.coinsEarned + granted
    end
    return granted, dp.coinsEarned, cap
end

function Config.recordMatchResult(mode, winnerPlayer, isDraw, lineTypeKey, totalHalfMoves, durationSec, moveHistoryCopy, opponentName)
    local p = Config.profile
    Config.ensureProfileFields(p)
    local dp = Config.ensureDailyProgress()
    p.gamesPlayed = p.gamesPlayed + 1

    -- Determine whether the human/primary player won
    local trackedPlayer = ((mode == Config.GameMode.VS_BOT or mode == Config.GameMode.LAN or mode == Config.GameMode.ONLINE) and Config.humanPlayer) or 1
    local playerWon = (not isDraw) and (winnerPlayer == trackedPlayer)

    local deltaRating = 0
    local coinRewardInfo = {
        earned     = 0,
        dailyTotal = dp.coinsEarned,
        dailyCap   = Config.DAILY_COIN_LIMIT or 100,
        pvpWins    = dp.pvpWins
    }
    local resKey = "res_draw"
    local eloKey = Config.getEloKey(Config.ruleMode, Config.onlineTimeMinutes)

    if isDraw then
        p.draws = p.draws + 1
        p.winStreak = 0
        resKey = "res_draw"
    elseif playerWon then
        p.wins = p.wins + 1
        p.winStreak = (p.winStreak or 0) + 1

        -- Начисление монет за победу (строго до дневного лимита 100 монет из любых источников)
        if mode == Config.GameMode.VS_BOT then
            local botReward = (Config.botDifficulty == 3 and 5) or (Config.botDifficulty == 2 and 2) or 1
            local earned, dTotal, dCap = Config.earnDailyCoins(botReward, false)
            coinRewardInfo.earned = earned
            coinRewardInfo.dailyTotal = dTotal
            coinRewardInfo.dailyCap = dCap
        else
            local earned, dTotal, dCap = Config.earnDailyCoins(10, true)
            coinRewardInfo.earned = earned
            coinRewardInfo.dailyTotal = dTotal
            coinRewardInfo.dailyCap = dCap
        end
        coinRewardInfo.pvpWins = dp.pvpWins

        -- Achievements & Skin wins are ONLY recorded for registered accounts (Guest achievements do NOT count!)
        if p.isRegistered then
            local sk = Config.activePieceSkin or "classic_bw"
            p.skinWins[sk] = (p.skinWins[sk] or 0) + 1
            local bsk = Config.activeBoardSkin or "classic_wood"
            p.boardWins = p.boardWins or {}
            p.boardWins[bsk] = (p.boardWins[bsk] or 0) + 1

            if mode == Config.GameMode.VS_BOT then
                if Config.botDifficulty == 1 then p.achievements.bot_easy = true end
                if Config.botDifficulty == 2 then p.achievements.bot_medium = true end
                if Config.botDifficulty == 3 then p.achievements.bot_hard = true end
            end
            if p.wins >= 10   then p.achievements.wins_10 = true end
            if p.wins >= 100  then p.achievements.wins_100 = true end
            if p.wins >= 1000 then p.achievements.wins_1000 = true end
        end

        -- ELO changes ONLY in Online mode AND ONLY when user is registered!
        if mode == Config.GameMode.ONLINE and p.isRegistered then
            deltaRating = 10
        end
        resKey = "res_victory"
    else
        p.losses = p.losses + 1
        p.winStreak = 0
        if mode == Config.GameMode.ONLINE and p.isRegistered then
            deltaRating = -10
        end
        resKey = "res_defeat"
    end

    if not p.isRegistered then
        p.rating = 800
        p.ratingHistory = { 800 }
        p.ratings = { std_bullet = 800, std_blitz = 800, free_bullet = 800, free_blitz = 800 }
        p.ratingHistories = { std_bullet = { 800 }, std_blitz = { 800 }, free_bullet = { 800 }, free_blitz = { 800 } }
    elseif deltaRating ~= 0 then
        local curR = p.ratings[eloKey] or 800
        local newR = math.max(100, curR + deltaRating)
        p.ratings[eloKey] = newR
        table.insert(p.ratingHistories[eloKey], newR)
        p.rating = p.ratings.std_blitz or newR
        p.ratingHistory = p.ratingHistories.std_blitz
    end

    local fullMoves = math.max(1, math.ceil(totalHalfMoves / 2))
    local dateStr = os.date("%d.%m.%Y %H:%M")
    -- Duration is recorded ONLY for non-bot matches (Offline PvP, LAN, Online)
    local recordedDuration = (mode ~= Config.GameMode.VS_BOT) and math.max(1, math.floor(durationSec or 0)) or nil

    -- Store compact copy of moveHistory so any game can be replayed from Match History
    local savedMoves = nil
    if type(moveHistoryCopy) == "table" and #moveHistoryCopy > 0 then
        savedMoves = {}
        for _, mv in ipairs(moveHistoryCopy) do
            table.insert(savedMoves, {
                x = mv.x, y = mv.y, z = mv.z, player = mv.player, notation = mv.notation
            })
        end
    end

    local matchEntry = {
        username     = p.username,
        opponent     = opponentName,
        mode         = mode,
        ruleMode     = Config.ruleMode,
        botDiff      = Config.botDifficulty,
        resKey       = resKey,
        won          = playerWon,
        draw         = isDraw and true or false,
        moves        = fullMoves,
        delta        = deltaRating,
        dateStr      = dateStr,
        durationSec  = recordedDuration,
        movesList    = savedMoves
    }
    -- Keep ALL matches in history so user can scroll all the way back to the 1st game!
    table.insert(p.recentMatches, 1, matchEntry)

    FirebaseClient.pushMatchRecord(matchEntry)
    if p.isRegistered then
        FirebaseClient.syncProfile(p.username, p)
    end

    return deltaRating, coinRewardInfo
end

function Config.recordTournamentWin(tournamentData)
    local p = Config.profile
    if not p.isRegistered or not tournamentData or tournamentData.isBotTournament then
        return
    end
    Config.ensureProfileFields(p)
    p.achievements.tournament_win = true
    table.insert(p.tournamentHistory, 1, {
        code       = tournamentData.code,
        system     = tournamentData.system,
        ruleMode   = tournamentData.ruleMode,
        timeMin    = tournamentData.timeMinutes,
        players    = #tournamentData.players,
        dateStr    = os.date("%d.%m.%Y %H:%M"),
        battles    = tournamentData.humanMatches or {}
    })
end

-- Friends / Requests / Block System (Works across local registered accounts + Firebase lookup)
local function listContains(tbl, val)
    for idx, v in ipairs(tbl) do
        if v:lower() == val:lower() then return idx end
    end
    return nil
end

function Config.findUserByUsername(username)
    if type(username) ~= "string" or username == "" then return nil end
    local lowerU = username:lower()
    for _, acc in pairs(Config.registeredAccounts) do
        if acc.username and acc.username:lower() == lowerU then
            Config.ensureProfileFields(acc)
            return acc
        end
    end
    local remote = FirebaseClient.fetchUserProfile(username)
    if remote then
        Config.ensureProfileFields(remote)
        return remote
    end
    return nil
end

Config.MAX_FRIENDS = 50

function Config.sendFriendRequest(targetName)
    local p = Config.profile
    if not p.isRegistered then return false, "err_need_register" end
    Config.ensureProfileFields(p)
    if #(p.friends or {}) >= Config.MAX_FRIENDS then
        return false, "err_friends_limit"
    end
    if not targetName or targetName == "" or targetName:lower() == p.username:lower() then
        return false, "friend_not_found"
    end
    if listContains(p.blockedUsers, targetName) then
        return false, "friend_blocked"
    end
    if listContains(p.friends, targetName) then
        return false, "friend_already"
    end
    if listContains(p.sentRequests, targetName) then
        return false, "friend_req_sent"
    end
    local target = Config.findUserByUsername(targetName)
    if not target then
        return false, "friend_not_found"
    end
    if listContains(target.blockedUsers or {}, p.username) then
        return false, "friend_blocked"
    end
    if #(target.friends or {}) >= Config.MAX_FRIENDS then
        return false, "err_friends_limit"
    end
    table.insert(p.sentRequests, 1, target.username)
    if Config.registeredAccounts[target.username] then
        Config.ensureProfileFields(Config.registeredAccounts[target.username])
        if not listContains(Config.registeredAccounts[target.username].incomingRequests, p.username) then
            table.insert(Config.registeredAccounts[target.username].incomingRequests, 1, p.username)
        end
    end
    FirebaseClient.sendFriendRequestRemote(p.username, target.username)
    return true, "friend_req_sent"
end

function Config.acceptFriendRequest(fromName)
    local p = Config.profile
    if not p.isRegistered then return false, "err_need_register" end
    Config.ensureProfileFields(p)
    if #(p.friends or {}) >= Config.MAX_FRIENDS and not listContains(p.friends, fromName) then
        return false, "err_friends_limit"
    end
    local idx = listContains(p.incomingRequests, fromName)
    if idx then table.remove(p.incomingRequests, idx) end
    if not listContains(p.friends, fromName) then
        table.insert(p.friends, 1, fromName)
    end
    p.achievements.first_friend = true
    local other = Config.registeredAccounts[fromName]
    if other then
        Config.ensureProfileFields(other)
        local sIdx = listContains(other.sentRequests, p.username)
        if sIdx then table.remove(other.sentRequests, sIdx) end
        if #(other.friends or {}) < Config.MAX_FRIENDS and not listContains(other.friends, p.username) then
            table.insert(other.friends, 1, p.username)
        end
        other.achievements.first_friend = true
    end
    FirebaseClient.acceptFriendRequestRemote(p.username, fromName)
    FirebaseClient.syncProfile(p.username, p)
    return true, nil
end

function Config.declineFriendRequest(fromName)
    local p = Config.profile
    if not p.isRegistered then return false, "err_need_register" end
    Config.ensureProfileFields(p)
    local idx = listContains(p.incomingRequests, fromName)
    if idx then table.remove(p.incomingRequests, idx) end
    local other = Config.registeredAccounts[fromName]
    if other then
        Config.ensureProfileFields(other)
        local sIdx = listContains(other.sentRequests, p.username)
        if sIdx then table.remove(other.sentRequests, sIdx) end
    end
    FirebaseClient.declineFriendRequestRemote(p.username, fromName)
    return true, nil
end

function Config.removeFriend(targetName)
    local p = Config.profile
    if not p.isRegistered then return false, "err_need_register" end
    Config.ensureProfileFields(p)
    local idx = listContains(p.friends, targetName)
    if idx then table.remove(p.friends, idx) end
    local other = Config.registeredAccounts[targetName]
    if other then
        Config.ensureProfileFields(other)
        local oIdx = listContains(other.friends, p.username)
        if oIdx then table.remove(other.friends, oIdx) end
    end
    FirebaseClient.removeFriendRemote(p.username, targetName)
    return true, nil
end

function Config.syncIncomingFriendMailbox()
    local p = Config.profile
    if not p.isRegistered then return {} end
    Config.ensureProfileFields(p)
    local box = FirebaseClient.pollFriendBox(p.username)
    for _, fromName in ipairs(box.incoming or {}) do
        if not listContains(p.blockedUsers, fromName)
           and not listContains(p.friends, fromName)
           and not listContains(p.incomingRequests, fromName) then
            table.insert(p.incomingRequests, 1, fromName)
        end
    end
    for _, accName in ipairs(box.accepted or {}) do
        local sIdx = listContains(p.sentRequests, accName)
        if sIdx then table.remove(p.sentRequests, sIdx) end
        if #(p.friends or {}) < Config.MAX_FRIENDS and not listContains(p.friends, accName) then
            table.insert(p.friends, 1, accName)
            p.achievements.first_friend = true
        end
    end
    for _, remName in ipairs(box.removed or {}) do
        local fIdx = listContains(p.friends, remName)
        if fIdx then table.remove(p.friends, fIdx) end
    end
    return box.invites or {}
end

function Config.blockUser(targetName)
    local p = Config.profile
    if not p.isRegistered then return false, "err_need_register" end
    Config.ensureProfileFields(p)
    Config.removeFriend(targetName)
    Config.declineFriendRequest(targetName)
    if not listContains(p.blockedUsers, targetName) then
        table.insert(p.blockedUsers, 1, targetName)
    end
end

function Config.formatMatchMeta(m)
    local dt = m.dateStr or ""
    if m.mode ~= Config.GameMode.VS_BOT and m.durationSec and m.durationSec > 0 then
        local mins = math.floor(m.durationSec / 60)
        local secs = m.durationSec % 60
        local durStr = string.format("%02d:%02d", mins, secs)
        if #dt > 0 then
            return string.format("%s  •  ⏱ %s", dt, durStr)
        else
            return durStr
        end
    end
    return dt
end

function Config.formatMatchRecord(m)
    local uName = m.username or Config.profile.username
    local resStr = I18N.t(m.resKey or "res_draw")
    local moves = m.moves or 1

    if m.mode == Config.GameMode.VS_BOT then
        local diffKey = (m.botDiff == 1 and "diff_easy") or (m.botDiff == 3 and "diff_hard") or "diff_medium"
        local diffStr = I18N.t(diffKey)
        return I18N.t("hist_vs_bot", uName, diffStr, resStr, moves)
    elseif m.mode == Config.GameMode.ONLINE then
        local dStr = ""
        if m.delta and m.delta ~= 0 then
            dStr = string.format(" [%s%d ELO]", m.delta > 0 and "+" or "", m.delta)
        end
        return I18N.t("hist_vs_online", uName, resStr, moves, dStr)
    elseif m.mode == Config.GameMode.LAN then
        return I18N.t("hist_vs_lan", uName, resStr, moves)
    else
        return I18N.t("hist_vs_local", uName, resStr, moves)
    end
end

return Config
