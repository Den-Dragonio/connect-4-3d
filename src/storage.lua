local Config = require("src.config")
local I18N   = require("src.i18n")

local Storage = {}
local SAVE_FILE = "save_state.lua"

local function serializeValue(v)
    local tv = type(v)
    if tv == "number" or tv == "boolean" then
        return tostring(v)
    elseif tv == "string" then
        return string.format("%q", v)
    elseif tv == "table" then
        local parts = { "{" }
        for k, val in pairs(v) do
            local keyStr
            if type(k) == "number" then
                keyStr = "[" .. tostring(k) .. "]="
            else
                keyStr = "[" .. string.format("%q", tostring(k)) .. "]="
            end
            table.insert(parts, keyStr .. serializeValue(val) .. ",")
        end
        table.insert(parts, "}")
        return table.concat(parts)
    end
    return "nil"
end

function Storage.save()
    local unlockedPieces = {}
    for id, s in pairs(Config.pieceSkins) do
        unlockedPieces[id] = s.unlocked and true or false
    end
    local unlockedBoards = {}
    for id, s in pairs(Config.boardSkins) do
        unlockedBoards[id] = s.unlocked and true or false
    end
    local unlockedThemes = {}
    for id, s in pairs(Config.uiThemes) do
        unlockedThemes[id] = s.unlocked and true or false
    end

    if not Config.profile.isRegistered then
        Config.profile.rating = 800
        Config.profile.ratingHistory = { 800 }
    end

    local data = {
        lang               = I18N.current,
        coins              = Config.coins,
        adsRemoved         = Config.adsRemoved,
        boardShape         = Config.boardShape,
        activePieceSkin    = Config.activePieceSkin,
        activeBoardSkin    = Config.activeBoardSkin,
        activeUITheme      = Config.activeUITheme,
        botDifficulty      = Config.botDifficulty,
        botColorChoice     = Config.botColorChoice,
        onlineTimeMinutes  = Config.onlineTimeMinutes,
        unlockedPieces     = unlockedPieces,
        unlockedBoards     = unlockedBoards,
        unlockedThemes     = unlockedThemes,
        registeredAccounts = Config.registeredAccounts,
        profile            = Config.profile
    }

    local content = "return " .. serializeValue(data)
    pcall(love.filesystem.write, SAVE_FILE, content)
end

function Storage.load()
    if not love.filesystem.getInfo(SAVE_FILE) then
        return
    end
    local ok, chunk = pcall(love.filesystem.load, SAVE_FILE)
    if not ok or not chunk then return end
    local ok2, data = pcall(chunk)
    if not ok2 or type(data) ~= "table" then return end

    if type(data.lang) == "string" and I18N.strings[data.lang] then
        I18N.current = data.lang
    end
    if type(data.coins) == "number" then
        Config.coins = data.coins
    end
    if type(data.adsRemoved) == "boolean" then
        Config.adsRemoved = data.adsRemoved
    end
    if data.boardShape == "round" or data.boardShape == "square" then
        Config.boardShape = data.boardShape
    end
    if type(data.activePieceSkin) == "string" and Config.pieceSkins[data.activePieceSkin] then
        Config.activePieceSkin = data.activePieceSkin
    end
    if type(data.activeBoardSkin) == "string" and Config.boardSkins[data.activeBoardSkin] then
        Config.activeBoardSkin = data.activeBoardSkin
    end
    if type(data.activeUITheme) == "string" and Config.uiThemes[data.activeUITheme] then
        Config.activeUITheme = data.activeUITheme
    end
    if type(data.botDifficulty) == "number" then
        Config.botDifficulty = math.max(1, math.min(3, data.botDifficulty))
    end
    if data.botColorChoice == "white" or data.botColorChoice == "black" or data.botColorChoice == "random" then
        Config.botColorChoice = data.botColorChoice
    end
    if data.onlineTimeMinutes == 1 or data.onlineTimeMinutes == 5 then
        Config.onlineTimeMinutes = data.onlineTimeMinutes
    end
    if type(data.unlockedPieces) == "table" then
        for id, unlocked in pairs(data.unlockedPieces) do
            if Config.pieceSkins[id] and unlocked then
                Config.pieceSkins[id].unlocked = true
            end
        end
    end
    if type(data.unlockedBoards) == "table" then
        for id, unlocked in pairs(data.unlockedBoards) do
            if Config.boardSkins[id] and unlocked then
                Config.boardSkins[id].unlocked = true
            end
        end
    end
    -- Always keep default free/unlocked boards unlocked even if an older save existed
    if Config.boardSkins.sweet_cake then Config.boardSkins.sweet_cake.unlocked = true end
    if Config.boardSkins.gold_ach   then Config.boardSkins.gold_ach.unlocked   = true end
    if Config.boardSkins.metal_steel then Config.boardSkins.metal_steel.unlocked = true end
    if type(data.unlockedThemes) == "table" then
        for id, unlocked in pairs(data.unlockedThemes) do
            if Config.uiThemes[id] and unlocked then
                Config.uiThemes[id].unlocked = true
            end
        end
    end
    if type(data.registeredAccounts) == "table" then
        Config.registeredAccounts = data.registeredAccounts
    end
    if type(data.profile) == "table" then
        for k, v in pairs(data.profile) do
            Config.profile[k] = v
        end
        -- Ensure unregistered guest always has 800 ELO
        if not Config.profile.isRegistered then
            Config.profile.rating = 800
            Config.profile.ratingHistory = { 800 }
        end
    end
end

return Storage
