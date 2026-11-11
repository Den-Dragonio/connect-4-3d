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
    botDifficulty = 2,          -- Default: Medium (2 on 1..3 slider)
    botColorChoice = "white",   -- "white", "black", "random"
    humanPlayer = 1,            -- 1 = White, 2 = Black
    onlineTimeMinutes = 5,      -- 5 minutes (300s) or 1 minute (60s)
    onlinePlayersCount = 29,    -- Active online players indicator

    cameraSensitivity = 1.0,
    animateDrops = true,

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
        rating = 800,
        ratingHistory = { 800 },
        gamesPlayed = 0,
        wins = 0,
        losses = 0,
        draws = 0,
        recentMatches = {},
        achievements = {
            first_win = false,
            diag_3d   = false,
            veteran   = false
        }
    },

    coins = 100,
    adsRemoved = false,

    boardShape = "round",
    activePieceSkin = "classic_bw",
    activeBoardSkin = "dark_wood",
    activeUITheme   = "minimal_gray",

    uiThemeOrder = {
        "minimal_gray",
        "wood_vibe",
        "carbon_dark",
        "clean_silver"
    },

    uiThemes = {
        minimal_gray = {
            id = "minimal_gray",
            nameKey = "ui_theme_gray",
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
        clean_silver = {
            id = "clean_silver",
            nameKey = "ui_theme_silver",
            bgClear        = { 0.22, 0.24, 0.27, 1.0 },
            panelBg        = { 0.26, 0.28, 0.32, 0.95 },
            panelBorder    = { 0.52, 0.55, 0.60, 0.92 },
            btnDefault     = { 0.32, 0.34, 0.39, 0.95 },
            btnPrimary     = { 0.44, 0.48, 0.55, 0.98 },
            btnActive      = { 0.28, 0.58, 0.46, 0.96 },
            btnAccent      = { 0.50, 0.54, 0.62, 0.96 },
            btnBorder      = { 0.58, 0.62, 0.68, 0.90 },
            btnHoverBorder = { 0.92, 0.94, 0.98, 1.0 },
            textMain       = { 0.98, 0.99, 1.00, 1.0 },
            textSub        = { 0.78, 0.81, 0.86, 1.0 },
            accentText     = { 0.90, 0.94, 1.00, 1.0 },
            unlocked       = false,
            unlockType     = "ach",
            price          = 0
        }
    },

    pieceSkinOrder = {
        "classic_bw",
        "glazed_donuts",
        "pine_tree",
        "nuclear_core",
        "crimson_cobalt",
        "amber_obsidian",
        "emerald_gold",
        "neon_ad",
        "ivory_ach"
    },

    pieceSkins = {
        classic_bw = {
            id = "classic_bw",
            nameKey = "skin_bw",
            style = "wood",
            player1Color = { 0.88, 0.82, 0.72, 1.0 },
            player2Color = { 0.19, 0.14, 0.11, 1.0 },
            woodStrength = 0.85,
            specular = 0.32,
            unlocked = true,
            unlockType = "free",
            price = 0
        },
        glazed_donuts = {
            id = "glazed_donuts",
            nameKey = "skin_donut",
            style = "donut",
            player1Color = { 0.98, 0.95, 0.92, 1.0 }, -- White icing glaze on golden donut
            player2Color = { 0.24, 0.12, 0.06, 1.0 }, -- Dark chocolate glaze on pastry donut
            woodStrength = 0.25,
            specular = 0.78,
            unlocked = true,
            unlockType = "free",
            price = 0
        },
        pine_tree = {
            id = "pine_tree",
            nameKey = "skin_pine",
            style = "pine",
            taperByHeight = true, -- Bottom pieces larger, top pieces smaller -> forms a pine tree!
            player1Color = { 0.14, 0.54, 0.24, 1.0 }, -- Lush Forest Pine Green
            player2Color = { 0.20, 0.52, 0.68, 1.0 }, -- Winter Frost Blue-Spruce
            woodStrength = 0.70,
            specular = 0.28,
            unlocked = true,
            unlockType = "free",
            price = 0
        },
        nuclear_core = {
            id = "nuclear_core",
            nameKey = "skin_nuclear",
            style = "nuclear",
            player1Color = { 0.28, 1.00, 0.22, 1.0 }, -- Uranium-235 (glowing & pulsing radiation)
            player2Color = { 0.21, 0.23, 0.26, 1.0 }, -- Reactor Graphite (dark carbon moderator)
            woodStrength = 0.45,
            specular = 0.62,
            unlocked = true,
            unlockType = "free",
            price = 0
        },
        crimson_cobalt = {
            id = "crimson_cobalt",
            nameKey = "skin_rb",
            player1Color = { 0.86, 0.20, 0.22, 1.0 },
            player2Color = { 0.16, 0.36, 0.82, 1.0 },
            woodStrength = 0.75,
            specular = 0.38,
            unlocked = false,
            unlockType = "coins",
            price = 100
        },
        amber_obsidian = {
            id = "amber_obsidian",
            nameKey = "skin_amber",
            player1Color = { 0.92, 0.62, 0.16, 1.0 },
            player2Color = { 0.16, 0.13, 0.22, 1.0 },
            woodStrength = 0.65,
            specular = 0.45,
            unlocked = false,
            unlockType = "coins",
            price = 100
        },
        emerald_gold = {
            id = "emerald_gold",
            nameKey = "skin_emerald",
            player1Color = { 0.94, 0.78, 0.26, 1.0 },
            player2Color = { 0.12, 0.52, 0.34, 1.0 },
            woodStrength = 0.60,
            specular = 0.50,
            unlocked = false,
            unlockType = "coins",
            price = 100
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
        "sweet_cake",
        "metal_steel",
        "forest_glade",
        "gold_ach",
        "white_wood",
        "obsidian_stub"
    },

    boardSkins = {
        dark_wood = {
            id = "dark_wood",
            nameKey = "board_dark_wood",
            style = "wood",
            soundType = "wood",
            baseColor = { 0.30, 0.19, 0.12, 1.0 },
            pegColor  = { 0.38, 0.25, 0.16, 1.0 },
            pegHover  = { 0.88, 0.68, 0.32, 1.0 },
            woodStrength = 1.0,
            unlocked = true,
            unlockType = "free",
            price = 0
        },
        sweet_cake = {
            id = "sweet_cake",
            nameKey = "board_cake",
            style = "cake",
            soundType = "cake",
            baseColor = { 0.96, 0.74, 0.82, 1.0 }, -- Strawberry-vanilla cake frosting & sponge layers
            pegColor  = { 0.84, 0.60, 0.34, 1.0 }, -- Crispy chocolate-striped wafer roll sticks
            pegHover  = { 1.00, 0.50, 0.74, 1.0 },
            woodStrength = 0.20,
            unlocked = true,
            unlockType = "free",
            price = 0
        },
        metal_steel = {
            id = "metal_steel",
            nameKey = "board_metal",
            style = "metal",
            soundType = "metal",
            baseColor = { 0.44, 0.48, 0.54, 1.0 }, -- Brushed industrial steel base
            pegColor  = { 0.68, 0.73, 0.80, 1.0 }, -- Polished chrome/steel rods
            pegHover  = { 0.45, 0.86, 1.00, 1.0 },
            woodStrength = 0.12,
            unlocked = true,
            unlockType = "free",
            price = 0
        },
        forest_glade = {
            id = "forest_glade",
            nameKey = "board_forest",
            style = "forest",
            soundType = "forest",
            baseColor = { 0.20, 0.46, 0.17, 1.0 }, -- Forest grass & moss around trunks
            pegColor  = { 0.35, 0.22, 0.12, 1.0 }, -- Tree trunk bark
            pegHover  = { 0.62, 0.90, 0.32, 1.0 },
            woodStrength = 0.95,
            unlocked = true,
            unlockType = "free",
            price = 0
        },
        white_wood = {
            id = "white_wood",
            nameKey = "board_white_wood",
            style = "wood",
            soundType = "light_wood",
            baseColor = { 0.88, 0.85, 0.79, 1.0 },
            pegColor  = { 0.82, 0.78, 0.71, 1.0 },
            pegHover  = { 0.95, 0.74, 0.30, 1.0 },
            woodStrength = 0.85,
            unlocked = false,
            unlockType = "coins",
            price = 100
        },
        obsidian_stub = {
            id = "obsidian_stub",
            nameKey = "board_obsidian",
            style = "stone",
            soundType = "stone",
            baseColor = { 0.16, 0.17, 0.21, 1.0 },
            pegColor  = { 0.32, 0.34, 0.40, 1.0 },
            pegHover  = { 0.55, 0.78, 0.98, 1.0 },
            woodStrength = 0.35,
            unlocked = false,
            unlockType = "coins",
            price = 200
        },
        gold_ach = {
            id = "gold_ach",
            nameKey = "board_gold",
            style = "metal",
            soundType = "metal",
            baseColor = { 0.56, 0.40, 0.18, 1.0 },
            pegColor  = { 0.78, 0.60, 0.26, 1.0 },
            pegHover  = { 1.00, 0.88, 0.42, 1.0 },
            woodStrength = 0.90,
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

function Config.getUITheme()
    return Config.uiThemes[Config.activeUITheme] or Config.uiThemes.minimal_gray
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

function Config.registerAccount(username, email, password, confirmPassword)
    if not Config.validateUsername(username) then
        return false, "err_username"
    end
    local lowerU = username:lower()
    for existingU, acc in pairs(Config.registeredAccounts) do
        if existingU:lower() == lowerU then
            return false, "err_username_taken"
        end
        if acc.email and acc.email:lower() == email:lower() then
            return false, "err_email_taken"
        end
    end
    if not Config.validateEmail(email) then
        return false, "err_email"
    end
    if not Config.validatePassword(password) then
        return false, "err_password"
    end
    if password ~= confirmPassword then
        return false, "err_password_mismatch"
    end

    local newAcc = {
        username         = username,
        email            = email,
        password         = password,
        bio              = "",
        avatarPreset     = 1,
        customAvatarFile = nil,
        isRegistered     = true,
        rating           = 800,
        ratingHistory    = { 800 },
        gamesPlayed      = Config.profile.gamesPlayed,
        wins             = Config.profile.wins,
        losses           = Config.profile.losses,
        draws            = Config.profile.draws,
        recentMatches    = Config.profile.recentMatches,
        achievements     = Config.profile.achievements
    }
    Config.registeredAccounts[username] = newAcc
    Config.profile = newAcc
    FirebaseClient.registerUser(username, email, password, newAcc)
    return true, nil
end

function Config.loginAccount(username, password)
    for _, acc in pairs(Config.registeredAccounts) do
        if acc.username:lower() == username:lower() and acc.password == password then
            Config.profile = acc
            Config.profile.isRegistered = true
            FirebaseClient.signInUser(acc.email, password)
            return true, nil
        end
    end

    -- Fallback: try cross-device login from Firebase Realtime Database + Firebase Auth
    local remoteProf = FirebaseClient.fetchUserProfile(username)
    if remoteProf and remoteProf.email ~= "" then
        if FirebaseClient.signInUser(remoteProf.email, password) then
            local restoredAcc = {
                username         = remoteProf.username,
                email            = remoteProf.email,
                password         = password,
                bio              = remoteProf.bio or "",
                avatarPreset     = 1,
                customAvatarFile = nil,
                isRegistered     = true,
                rating           = remoteProf.rating or 800,
                ratingHistory    = { 800, remoteProf.rating or 800 },
                gamesPlayed      = remoteProf.gamesPlayed or 0,
                wins             = remoteProf.wins or 0,
                losses           = remoteProf.losses or 0,
                draws            = remoteProf.draws or 0,
                recentMatches    = {},
                achievements     = {
                    first_win = (remoteProf.wins or 0) > 0,
                    diag_3d   = false,
                    veteran   = (remoteProf.gamesPlayed or 0) >= 10
                }
            }
            Config.registeredAccounts[restoredAcc.username] = restoredAcc
            Config.profile = restoredAcc
            return true, nil
        end
    end

    return false, "err_login_failed"
end

function Config.updateRegisteredProfile(newUsername, newEmail, newPassword, newBio, newAvatarPreset, newCustomAvatarFile)
    local cur = Config.profile
    if not Config.validateUsername(newUsername) then
        return false, "err_username"
    end
    local lowerU = newUsername:lower()
    for existingU, acc in pairs(Config.registeredAccounts) do
        if acc ~= cur and existingU:lower() == lowerU then
            return false, "err_username_taken"
        end
        if acc ~= cur and acc.email and acc.email:lower() == newEmail:lower() then
            return false, "err_email_taken"
        end
    end
    if not Config.validateEmail(newEmail) then
        return false, "err_email"
    end
    if not Config.validatePassword(newPassword) then
        return false, "err_password"
    end

    Config.registeredAccounts[cur.username] = nil
    cur.username = newUsername
    cur.email    = newEmail
    cur.password = newPassword
    cur.bio      = newBio or ""
    if newAvatarPreset then
        cur.avatarPreset = newAvatarPreset
    end
    if newCustomAvatarFile ~= nil then
        cur.customAvatarFile = newCustomAvatarFile
    end
    Config.registeredAccounts[newUsername] = cur
    FirebaseClient.syncProfile(newUsername, cur)
    return true, nil
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
        rating           = 800,
        ratingHistory    = { 800 },
        gamesPlayed      = 0,
        wins             = 0,
        losses           = 0,
        draws            = 0,
        recentMatches    = {},
        achievements     = {
            first_win = false,
            diag_3d   = false,
            veteran   = false
        }
    }
end

function Config.recordMatchResult(mode, winnerPlayer, isDraw, lineTypeKey, totalHalfMoves, durationSec)
    local p = Config.profile
    p.gamesPlayed = p.gamesPlayed + 1

    -- Determine whether the human/primary player won
    local trackedPlayer = ((mode == Config.GameMode.VS_BOT or mode == Config.GameMode.LAN) and Config.humanPlayer) or 1
    local playerWon = (not isDraw) and (winnerPlayer == trackedPlayer)

    local deltaRating = 0
    local resKey = "res_draw"

    if isDraw then
        p.draws = p.draws + 1
        resKey = "res_draw"
    elseif playerWon then
        p.wins = p.wins + 1
        p.achievements.first_win = true
        if lineTypeKey == "line_diag_3d" then
            p.achievements.diag_3d = true
        end
        -- ELO changes ONLY in Online mode AND ONLY when user is registered!
        if mode == Config.GameMode.ONLINE and p.isRegistered then
            deltaRating = 10
        end
        resKey = "res_victory"
    else
        p.losses = p.losses + 1
        if mode == Config.GameMode.ONLINE and p.isRegistered then
            deltaRating = -10
        end
        resKey = "res_defeat"
    end

    if p.gamesPlayed >= 10 then
        p.achievements.veteran = true
    end

    if not p.isRegistered then
        p.rating = 800
        p.ratingHistory = { 800 }
    elseif deltaRating ~= 0 then
        p.rating = math.max(100, p.rating + deltaRating)
        table.insert(p.ratingHistory, p.rating)
    end

    local fullMoves = math.max(1, math.ceil(totalHalfMoves / 2))
    local dateStr = os.date("%d.%m.%Y %H:%M")
    -- Duration is recorded ONLY for non-bot matches (Offline PvP, LAN, Online)
    local recordedDuration = (mode ~= Config.GameMode.VS_BOT) and math.max(1, math.floor(durationSec or 0)) or nil

    local matchEntry = {
        username    = p.username,
        mode        = mode,
        botDiff     = Config.botDifficulty,
        resKey      = resKey,
        moves       = fullMoves,
        delta       = deltaRating,
        dateStr     = dateStr,
        durationSec = recordedDuration
    }
    -- Keep ALL matches in history so user can scroll all the way back to the 1st game!
    table.insert(p.recentMatches, 1, matchEntry)

    FirebaseClient.pushMatchRecord(matchEntry)
    if p.isRegistered then
        FirebaseClient.syncProfile(p.username, p)
    end

    return deltaRating
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
