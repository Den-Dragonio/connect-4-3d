local Config     = require("src.config")
local I18N       = require("src.i18n")
local BoardLogic = require("src.board_logic")
local Renderer3D = require("src.renderer3d")
local BotAI      = require("src.bot_ai")
local Sound      = require("src.sound")
local Storage    = require("src.storage")
local LAN        = require("src.lan")
local Firebase   = require("src.firebase_client")
local Tournament = require("src.tournament")
local utf8       = require("utf8")

local fonts = {}
local renderer = nil
local gameLogic = nil
local menuDemoLogic = nil
local customAvatarImage = nil

-- Screens: "menu", "bot_modal", "online_modal", "lan_modal", "profile_modal", "auth_modal", "settings_modal", "rules_modal", "shop", "game"
local currentScreen = "menu"

-- Auth / Edit Profile form state
local authState = {
    mode = "register", -- "register", "login", "edit"
    activeField = "username", -- "username", "email", "password", "confirmPassword", "bio"
    username = "",
    email = "",
    password = "",
    confirmPassword = "",
    bio = "",
    avatarPreset = 1,
    customAvatarFile = nil,
    showPassword = false,
    showConfirmPassword = false,
    errorKey = nil
}

-- Shop state
local shopTab = "pieces" -- "pieces", "board", "themes", "currency"
local shopScrollX = 0.0
local shopTargetScrollX = 0.0
local shopDragging = false
local shopSpinAngle = 0.0

-- Mouse, Touch & camera state
local mouseState = {
    leftDown = false,
    rightDown = false,
    pressX = 0,
    pressY = 0,
    dragged = false,
    inMoveLog = false,
    inProfileMatches = false,
    scrollAccumY = 0
}
local DRAG_THRESHOLD = 8.0
local isTouchDevice = (love.system and (love.system.getOS() == "Android" or love.system.getOS() == "iOS")) or false
local activeTouches = {}
local lastPinchDist = nil
local pinchActive = false

local function getUIScaleAndDims()
    local realW, realH = love.graphics.getDimensions()
    local scale = 1.0
    if realW < 920 or realH < 600 then
        if realW >= realH then
            scale = math.min(1.0, realW / 1024, realH / 620)
        else
            scale = math.min(1.0, realW / 660, realH / 860)
        end
        scale = math.max(0.45, scale)
    end
    return realW / scale, realH / scale, scale, realW, realH
end

local function getUIMousePos()
    local mx, my = love.mouse.getPosition()
    local _, _, scale = getUIScaleAndDims()
    return mx / scale, my / scale
end

local function setUIScissor(x, y, w, h)
    if not x then
        love.graphics.setScissor()
        return
    end
    local _, _, scale = getUIScaleAndDims()
    love.graphics.setScissor(x * scale, y * scale, w * scale, h * scale)
end

-- Gameplay state
local hoveredX, hoveredZ, hoveredY = nil, nil, nil
local isReplayMode = false
local replaySourceMatch = nil
local matchmakingState = { active = false, timer = 0, statsTimer = 0 }
local activeTournamentMatch = nil
local tournamentUI = {
    view = "hub", -- "hub" | "create" | "join" | "room"
    system = "swiss",
    maxPlayers = 4,
    timeMinutes = 5,
    ruleMode = "standard",
    isBotTournament = false,
    botDifficulty = "medium",
    joinCode = "",
    errorMsg = nil
}
local selectedAchievementId = nil
local friendSearchText = ""
local friendStatusFeedback = nil
local friendStatusCache = {}
local viewedFriendProfile = nil
local friendProfileReturnScreen = "friend_game_modal"
local localOnlineRoom = nil
local friendGameUI = {
    view = "list", -- "list" | "lobby" | "join"
    joinCode = "",
    listScroll = 0,
    room = nil,
    errorMsg = nil,
    pollTimer = 0,
    invites = {}
}

local function formatLastSeen(ts, inGame)
    ts = tonumber(ts) or 0
    if ts <= 0 then
        return false, I18N.t("friend_last_unknown")
    end
    local diff = math.max(0, os.time() - ts)
    if diff <= 90 then
        return true, inGame and I18N.t("friend_in_game") or I18N.t("friend_online_now")
    elseif diff < 60 then
        return false, I18N.t("friend_last_seen", I18N.t("friend_just_now"))
    elseif diff < 3600 then
        return false, I18N.t("friend_last_seen", I18N.t("friend_mins_ago", math.max(1, math.floor(diff / 60))))
    elseif diff < 86400 then
        return false, I18N.t("friend_last_seen", I18N.t("friend_hours_ago", math.max(1, math.floor(diff / 3600))))
    end
    return false, I18N.t("friend_last_seen", os.date("%d.%m.%Y %H:%M", ts))
end

local function refreshFriendsState()
    local p = Config.profile
    if not p or not p.isRegistered then return end
    friendGameUI.invites = Config.syncIncomingFriendMailbox()
    local pres = Firebase.fetchAllUserPresences()
    if pres then
        for k, v in pairs(pres) do
            friendStatusCache[k] = v
        end
    end
    Storage.save()
end

local function openFriendProfile(targetUsername, returnScreen)
    if not Config.profile.isRegistered then
        friendProfileReturnScreen = returnScreen or "profile_modal"
        viewedFriendProfile = nil
        return
    end
    local prof = Config.findUserByUsername(targetUsername)
    if prof then
        Config.ensureProfileFields(prof)
        local key = (prof.username or targetUsername):lower()
        local pres = friendStatusCache[key]
        if not pres then
            local allPres = Firebase.fetchAllUserPresences()
            if allPres and allPres[key] then
                friendStatusCache[key] = allPres[key]
                pres = allPres[key]
            end
        end
        if pres and pres.ts and pres.ts > (prof.lastSeen or 0) then
            prof.lastSeen = pres.ts
            prof.inGameNow = pres.inGame
        end
        viewedFriendProfile = prof
        friendProfileReturnScreen = returnScreen or "friend_game_modal"
        selectedAchievementId = nil
        currentScreen = "friend_profile_modal"
    else
        friendStatusFeedback = I18N.t("friend_not_found")
    end
end

local ACHIEVEMENTS_META = {
    { id = "first_win",      icon = "★", key = "ach_first_win",      desc = "ach_desc_first_win" },
    { id = "diag_3d",        icon = "❖", key = "ach_3d_diag",        desc = "ach_desc_3d_diag" },
    { id = "veteran",        icon = "10", key = "ach_veteran",       desc = "ach_desc_veteran" },
    { id = "bot_easy",       icon = "B1", key = "ach_bot_easy",      desc = "ach_desc_bot_easy" },
    { id = "bot_medium",     icon = "B2", key = "ach_bot_medium",    desc = "ach_desc_bot_medium" },
    { id = "bot_hard",       icon = "B3", key = "ach_bot_hard",      desc = "ach_desc_bot_hard" },
    { id = "wins_10",        icon = "W10", key = "ach_wins_10",      desc = "ach_desc_wins_10" },
    { id = "wins_100",       icon = "W100", key = "ach_wins_100",    desc = "ach_desc_wins_100" },
    { id = "wins_1000",      icon = "1K", key = "ach_wins_1000",     desc = "ach_desc_wins_1000" },
    { id = "first_friend",   icon = "F1", key = "ach_first_friend",  desc = "ach_desc_first_friend" },
    { id = "pioneer_1000",   icon = "#1K", key = "ach_pioneer_1000", desc = "ach_desc_pioneer_1000" },
    { id = "tournament_win", icon = "🏆", key = "ach_tournament_win", desc = "ach_desc_tournament_win" }
}

local function startFriendRoomLobby(inviteTarget)
    if not Config.profile.isRegistered then
        friendGameUI.errorMsg = I18N.t("friends_reg_only")
        friendStatusFeedback = I18N.t("friends_reg_only")
        return false
    end
    local room = Firebase.createFriendRoom({
        host = Config.profile.username,
        ruleMode = Config.ruleMode,
        timeMinutes = Config.onlineTimeMinutes or 5
    })
    if not room then
        friendGameUI.errorMsg = I18N.t("friend_room_not_found")
        return false
    end
    if inviteTarget and #inviteTarget > 0 then
        Firebase.sendGameInvite(inviteTarget, Config.profile.username, room.code, Config.ruleMode, Config.onlineTimeMinutes or 5)
    end
    friendGameUI.room = room
    friendGameUI.view = "lobby"
    friendGameUI.errorMsg = nil
    friendGameUI.pollTimer = 1.2
    currentScreen = "friend_game_modal"
    return true
end
local rulesScrollOffset = 0
local snowflakes = {}
for i = 1, 70 do
    snowflakes[i] = {
        x = math.random(),
        y = math.random(),
        r = 1.5 + math.random() * 2.5,
        vy = 0.035 + math.random() * 0.06,
        vx = (math.random() - 0.5) * 0.02,
        phase = math.random() * 6.28
    }
end
local activeDrop = nil
local botTimer = nil
local uiButtons = {}

-- 5-minute timers (300 seconds per player) for Offline PvP & Online modes
local timers = {
    enabled = true,
    white = 300.0,
    black = 300.0
}
local lastRatingDelta = 0
local turnBannerPulse = 0.0
local hideWinModal = false
local lanIpFocused = false
local matchStartTime = 0.0
local viewPly = 0
local moveLogScroll = 0
local profileMatchScroll = 0

local function easeOutBounce(t)
    local n1 = 7.5625
    local d1 = 2.75
    if t < 1 / d1 then
        return n1 * t * t
    elseif t < 2 / d1 then
        t = t - 1.5 / d1
        return n1 * t * t + 0.75
    elseif t < 2.5 / d1 then
        t = t - 2.25 / d1
        return n1 * t * t + 0.9375
    else
        t = t - 2.625 / d1
        return n1 * t * t + 0.984375
    end
end

-- Draw a clean vector 5-pointed star icon (avoids missing glyph boxes in TTF fonts)
local function drawStarIcon(cx, cy, r, color)
    local pts = {}
    for i = 0, 9 do
        local a = -math.pi * 0.5 + i * (math.pi / 5)
        local rad = (i % 2 == 0) and r or (r * 0.44)
        table.insert(pts, cx + math.cos(a) * rad)
        table.insert(pts, cy + math.sin(a) * rad)
    end
    love.graphics.setColor(color)
    love.graphics.polygon("fill", pts)
end

-- Draw a vector Eye Icon for password reveal/hide toggle
local function drawEyeIcon(cx, cy, isOpen, color)
    love.graphics.setColor(color)
    love.graphics.setLineWidth(1.8)
    love.graphics.ellipse("line", cx, cy, 11, 6.5)
    if isOpen then
        love.graphics.circle("fill", cx, cy, 3.4)
    else
        love.graphics.circle("line", cx, cy, 2.8)
        love.graphics.line(cx - 10, cy + 7, cx + 10, cy - 7)
    end
end

local AVATAR_PRESET_COLORS = {
    { 0.42, 0.46, 0.54, 1.0 },
    { 0.24, 0.56, 0.44, 1.0 },
    { 0.72, 0.44, 0.24, 1.0 },
    { 0.34, 0.48, 0.76, 1.0 },
    { 0.68, 0.28, 0.42, 1.0 }
}

local function reloadCustomAvatarImage()
    customAvatarImage = nil
    local fname = Config.profile.customAvatarFile
    if fname and love.filesystem.getInfo(fname) then
        local ok, img = pcall(love.graphics.newImage, fname)
        if ok and img then
            customAvatarImage = img
        end
    end
end

local function drawUserAvatar(cx, cy, radius, presetOverride, customFileOverride)
    local ui = Config.getUITheme()
    local presetIdx = presetOverride or Config.profile.avatarPreset or 1
    local col = AVATAR_PRESET_COLORS[((presetIdx - 1) % #AVATAR_PRESET_COLORS) + 1]

    love.graphics.setColor(col)
    love.graphics.circle("fill", cx, cy, radius)

    local useCustom = (customFileOverride or Config.profile.customAvatarFile) and customAvatarImage
    if useCustom then
        local iw, ih = customAvatarImage:getDimensions()
        local scale = (radius * 1.65) / math.max(iw, ih)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(customAvatarImage, cx, cy, 0, scale, scale, iw * 0.5, ih * 0.5)
    else
        love.graphics.setColor(ui.textMain)
        love.graphics.circle("fill", cx, cy - radius * 0.28, radius * 0.34)
        love.graphics.arc("fill", cx, cy + radius * 0.70, radius * 0.58, math.pi * 1.15, math.pi * 1.85)
    end

    love.graphics.setColor(ui.panelBorder)
    love.graphics.setLineWidth(1.5)
    love.graphics.circle("line", cx, cy, radius)
end

-- Physical scancode check so WASD / ЦФЫВ and Z/X (Я/Ч) work on any layout
-- (Arrow keys are reserved for move history rewinding in-game!)
local function isControlDown(action)
    if action == "left" then
        return love.keyboard.isScancodeDown("a", "q")
            or love.keyboard.isDown("a", "q")
    elseif action == "right" then
        return love.keyboard.isScancodeDown("d", "e")
            or love.keyboard.isDown("d", "e")
    elseif action == "up" then
        return love.keyboard.isScancodeDown("w")
            or love.keyboard.isDown("w")
    elseif action == "down" then
        return love.keyboard.isScancodeDown("s")
            or love.keyboard.isDown("s")
    elseif action == "zoom_in" then
        return love.keyboard.isScancodeDown("z")
            or love.keyboard.isDown("z")
    elseif action == "zoom_out" then
        return love.keyboard.isScancodeDown("x")
            or love.keyboard.isDown("x")
    end
    return false
end

local function createMittelspielBoard()
    local demo = BoardLogic.new()
    local sampleMoves = {
        {1,1}, {4,4}, {2,2}, {3,3}, {1,1}, {2,3},
        {3,1}, {2,2}, {4,1}, {1,4}, {3,3}, {2,3},
        {2,2}, {1,1}, {3,4}, {4,2}, {2,4}, {3,2}
    }
    for _, m in ipairs(sampleMoves) do
        demo:dropPiece(m[1], m[2])
    end
    return demo
end

local function isBotTurn()
    if Config.currentMode ~= Config.GameMode.VS_BOT or gameLogic.isGameOver then
        return false
    end
    return gameLogic.currentPlayer ~= Config.humanPlayer
end

local function isLocalPlayerTurn()
    if gameLogic.isGameOver then return false end
    if Config.currentMode == Config.GameMode.VS_BOT then
        return gameLogic.currentPlayer == Config.humanPlayer
    elseif Config.currentMode == Config.GameMode.LAN then
        return gameLogic.currentPlayer == Config.humanPlayer
    elseif Config.currentMode == Config.GameMode.ONLINE and localOnlineRoom then
        return gameLogic.currentPlayer == Config.humanPlayer
    end
    return true
end

local function startNewGame(mode, difficulty, lanRole, onlineRoom)
    Config.currentMode = mode or Config.GameMode.LOCAL_PVP
    if difficulty then
        Config.botDifficulty = difficulty
    end
    localOnlineRoom = onlineRoom

    if Config.currentMode == Config.GameMode.VS_BOT then
        if Config.botColorChoice == "white" then
            Config.humanPlayer = BoardLogic.Player.WHITE
        elseif Config.botColorChoice == "black" then
            Config.humanPlayer = BoardLogic.Player.BLACK
        else
            Config.humanPlayer = (love.math.random(1, 2) == 1)
                and BoardLogic.Player.WHITE
                or  BoardLogic.Player.BLACK
        end
    elseif Config.currentMode == Config.GameMode.LAN then
        if lanRole == "client" then
            Config.humanPlayer = BoardLogic.Player.BLACK
        else
            Config.humanPlayer = BoardLogic.Player.WHITE
        end
    elseif Config.currentMode == Config.GameMode.ONLINE and localOnlineRoom then
        Config.ruleMode = localOnlineRoom.ruleMode or Config.ruleMode
        Config.onlineTimeMinutes = localOnlineRoom.timeMinutes or Config.onlineTimeMinutes
        Config.humanPlayer = (localOnlineRoom.role == "guest")
            and BoardLogic.Player.BLACK
            or  BoardLogic.Player.WHITE
    else
        Config.humanPlayer = BoardLogic.Player.WHITE
    end

    gameLogic:reset(Config.ruleMode)
    hoveredX, hoveredZ, hoveredY = nil, nil, nil
    isReplayMode = false
    replaySourceMatch = nil
    activeDrop = nil
    botTimer = nil
    lastRatingDelta = 0
    hideWinModal = false
    matchStartTime = love.timer.getTime()
    viewPly = 0
    moveLogScroll = 0

    -- Timers in Offline PvP (5:00), and LAN & Online modes (5:00 or 1:00 from Online modal)
    timers.enabled = (Config.currentMode ~= Config.GameMode.VS_BOT)
    local baseClock = 300.0
    if (Config.currentMode == Config.GameMode.ONLINE or Config.currentMode == Config.GameMode.LAN)
       and Config.onlineTimeMinutes == 1 then
        baseClock = 60.0
    end
    timers.white = baseClock
    timers.black = baseClock

    renderer:resetCamera()
    currentScreen = "game"

    -- If human chose Black, Bot plays White and makes the 1st move!
    if isBotTurn() then
        botTimer = 0.45
    end
end

local function finalizeGameEnd()
    if isReplayMode then return end
    Sound.play("win")
    local elapsedSec = math.max(1, math.floor(love.timer.getTime() - matchStartTime))
    lastRatingDelta = Config.recordMatchResult(
        Config.currentMode,
        gameLogic.winner,
        gameLogic.isDraw,
        gameLogic.winningLineType,
        #gameLogic.moveHistory,
        elapsedSec,
        gameLogic.moveHistory,
        localOnlineRoom and localOnlineRoom.opponent or nil
    )
    if activeTournamentMatch and Tournament.active then
        local humanWon = (gameLogic.winner == Config.humanPlayer)
        local tRes = Tournament.recordHumanMatchResult(Config.profile.username, humanWon, gameLogic.isDraw, #gameLogic.moveHistory)
        if tRes and tRes.finished and tRes.champion == Config.profile.username and not Tournament.active.isBotTournament then
            Config.recordTournamentWin(Tournament.active.name or "Tournament", Tournament.active.opponents or {}, Tournament.active.system)
        end
        activeTournamentMatch = nil
    end
    Storage.save()
end

local function syncMoveLogScrollToPly()
    local totalPairs = math.ceil(#gameLogic.moveHistory / 2)
    local maxVisible = 9
    if totalPairs <= maxVisible then
        moveLogScroll = 0
        return
    end
    local activePair = math.max(1, math.ceil(math.max(1, viewPly) / 2))
    if activePair < moveLogScroll + 1 then
        moveLogScroll = math.max(0, activePair - 1)
    elseif activePair > moveLogScroll + maxVisible then
        moveLogScroll = math.min(totalPairs - maxVisible, activePair - maxVisible)
    end
end

local function triggerMove(gx, gz, fromNetwork, gy)
    if isReplayMode then return end
    -- If user was inspecting an earlier move, snap back to live before placing a new piece
    viewPly = #gameLogic.moveHistory
    local res
    if gameLogic.ruleMode == "free" then
        local targetY = gy or gameLogic:getNextEmptyY(gx, gz)
        if not targetY or not gameLogic:canPlace(gx, targetY, gz) then return end
        res = gameLogic:placePiece(gx, targetY, gz)
    else
        if not gameLogic:canDrop(gx, gz) then return end
        res = gameLogic:dropPiece(gx, gz)
    end
    if not res or not res.ok then return end

    viewPly = #gameLogic.moveHistory
    syncMoveLogScrollToPly()

    if Config.currentMode == Config.GameMode.LAN and not fromNetwork then
        LAN.sendMove(gx, gz)
    elseif Config.currentMode == Config.GameMode.ONLINE and localOnlineRoom and not fromNetwork then
        local token = string.format("%d,%d,%d", res.pos.x, res.pos.y, res.pos.z)
        localOnlineRoom.movesStr = (localOnlineRoom.movesStr and localOnlineRoom.movesStr ~= "")
            and (localOnlineRoom.movesStr .. ";" .. token)
            or  token
        localOnlineRoom.syncedMoves = #gameLogic.moveHistory
        Firebase.pushFriendRoomMove(localOnlineRoom.code, localOnlineRoom.movesStr, localOnlineRoom.syncedMoves)
    end

    hoveredX, hoveredZ, hoveredY = nil, nil, nil
    turnBannerPulse = 1.0
    local _, targetY, _ = renderer:gridToWorldXYZ(res.pos.x, res.pos.y, res.pos.z, Config.getPieceSkin())

    if Config.animateDrops then
        activeDrop = {
            x = res.pos.x,
            y = res.pos.y,
            z = res.pos.z,
            startY = Renderer3D.DROP_SPAWN_Y,
            targetY = targetY,
            currentY = Renderer3D.DROP_SPAWN_Y,
            elapsed = 0.0,
            duration = 0.28 + (4 - res.pos.y) * 0.04,
            moveResult = res
        }
    else
        Sound.playDrop(Config.getBoardSkin().soundType)
        if res.isGameOver then
            finalizeGameEnd()
        elseif isBotTurn() then
            botTimer = 0.40
        end
    end
end

local function performBotMove()
    if not isBotTurn() then return end
    local pick = BotAI.chooseMove(gameLogic, Config.botDifficulty)
    if pick then
        triggerMove(pick.x, pick.z, false, pick.y)
    end
end

local function openAuthModal(mode)
    authState.mode = mode
    authState.errorKey = nil
    authState.showPassword = false
    authState.showConfirmPassword = false
    if mode == "edit" then
        authState.username         = Config.profile.username or ""
        authState.email            = Config.profile.email or ""
        authState.password         = Config.profile.password or ""
        authState.confirmPassword  = Config.profile.password or ""
        authState.bio              = Config.profile.bio or ""
        authState.avatarPreset     = Config.profile.avatarPreset or 1
        authState.customAvatarFile = Config.profile.customAvatarFile
    else
        authState.username         = ""
        authState.email            = ""
        authState.password         = ""
        authState.confirmPassword  = ""
        authState.bio              = ""
        authState.avatarPreset     = 1
        authState.customAvatarFile = nil
    end
    authState.activeField = "username"
    currentScreen = "auth_modal"
end

function love.load()
    love.math.setRandomSeed(os.time())
    love.keyboard.setKeyRepeat(true)
    Storage.load()
    reloadCustomAvatarImage()
    Sound.init()

    LAN.onMatchStart = function(role)
        Sound.play("win")
        startNewGame(Config.GameMode.LAN, nil, role)
    end
    LAN.onMoveReceived = function(gx, gz)
        if currentScreen == "game" and Config.currentMode == Config.GameMode.LAN then
            triggerMove(gx, gz, true)
        end
    end

    fonts.title    = love.graphics.newFont("assets/fonts/bold.ttf", 32)
    fonts.h2       = love.graphics.newFont("assets/fonts/bold.ttf", 23)
    fonts.btn      = love.graphics.newFont("assets/fonts/bold.ttf", 16)
    fonts.hudTurn  = love.graphics.newFont("assets/fonts/bold.ttf", 22)
    fonts.hudTimer = love.graphics.newFont("assets/fonts/bold.ttf", 18)
    fonts.body     = love.graphics.newFont("assets/fonts/regular.ttf", 15)
    fonts.small    = love.graphics.newFont("assets/fonts/regular.ttf", 13)
    fonts.coord    = love.graphics.newFont("assets/fonts/bold.ttf", 14)

    renderer      = Renderer3D.new()
    gameLogic     = BoardLogic.new()
    menuDemoLogic = createMittelspielBoard()

    local isCI = false
    if arg then
        for _, a in ipairs(arg) do
            if a == "--ci-test" then isCI = true break end
        end
    end
    if isCI then
        print("[CI-TEST] Starting automated smoke tests...")
        for id, bskin in pairs(Config.boardSkins) do
            print("[CI-TEST] Testing boardSkin: " .. id)
            renderer:renderShopPreview(0, 0, 200, 200, 800, 600, "board_skin", bskin, 0.5)
        end
        for id, pskin in pairs(Config.pieceSkins) do
            print("[CI-TEST] Testing pieceSkin: " .. id)
            renderer:renderShopPreview(0, 0, 200, 200, 800, 600, "pieces", pskin, 0.5)
        end
        assert(gameLogic:getNextEmptyY(1, 1) == 1)
        Config.activeBoardSkin = "manhattan"
        renderer:renderScene(800, 600, {
            config = Config, logic = gameLogic, maxPly = 0, showCoords = true, coordFont = fonts.coord
        })
        Config.activeBoardSkin = "japanese_roof"
        renderer:renderScene(800, 600, {
            config = Config, logic = gameLogic, maxPly = 0, showCoords = true, coordFont = fonts.coord
        })
        Config.activeBoardSkin = "forest_glade"
        Config.profile.boardWins = { forest_glade = 10 }
        renderer:renderScene(800, 600, {
            config = Config, logic = gameLogic, maxPly = 0, showCoords = true, coordFont = fonts.coord
        })

        -- Проверка полного стека gy=1..4, победы и HUD-экрана для 3D-скинов (pine_tree, snowman)
        gameLogic:reset()
        gameLogic:dropPiece(1, 1); gameLogic:dropPiece(2, 1)
        gameLogic:dropPiece(1, 1); gameLogic:dropPiece(2, 1)
        gameLogic:dropPiece(1, 1); gameLogic:dropPiece(2, 1)
        local winRes = gameLogic:dropPiece(1, 1)
        assert(winRes and winRes.ok and gameLogic.isGameOver, "Expected vertical win in CI test")
        currentScreen = "game"
        for _, skinId in ipairs({ "pine_tree", "snowman", "classic_bw" }) do
            Config.activePieceSkin = skinId
            hideWinModal = false
            love.draw()
            hideWinModal = true
            love.draw()
        end
        currentScreen = "shop"
        love.draw()
        currentScreen = "online_modal"
        love.draw()
        currentScreen = "profile_modal"
        love.draw()
        currentScreen = "friend_game_modal"
        love.draw()
        viewedFriendProfile = Config.profile
        currentScreen = "friend_profile_modal"
        love.draw()
        viewedFriendProfile = nil
        gameLogic:reset()
        currentScreen = "menu"
        print("[CI-TEST] ALL TESTS PASSED SUCCESSFULLY!")
        love.event.quit(0)
    end
end

function love.update(dt)
    local sw, sh = love.graphics.getDimensions()
    shopSpinAngle = shopSpinAngle + dt * 1.35
    shopScrollX = shopScrollX + (shopTargetScrollX - shopScrollX) * math.min(1.0, dt * 12.0)

    LAN.update()

    if Config.selectedUITheme == "new_year" then
        for _, sf in ipairs(snowflakes) do
            sf.y = sf.y + sf.vy * dt
            sf.x = sf.x + (sf.vx + math.sin(love.timer.getTime() * 1.3 + sf.phase) * 0.015) * dt
            if sf.y > 1.02 then sf.y = -0.02; sf.x = math.random() end
            if sf.x < -0.02 then sf.x = 1.02 elseif sf.x > 1.02 then sf.x = -0.02 end
        end
    end

    matchmakingState.statsTimer = (matchmakingState.statsTimer or 0) - dt
    if matchmakingState.statsTimer <= 0 then
        matchmakingState.statsTimer = 12.0
        local inMatch = (currentScreen == "game" and Config.currentMode == Config.GameMode.ONLINE)
        Firebase.sendPresenceHeartbeat(Config.profile.username, inMatch, Config.profile.isRegistered)
        local pCnt, gCnt = Firebase.fetchOnlineStats()
        if pCnt then Config.onlinePlayersCount = pCnt end
        if gCnt then Config.onlineActiveGames = gCnt end
    end

    if currentScreen == "friend_game_modal" and Config.profile.isRegistered then
        friendGameUI.pollTimer = (friendGameUI.pollTimer or 0) - dt
        if friendGameUI.pollTimer <= 0 then
            if friendGameUI.view == "lobby" and friendGameUI.room then
                friendGameUI.pollTimer = 1.2
                local remote = Firebase.fetchFriendRoom(friendGameUI.room.code)
                if remote and remote.guest ~= "" and remote.status == "playing" then
                    local roomObj = {
                        code        = remote.code,
                        role        = "host",
                        opponent    = remote.guest,
                        ruleMode    = remote.ruleMode,
                        timeMinutes = remote.timeMinutes,
                        syncedMoves = 0,
                        movesStr    = "",
                        pollTimer   = 0.9
                    }
                    friendGameUI.room = nil
                    friendGameUI.view = "list"
                    startNewGame(Config.GameMode.ONLINE, nil, nil, roomObj)
                end
            else
                friendGameUI.pollTimer = 6.0
                refreshFriendsState()
            end
        end
    end

    if currentScreen == "game" and Config.currentMode == Config.GameMode.ONLINE and localOnlineRoom and not gameLogic.isGameOver then
        localOnlineRoom.pollTimer = (localOnlineRoom.pollTimer or 0) - dt
        if localOnlineRoom.pollTimer <= 0 then
            localOnlineRoom.pollTimer = 0.9
            local remote = Firebase.fetchFriendRoom(localOnlineRoom.code)
            if remote and remote.moveCount > #gameLogic.moveHistory then
                localOnlineRoom.movesStr = remote.moves or ""
                local parsed = {}
                for mx, my, mz in (remote.moves or ""):gmatch("(%d+),(%d+),(%d+)") do
                    table.insert(parsed, { tonumber(mx), tonumber(my), tonumber(mz) })
                end
                for idx = #gameLogic.moveHistory + 1, #parsed do
                    local mv = parsed[idx]
                    if mv then
                        triggerMove(mv[1], mv[3], true, mv[2])
                    end
                end
            end
        end
    end

    if matchmakingState.active then
        matchmakingState.timer = matchmakingState.timer + dt
    end

    if turnBannerPulse > 0 then
        turnBannerPulse = math.max(0.0, turnBannerPulse - dt * 2.5)
    end

    if currentScreen ~= "game" then
        renderer:rotateCamera(dt * 11.0, 0)
        return
    end

    -- Camera rotation: WASD / ЦФЫВ / Arrows
    local yawSpeed = 0
    local pitchSpeed = 0
    if isControlDown("left")  then yawSpeed = yawSpeed - 1 end
    if isControlDown("right") then yawSpeed = yawSpeed + 1 end
    if isControlDown("up")    then pitchSpeed = pitchSpeed - 1 end
    if isControlDown("down")  then pitchSpeed = pitchSpeed + 1 end
    if yawSpeed ~= 0 or pitchSpeed ~= 0 then
        renderer:rotateCamera(yawSpeed * 78.0 * dt, pitchSpeed * 54.0 * dt)
    end

    -- Camera zoom: Z / X (Я / Ч)
    local zoomSpeed = 0
    if isControlDown("zoom_in")  then zoomSpeed = zoomSpeed - 1 end
    if isControlDown("zoom_out") then zoomSpeed = zoomSpeed + 1 end
    if zoomSpeed ~= 0 then
        renderer:zoomCamera(zoomSpeed * 6.5 * dt)
    end

    -- 5-Minute Clocks (in Offline PvP & Online modes)
    if timers.enabled and not gameLogic.isGameOver and not activeDrop then
        if gameLogic.currentPlayer == BoardLogic.Player.WHITE then
            timers.white = math.max(0.0, timers.white - dt)
            if timers.white <= 0.0 then
                gameLogic.isGameOver = true
                gameLogic.winner = BoardLogic.Player.BLACK
                gameLogic.timeoutWinner = BoardLogic.Player.BLACK
                finalizeGameEnd()
            end
        else
            timers.black = math.max(0.0, timers.black - dt)
            if timers.black <= 0.0 then
                gameLogic.isGameOver = true
                gameLogic.winner = BoardLogic.Player.WHITE
                gameLogic.timeoutWinner = BoardLogic.Player.WHITE
                finalizeGameEnd()
            end
        end
    end

    -- Piece drop animation
    if activeDrop then
        activeDrop.elapsed = activeDrop.elapsed + dt
        local t = math.min(1.0, activeDrop.elapsed / activeDrop.duration)
        local eased = easeOutBounce(t)
        activeDrop.currentY = activeDrop.startY + (activeDrop.targetY - activeDrop.startY) * eased
        if t >= 1.0 then
            local res = activeDrop.moveResult
            activeDrop = nil
            Sound.playDrop(Config.getBoardSkin().soundType)
            if res.isGameOver then
                finalizeGameEnd()
            elseif isBotTurn() then
                botTimer = 0.38
            end
        end
    end

    -- Bot move timer
    if botTimer then
        botTimer = botTimer - dt
        if botTimer <= 0 then
            botTimer = nil
            performBotMove()
        end
    end

    -- Raycast hover on pegs (on desktop mouse mode; on touch devices 1st tap sets hoveredX/Z)
    if not isTouchDevice then
        local mx, my = love.mouse.getPosition()
        if not isReplayMode and not gameLogic.isGameOver and not activeDrop and isLocalPlayerTurn() and not mouseState.dragged then
            local nx, nz, ny = renderer:pickPegAtScreenPos(mx, my, sw, sh, gameLogic)
            if (nx ~= hoveredX or nz ~= hoveredZ or ny ~= hoveredY) and nx ~= nil then
                Sound.play("hover")
            end
            hoveredX, hoveredZ, hoveredY = nx, nz, ny
        else
            hoveredX, hoveredZ, hoveredY = nil, nil, nil
        end
    end
end

local function drawButton(id, x, y, w, h, label, opts)
    opts = opts or {}
    local ui = Config.getUITheme()
    local mx, my = getUIMousePos()
    local hovered = mx >= x and mx <= x + w and my >= y and my <= y + h

    if opts.disabled then
        love.graphics.setColor(0.18, 0.19, 0.22, 0.90)
        love.graphics.rectangle("fill", x, y, w, h, 10, 10)
        love.graphics.setColor(0.35, 0.38, 0.44, 0.70)
        love.graphics.setLineWidth(1.2)
        love.graphics.rectangle("line", x, y, w, h, 10, 10)
        local f = opts.font or fonts.btn
        love.graphics.setFont(f)
        love.graphics.setColor(0.55, 0.58, 0.65, 0.85)
        local _, wrapped = f:getWrap(label, w - 14)
        local totalH = #wrapped * f:getHeight()
        love.graphics.printf(label, x + 7, y + (h - totalH) * 0.5, w - 14, "center")
        table.insert(uiButtons, { id = id, x = x, y = y, w = w, h = h, onClick = opts.onClick or function() end })
        return
    end

    local bg = opts.primary and ui.btnPrimary or ui.btnDefault
    if opts.active then
        bg = ui.btnActive
    elseif opts.accent then
        bg = ui.btnAccent
    end
    if hovered then
        bg = { math.min(1, bg[1] + 0.08), math.min(1, bg[2] + 0.08), math.min(1, bg[3] + 0.08), 1.0 }
    end

    love.graphics.setColor(bg)
    love.graphics.rectangle("fill", x, y, w, h, 10, 10)

    love.graphics.setColor(hovered and ui.btnHoverBorder or ui.btnBorder)
    love.graphics.setLineWidth(1.5)
    love.graphics.rectangle("line", x, y, w, h, 10, 10)

    local f = opts.font or fonts.btn
    love.graphics.setFont(f)
    love.graphics.setColor(ui.textMain)
    local _, wrapped = f:getWrap(label, w - 14)
    local totalH = #wrapped * f:getHeight()
    love.graphics.printf(label, x + 7, y + (h - totalH) * 0.5, w - 14, "center")

    table.insert(uiButtons, { id = id, x = x, y = y, w = w, h = h, onClick = opts.onClick })
end

local function drawPanel(x, y, w, h)
    local ui = Config.getUITheme()
    love.graphics.setColor(ui.panelBg)
    love.graphics.rectangle("fill", x, y, w, h, 14, 14)
    love.graphics.setColor(ui.panelBorder)
    love.graphics.setLineWidth(1.8)
    love.graphics.rectangle("line", x, y, w, h, 14, 14)
end

local function drawTorusBadge(cx, cy, outerR, color)
    local ui = Config.getUITheme()
    love.graphics.setColor(color[1], color[2], color[3], 1.0)
    love.graphics.circle("fill", cx, cy, outerR)
    love.graphics.setColor(ui.panelBg)
    love.graphics.circle("fill", cx, cy, outerR * 0.42)
    love.graphics.setColor(ui.panelBorder)
    love.graphics.setLineWidth(1.5)
    love.graphics.circle("line", cx, cy, outerR)
end

local function formatClock(sec)
    local total = math.max(0, math.ceil(sec))
    local m = math.floor(total / 60)
    local s = total % 60
    return string.format("%02d:%02d", m, s)
end

-- Top-Right Profile Icon button with clean Vector ELO star icon (no missing glyph boxes!)
local function drawProfileCornerButton(sw)
    local ui = Config.getUITheme()
    local bw, bh = 220, 54
    local bx, by = sw - bw - 24, 20
    local mx, my = getUIMousePos()
    local hovered = mx >= bx and mx <= bx + bw and my >= by and my <= by + bh

    love.graphics.setColor(hovered and ui.btnPrimary or ui.panelBg)
    love.graphics.rectangle("fill", bx, by, bw, bh, 27, 27)
    love.graphics.setColor(hovered and ui.btnHoverBorder or ui.panelBorder)
    love.graphics.setLineWidth(1.5)
    love.graphics.rectangle("line", bx, by, bw, bh, 27, 27)

    -- Avatar icon
    drawUserAvatar(bx + 28, by + 27, 18)

    love.graphics.setFont(fonts.btn)
    love.graphics.setColor(ui.textMain)
    love.graphics.print(Config.profile.username, bx + 54, by + 8)

    -- Vector Star + ELO 800
    drawStarIcon(bx + 61, by + 37, 6.5, { 0.95, 0.78, 0.28, 1.0 })
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(ui.accentText)
    love.graphics.print("ELO " .. tostring(Config.profile.rating), bx + 72, by + 29)

    table.insert(uiButtons, {
        id = "open_profile",
        x = bx, y = by, w = bw, h = bh,
        onClick = function()
            Sound.play("click")
            friendStatusFeedback = nil
            refreshFriendsState()
            currentScreen = "profile_modal"
        end
    })
end

local function drawLeftMainMenu(sw, sh)
    local ui = Config.getUITheme()
    local pw, ph = 340, 500
    local isPortrait = (sw < sh)
    local px = isPortrait and ((sw - pw) * 0.5) or 44
    local py = isPortrait and math.max(84, sh - ph - 24) or math.max(24, (sh - ph) * 0.5)
    drawPanel(px, py, pw, ph)

    love.graphics.setFont(fonts.title)
    love.graphics.setColor(ui.textMain)
    love.graphics.printf(I18N.t("title"), px + 16, py + 24, pw - 32, "center")

    local bx = px + 28
    local bw = pw - 56

    -- 1. PLAY OFFLINE
    drawButton("btn_offline", bx, py + 82, bw, 68, I18N.t("play_offline"), {
        primary = true,
        onClick = function()
            Sound.play("click")
            startNewGame(Config.GameMode.LOCAL_PVP)
        end
    })

    -- 2. PLAY VS BOT
    drawButton("btn_bot", bx, py + 162, bw, 68, I18N.t("play_bot"), {
        onClick = function()
            Sound.play("click")
            currentScreen = "bot_modal"
        end
    })

    -- 3. PLAY ONLINE
    drawButton("btn_online", bx, py + 242, bw, 68, I18N.t("play_online"), {
        onClick = function()
            Sound.play("click")
            currentScreen = "online_modal"
        end
    })

    -- 4. SETTINGS
    drawButton("btn_settings", bx, py + 326, bw, 52, I18N.t("settings"), {
        onClick = function()
            Sound.play("click")
            currentScreen = "settings_modal"
        end
    })

    -- 5. SHOP
    drawButton("btn_shop", bx, py + 392, bw, 56, I18N.t("shop"), {
        accent = true,
        onClick = function()
            Sound.play("click")
            shopTab = "pieces"
            shopScrollX = 0
            shopTargetScrollX = 0
            currentScreen = "shop"
        end
    })

    drawProfileCornerButton(sw)
end

-- Bot Modal: 3-Step Difficulty Slider + Piece Color Selection (White / Black / Random)
local function drawBotModal(sw, sh)
    local ui = Config.getUITheme()
    local pw, ph = 520, 446
    local px, py = (sw - pw) * 0.5, (sh - ph) * 0.5
    drawPanel(px, py, pw, ph)

    love.graphics.setFont(fonts.h2)
    love.graphics.setColor(ui.textMain)
    love.graphics.printf(I18N.t("bot_title"), px, py + 20, pw, "center")

    love.graphics.setFont(fonts.btn)
    love.graphics.setColor(ui.textSub)
    love.graphics.printf(I18N.t("diff_label"), px, py + 62, pw, "center")

    local trackX = px + 76
    local trackW = pw - 152
    local trackY = py + 112

    love.graphics.setColor(ui.panelBorder)
    love.graphics.setLineWidth(6)
    love.graphics.line(trackX, trackY, trackX + trackW, trackY)

    local labels = { I18N.t("diff_easy"), I18N.t("diff_medium"), I18N.t("diff_hard") }
    for i = 1, 3 do
        local tx = trackX + ((i - 1) / 2) * trackW
        local isSelected = (Config.botDifficulty == i)

        love.graphics.setColor(isSelected and ui.textMain or ui.btnBorder)
        love.graphics.circle("fill", tx, trackY, isSelected and 15 or 10)
        love.graphics.setColor(ui.panelBg)
        love.graphics.circle("line", tx, trackY, isSelected and 15 or 10)

        love.graphics.setFont(isSelected and fonts.btn or fonts.body)
        love.graphics.setColor(isSelected and ui.textMain or ui.textSub)
        love.graphics.printf(labels[i], tx - 65, trackY + 22, 130, "center")

        table.insert(uiButtons, {
            id = "slider_tick_" .. i,
            x = tx - 45, y = trackY - 24, w = 90, h = 68,
            onClick = function()
                Sound.play("click")
                Config.botDifficulty = i
                Storage.save()
            end
        })
    end

    -- Piece Color Selection: White (1st) / Black (2nd) / Random
    love.graphics.setFont(fonts.btn)
    love.graphics.setColor(ui.textSub)
    love.graphics.printf(I18N.t("color_label"), px, py + 186, pw, "center")

    local colBtnW = (pw - 88) / 3
    local colChoices = {
        { id = "white",  label = I18N.t("color_white")  },
        { id = "black",  label = I18N.t("color_black")  },
        { id = "random", label = I18N.t("color_random") }
    }
    for i, c in ipairs(colChoices) do
        local cbx = px + 34 + (i - 1) * (colBtnW + 10)
        drawButton("bot_color_" .. c.id, cbx, py + 216, colBtnW, 44, c.label, {
            active = (Config.botColorChoice == c.id),
            font = fonts.small,
            onClick = function()
                Sound.play("click")
                Config.botColorChoice = c.id
                Storage.save()
            end
        })
    end

    -- Rule Mode: Standard (Gravity) vs Free (Any Height)
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(ui.textSub)
    love.graphics.printf(I18N.t("rule_mode_label"), px, py + 272, pw, "center")
    local rmW = (pw - 78) * 0.5
    drawButton("bot_rule_std", px + 34, py + 292, rmW, 38, I18N.t("rule_standard"), {
        active = (Config.ruleMode == "standard"),
        font = fonts.small,
        onClick = function()
            Sound.play("click")
            Config.ruleMode = "standard"
            Storage.save()
        end
    })
    drawButton("bot_rule_free", px + 44 + rmW, py + 292, rmW, 38, I18N.t("rule_free"), {
        active = (Config.ruleMode == "free"),
        font = fonts.small,
        onClick = function()
            Sound.play("click")
            Config.ruleMode = "free"
            Storage.save()
        end
    })

    -- Bottom-left Back & Bottom-right Play
    drawButton("bot_back", px + 34, py + ph - 62, 155, 44, I18N.t("back_btn"), {
        onClick = function()
            Sound.play("click")
            currentScreen = "menu"
        end
    })
    drawButton("bot_play", px + pw - 189, py + ph - 62, 155, 44, I18N.t("play_btn"), {
        primary = true,
        onClick = function()
            Sound.play("click")
            startNewGame(Config.GameMode.VS_BOT, Config.botDifficulty)
        end
    })
end

local function drawOnlineModal(sw, sh)
    local ui = Config.getUITheme()
    local pw, ph = 560, 520
    local px, py = (sw - pw) * 0.5, (sh - ph) * 0.5
    drawPanel(px, py, pw, ph)

    love.graphics.setFont(fonts.h2)
    love.graphics.setColor(ui.textMain)
    love.graphics.printf(I18N.t("online_title"), px, py + 16, pw, "center")

    -- Реальный счётчик игроков онлайн в правом верхнем углу окна
    local badgeW, badgeH = 78, 28
    local badgeX, badgeY = px + pw - badgeW - 18, py + 16
    love.graphics.setColor(ui.bgClear)
    love.graphics.rectangle("fill", badgeX, badgeY, badgeW, badgeH, 14, 14)
    love.graphics.setColor(ui.panelBorder)
    love.graphics.setLineWidth(1.2)
    love.graphics.rectangle("line", badgeX, badgeY, badgeW, badgeH, 14, 14)

    local pulse = 0.75 + 0.25 * math.sin(love.timer.getTime() * 3.2)
    love.graphics.setColor(0.24, 0.86, 0.48, pulse)
    love.graphics.circle("fill", badgeX + 13, badgeY + 14, 3.8)
    love.graphics.setColor(ui.textSub)
    love.graphics.circle("fill", badgeX + 27, badgeY + 10.5, 3.2)
    love.graphics.arc("fill", badgeX + 27, badgeY + 20.5, 5.8, math.pi * 1.12, math.pi * 1.88)

    love.graphics.setFont(fonts.small)
    love.graphics.setColor(ui.textMain)
    love.graphics.printf(tostring(math.max(1, Config.onlinePlayersCount or 1)), badgeX + 35, badgeY + 7, badgeW - 40, "center")

    if matchmakingState.active then
        -- Экран поиска соперника: крутящееся колесико, ориентировочное время, активные партии и игроки
        local cx, cy = px + pw * 0.5, py + 175
        local spin = love.timer.getTime() * 4.5
        love.graphics.setColor(ui.panelBorder)
        love.graphics.setLineWidth(5)
        love.graphics.circle("line", cx, cy, 34)
        love.graphics.setColor(0.32, 0.76, 0.98, 1.0)
        love.graphics.arc("line", "open", cx, cy, 34, spin, spin + math.pi * 0.85)

        love.graphics.setFont(fonts.h2)
        love.graphics.setColor(ui.textMain)
        love.graphics.printf("Поиск соперника...", px, cy + 52, pw, "center")

        love.graphics.setFont(fonts.body)
        love.graphics.setColor(ui.textSub)
        love.graphics.printf(string.format("(Ориентировочное время: ~15 сек)  •  %ds", math.floor(matchmakingState.timer)), px, cy + 88, pw, "center")
        love.graphics.printf(string.format("Активных партий: %d", Config.onlineActiveGames or 0), px, cy + 122, pw, "center")
        love.graphics.printf(string.format("Активных игроков: %d", math.max(1, Config.onlinePlayersCount or 1)), px, cy + 146, pw, "center")

        drawButton("online_cancel_search", px + pw * 0.5 - 100, py + ph - 66, 200, 44, I18N.t("back_btn"), {
            onClick = function()
                Sound.play("click")
                matchmakingState.active = false
                matchmakingState.timer = 0
            end
        })
        return
    end

    love.graphics.setFont(fonts.body)
    love.graphics.setColor(ui.textSub)
    love.graphics.printf(I18N.t("online_desc"), px + 30, py + 50, pw - 60, "center")

    local bx, bw = px + 44, pw - 88
    local halfW = (bw - 12) * 0.5

    -- Time Control: 5m vs 1m
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(ui.textSub)
    love.graphics.printf(I18N.t("time_control_label"), bx, py + 96, bw, "center")

    drawButton("online_time_5m", bx, py + 116, halfW, 38, I18N.t("time_5m"), {
        active = (Config.onlineTimeMinutes == 5),
        font = fonts.small,
        onClick = function() Sound.play("click"); Config.onlineTimeMinutes = 5; Storage.save() end
    })
    drawButton("online_time_1m", bx + halfW + 12, py + 116, halfW, 38, I18N.t("time_1m"), {
        active = (Config.onlineTimeMinutes == 1),
        font = fonts.small,
        onClick = function() Sound.play("click"); Config.onlineTimeMinutes = 1; Storage.save() end
    })

    -- Rule Mode: Standard vs Free
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(ui.textSub)
    love.graphics.printf(I18N.t("rule_mode_label"), bx, py + 162, bw, "center")
    drawButton("online_rule_std", bx, py + 182, halfW, 36, I18N.t("rule_standard"), {
        active = (Config.ruleMode == "standard"),
        font = fonts.small,
        onClick = function() Sound.play("click"); Config.ruleMode = "standard"; Storage.save() end
    })
    drawButton("online_rule_free", bx + halfW + 12, py + 182, halfW, 36, I18N.t("rule_free"), {
        active = (Config.ruleMode == "free"),
        font = fonts.small,
        onClick = function() Sound.play("click"); Config.ruleMode = "free"; Storage.save() end
    })

    drawButton("online_reg", bx, py + 232, halfW, 42, I18N.t("register_btn"), {
        accent = true,
        onClick = function() Sound.play("click"); openAuthModal("register") end
    })
    drawButton("online_signin", bx + halfW + 12, py + 232, halfW, 42, I18N.t("signin_btn"), {
        onClick = function() Sound.play("click"); openAuthModal("login") end
    })

    drawButton("online_guest", bx, py + 284, halfW, 44, I18N.t("play_guest_btn"), {
        primary = true,
        font = fonts.small,
        onClick = function()
            Sound.play("click")
            matchmakingState.active = true
            matchmakingState.timer = 0
        end
    })
    drawButton("online_friends", bx + halfW + 12, py + 284, halfW, 44, I18N.t("play_friend_btn"), {
        accent = true,
        font = fonts.small,
        onClick = function()
            Sound.play("click")
            friendGameUI.errorMsg = nil
            friendStatusFeedback = nil
            if Config.profile.isRegistered then
                friendGameUI.view = friendGameUI.room and "lobby" or "list"
                refreshFriendsState()
            else
                friendGameUI.view = "list"
            end
            currentScreen = "friend_game_modal"
        end
    })

    drawButton("online_tournament", bx, py + 338, halfW, 42, I18N.t("tournament_btn"), {
        accent = true,
        font = fonts.small,
        onClick = function()
            Sound.play("click")
            tournamentUI.view = Tournament.active and "room" or "hub"
            tournamentUI.errorMsg = nil
            currentScreen = "tournament_modal"
        end
    })
    drawButton("online_lan", bx + halfW + 12, py + 338, halfW, 42, I18N.t("lan_btn"), {
        active = true,
        font = fonts.small,
        onClick = function()
            Sound.play("click")
            LAN.stop()
            lanIpFocused = false
            currentScreen = "lan_modal"
        end
    })

    love.graphics.setFont(fonts.small)
    love.graphics.setColor(ui.textSub)
    love.graphics.printf(I18N.t("online_stub_note"), px + 28, py + 392, pw - 56, "center")

    drawButton("online_back", px + pw * 0.5 - 80, py + ph - 52, 160, 40, I18N.t("back_btn"), {
        onClick = function()
            Sound.play("click")
            currentScreen = "menu"
        end
    })
end

local function drawFriendGameModal(sw, sh)
    local ui = Config.getUITheme()
    local p = Config.profile
    if not p.isRegistered then
        local pw, ph = 520, 290
        local px, py = (sw - pw) * 0.5, (sh - ph) * 0.5
        drawPanel(px, py, pw, ph)
        love.graphics.setFont(fonts.h2)
        love.graphics.setColor(ui.textMain)
        love.graphics.printf(I18N.t("friend_game_title"), px, py + 24, pw, "center")

        love.graphics.setFont(fonts.body)
        love.graphics.setColor(ui.textSub)
        love.graphics.printf(I18N.t("friends_reg_only"), px + 36, py + 84, pw - 72, "center")

        local bx, bw = px + 44, pw - 88
        local halfW = (bw - 12) * 0.5
        drawButton("fg_reg_btn", bx, py + 158, halfW, 42, I18N.t("register_btn"), {
            accent = true,
            onClick = function() Sound.play("click"); openAuthModal("register") end
        })
        drawButton("fg_login_btn", bx + halfW + 12, py + 158, halfW, 42, I18N.t("signin_btn"), {
            onClick = function() Sound.play("click"); openAuthModal("login") end
        })
        drawButton("fg_unreg_back", px + pw * 0.5 - 85, py + ph - 56, 170, 40, I18N.t("back_btn"), {
            onClick = function() Sound.play("click"); currentScreen = "online_modal" end
        })
        return
    end

    local pw, ph = 760, 560
    local px, py = (sw - pw) * 0.5, (sh - ph) * 0.5
    drawPanel(px, py, pw, ph)

    love.graphics.setFont(fonts.h2)
    love.graphics.setColor(ui.textMain)
    love.graphics.printf(I18N.t("friend_game_title"), px, py + 18, pw, "center")

    -- Navigation tabs: Friends List (N/50) | Create Room | Join by Code
    local tabW = (pw - 84) / 3
    drawButton("fg_tab_list", px + 30, py + 56, tabW, 36, I18N.t("friends_title") .. " (" .. tostring(#(p.friends or {})) .. "/50)", {
        active = (friendGameUI.view == "list"),
        font = fonts.small,
        onClick = function()
            Sound.play("click")
            friendGameUI.view = "list"
            friendGameUI.errorMsg = nil
            refreshFriendsState()
        end
    })
    drawButton("fg_tab_create", px + 42 + tabW, py + 56, tabW, 36, I18N.t("friend_create_room"), {
        active = (friendGameUI.view == "lobby"),
        accent = true,
        font = fonts.small,
        onClick = function()
            Sound.play("click")
            startFriendRoomLobby(nil)
        end
    })
    drawButton("fg_tab_join", px + 54 + tabW * 2, py + 56, tabW, 36, I18N.t("friend_join_room"), {
        active = (friendGameUI.view == "join"),
        font = fonts.small,
        onClick = function()
            Sound.play("click")
            friendGameUI.view = "join"
            friendGameUI.errorMsg = nil
            pcall(love.keyboard.setTextInput, true)
        end
    })

    if friendGameUI.view == "lobby" and friendGameUI.room then
        local room = friendGameUI.room
        love.graphics.setColor(ui.bgClear)
        love.graphics.rectangle("fill", px + 90, py + 132, pw - 180, 270, 12, 12)
        love.graphics.setColor(ui.panelBorder)
        love.graphics.rectangle("line", px + 90, py + 132, pw - 180, 270, 12, 12)

        love.graphics.setFont(fonts.body)
        love.graphics.setColor(ui.textSub)
        love.graphics.printf(I18N.t("friend_room_code_label"), px + 90, py + 154, pw - 180, "center")

        love.graphics.setFont(fonts.title)
        love.graphics.setColor(ui.accentText)
        love.graphics.printf(tostring(room.code or "------"), px + 90, py + 190, pw - 180, "center")

        local ruleStr = (room.ruleMode == "free") and I18N.t("rule_free") or I18N.t("rule_standard")
        local timeStr = tostring(room.timeMinutes or 5) .. "m"
        love.graphics.setFont(fonts.small)
        love.graphics.setColor(ui.textSub)
        love.graphics.printf(ruleStr .. "  •  " .. timeStr, px + 90, py + 244, pw - 180, "center")

        local pulse = 0.65 + 0.35 * math.sin(love.timer.getTime() * 3.0)
        love.graphics.setFont(fonts.btn)
        love.graphics.setColor(ui.textMain[1], ui.textMain[2], ui.textMain[3], pulse)
        love.graphics.printf(I18N.t("friend_waiting_room"), px + 90, py + 280, pw - 180, "center")

        love.graphics.setFont(fonts.small)
        love.graphics.setColor(ui.textSub)
        love.graphics.printf(I18N.t("friend_waiting_hint"), px + 110, py + 314, pw - 220, "center")

        drawButton("fg_cancel_room", px + pw * 0.5 - 110, py + 348, 220, 38, I18N.t("friend_cancel_room"), {
            onClick = function()
                Sound.play("click")
                Firebase.closeFriendRoom(room.code)
                friendGameUI.room = nil
                friendGameUI.view = "list"
            end
        })
    elseif friendGameUI.view == "join" then
        love.graphics.setColor(ui.bgClear)
        love.graphics.rectangle("fill", px + 110, py + 140, pw - 220, 240, 12, 12)
        love.graphics.setColor(ui.panelBorder)
        love.graphics.rectangle("line", px + 110, py + 140, pw - 220, 240, 12, 12)

        love.graphics.setFont(fonts.body)
        love.graphics.setColor(ui.textMain)
        love.graphics.printf(I18N.t("friend_room_code_label"), px + 110, py + 164, pw - 220, "center")

        local boxX, boxY, boxW, boxH = px + pw * 0.5 - 130, py + 200, 260, 48
        love.graphics.setColor(ui.panelBg)
        love.graphics.rectangle("fill", boxX, boxY, boxW, boxH, 8, 8)
        love.graphics.setColor(ui.btnHoverBorder)
        love.graphics.rectangle("line", boxX, boxY, boxW, boxH, 8, 8)

        local blink = (math.floor(love.timer.getTime() * 2) % 2 == 0) and "|" or ""
        love.graphics.setFont(fonts.h2)
        love.graphics.setColor(ui.textMain)
        love.graphics.printf((friendGameUI.joinCode or "") .. blink, boxX, boxY + 11, boxW, "center")
        table.insert(uiButtons, {
            id = "fg_code_focus",
            x = boxX, y = boxY, w = boxW, h = boxH,
            onClick = function() pcall(love.keyboard.setTextInput, true) end
        })

        drawButton("fg_join_confirm", px + pw * 0.5 - 110, py + 266, 220, 44, I18N.t("friend_join_room"), {
            primary = true,
            onClick = function()
                Sound.play("click")
                local code = (friendGameUI.joinCode or ""):upper()
                if #code < 4 then
                    friendGameUI.errorMsg = I18N.t("friend_room_not_found")
                    return
                end
                local okJoin, roomOrErr = Firebase.joinFriendRoom(code, p.username)
                if okJoin and type(roomOrErr) == "table" then
                    friendGameUI.errorMsg = nil
                    friendGameUI.room = nil
                    localOnlineRoom = {
                        code = roomOrErr.code,
                        role = "guest",
                        opponent = roomOrErr.host,
                        ruleMode = roomOrErr.ruleMode or Config.ruleMode,
                        timeMinutes = tonumber(roomOrErr.timeMinutes) or 5,
                        lastMoveCount = 0,
                        pollTimer = 0
                    }
                    startNewGame(Config.GameMode.ONLINE)
                else
                    friendGameUI.errorMsg = I18N.t("friend_room_not_found")
                end
            end
        })

        if friendGameUI.errorMsg then
            love.graphics.setFont(fonts.small)
            love.graphics.setColor(0.95, 0.38, 0.38, 1.0)
            love.graphics.printf(friendGameUI.errorMsg, px + 110, py + 324, pw - 220, "center")
        end
    else
        -- Friends List + Search + Live Invites + Online/Last Seen Status
        local sy = py + 104
        love.graphics.setColor(ui.bgClear)
        love.graphics.rectangle("fill", px + 30, sy, 260, 34, 6, 6)
        love.graphics.setColor(ui.panelBorder)
        love.graphics.rectangle("line", px + 30, sy, 260, 34, 6, 6)
        love.graphics.setFont(fonts.small)
        love.graphics.setColor(friendSearchText ~= "" and ui.textMain or ui.textSub)
        love.graphics.print(friendSearchText ~= "" and friendSearchText or I18N.t("friend_search"), px + 40, sy + 10)
        table.insert(uiButtons, {
            id = "fg_search_focus",
            x = px + 30, y = sy, w = 260, h = 34,
            onClick = function() pcall(love.keyboard.setTextInput, true) end
        })

        drawButton("fg_add_friend", px + 298, sy, 120, 34, I18N.t("friend_add"), {
            primary = true,
            font = fonts.small,
            onClick = function()
                Sound.play("click")
                if #friendSearchText >= 3 then
                    local okAdd, errKey = Config.sendFriendRequest(friendSearchText)
                    if okAdd then
                        friendSearchText = ""
                        friendStatusFeedback = nil
                    else
                        friendStatusFeedback = I18N.t(errKey or "friend_not_found")
                    end
                    Storage.save()
                    refreshFriendsState()
                end
            end
        })

        if friendStatusFeedback then
            love.graphics.setFont(fonts.small)
            love.graphics.setColor(0.95, 0.45, 0.38, 1.0)
            love.graphics.print(friendStatusFeedback, px + 430, sy + 10)
        end

        local listTop = py + 148
        -- Pending game invite banner
        if #(friendGameUI.invites or {}) > 0 then
            local inv = friendGameUI.invites[1]
            love.graphics.setColor(0.18, 0.40, 0.28, 0.95)
            love.graphics.rectangle("fill", px + 30, listTop, pw - 60, 36, 8, 8)
            love.graphics.setColor(0.32, 0.85, 0.52, 1.0)
            love.graphics.rectangle("line", px + 30, listTop, pw - 60, 36, 8, 8)
            love.graphics.setFont(fonts.small)
            love.graphics.setColor(ui.textMain)
            love.graphics.print(I18N.t("friend_invite_from", inv.from or "?", inv.code or ""), px + 42, listTop + 10)

            drawButton("fg_acc_inv", px + pw - 210, listTop + 5, 96, 26, I18N.t("friend_accept"), {
                primary = true, font = fonts.small,
                onClick = function()
                    Sound.play("click")
                    Firebase.clearGameInvite(p.username, inv.from)
                    local okJoin, roomOrErr = Firebase.joinFriendRoom(inv.code, p.username)
                    if okJoin and type(roomOrErr) == "table" then
                        localOnlineRoom = {
                            code = roomOrErr.code,
                            role = "guest",
                            opponent = roomOrErr.host,
                            ruleMode = roomOrErr.ruleMode or Config.ruleMode,
                            timeMinutes = tonumber(roomOrErr.timeMinutes) or 5,
                            lastMoveCount = 0,
                            pollTimer = 0
                        }
                        friendGameUI.invites = {}
                        startNewGame(Config.GameMode.ONLINE)
                    else
                        friendStatusFeedback = I18N.t("friend_room_not_found")
                        refreshFriendsState()
                    end
                end
            })
            drawButton("fg_dec_inv", px + pw - 108, listTop + 5, 68, 26, I18N.t("friend_decline"), {
                font = fonts.small,
                onClick = function()
                    Sound.play("click")
                    Firebase.clearGameInvite(p.username, inv.from)
                    refreshFriendsState()
                end
            })
            listTop = listTop + 44
        end

        -- Pending incoming friend request banner (up to 1 inline)
        if #(p.incomingRequests or {}) > 0 then
            local reqName = p.incomingRequests[1]
            love.graphics.setColor(ui.bgClear)
            love.graphics.rectangle("fill", px + 30, listTop, pw - 60, 34, 6, 6)
            love.graphics.setColor(ui.panelBorder)
            love.graphics.rectangle("line", px + 30, listTop, pw - 60, 34, 6, 6)
            love.graphics.setFont(fonts.small)
            love.graphics.setColor(ui.accentText)
            love.graphics.print("+ " .. reqName, px + 42, listTop + 9)
            drawButton("fg_req_acc", px + pw - 210, listTop + 4, 86, 26, I18N.t("friend_accept"), {
                primary = true, font = fonts.small,
                onClick = function()
                    Sound.play("click")
                    local okA, errA = Config.acceptFriendRequest(reqName)
                    if not okA and errA then friendStatusFeedback = I18N.t(errA) end
                    Storage.save()
                    refreshFriendsState()
                end
            })
            drawButton("fg_req_dec", px + pw - 118, listTop + 4, 78, 26, I18N.t("friend_decline"), {
                font = fonts.small,
                onClick = function()
                    Sound.play("click")
                    Config.declineFriendRequest(reqName)
                    Storage.save()
                    refreshFriendsState()
                end
            })
            listTop = listTop + 42
        end

        local friends = p.friends or {}
        if #friends == 0 then
            love.graphics.setFont(fonts.body)
            love.graphics.setColor(ui.textSub)
            love.graphics.printf(I18N.t("friend_empty_list"), px + 40, listTop + 48, pw - 80, "center")
        else
            local listH = (py + ph - 68) - listTop
            local rowH = 44
            local maxVisible = math.max(1, math.floor(listH / (rowH + 6)))
            local maxScroll = math.max(0, #friends - maxVisible)
            friendGameUI.listScroll = math.max(0, math.min(maxScroll, friendGameUI.listScroll or 0))

            for idx = 1, maxVisible do
                local fi = idx + friendGameUI.listScroll
                local fn = friends[fi]
                if not fn then break end
                local ry = listTop + (idx - 1) * (rowH + 6)
                love.graphics.setColor(ui.bgClear)
                love.graphics.rectangle("fill", px + 30, ry, pw - 60, rowH, 8, 8)
                love.graphics.setColor(ui.panelBorder)
                love.graphics.rectangle("line", px + 30, ry, pw - 60, rowH, 8, 8)

                local pres = friendStatusCache[fn:lower()] or {}
                local isOnline, statusText = formatLastSeen(pres.ts, pres.inGame)
                love.graphics.setColor(isOnline and { 0.22, 0.88, 0.45, 1.0 } or { 0.48, 0.52, 0.58, 1.0 })
                love.graphics.circle("fill", px + 48, ry + rowH * 0.5, 5.5)

                love.graphics.setFont(fonts.btn)
                love.graphics.setColor(ui.textMain)
                love.graphics.print(fn, px + 64, ry + 5)

                love.graphics.setFont(fonts.small)
                love.graphics.setColor(isOnline and { 0.35, 0.90, 0.55, 1.0 } or ui.textSub)
                love.graphics.print(statusText, px + 64, ry + 24)

                drawButton("fg_prof_" .. fi, px + pw - 294, ry + 7, 102, 30, I18N.t("friend_profile_title"), {
                    font = fonts.small,
                    onClick = function()
                        Sound.play("click")
                        openFriendProfile(fn, "friend_game_modal")
                    end
                })
                drawButton("fg_inv_" .. fi, px + pw - 186, ry + 7, 106, 30, I18N.t("friend_invite_btn"), {
                    primary = true, font = fonts.small,
                    onClick = function()
                        Sound.play("click")
                        startFriendRoomLobby(fn)
                    end
                })
                drawButton("fg_rem_" .. fi, px + pw - 74, ry + 7, 34, 30, "X", {
                    font = fonts.small,
                    onClick = function()
                        Sound.play("click")
                        Config.removeFriend(fn)
                        Storage.save()
                        refreshFriendsState()
                    end
                })
            end
        end
    end

    drawButton("fg_back", px + pw * 0.5 - 90, py + ph - 54, 180, 40, I18N.t("back_btn"), {
        onClick = function()
            Sound.play("click")
            if friendGameUI.room then
                Firebase.closeFriendRoom(friendGameUI.room.code)
                friendGameUI.room = nil
            end
            currentScreen = "online_modal"
        end
    })
end

local function drawFriendProfileModal(sw, sh)
    local ui = Config.getUITheme()
    local fp = viewedFriendProfile
    if not fp then
        currentScreen = friendProfileReturnScreen or "profile_modal"
        return
    end
    local pw, ph = 660, 510
    local px, py = (sw - pw) * 0.5, (sh - ph) * 0.5
    drawPanel(px, py, pw, ph)

    love.graphics.setFont(fonts.h2)
    love.graphics.setColor(ui.textMain)
    love.graphics.printf(I18N.t("friend_profile_title") .. " — " .. tostring(fp.username), px, py + 18, pw, "center")

    -- Avatar circle + online status + Registration date
    local acx, acy = px + 62, py + 86
    local presets = {
        { 0.25, 0.58, 0.88 }, { 0.85, 0.36, 0.36 }, { 0.28, 0.72, 0.48 },
        { 0.78, 0.55, 0.22 }, { 0.62, 0.42, 0.85 }, { 0.22, 0.68, 0.74 }
    }
    local acol = presets[((fp.avatarPreset or 1) - 1) % #presets + 1]
    love.graphics.setColor(acol[1], acol[2], acol[3], 1.0)
    love.graphics.circle("fill", acx, acy, 28)
    love.graphics.setColor(ui.panelBorder)
    love.graphics.circle("line", acx, acy, 28)
    love.graphics.setFont(fonts.h2)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf((fp.username or "?"):sub(1, 1):upper(), acx - 28, acy - 13, 56, "center")

    local isOnline, statusText = formatLastSeen(fp.lastSeen, fp.inGameNow)
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(isOnline and { 0.30, 0.90, 0.50, 1.0 } or ui.textSub)
    love.graphics.print(statusText, px + 106, py + 62)

    love.graphics.setColor(ui.accentText)
    love.graphics.print(I18N.t("profile_registered_at", fp.createdAtStr or "—"), px + 106, py + 82)

    love.graphics.setFont(fonts.body)
    love.graphics.setColor(ui.textMain)
    love.graphics.print(I18N.t("profile_games", fp.gamesPlayed or 0, fp.wins or 0, fp.losses or 0, fp.draws or 0), px + 106, py + 104)

    -- All 4 ELO ratings
    love.graphics.setFont(fonts.btn)
    love.graphics.setColor(ui.textMain)
    love.graphics.print(I18N.t("friend_all_elo"), px + 34, py + 140)

    local eloModes = { "std_blitz", "std_bullet", "free_blitz", "free_bullet" }
    local cardW = (pw - 92) / 4
    for i, em in ipairs(eloModes) do
        local cx = px + 34 + (i - 1) * (cardW + 8)
        local cy = py + 168
        love.graphics.setColor(ui.bgClear)
        love.graphics.rectangle("fill", cx, cy, cardW, 64, 8, 8)
        love.graphics.setColor(ui.panelBorder)
        love.graphics.rectangle("line", cx, cy, cardW, 64, 8, 8)
        love.graphics.setFont(fonts.small)
        love.graphics.setColor(ui.textSub)
        love.graphics.printf(I18N.t("elo_" .. em), cx + 4, cy + 8, cardW - 8, "center")
        love.graphics.setFont(fonts.h2)
        love.graphics.setColor(ui.accentText)
        local val = (fp.ratings and fp.ratings[em]) or fp.rating or 800
        love.graphics.printf(tostring(val), cx + 4, cy + 32, cardW - 8, "center")
    end

    -- Friend's earned achievements
    love.graphics.setFont(fonts.btn)
    love.graphics.setColor(ui.textMain)
    love.graphics.print(I18N.t("profile_achievements"), px + 34, py + 250)

    local earnedAchs = {}
    for _, a in ipairs(ACHIEVEMENTS_META) do
        if fp.achievements and fp.achievements[a.id] then
            table.insert(earnedAchs, a)
        end
    end
    if #earnedAchs == 0 then
        love.graphics.setFont(fonts.small)
        love.graphics.setColor(ui.textSub)
        love.graphics.print(I18N.t("no_achievements_yet"), px + 34, py + 284)
    else
        local badgeSize, gap = 52, 10
        for i, a in ipairs(earnedAchs) do
            if i <= 9 then
                local abx = px + 34 + (i - 1) * (badgeSize + gap)
                local aby = py + 280
                love.graphics.setColor(0.22, 0.68, 0.44, 1.0)
                love.graphics.rectangle("fill", abx, aby, badgeSize, 42, 8, 8)
                love.graphics.setColor(selectedAchievementId == a.id and ui.accentText or ui.panelBorder)
                love.graphics.rectangle("line", abx, aby, badgeSize, 42, 8, 8)
                love.graphics.setFont(fonts.small)
                love.graphics.setColor(ui.textMain)
                love.graphics.printf(a.icon, abx, aby + 13, badgeSize, "center")
                table.insert(uiButtons, {
                    id = "fp_ach_" .. a.id,
                    x = abx, y = aby, w = badgeSize, h = 42,
                    onClick = function()
                        Sound.play("click")
                        selectedAchievementId = (selectedAchievementId == a.id) and nil or a.id
                    end
                })
            end
        end
    end

    if selectedAchievementId then
        for _, a in ipairs(ACHIEVEMENTS_META) do
            if a.id == selectedAchievementId then
                love.graphics.setColor(ui.bgClear)
                love.graphics.rectangle("fill", px + 34, py + 334, pw - 68, 30, 6, 6)
                love.graphics.setFont(fonts.small)
                love.graphics.setColor(ui.textMain)
                love.graphics.print(I18N.t(a.key) .. " — " .. I18N.t(a.desc), px + 44, py + 341)
            end
        end
    end

    if Config.profile.isRegistered then
        drawButton("fp_invite_play", px + pw * 0.5 - 195, py + ph - 58, 185, 42, I18N.t("friend_invite_btn"), {
            primary = true,
            onClick = function()
                Sound.play("click")
                startFriendRoomLobby(fp.username)
            end
        })
        drawButton("fp_back", px + pw * 0.5 + 10, py + ph - 58, 185, 42, I18N.t("back_btn"), {
            onClick = function()
                Sound.play("click")
                selectedAchievementId = nil
                currentScreen = friendProfileReturnScreen or "profile_modal"
            end
        })
    else
        drawButton("fp_back", px + pw * 0.5 - 90, py + ph - 58, 180, 42, I18N.t("back_btn"), {
            onClick = function()
                Sound.play("click")
                selectedAchievementId = nil
                currentScreen = friendProfileReturnScreen or "profile_modal"
            end
        })
    end
end

local function drawTournamentModal(sw, sh)
    local ui = Config.getUITheme()
    local pw, ph = 680, 520
    local px, py = (sw - pw) * 0.5, (sh - ph) * 0.5
    drawPanel(px, py, pw, ph)

    love.graphics.setFont(fonts.h2)
    love.graphics.setColor(ui.textMain)
    love.graphics.printf(I18N.t("tournament_title"), px, py + 16, pw, "center")

    local bx, bw = px + 36, pw - 72
    local halfW = (bw - 12) * 0.5

    if tournamentUI.view == "hub" then
        drawButton("tourn_go_create", bx, py + 120, bw, 56, I18N.t("tourn_create"), {
            primary = true,
            onClick = function() Sound.play("click"); tournamentUI.view = "create" end
        })
        drawButton("tourn_go_join", bx, py + 196, bw, 56, I18N.t("tourn_join"), {
            accent = true,
            onClick = function() Sound.play("click"); tournamentUI.view = "join"; tournamentUI.errorMsg = nil end
        })
    elseif tournamentUI.view == "create" then
        love.graphics.setFont(fonts.small)
        love.graphics.setColor(ui.textSub)
        love.graphics.print(I18N.t("tourn_system"), bx, py + 68)
        drawButton("tc_swiss", bx, py + 88, halfW, 36, I18N.t("tourn_swiss"), {
            active = (tournamentUI.system == "swiss"), font = fonts.small,
            onClick = function() Sound.play("click"); tournamentUI.system = "swiss" end
        })
        drawButton("tc_bracket", bx + halfW + 12, py + 88, halfW, 36, I18N.t("tourn_bracket"), {
            active = (tournamentUI.system == "bracket"), font = fonts.small,
            onClick = function() Sound.play("click"); tournamentUI.system = "bracket" end
        })

        love.graphics.setColor(ui.textSub)
        love.graphics.print(I18N.t("tourn_players"), bx, py + 134)
        drawButton("tc_p4", bx, py + 154, halfW, 36, "4", {
            active = (tournamentUI.maxPlayers == 4),
            onClick = function() Sound.play("click"); tournamentUI.maxPlayers = 4 end
        })
        drawButton("tc_p8", bx + halfW + 12, py + 154, halfW, 36, "8", {
            active = (tournamentUI.maxPlayers == 8),
            onClick = function() Sound.play("click"); tournamentUI.maxPlayers = 8 end
        })

        love.graphics.setColor(ui.textSub)
        love.graphics.print(I18N.t("time_control_label"), bx, py + 200)
        drawButton("tc_t5", bx, py + 220, halfW, 36, I18N.t("time_5m"), {
            active = (tournamentUI.timeMinutes == 5), font = fonts.small,
            onClick = function() Sound.play("click"); tournamentUI.timeMinutes = 5 end
        })
        drawButton("tc_t1", bx + halfW + 12, py + 220, halfW, 36, I18N.t("time_1m"), {
            active = (tournamentUI.timeMinutes == 1), font = fonts.small,
            onClick = function() Sound.play("click"); tournamentUI.timeMinutes = 1 end
        })

        drawButton("tc_bot_toggle", bx, py + 270, bw, 38, I18N.t("tourn_bot_mode") .. (tournamentUI.isBotTournament and " [ON]" or " [OFF]"), {
            active = tournamentUI.isBotTournament, font = fonts.small,
            onClick = function() Sound.play("click"); tournamentUI.isBotTournament = not tournamentUI.isBotTournament end
        })
        if tournamentUI.isBotTournament then
            local thirdW = (bw - 16) / 3
            for idx, d in ipairs({ { "easy", I18N.t("diff_easy") }, { "medium", I18N.t("diff_medium") }, { "hard", I18N.t("diff_hard") } }) do
                drawButton("tc_bdiff_" .. d[1], bx + (idx - 1) * (thirdW + 8), py + 318, thirdW, 34, d[2], {
                    active = (tournamentUI.botDifficulty == d[1]), font = fonts.small,
                    onClick = function() Sound.play("click"); tournamentUI.botDifficulty = d[1] end
                })
            end
        end

        drawButton("tc_submit", bx, py + ph - 112, bw, 44, I18N.t("tourn_create"), {
            primary = true,
            onClick = function()
                Sound.play("click")
                Tournament.create({
                    system = tournamentUI.system,
                    maxPlayers = tournamentUI.maxPlayers,
                    timeMinutes = tournamentUI.timeMinutes,
                    ruleMode = Config.ruleMode,
                    isBotTournament = tournamentUI.isBotTournament,
                    botDifficulty = tournamentUI.botDifficulty,
                    hostName = Config.profile.username
                })
                tournamentUI.view = "room"
            end
        })
    elseif tournamentUI.view == "join" then
        love.graphics.setFont(fonts.body)
        love.graphics.setColor(ui.textSub)
        love.graphics.print(I18N.t("tourn_code"), bx, py + 110)
        love.graphics.setColor(ui.bgClear)
        love.graphics.rectangle("fill", bx, py + 138, bw, 46, 8, 8)
        love.graphics.setColor(ui.panelBorder)
        love.graphics.rectangle("line", bx, py + 138, bw, 46, 8, 8)
        love.graphics.setFont(fonts.h2)
        love.graphics.setColor(ui.textMain)
        love.graphics.printf(tournamentUI.joinCode ~= "" and tournamentUI.joinCode or "XXXXXX", bx, py + 148, bw, "center")
        if tournamentUI.errorMsg then
            love.graphics.setFont(fonts.small)
            love.graphics.setColor(0.95, 0.35, 0.35, 1.0)
            love.graphics.printf(tournamentUI.errorMsg, bx, py + 196, bw, "center")
        end
        drawButton("tj_submit", bx, py + 230, bw, 44, I18N.t("tourn_join"), {
            primary = true,
            onClick = function()
                Sound.play("click")
                local ok, err = Tournament.joinByCode(tournamentUI.joinCode, Config.profile.username)
                if ok then
                    tournamentUI.view = "room"
                    tournamentUI.errorMsg = nil
                else
                    tournamentUI.errorMsg = err
                end
            end
        })
    elseif tournamentUI.view == "room" and Tournament.active then
        local t = Tournament.active
        love.graphics.setFont(fonts.body)
        love.graphics.setColor(ui.textMain)
        love.graphics.printf(I18N.t("tourn_code") .. " " .. t.code .. "   |   " .. (t.system == "swiss" and I18N.t("tourn_swiss") or I18N.t("tourn_bracket")), px, py + 52, pw, "center")

        if t.status == "lobby" then
            drawButton("tr_start", bx, py + 92, bw, 42, I18N.t("tourn_start"), {
                primary = true,
                onClick = function() Sound.play("click"); Tournament.startTournament() end
            })
        end

        if t.system == "swiss" then
            -- Таблица лидеров Швейцарки
            love.graphics.setFont(fonts.small)
            love.graphics.setColor(ui.textSub)
            love.graphics.print(I18N.t("tourn_leaderboard"), bx, py + 144)
            local lb = Tournament.getLeaderboard()
            for idx, row in ipairs(lb) do
                if idx <= 8 then
                    local ry = py + 168 + (idx - 1) * 26
                    love.graphics.setColor(idx == 1 and { 0.96, 0.78, 0.22, 1.0 } or ui.textMain)
                    love.graphics.print(string.format("#%d  %s", idx, row.name), bx, ry)
                    love.graphics.printf(string.format("%.1f pts  (%dW/%dD/%dL)", row.score, row.wins, row.draws, row.losses), bx, ry, bw, "right")
                end
            end
        else
            -- График турнирной сетки (Bracket Tree)
            local rounds = #t.rounds
            local colW = (bw - 20) / math.max(1, rounds)
            for rIdx, rMatches in ipairs(t.rounds) do
                local rx = bx + (rIdx - 1) * colW
                local stepY = 230 / math.max(1, #rMatches)
                for mIdx, m in ipairs(rMatches) do
                    local my = py + 148 + (mIdx - 0.5) * stepY
                    love.graphics.setColor(ui.bgClear)
                    love.graphics.rectangle("fill", rx, my - 18, colW - 14, 38, 6, 6)
                    love.graphics.setColor(m.done and { 0.30, 0.75, 0.48, 1.0 } or ui.panelBorder)
                    love.graphics.rectangle("line", rx, my - 18, colW - 14, 38, 6, 6)
                    love.graphics.setFont(fonts.small)
                    love.graphics.setColor(ui.textMain)
                    love.graphics.printf((m.p1 or "?") .. " vs " .. (m.p2 or "?"), rx + 4, my - 10, colW - 22, "center")
                end
            end
        end

        local pending = Tournament.getHumanPendingMatch(Config.profile.username)
        if pending and t.status == "active" then
            drawButton("tr_play_match", bx, py + ph - 104, bw, 42, I18N.t("tourn_play_match") .. " (" .. pending.p1 .. " vs " .. pending.p2 .. ")", {
                primary = true,
                onClick = function()
                    Sound.play("click")
                    activeTournamentMatch = pending
                    Config.ruleMode = t.ruleMode or "standard"
                    Config.onlineTimeMinutes = t.timeMinutes or 5
                    local diffNum = (t.botDifficulty == "easy" and 1) or (t.botDifficulty == "hard" and 3) or 2
                    startNewGame(t.isBotTournament and Config.GameMode.VS_BOT or Config.GameMode.ONLINE, diffNum)
                end
            })
        elseif t.status == "finished" and t.champion then
            love.graphics.setFont(fonts.h2)
            love.graphics.setColor(0.96, 0.78, 0.22, 1.0)
            love.graphics.printf("Champion: " .. tostring(t.champion), bx, py + ph - 98, bw, "center")
        end
    end

    drawButton("tourn_back", px + pw * 0.5 - 80, py + ph - 50, 160, 38, I18N.t("back_btn"), {
        onClick = function()
            Sound.play("click")
            if tournamentUI.view == "create" or tournamentUI.view == "join" then
                tournamentUI.view = "hub"
            else
                currentScreen = "online_modal"
            end
        end
    })
end

local function drawLanModal(sw, sh)
    local ui = Config.getUITheme()
    local pw, ph = 540, 360
    local px, py = (sw - pw) * 0.5, (sh - ph) * 0.5
    drawPanel(px, py, pw, ph)

    love.graphics.setFont(fonts.h2)
    love.graphics.setColor(ui.textMain)
    love.graphics.printf(I18N.t("lan_title"), px, py + 20, pw, "center")

    love.graphics.setFont(fonts.body)
    love.graphics.setColor(ui.textSub)
    love.graphics.printf(I18N.t("lan_desc"), px + 32, py + 58, pw - 64, "center")

    local bx, bw = px + 44, pw - 88
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(ui.textSub)
    love.graphics.print(I18N.t("lan_ip_label"), bx, py + 106)

    local ipBoxY = py + 126
    love.graphics.setColor(ui.bgClear)
    love.graphics.rectangle("fill", bx, ipBoxY, bw, 40, 8, 8)
    love.graphics.setColor(lanIpFocused and ui.btnHoverBorder or ui.panelBorder)
    love.graphics.setLineWidth(lanIpFocused and 2.0 or 1.2)
    love.graphics.rectangle("line", bx, ipBoxY, bw, 40, 8, 8)

    local cursorBlink = (lanIpFocused and (math.floor(love.timer.getTime() * 2) % 2 == 0)) and "|" or ""
    love.graphics.setFont(fonts.body)
    love.graphics.setColor(ui.textMain)
    love.graphics.print(LAN.joinIP .. cursorBlink, bx + 12, ipBoxY + 11)

    table.insert(uiButtons, {
        id = "focus_lan_ip",
        x = bx, y = ipBoxY, w = bw, h = 40,
        onClick = function()
            lanIpFocused = true
            pcall(love.keyboard.setTextInput, true)
        end
    })

    local halfW = (bw - 14) * 0.5
    drawButton("lan_host", bx, py + 184, halfW, 48, I18N.t("lan_host_btn"), {
        primary = true,
        onClick = function()
            Sound.play("click")
            lanIpFocused = false
            LAN.startHost()
        end
    })
    drawButton("lan_join", bx + halfW + 14, py + 184, halfW, 48, I18N.t("lan_join_btn"), {
        accent = true,
        onClick = function()
            Sound.play("click")
            lanIpFocused = false
            LAN.startClient(LAN.joinIP)
        end
    })

    love.graphics.setFont(fonts.small)
    love.graphics.setColor(ui.accentText)
    local statusStr = (#LAN.statusMsg > 0) and LAN.statusMsg or I18N.t("lan_status_idle")
    love.graphics.printf(statusStr, px + 28, py + 248, pw - 56, "center")

    drawButton("lan_back", px + pw * 0.5 - 80, py + ph - 54, 160, 40, I18N.t("back_btn"), {
        onClick = function()
            Sound.play("click")
            LAN.stop()
            lanIpFocused = false
            currentScreen = "online_modal"
        end
    })
end

local function drawProfileModal(sw, sh)
    local ui = Config.getUITheme()
    local pw, ph = 880, 620
    local px, py = (sw - pw) * 0.5, (sh - ph) * 0.5
    drawPanel(px, py, pw, ph)

    local p = Config.profile

    love.graphics.setFont(fonts.h2)
    love.graphics.setColor(ui.textMain)
    love.graphics.printf(I18N.t("profile_title"), px, py + 14, pw, "center")

    -- Avatar
    local ax, ay = px + 58, py + 82
    drawUserAvatar(ax, ay, 30)

    love.graphics.setFont(fonts.h2)
    love.graphics.setColor(ui.textMain)
    local streakStr = ((p.winStreak or 0) >= 5) and ("  🔥 " .. tostring(p.winStreak)) or ""
    love.graphics.print(p.username .. streakStr, px + 104, py + 48)

    if p.isRegistered then
        love.graphics.setFont(fonts.small)
        love.graphics.setColor(ui.accentText)
        love.graphics.print(I18N.t("profile_registered_at", p.createdAtStr or os.date("%d.%m.%Y")), px + 104, py + 76)
    end

    love.graphics.setFont(fonts.small)
    love.graphics.setColor(ui.textSub)
    local bioText = (#p.bio > 0) and p.bio or I18N.t("profile_bio_empty")
    love.graphics.print(I18N.t("profile_bio") .. " " .. bioText, px + 104, py + 96)

    -- ELO Rating box (4 modes via Config.eloGraphMode)
    local eloMode = Config.eloGraphMode or "std_blitz"
    local curElo = (p.ratings and p.ratings[eloMode]) or p.rating or 800
    local rBoxX, rBoxY, rBoxW, rBoxH = px + pw - 220, py + 48, 190, 66
    love.graphics.setColor(ui.btnDefault)
    love.graphics.rectangle("fill", rBoxX, rBoxY, rBoxW, rBoxH, 10, 10)
    love.graphics.setColor(ui.panelBorder)
    love.graphics.rectangle("line", rBoxX, rBoxY, rBoxW, rBoxH, 10, 10)

    love.graphics.setFont(fonts.small)
    love.graphics.setColor(ui.textSub)
    love.graphics.printf(I18N.t("elo_" .. eloMode), rBoxX, rBoxY + 6, rBoxW, "center")

    drawStarIcon(rBoxX + 44, rBoxY + 42, 8, { 0.95, 0.78, 0.28, 1.0 })
    love.graphics.setFont(fonts.h2)
    love.graphics.setColor(ui.textMain)
    love.graphics.print("ELO " .. tostring(curElo), rBoxX + 58, rBoxY + 28)

    love.graphics.setFont(fonts.btn)
    love.graphics.setColor(ui.textMain)
    love.graphics.print(I18N.t("profile_games", p.gamesPlayed, p.wins, p.losses, p.draws), px + 30, py + 124)

    -- Left Column: ELO Mode Dropdown/Tabs + Rating History Graph
    local gx, gy, gw, gh = px + 30, py + 154, 380, 194
    love.graphics.setColor(ui.bgClear)
    love.graphics.rectangle("fill", gx, gy, gw, gh, 8, 8)
    love.graphics.setColor(ui.panelBorder)
    love.graphics.rectangle("line", gx, gy, gw, gh, 8, 8)

    local eloModes = {
        { id = "std_blitz",   lbl = "Клас 5м" },
        { id = "std_bullet",  lbl = "Клас 1м" },
        { id = "free_blitz",  lbl = "Вольн 5м" },
        { id = "free_bullet", lbl = "Вольн 1м" }
    }
    local emW = (gw - 24) / 4
    for i, em in ipairs(eloModes) do
        drawButton("prof_elo_" .. em.id, gx + 6 + (i - 1) * (emW + 4), gy + 6, emW, 24, em.lbl, {
            active = (eloMode == em.id),
            font = fonts.small,
            onClick = function()
                Sound.play("click")
                Config.eloGraphMode = em.id
            end
        })
    end

    local hist = (p.ratingHistories and p.ratingHistories[eloMode]) or p.ratingHistory or { 800 }
    local minR, maxR = 760, 840
    for _, r in ipairs(hist) do
        if r - 20 < minR then minR = r - 20 end
        if r + 20 > maxR then maxR = r + 20 end
    end
    local plotX, plotY, plotW, plotH = gx + 42, gy + 44, gw - 58, gh - 58
    love.graphics.setColor(ui.panelBorder)
    love.graphics.line(plotX, plotY + plotH * 0.5, plotX + plotW, plotY + plotH * 0.5)
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(ui.textSub)
    love.graphics.print(tostring(maxR), gx + 6, plotY - 4)
    love.graphics.print(tostring(minR), gx + 6, plotY + plotH - 10)

    local pts = {}
    local count = #hist
    for i, r in ipairs(hist) do
        local tx = (count == 1) and (plotX + plotW * 0.5) or (plotX + ((i - 1) / (count - 1)) * plotW)
        local ty = plotY + plotH - ((r - minR) / math.max(1, maxR - minR)) * plotH
        table.insert(pts, tx)
        table.insert(pts, ty)
    end
    if #pts >= 4 then
        love.graphics.setColor(ui.textMain)
        love.graphics.setLineWidth(2.5)
        love.graphics.line(pts)
    end
    for i = 1, #pts, 2 do
        love.graphics.setColor(0.95, 0.78, 0.28, 1)
        love.graphics.circle("fill", pts[i], pts[i + 1], 4.5)
    end

    -- Right Column: Scrollable Previous Matches (W/L/D badges + click to replay!)
    local rx, ry, rw, rh = px + 424, py + 154, 426, 194
    love.graphics.setColor(ui.bgClear)
    love.graphics.rectangle("fill", rx, ry, rw, rh, 8, 8)
    love.graphics.setColor(ui.panelBorder)
    love.graphics.rectangle("line", rx, ry, rw, rh, 8, 8)

    love.graphics.setFont(fonts.small)
    love.graphics.setColor(ui.textSub)
    love.graphics.print(I18N.t("profile_recent") .. string.format(" (%d)", #p.recentMatches), rx + 12, ry + 8)

    if #p.recentMatches == 0 then
        love.graphics.setColor(ui.textSub)
        love.graphics.printf(I18N.t("profile_no_games"), rx + 12, ry + 84, rw - 24, "center")
    else
        local listX, listY, listW, listH = rx + 6, ry + 30, rw - 16, rh - 34
        local itemH = 38
        local visibleItems = math.floor(listH / itemH)
        local maxScroll = math.max(0, #p.recentMatches - visibleItems)
        profileMatchScroll = math.max(0, math.min(maxScroll, profileMatchScroll))

        setUIScissor(listX, listY, listW, listH)
        local myY = listY + 2
        for idx = profileMatchScroll + 1, math.min(#p.recentMatches, profileMatchScroll + visibleItems + 1) do
            local m = p.recentMatches[idx]
            local badgeChar = (m.result == "win") and "W" or ((m.result == "loss") and "L" or "D")
            local badgeCol  = (m.result == "win") and { 0.20, 0.78, 0.42, 1.0 }
                or ((m.result == "loss") and { 0.88, 0.26, 0.26, 1.0 } or { 0.55, 0.58, 0.64, 1.0 })
            love.graphics.setColor(badgeCol)
            love.graphics.rectangle("fill", listX + 4, myY + 2, 22, 22, 5, 5)
            love.graphics.setFont(fonts.small)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.printf(badgeChar, listX + 4, myY + 5, 22, "center")

            local formatted = Config.formatMatchRecord(m)
            local metaStr   = Config.formatMatchMeta(m)
            love.graphics.setColor(ui.textMain)
            love.graphics.print(formatted, listX + 32, myY)
            if #metaStr > 0 then
                love.graphics.setColor(ui.textSub)
                love.graphics.print(metaStr, listX + 32, myY + 16)
            end

            if m.movesList and #m.movesList > 0 then
                local linkW = 96
                local linkH = 26
                local linkX = listX + listW - linkW - 4
                local linkY = myY + 5
                drawButton("prof_replay_" .. idx, linkX, linkY, linkW, linkH, I18N.t("replay_match_btn"), {
                    font = fonts.small,
                    primary = true,
                    onClick = function()
                        Sound.play("click")
                        isReplayMode = true
                        replaySourceMatch = m
                        gameLogic:reset(m.ruleMode or "standard")
                        for _, mv in ipairs(m.movesList) do
                            if gameLogic.ruleMode == "free" then
                                gameLogic:placePiece(mv.x, mv.y, mv.z)
                            else
                                gameLogic:dropPiece(mv.x, mv.z)
                            end
                        end
                        viewPly = #gameLogic.moveHistory
                        syncMoveLogScrollToPly()
                        renderer:resetCamera()
                        currentScreen = "game"
                    end
                })
            end
            myY = myY + itemH
        end
        setUIScissor()

        if maxScroll > 0 then
            local sbX = rx + rw - 8
            local sbY = ry + 32
            local sbH = rh - 38
            love.graphics.setColor(ui.panelBorder)
            love.graphics.rectangle("fill", sbX, sbY, 4, sbH, 2, 2)
            local thumbH = math.max(18, sbH * (visibleItems / #p.recentMatches))
            local thumbY = sbY + (sbH - thumbH) * (profileMatchScroll / maxScroll)
            love.graphics.setColor(ui.accentText)
            love.graphics.rectangle("fill", sbX, thumbY, 4, thumbH, 2, 2)
        end
    end

    -- Achievements (отображаем только открытые ачивки, нераскрытые скрыты)
    love.graphics.setFont(fonts.btn)
    love.graphics.setColor(ui.textMain)
    love.graphics.print(I18N.t("profile_achievements"), px + 30, py + 356)

    local earnedAchs = {}
    for _, a in ipairs(ACHIEVEMENTS_META) do
        if p.achievements and p.achievements[a.id] then
            table.insert(earnedAchs, a)
        end
    end

    if #earnedAchs == 0 then
        love.graphics.setFont(fonts.small)
        love.graphics.setColor(ui.textSub)
        love.graphics.print(I18N.t("no_achievements_yet"), px + 30, py + 386)
    else
        local badgeSize = 54
        local gap = 12
        for i, a in ipairs(earnedAchs) do
            local abx = px + 30 + (i - 1) * (badgeSize + gap)
            local aby = py + 382
            love.graphics.setColor(0.22, 0.68, 0.44, 1.0)
            love.graphics.rectangle("fill", abx, aby, badgeSize, 42, 8, 8)
            love.graphics.setColor(selectedAchievementId == a.id and ui.accentText or ui.panelBorder)
            love.graphics.rectangle("line", abx, aby, badgeSize, 42, 8, 8)
            love.graphics.setFont(fonts.small)
            love.graphics.setColor(ui.textMain)
            love.graphics.printf(a.icon, abx, aby + 13, badgeSize, "center")
            table.insert(uiButtons, {
                id = "ach_badge_" .. a.id,
                x = abx, y = aby, w = badgeSize, h = 42,
                onClick = function()
                    Sound.play("click")
                    selectedAchievementId = (selectedAchievementId == a.id) and nil or a.id
                end
            })
        end
    end

    if selectedAchievementId then
        for _, a in ipairs(ACHIEVEMENTS_META) do
            if a.id == selectedAchievementId then
                love.graphics.setColor(ui.bgClear)
                love.graphics.rectangle("fill", px + 30, py + 430, pw - 60, 28, 6, 6)
                love.graphics.setFont(fonts.small)
                love.graphics.setColor(ui.textMain)
                love.graphics.print(I18N.t(a.key) .. " — " .. I18N.t(a.desc), px + 40, py + 437)
            end
        end
    end

    -- Friends & Requests Section (Registered accounts only, max 50 friends)
    local fy = py + 464
    love.graphics.setColor(ui.bgClear)
    love.graphics.rectangle("fill", px + 30, fy, pw - 60, 86, 8, 8)
    love.graphics.setColor(ui.panelBorder)
    love.graphics.rectangle("line", px + 30, fy, pw - 60, 86, 8, 8)

    if not p.isRegistered then
        love.graphics.setFont(fonts.small)
        love.graphics.setColor(ui.textSub)
        love.graphics.printf(I18N.t("friends_reg_only"), px + 44, fy + 34, pw - 88, "center")
    else
        love.graphics.setFont(fonts.small)
        love.graphics.setColor(ui.textMain)
        love.graphics.print(I18N.t("friends_title") .. " (" .. tostring(#(p.friends or {})) .. "/50)", px + 42, fy + 8)

        -- Search input + Add button + Open All Friends button
        love.graphics.setColor(ui.panelBg)
        love.graphics.rectangle("fill", px + 178, fy + 6, 160, 24, 5, 5)
        love.graphics.setColor(ui.panelBorder)
        love.graphics.rectangle("line", px + 178, fy + 6, 160, 24, 5, 5)
        love.graphics.setColor(friendSearchText ~= "" and ui.textMain or ui.textSub)
        love.graphics.print(friendSearchText ~= "" and friendSearchText or I18N.t("friend_search"), px + 184, fy + 10)
        table.insert(uiButtons, {
            id = "prof_friend_search_focus",
            x = px + 178, y = fy + 6, w = 160, h = 24,
            onClick = function() pcall(love.keyboard.setTextInput, true) end
        })

        drawButton("friend_add_btn", px + 344, fy + 6, 84, 24, I18N.t("friend_add"), {
            font = fonts.small,
            onClick = function()
                Sound.play("click")
                if #friendSearchText >= 3 then
                    local okAdd, errKey = Config.sendFriendRequest(friendSearchText)
                    if okAdd then
                        friendSearchText = ""
                        friendStatusFeedback = nil
                    else
                        friendStatusFeedback = I18N.t(errKey or "friend_not_found")
                    end
                    Storage.save()
                    refreshFriendsState()
                end
            end
        })
        drawButton("friend_open_all_btn", px + pw - 160, fy + 6, 118, 24, I18N.t("friend_open_all"), {
            accent = true,
            font = fonts.small,
            onClick = function()
                Sound.play("click")
                friendGameUI.view = friendGameUI.room and "lobby" or "list"
                friendGameUI.errorMsg = nil
                refreshFriendsState()
                currentScreen = "friend_game_modal"
            end
        })

        if friendStatusFeedback then
            love.graphics.setFont(fonts.small)
            love.graphics.setColor(0.95, 0.42, 0.38, 1.0)
            love.graphics.print(friendStatusFeedback, px + 436, fy + 10)
        end

        -- Unified Requests + Friends quick row
        local combinedRequests = {}
        for _, name in ipairs(p.incomingRequests or {}) do
            table.insert(combinedRequests, { name = name, dir = "in" })
        end
        for _, name in ipairs(p.sentRequests or {}) do
            table.insert(combinedRequests, { name = name, dir = "out" })
        end

        local fx = px + 42
        for idx, req in ipairs(combinedRequests) do
            if idx <= 2 then
                love.graphics.setColor(ui.textSub)
                love.graphics.print(req.name .. (req.dir == "out" and " (" .. I18N.t("friend_pending") .. ")" or ""), fx, fy + 38)
                if req.dir == "in" then
                    drawButton("freq_acc_" .. idx, fx + 110, fy + 34, 62, 22, I18N.t("friend_accept"), {
                        font = fonts.small, primary = true,
                        onClick = function()
                            Sound.play("click")
                            local okA, errA = Config.acceptFriendRequest(req.name)
                            if not okA and errA then friendStatusFeedback = I18N.t(errA) end
                            Storage.save()
                            refreshFriendsState()
                        end
                    })
                    drawButton("freq_dec_" .. idx, fx + 176, fy + 34, 62, 22, I18N.t("friend_decline"), {
                        font = fonts.small,
                        onClick = function()
                            Sound.play("click")
                            Config.declineFriendRequest(req.name)
                            Storage.save()
                            refreshFriendsState()
                        end
                    })
                end
                fx = fx + 250
            end
        end

        for idx, fn in ipairs(p.friends or {}) do
            if idx <= 2 then
                local fyRow = fy + 60
                local fxRow = px + 42 + (idx - 1) * 395
                local pres = friendStatusCache[fn:lower()] or {}
                local isOnline = select(1, formatLastSeen(pres.ts, pres.inGame))
                love.graphics.setColor(isOnline and { 0.22, 0.88, 0.45, 1.0 } or { 0.48, 0.52, 0.58, 1.0 })
                love.graphics.circle("fill", fxRow + 5, fyRow + 10, 4.5)

                love.graphics.setFont(fonts.small)
                love.graphics.setColor(ui.textMain)
                love.graphics.print(fn, fxRow + 15, fyRow + 3)

                drawButton("fr_prof_" .. idx, fxRow + 125, fyRow, 76, 20, I18N.t("friend_profile_title"), {
                    font = fonts.small,
                    onClick = function() Sound.play("click"); openFriendProfile(fn, "profile_modal") end
                })
                drawButton("fr_play_" .. idx, fxRow + 205, fyRow, 74, 20, I18N.t("friend_challenge"), {
                    font = fonts.small, primary = true,
                    onClick = function() Sound.play("click"); startFriendRoomLobby(fn) end
                })
                drawButton("fr_rem_" .. idx, fxRow + 283, fyRow, 32, 20, "X", {
                    font = fonts.small,
                    onClick = function() Sound.play("click"); Config.removeFriend(fn); Storage.save(); refreshFriendsState() end
                })
                drawButton("fr_blk_" .. idx, fxRow + 319, fyRow, 64, 20, I18N.t("friend_block"), {
                    font = fonts.small,
                    onClick = function() Sound.play("click"); Config.blockUser(fn); Storage.save(); refreshFriendsState() end
                })
            end
        end
    end

    -- Bottom Buttons: Register / Sign In / Edit Profile / Log Out + Close
    local btnY = py + ph - 56
    if not p.isRegistered then
        drawButton("prof_reg", px + 34, btnY, 190, 42, I18N.t("register_btn"), {
            accent = true,
            onClick = function()
                Sound.play("click")
                openAuthModal("register")
            end
        })
        drawButton("prof_login", px + 238, btnY, 190, 42, I18N.t("signin_btn"), {
            onClick = function()
                Sound.play("click")
                openAuthModal("login")
            end
        })
        drawButton("profile_close", px + pw - 214, btnY, 180, 42, I18N.t("close_btn"), {
            primary = true,
            onClick = function()
                Sound.play("click")
                currentScreen = "menu"
            end
        })
    else
        drawButton("prof_edit", px + 34, btnY, 200, 42, I18N.t("edit_profile_btn"), {
            accent = true,
            onClick = function()
                Sound.play("click")
                openAuthModal("edit")
            end
        })
        drawButton("prof_logout", px + 248, btnY, 170, 42, I18N.t("logout_btn"), {
            onClick = function()
                Sound.play("click")
                Config.logoutAccount()
                Storage.save()
            end
        })
        drawButton("profile_close", px + pw - 214, btnY, 180, 42, I18N.t("close_btn"), {
            primary = true,
            onClick = function()
                Sound.play("click")
                currentScreen = "menu"
            end
        })
    end
end

-- Registration / Sign In / Edit Profile Modal with full field validation, Password Eye Toggle & Confirm Password
local function drawAuthModal(sw, sh)
    local ui = Config.getUITheme()
    local isLogin    = (authState.mode == "login")
    local isRegister = (authState.mode == "register")
    local isEdit     = (authState.mode == "edit")
    local pw = 600
    local ph = isLogin and 350 or (isRegister and 500 or 565)
    local px, py = (sw - pw) * 0.5, (sh - ph) * 0.5
    drawPanel(px, py, pw, ph)

    local titleKey = (isRegister and "auth_reg_title")
                  or (isLogin    and "auth_login_title")
                  or "auth_edit_title"

    love.graphics.setFont(fonts.h2)
    love.graphics.setColor(ui.textMain)
    love.graphics.printf(I18N.t(titleKey), px, py + 18, pw, "center")

    local bx, bw = px + 36, pw - 72
    local cursorBlink = (math.floor(love.timer.getTime() * 2) % 2 == 0) and "|" or ""

    local function drawInputBox(fieldId, labelKey, yPos, valText, isMasked, eyeOptions)
        love.graphics.setFont(fonts.small)
        love.graphics.setColor(ui.textSub)
        love.graphics.print(I18N.t(labelKey), bx, yPos)

        local boxY = yPos + 19
        local isFocused = (authState.activeField == fieldId)
        love.graphics.setColor(ui.bgClear)
        love.graphics.rectangle("fill", bx, boxY, bw, 38, 8, 8)
        love.graphics.setColor(isFocused and ui.btnHoverBorder or ui.panelBorder)
        love.graphics.setLineWidth(isFocused and 2.0 or 1.2)
        love.graphics.rectangle("line", bx, boxY, bw, 38, 8, 8)

        local shown = isMasked and string.rep("*", utf8.len(valText) or #valText) or valText
        if isFocused then
            shown = shown .. cursorBlink
        end
        love.graphics.setFont(fonts.body)
        love.graphics.setColor(ui.textMain)
        love.graphics.print(shown, bx + 12, boxY + 10)

        local inputClickW = eyeOptions and (bw - 46) or bw
        table.insert(uiButtons, {
            id = "focus_" .. fieldId,
            x = bx, y = boxY, w = inputClickW, h = 38,
            onClick = function()
                authState.activeField = fieldId
                pcall(love.keyboard.setTextInput, true)
            end
        })

        if eyeOptions then
            local eyeX = bx + bw - 23
            local eyeY = boxY + 19
            drawEyeIcon(eyeX, eyeY, eyeOptions.isOpen, ui.textSub)
            table.insert(uiButtons, {
                id = "eye_" .. fieldId,
                x = bx + bw - 44, y = boxY, w = 44, h = 38,
                onClick = function()
                    Sound.play("click")
                    eyeOptions.onToggle()
                end
            })
        end
    end

    if isLogin then
        drawInputBox("username", "field_username", py + 68, authState.username, false)
        drawInputBox("password", "field_password", py + 144, authState.password, not authState.showPassword, {
            isOpen = authState.showPassword,
            onToggle = function() authState.showPassword = not authState.showPassword end
        })
    elseif isRegister then
        -- Регистрация: только Логин, Пароль и Подтверждение пароля (без Email)
        drawInputBox("username", "field_username", py + 72, authState.username, false)
        drawInputBox("password", "field_password", py + 148, authState.password, not authState.showPassword, {
            isOpen = authState.showPassword,
            onToggle = function() authState.showPassword = not authState.showPassword end
        })
        drawInputBox("confirmPassword", "field_password_confirm", py + 224, authState.confirmPassword, not authState.showConfirmPassword, {
            isOpen = authState.showConfirmPassword,
            onToggle = function() authState.showConfirmPassword = not authState.showConfirmPassword end
        })
    elseif isEdit then
        -- Настройки профиля: Аватар + Логин (смена раз в неделю) + Пароль + О себе
        drawUserAvatar(bx + 28, py + 84, 24, authState.avatarPreset, authState.customAvatarFile)
        drawButton("btn_upload_photo", bx + 66, py + 62, 230, 36, I18N.t("upload_photo_btn"), {
            accent = true,
            font = fonts.small,
            onClick = function()
                Sound.play("click")
                authState.customAvatarFile = nil
                authState.avatarPreset = (authState.avatarPreset % #AVATAR_PRESET_COLORS) + 1
            end
        })
        love.graphics.setFont(fonts.small)
        love.graphics.setColor(ui.textSub)
        love.graphics.printf(I18N.t("photo_hint"), bx + 308, py + 62, bw - 308, "left")

        drawInputBox("username", "field_username", py + 114, authState.username, false)
        local curAcc = Config.profile or {}
        local lastChange = curAcc.lastUsernameChangeTime or 0
        local now = os.time()
        local remSec = 7 * 86400 - (now - lastChange)
        if remSec > 0 and lastChange > 0 then
            local remDays = math.ceil(remSec / 86400)
            love.graphics.setFont(fonts.small)
            love.graphics.setColor(0.95, 0.76, 0.28, 1.0)
            love.graphics.print(string.format(I18N.t("err_username_cooldown"), remDays), bx + 2, py + 162)
        end

        drawInputBox("password", "field_password", py + 184, authState.password, not authState.showPassword, {
            isOpen = authState.showPassword,
            onToggle = function() authState.showPassword = not authState.showPassword end
        })
        drawInputBox("bio",      "field_bio",      py + 258, authState.bio,      false)
    end

    -- Error message banner if validation failed
    if authState.errorKey then
        love.graphics.setFont(fonts.small)
        love.graphics.setColor(0.95, 0.38, 0.38, 1.0)
        local errText = (authState.errorKey == "err_username_cooldown")
            and string.format(I18N.t(authState.errorKey), authState.errorParam or 7)
            or I18N.t(authState.errorKey)
        love.graphics.printf(errText, bx, py + ph - 104, bw, "center")
    end

    local btnY = py + ph - 60
    drawButton("auth_cancel", bx, btnY, 170, 44, I18N.t("back_btn"), {
        onClick = function()
            Sound.play("click")
            currentScreen = "profile_modal"
        end
    })

    local submitKey = (isRegister and "submit_register")
                   or (isLogin    and "submit_login")
                   or "submit_save"

    drawButton("auth_submit", bx + bw - 220, btnY, 220, 44, I18N.t(submitKey), {
        primary = true,
        onClick = function()
            local ok, errKey, errParam
            if isRegister then
                ok, errKey = Config.registerAccount(
                    authState.username,
                    authState.password,
                    authState.confirmPassword
                )
            elseif isLogin then
                ok, errKey = Config.loginAccount(
                    authState.username,
                    authState.password
                )
            else
                ok, errKey, errParam = Config.updateRegisteredProfile(
                    authState.username,
                    authState.password,
                    authState.bio,
                    authState.avatarPreset,
                    authState.customAvatarFile
                )
            end

            if ok then
                Sound.play("win")
                reloadCustomAvatarImage()
                Storage.save()
                currentScreen = "profile_modal"
            else
                Sound.play("click")
                authState.errorKey = errKey
                authState.errorParam = errParam
            end
        end
    })
end

local function applyDisplaySettings()
    local res = Config.resolutions[Config.currentResIndex] or Config.resolutions[1]
    love.window.setMode(res.w, res.h, {
        fullscreen = Config.fullscreen,
        resizable = true,
        msaa = 4,
        depth = 24,
        vsync = 1
    })
end

local function drawSettingsModal(sw, sh)
    local ui = Config.getUITheme()
    local pw, ph = 560, 460
    local px, py = (sw - pw) * 0.5, (sh - ph) * 0.5
    drawPanel(px, py, pw, ph)

    love.graphics.setFont(fonts.h2)
    love.graphics.setColor(ui.textMain)
    love.graphics.printf(I18N.t("settings_title"), px, py + 22, pw, "center")

    local bx, bw = px + 34, pw - 68

    love.graphics.setFont(fonts.btn)
    love.graphics.setColor(ui.textSub)
    love.graphics.print(I18N.t("lang_label"), bx, py + 72)

    local langW = (bw - 20) / 3
    local langs = {
        { code = "en", label = I18N.t("lang_en") },
        { code = "ru", label = I18N.t("lang_ru") },
        { code = "fr", label = I18N.t("lang_fr") }
    }
    for i, l in ipairs(langs) do
        drawButton("lang_" .. l.code, bx + (i - 1) * (langW + 10), py + 100, langW, 40, l.label, {
            active = (I18N.current == l.code),
            font = fonts.small,
            onClick = function()
                Sound.play("click")
                I18N.current = l.code
                Storage.save()
            end
        })
    end

    love.graphics.setFont(fonts.btn)
    love.graphics.setColor(ui.textSub)
    love.graphics.print(I18N.t("display_label"), bx, py + 156)

    local halfW = (bw - 12) * 0.5
    drawButton("disp_win", bx, py + 184, halfW, 40, I18N.t("windowed"), {
        active = not Config.fullscreen,
        font = fonts.small,
        onClick = function()
            Sound.play("click")
            Config.fullscreen = false
            applyDisplaySettings()
        end
    })
    drawButton("disp_full", bx + halfW + 12, py + 184, halfW, 40, I18N.t("fullscreen"), {
        active = Config.fullscreen,
        font = fonts.small,
        onClick = function()
            Sound.play("click")
            Config.fullscreen = true
            applyDisplaySettings()
        end
    })

    love.graphics.setFont(fonts.btn)
    love.graphics.setColor(ui.textSub)
    love.graphics.print(I18N.t("resolution_label"), bx, py + 238)

    local resW = (bw - 30) / 4
    for i, r in ipairs(Config.resolutions) do
        drawButton("res_" .. i, bx + (i - 1) * (resW + 10), py + 266, resW, 38, r.label, {
            active = (Config.currentResIndex == i),
            font = fonts.small,
            onClick = function()
                Sound.play("click")
                Config.currentResIndex = i
                applyDisplaySettings()
            end
        })
    end

    love.graphics.setFont(fonts.small)
    love.graphics.setColor(ui.textSub)
    love.graphics.print(I18N.t("server_label") .. "  " .. I18N.t("server_stub"), bx, py + 322)

    drawButton("open_rules", bx, py + 350, bw, 42, I18N.t("rules_btn"), {
        accent = true,
        onClick = function()
            Sound.play("click")
            currentScreen = "rules_modal"
        end
    })

    drawButton("settings_back", px + pw * 0.5 - 85, py + ph - 54, 170, 40, I18N.t("back_btn"), {
        primary = true,
        onClick = function()
            Sound.play("click")
            currentScreen = "menu"
        end
    })
end

local function drawRulesModal(sw, sh)
    local ui = Config.getUITheme()
    local pw, ph = 660, 500
    local px, py = (sw - pw) * 0.5, (sh - ph) * 0.5
    drawPanel(px, py, pw, ph)

    love.graphics.setFont(fonts.h2)
    love.graphics.setColor(ui.textMain)
    love.graphics.printf(I18N.t("rules_title"), px, py + 20, pw, "center")

    local boxX, boxY, boxW, boxH = px + 28, py + 62, pw - 56, ph - 134
    love.graphics.setColor(ui.bgClear)
    love.graphics.rectangle("fill", boxX, boxY, boxW, boxH, 8, 8)
    love.graphics.setColor(ui.panelBorder)
    love.graphics.rectangle("line", boxX, boxY, boxW, boxH, 8, 8)

    local bodyText = I18N.t("rules_body")
    local textW = boxW - 36
    local _, wrapped = fonts.body:getWrap(bodyText, textW)
    local totalH = #wrapped * fonts.body:getHeight() * 1.25 + 16
    local maxScroll = math.max(0, totalH - boxH)
    rulesScrollOffset = math.max(0, math.min(maxScroll, rulesScrollOffset))

    setUIScissor(boxX + 4, boxY + 4, boxW - 18, boxH - 8)
    love.graphics.setFont(fonts.body)
    love.graphics.setColor(ui.textSub)
    love.graphics.printf(bodyText, boxX + 14, boxY + 10 - rulesScrollOffset, textW, "left")
    setUIScissor()

    -- Визуальный скроллбар / ползунок справа
    if maxScroll > 0 then
        local sbX = boxX + boxW - 10
        local sbY = boxY + 8
        local sbH = boxH - 16
        love.graphics.setColor(ui.panelBorder)
        love.graphics.rectangle("fill", sbX, sbY, 5, sbH, 3, 3)
        local thumbH = math.max(26, sbH * (boxH / totalH))
        local thumbY = sbY + (sbH - thumbH) * (rulesScrollOffset / maxScroll)
        love.graphics.setColor(ui.accentText)
        love.graphics.rectangle("fill", sbX, thumbY, 5, thumbH, 3, 3)
    end

    drawButton("rules_back", px + pw * 0.5 - 85, py + ph - 58, 170, 42, I18N.t("back_btn"), {
        primary = true,
        onClick = function()
            Sound.play("click")
            currentScreen = "settings_modal"
        end
    })
end

local function getShopMaxScrollX(sw)
    local cardW, cardGap = 260, 26
    local count = 0
    if shopTab == "pieces" then
        count = #Config.pieceSkinOrder
    elseif shopTab == "board" then
        count = 1 + #Config.boardSkinOrder
    elseif shopTab == "themes" then
        count = #Config.uiThemeOrder
    end
    if count <= 0 then return 0 end
    local contentW = 64 + count * cardW + (count - 1) * cardGap + 64
    return math.max(0, contentW - (sw or 1280))
end

local function drawShopScreen(sw, sh)
    local ui = Config.getUITheme()
    local maxShopScroll = getShopMaxScrollX(sw)
    shopTargetScrollX = math.max(0, math.min(maxShopScroll, shopTargetScrollX))
    shopScrollX = math.max(0, math.min(maxShopScroll, shopScrollX))
    love.graphics.setColor(ui.bgClear)
    love.graphics.rectangle("fill", 0, 0, sw, sh)

    -- Top Header (PIECES | BOARD | THEMES | CURRENCY)
    love.graphics.setColor(ui.panelBg)
    love.graphics.rectangle("fill", 0, 0, sw, 78)
    love.graphics.setColor(ui.panelBorder)
    love.graphics.line(0, 78, sw, 78)

    drawButton("shop_back", 24, 16, 120, 46, I18N.t("back_btn"), {
        onClick = function()
            Sound.play("click")
            currentScreen = "menu"
        end
    })

    local tabW = 165
    local tabsStart = (sw - (tabW * 4 + 30)) * 0.5
    local tabs = {
        { id = "pieces",   label = I18N.t("tab_pieces")   },
        { id = "board",    label = I18N.t("tab_board")    },
        { id = "themes",   label = I18N.t("tab_themes")   },
        { id = "currency", label = I18N.t("tab_currency") }
    }
    for i, t in ipairs(tabs) do
        drawButton("tab_" .. t.id, tabsStart + (i - 1) * (tabW + 10), 14, tabW, 50, t.label, {
            active = (shopTab == t.id),
            onClick = function()
                Sound.play("click")
                shopTab = t.id
                shopScrollX = 0
                shopTargetScrollX = 0
            end
        })
    end

    -- Coin counter in top-right (vector coin icon, no missing glyphs)
    love.graphics.setColor(ui.btnDefault)
    love.graphics.rectangle("fill", sw - 200, 16, 176, 46, 22, 22)
    love.graphics.setColor(ui.panelBorder)
    love.graphics.rectangle("line", sw - 200, 16, 176, 46, 22, 22)
    love.graphics.setColor(0.95, 0.78, 0.26, 1.0)
    love.graphics.circle("fill", sw - 176, 39, 8)
    love.graphics.setFont(fonts.btn)
    love.graphics.setColor(ui.textMain)
    love.graphics.printf(I18N.t("coins_label", Config.coins), sw - 162, 29, 130, "center")

    local availH = sh - 100
    local cardW = 260
    local cardH = math.floor(math.min(415, availH - 24))
    local cardGap = 26
    local rowY = math.floor(92 + math.max(0, (availH - cardH - 20) * 0.5))
    local prevH = math.floor(cardH - 165)
    local prevY = rowY + 54
    local btnY = rowY + cardH - 58
    local btnH = 44

    if shopTab == "pieces" then
        for i, skinId in ipairs(Config.pieceSkinOrder) do
            local skin = Config.pieceSkins[skinId]
            if skin then
                local cx = 64 + (i - 1) * (cardW + cardGap) - shopScrollX
                if cx + cardW >= -20 and cx <= sw + 20 then
                    drawPanel(cx, rowY, cardW, cardH)
                    if skin.underRework then
                        love.graphics.setColor(0.12, 0.13, 0.16, 0.60)
                        love.graphics.rectangle("fill", cx + 2, rowY + 2, cardW - 4, cardH - 4, 14, 14)
                        love.graphics.setColor(0.38, 0.40, 0.46, 0.60)
                        love.graphics.setLineWidth(1.5)
                        love.graphics.rectangle("line", cx, rowY, cardW, cardH, 14, 14)
                    elseif skin.rarity == "legendary" then
                        love.graphics.setColor(0.95, 0.76, 0.14, 0.24)
                        love.graphics.rectangle("fill", cx + 2, rowY + 2, cardW - 4, cardH - 4, 14, 14)
                        love.graphics.setColor(0.98, 0.82, 0.22, 0.90)
                        love.graphics.setLineWidth(2)
                        love.graphics.rectangle("line", cx, rowY, cardW, cardH, 14, 14)
                    elseif skin.rarity == "epic" then
                        love.graphics.setColor(0.62, 0.24, 0.88, 0.24)
                        love.graphics.rectangle("fill", cx + 2, rowY + 2, cardW - 4, cardH - 4, 14, 14)
                        love.graphics.setColor(0.74, 0.36, 0.98, 0.90)
                        love.graphics.setLineWidth(2)
                        love.graphics.rectangle("line", cx, rowY, cardW, cardH, 14, 14)
                    elseif skin.rarity == "rare" then
                        love.graphics.setColor(0.16, 0.70, 0.34, 0.20)
                        love.graphics.rectangle("fill", cx + 2, rowY + 2, cardW - 4, cardH - 4, 14, 14)
                        love.graphics.setColor(0.25, 0.88, 0.45, 0.90)
                        love.graphics.setLineWidth(2)
                        love.graphics.rectangle("line", cx, rowY, cardW, cardH, 14, 14)
                    end

                    love.graphics.setFont(fonts.btn)
                    if skin.underRework then
                        love.graphics.setColor(0.58, 0.62, 0.68, 1.0)
                    elseif skin.rarity == "legendary" then
                        love.graphics.setColor(1.00, 0.88, 0.35, 1.0)
                    elseif skin.rarity == "epic" then
                        love.graphics.setColor(0.85, 0.55, 1.00, 1.0)
                    elseif skin.rarity == "rare" then
                        love.graphics.setColor(0.40, 0.95, 0.55, 1.0)
                    else
                        love.graphics.setColor(ui.textMain)
                    end
                    love.graphics.printf(I18N.t(skin.nameKey), cx + 12, rowY + 12, cardW - 24, "center")

                    love.graphics.setFont(fonts.small)
                    if skin.underRework then
                        love.graphics.setColor(0.85, 0.45, 0.35, 1.0)
                        love.graphics.printf(I18N.t("btn_rework"), cx + 10, rowY + 34, cardW - 20, "center")
                    elseif skin.upgradeable then
                        local wCount = (Config.skinWins and Config.skinWins[skinId]) or 0
                        love.graphics.setColor(0.98, 0.84, 0.28, 1.0)
                        love.graphics.printf(I18N.t("skin_upgrade_hint", math.min(10, wCount)), cx + 10, rowY + 34, cardW - 20, "center")
                    elseif skin.rarity == "legendary" then
                        love.graphics.setColor(0.98, 0.84, 0.28, 1.0)
                        love.graphics.printf(I18N.t("rarity_legendary"), cx + 10, rowY + 34, cardW - 20, "center")
                    elseif skin.rarity == "epic" then
                        love.graphics.setColor(0.78, 0.46, 0.98, 1.0)
                        love.graphics.printf(I18N.t("rarity_epic"), cx + 10, rowY + 34, cardW - 20, "center")
                    elseif skin.rarity == "rare" then
                        love.graphics.setColor(0.35, 0.88, 0.50, 1.0)
                        love.graphics.printf(I18N.t("rarity_rare"), cx + 10, rowY + 34, cardW - 20, "center")
                    else
                        love.graphics.setColor(ui.textSub)
                        love.graphics.printf(I18N.t("rarity_common"), cx + 10, rowY + 34, cardW - 20, "center")
                    end

                    local isClosed = (skin.underRework == true) or (not skin.unlocked and skin.unlockType == "ach")
                    local prevX, prevW = cx + 18, cardW - 36
                    if isClosed then
                        love.graphics.setColor(math.max(0.16, ui.bgClear[1]), math.max(0.17, ui.bgClear[2]), math.max(0.21, ui.bgClear[3]), 1.0)
                    else
                        love.graphics.setColor(ui.bgClear)
                    end
                    love.graphics.rectangle("fill", prevX, prevY, prevW, prevH, 10, 10)
                    local prevItem = skin
                    if isClosed then
                        prevItem = {
                            id = skin.id,
                            style = skin.style,
                            taperByHeight = skin.taperByHeight,
                            player1Color = skin.player1Color,
                            player2Color = skin.player2Color,
                            woodStrength = skin.woodStrength,
                            specular = skin.specular,
                            silhouette = true
                        }
                    end
                    renderer:renderShopPreview(
                        prevX, prevY, prevW, prevH, sw, sh, "pieces",
                        prevItem, isClosed and 0.45 or (shopSpinAngle + i * 0.5)
                    )

                    local isSelected = (Config.activePieceSkin == skinId)
                    if skin.underRework then
                        drawButton("pskin_rework_" .. skinId, cx + 24, btnY, cardW - 48, btnH,
                            I18N.t("btn_rework"),
                            {
                                disabled = true,
                                font = fonts.small,
                                onClick = function() Sound.play("click") end
                            }
                        )
                    elseif skin.unlocked then
                        drawButton("pskin_" .. skinId, cx + 24, btnY, cardW - 48, btnH,
                            isSelected and I18N.t("btn_selected") or I18N.t("btn_select"),
                            {
                                active = isSelected,
                                primary = not isSelected,
                                onClick = function()
                                    Sound.play("click")
                                    Config.activePieceSkin = skinId
                                    Storage.save()
                                end
                            }
                        )
                    elseif skin.unlockType == "coins" then
                        drawButton("pskin_buy_" .. skinId, cx + 24, btnY, cardW - 48, btnH,
                            I18N.t("btn_buy", skin.price),
                            {
                                accent = true,
                                onClick = function()
                                    if Config.coins >= skin.price then
                                        Sound.play("win")
                                        Config.coins = Config.coins - skin.price
                                        skin.unlocked = true
                                        Config.activePieceSkin = skinId
                                        Storage.save()
                                    else
                                        Sound.play("click")
                                        shopTab = "currency"
                                    end
                                end
                            }
                        )
                    elseif skin.unlockType == "ad" then
                        drawButton("pskin_ad_" .. skinId, cx + 24, btnY, cardW - 48, 46, I18N.t("btn_ad_stub"), {
                            onClick = function()
                                Sound.play("win")
                                skin.unlocked = true
                                Config.activePieceSkin = skinId
                                Storage.save()
                            end
                        })
                    else
                        drawButton("pskin_ach_" .. skinId, cx + 24, btnY, cardW - 48, 46, I18N.t("btn_ach_stub"), {
                            font = fonts.small,
                            onClick = function() Sound.play("click") end
                        })
                    end
                end
            end
        end

    elseif shopTab == "board" then
        local c1x = 64 - shopScrollX
        local halfH = (cardH - 16) * 0.5
        local curBoardSkin = Config.getBoardSkin()

        -- Top Half: Round Board
        drawPanel(c1x, rowY, cardW, halfH)
        love.graphics.setFont(fonts.btn)
        love.graphics.setColor(ui.textMain)
        love.graphics.printf(I18N.t("shape_round"), c1x + 10, rowY + 10, cardW - 20, "center")
        renderer:renderShopPreview(c1x + 20, rowY + 36, cardW - 40, 105, sw, sh, "board_shape", {
            shape = "round",
            baseColor = curBoardSkin.baseColor,
            woodStrength = curBoardSkin.woodStrength
        }, shopSpinAngle)
        local roundActive = (Config.boardShape == "round")
        drawButton("shape_round_btn", c1x + 24, rowY + halfH - 50, cardW - 48, 38,
            roundActive and I18N.t("btn_selected") or I18N.t("btn_select"),
            {
                active = roundActive,
                primary = not roundActive,
                font = fonts.small,
                onClick = function()
                    Sound.play("click")
                    Config.boardShape = "round"
                    Storage.save()
                end
            }
        )

        -- Bottom Half: Square Board
        local botY = rowY + halfH + 16
        drawPanel(c1x, botY, cardW, halfH)
        love.graphics.setFont(fonts.btn)
        love.graphics.setColor(ui.textMain)
        love.graphics.printf(I18N.t("shape_square"), c1x + 10, botY + 10, cardW - 20, "center")
        renderer:renderShopPreview(c1x + 20, botY + 36, cardW - 40, 105, sw, sh, "board_shape", {
            shape = "square",
            baseColor = curBoardSkin.baseColor,
            woodStrength = curBoardSkin.woodStrength
        }, shopSpinAngle)
        local sqActive = (Config.boardShape == "square")
        drawButton("shape_sq_btn", c1x + 24, botY + halfH - 50, cardW - 48, 38,
            sqActive and I18N.t("btn_selected") or I18N.t("btn_select"),
            {
                active = sqActive,
                primary = not sqActive,
                font = fonts.small,
                onClick = function()
                    Sound.play("click")
                    Config.boardShape = "square"
                    Storage.save()
                end
            }
        )

        for idx, bSkinId in ipairs(Config.boardSkinOrder) do
            local bSkin = Config.boardSkins[bSkinId]
            if bSkin then
                local cx = 64 + idx * (cardW + cardGap) - shopScrollX
                if cx + cardW >= -20 and cx <= sw + 20 then
                    drawPanel(cx, rowY, cardW, cardH)

                    if bSkin.underRework then
                        love.graphics.setColor(0.12, 0.13, 0.16, 0.60)
                        love.graphics.rectangle("fill", cx + 2, rowY + 2, cardW - 4, cardH - 4, 14, 14)
                        love.graphics.setColor(0.38, 0.40, 0.46, 0.60)
                        love.graphics.setLineWidth(1.5)
                        love.graphics.rectangle("line", cx, rowY, cardW, cardH, 14, 14)
                    elseif bSkin.rarity == "legendary" then
                        love.graphics.setColor(0.95, 0.76, 0.14, 0.24)
                        love.graphics.rectangle("fill", cx + 2, rowY + 2, cardW - 4, cardH - 4, 14, 14)
                        love.graphics.setColor(0.98, 0.82, 0.22, 0.90)
                        love.graphics.setLineWidth(2)
                        love.graphics.rectangle("line", cx, rowY, cardW, cardH, 14, 14)
                    elseif bSkin.rarity == "epic" then
                        love.graphics.setColor(0.62, 0.24, 0.88, 0.24)
                        love.graphics.rectangle("fill", cx + 2, rowY + 2, cardW - 4, cardH - 4, 14, 14)
                        love.graphics.setColor(0.74, 0.36, 0.98, 0.90)
                        love.graphics.setLineWidth(2)
                        love.graphics.rectangle("line", cx, rowY, cardW, cardH, 14, 14)
                    elseif bSkin.rarity == "rare" then
                        love.graphics.setColor(0.16, 0.70, 0.34, 0.20)
                        love.graphics.rectangle("fill", cx + 2, rowY + 2, cardW - 4, cardH - 4, 14, 14)
                        love.graphics.setColor(0.25, 0.88, 0.45, 0.90)
                        love.graphics.setLineWidth(2)
                        love.graphics.rectangle("line", cx, rowY, cardW, cardH, 14, 14)
                    end

                    love.graphics.setFont(fonts.btn)
                    if bSkin.underRework then
                        love.graphics.setColor(0.58, 0.62, 0.68, 1.0)
                    elseif bSkin.rarity == "legendary" then
                        love.graphics.setColor(1.00, 0.88, 0.35, 1.0)
                    elseif bSkin.rarity == "epic" then
                        love.graphics.setColor(0.85, 0.55, 1.00, 1.0)
                    elseif bSkin.rarity == "rare" then
                        love.graphics.setColor(0.40, 0.95, 0.55, 1.0)
                    else
                        love.graphics.setColor(ui.textMain)
                    end
                    love.graphics.printf(I18N.t(bSkin.nameKey), cx + 12, rowY + 12, cardW - 24, "center")

                    love.graphics.setFont(fonts.small)
                    if bSkin.underRework then
                        love.graphics.setColor(0.85, 0.45, 0.35, 1.0)
                        love.graphics.printf(I18N.t("btn_rework"), cx + 10, rowY + 34, cardW - 20, "center")
                    elseif bSkin.upgradeable then
                        local prof = Config.profile or {}
                        local wCount = (prof.boardWins and prof.boardWins[bSkinId])
                                    or (prof.skinWins and prof.skinWins[bSkinId]) or 0
                        love.graphics.setColor(0.98, 0.84, 0.28, 1.0)
                        love.graphics.printf(I18N.t("skin_upgrade_hint", math.min(10, wCount)), cx + 10, rowY + 34, cardW - 20, "center")
                    elseif bSkin.rarity == "legendary" then
                        love.graphics.setColor(0.98, 0.84, 0.28, 1.0)
                        love.graphics.printf(I18N.t("rarity_legendary"), cx + 10, rowY + 34, cardW - 20, "center")
                    elseif bSkin.rarity == "rare" then
                        love.graphics.setColor(0.35, 0.88, 0.50, 1.0)
                        love.graphics.printf(I18N.t("rarity_rare"), cx + 10, rowY + 34, cardW - 20, "center")
                    else
                        love.graphics.setColor(ui.textSub)
                        love.graphics.printf(I18N.t("rarity_common"), cx + 10, rowY + 34, cardW - 20, "center")
                    end

                    local isClosed = (bSkin.underRework == true) or (not bSkin.unlocked and bSkin.unlockType == "ach")
                    local prevX, prevW = cx + 18, cardW - 36
                    if isClosed then
                        love.graphics.setColor(math.max(0.16, ui.bgClear[1]), math.max(0.17, ui.bgClear[2]), math.max(0.21, ui.bgClear[3]), 1.0)
                    else
                        love.graphics.setColor(ui.bgClear)
                    end
                    love.graphics.rectangle("fill", prevX, prevY, prevW, prevH, 10, 10)
                    renderer:renderShopPreview(prevX, prevY, prevW, prevH, sw, sh, "board_skin", {
                        isRound = (Config.boardShape == "round"),
                        style = bSkin.style,
                        baseColor = bSkin.baseColor,
                        pegColor = bSkin.pegColor,
                        woodStrength = bSkin.woodStrength,
                        silhouette = isClosed
                    }, isClosed and 0.45 or (shopSpinAngle + idx * 0.4))

                    local isSelected = (Config.activeBoardSkin == bSkinId)
                    if bSkin.underRework then
                        drawButton("bskin_rework_" .. bSkinId, cx + 24, btnY, cardW - 48, btnH,
                            I18N.t("btn_rework"),
                            {
                                disabled = true,
                                font = fonts.small,
                                onClick = function() Sound.play("click") end
                            }
                        )
                    elseif bSkin.unlocked then
                        drawButton("bskin_" .. bSkinId, cx + 24, btnY, cardW - 48, btnH,
                            isSelected and I18N.t("btn_selected") or I18N.t("btn_select"),
                            {
                                active = isSelected,
                                primary = not isSelected,
                                onClick = function()
                                    Config.activeBoardSkin = bSkinId
                                    Sound.playDrop(bSkin.soundType)
                                    Storage.save()
                                end
                            }
                        )
                    elseif bSkin.unlockType == "coins" then
                        drawButton("bskin_buy_" .. bSkinId, cx + 24, btnY, cardW - 48, btnH,
                            I18N.t("btn_buy", bSkin.price),
                            {
                                accent = true,
                                onClick = function()
                                    if Config.coins >= bSkin.price then
                                        Config.coins = Config.coins - bSkin.price
                                        bSkin.unlocked = true
                                        Config.activeBoardSkin = bSkinId
                                        Sound.playDrop(bSkin.soundType)
                                        Storage.save()
                                    else
                                        Sound.play("click")
                                        shopTab = "currency"
                                    end
                                end
                            }
                        )
                    else
                        drawButton("bskin_ach_" .. bSkinId, cx + 24, btnY, cardW - 48, btnH, I18N.t("btn_ach_stub"), {
                            font = fonts.small,
                            onClick = function() Sound.play("click") end
                        })
                    end
                end
            end
        end

    elseif shopTab == "themes" then
        for i, themeId in ipairs(Config.uiThemeOrder) do
            local th = Config.uiThemes[themeId]
            local cx = 64 + (i - 1) * (cardW + cardGap) - shopScrollX
            if cx + cardW >= -20 and cx <= sw + 20 then
                drawPanel(cx, rowY, cardW, cardH)

                love.graphics.setFont(fonts.btn)
                love.graphics.setColor(ui.textMain)
                love.graphics.printf(I18N.t(th.nameKey), cx + 12, rowY + 18, cardW - 24, "center")

                local prevX, prevW = cx + 22, cardW - 44
                love.graphics.setColor(th.bgClear)
                love.graphics.rectangle("fill", prevX, prevY, prevW, prevH, 10, 10)
                love.graphics.setColor(th.panelBg)
                love.graphics.rectangle("fill", prevX + 18, prevY + 16, prevW - 36, prevH - 32, 10, 10)
                love.graphics.setColor(th.panelBorder)
                love.graphics.rectangle("line", prevX + 18, prevY + 16, prevW - 36, prevH - 32, 10, 10)

                love.graphics.setColor(th.btnPrimary)
                love.graphics.rectangle("fill", prevX + 34, prevY + 32, prevW - 68, 32, 8, 8)
                love.graphics.setColor(th.btnDefault)
                love.graphics.rectangle("fill", prevX + 34, prevY + 74, prevW - 68, 30, 8, 8)
                love.graphics.setColor(th.btnAccent)
                love.graphics.rectangle("fill", prevX + 34, prevY + 114, prevW - 68, 30, 8, 8)

                local isSelected = (Config.activeUITheme == themeId)
                if th.unlocked then
                    drawButton("uitheme_" .. themeId, cx + 24, btnY, cardW - 48, btnH,
                        isSelected and I18N.t("btn_selected") or I18N.t("btn_select"),
                        {
                            active = isSelected,
                            primary = not isSelected,
                            onClick = function()
                                Sound.play("click")
                                Config.activeUITheme = themeId
                                Storage.save()
                            end
                        }
                    )
                elseif th.unlockType == "coins" then
                    drawButton("uitheme_buy_" .. themeId, cx + 24, btnY, cardW - 48, btnH,
                        I18N.t("btn_buy", th.price),
                        {
                            accent = true,
                            onClick = function()
                                if Config.coins >= th.price then
                                    Sound.play("win")
                                    Config.coins = Config.coins - th.price
                                    th.unlocked = true
                                    Config.activeUITheme = themeId
                                    Storage.save()
                                else
                                    Sound.play("click")
                                    shopTab = "currency"
                                end
                            end
                        }
                    )
                else
                    drawButton("uitheme_ach_" .. themeId, cx + 24, btnY, cardW - 48, btnH, I18N.t("btn_ach_stub"), {
                        font = fonts.small,
                        onClick = function() Sound.play("click") end
                    })
                end
            end
        end

    elseif shopTab == "currency" then
        local cols = 4
        local pw, ph = 250, 175
        local gapX, gapY = 22, 20
        local totalW = cols * pw + (cols - 1) * gapX
        local startX = (sw - totalW) * 0.5
        local startY = 112

        for i, pack in ipairs(Config.currencyPacks) do
            local c = (i - 1) % cols
            local r = math.floor((i - 1) / cols)
            local px = startX + c * (pw + gapX)
            local py = startY + r * (ph + gapY)
            drawPanel(px, py, pw, ph)

            love.graphics.setColor(ui.btnAccent)
            love.graphics.rectangle("fill", px + 16, py + 12, pw - 32, 26, 6, 6)
            love.graphics.setFont(fonts.small)
            love.graphics.setColor(ui.textMain)
            love.graphics.printf(pack.bonus, px + 16, py + 17, pw - 32, "center")

            love.graphics.setFont(fonts.h2)
            love.graphics.setColor(ui.accentText)
            love.graphics.printf(tostring(pack.coins) .. " Coins", px, py + 54, pw, "center")

            drawButton("buy_pack_" .. pack.id, px + 24, py + ph - 58, pw - 48, 42, pack.price, {
                primary = true,
                onClick = function()
                    Sound.play("win")
                    Config.coins = Config.coins + pack.coins
                    Storage.save()
                end
            })
        end

        local banW, banH = totalW, 96
        local banX, banY = startX, startY + 2 * (ph + gapY) + 10
        drawPanel(banX, banY, banW, banH)

        love.graphics.setFont(fonts.h2)
        love.graphics.setColor(ui.textMain)
        love.graphics.print(I18N.t("remove_ads_title"), banX + 28, banY + 18)

        love.graphics.setFont(fonts.body)
        love.graphics.setColor(ui.textSub)
        love.graphics.print(I18N.t("remove_ads_desc"), banX + 28, banY + 52)

        drawButton("remove_ads_btn", banX + banW - 220, banY + 24, 192, 48,
            Config.adsRemoved and I18N.t("ads_removed") or I18N.t("remove_ads_btn"),
            {
                active = Config.adsRemoved,
                accent = not Config.adsRemoved,
                onClick = function()
                    if not Config.adsRemoved then
                        Sound.play("win")
                        Config.adsRemoved = true
                        Config.coins = Config.coins + 50
                        Storage.save()
                    end
                end
            }
        )
    end
end

local function drawCleanGameHUD(sw, sh)
    local ui = Config.getUITheme()
    local pieceSkin = Config.getPieceSkin()
    local isWhiteTurn = (gameLogic.currentPlayer == BoardLogic.Player.WHITE)

    -- 1. TOP-CENTER: Turn Indicator + 5:00 Timers
    local bannerW = timers.enabled and 440 or 280
    local bannerH = 58
    local bx = (sw - bannerW) * 0.5
    local by = 14 + turnBannerPulse * 3.0

    drawPanel(bx, by, bannerW, bannerH)

    local activeCol = isWhiteTurn and pieceSkin.player1Color or pieceSkin.player2Color
    local turnStr   = isWhiteTurn and I18N.t("turn_white") or I18N.t("turn_black")

    if timers.enabled then
        love.graphics.setFont(fonts.hudTimer)
        love.graphics.setColor(isWhiteTurn and ui.textMain or ui.textSub)
        love.graphics.printf(formatClock(timers.white), bx + 16, by + 19, 80, "left")

        drawTorusBadge(bx + bannerW * 0.5 - 78, by + 29, 12, activeCol)
        love.graphics.setFont(fonts.hudTurn)
        love.graphics.setColor(ui.textMain)
        love.graphics.printf(turnStr, bx + 95, by + 16, bannerW - 190, "center")

        love.graphics.setFont(fonts.hudTimer)
        love.graphics.setColor((not isWhiteTurn) and ui.textMain or ui.textSub)
        love.graphics.printf(formatClock(timers.black), bx + bannerW - 96, by + 19, 80, "right")
    else
        drawTorusBadge(bx + 36, by + 29, 13, activeCol)
        love.graphics.setFont(fonts.hudTurn)
        love.graphics.setColor(ui.textMain)
        love.graphics.printf(turnStr, bx + 54, by + 16, bannerW - 70, "center")
    end

    -- 2. TOP-RIGHT: Scrollable Chess-Style Move Log (1. a1.1   b2.1) + Arrow Rewind Indicator
    local logW, logH = 225, 250
    local lx, ly = sw - logW - 18, 14
    drawPanel(lx, ly, logW, logH)

    love.graphics.setFont(fonts.btn)
    love.graphics.setColor(ui.textMain)
    love.graphics.printf(I18N.t("moves_header"), lx, ly + 10, logW, "center")
    love.graphics.setColor(ui.panelBorder)
    love.graphics.line(lx + 14, ly + 34, lx + logW - 14, ly + 34)

    local pairsList = gameLogic:getChessMovePairs()
    local totalHalfMoves = #gameLogic.moveHistory
    if #pairsList == 0 then
        love.graphics.setFont(fonts.small)
        love.graphics.setColor(ui.textSub)
        love.graphics.printf(I18N.t("no_moves_yet"), lx + 12, ly + 110, logW - 24, "center")
    else
        love.graphics.setFont(fonts.small)
        local maxVisible = 9
        local maxScroll = math.max(0, #pairsList - maxVisible)
        moveLogScroll = math.max(0, math.min(maxScroll, moveLogScroll))
        local startIdx = moveLogScroll + 1
        local endIdx   = math.min(#pairsList, startIdx + maxVisible - 1)
        local rowY = ly + 42

        setUIScissor(lx + 4, ly + 38, logW - 8, logH - 44)
        for i = startIdx, endIdx do
            local p = pairsList[i]
            local wPly = (i - 1) * 2 + 1
            local bPly = (i - 1) * 2 + 2

            love.graphics.setColor(ui.textSub)
            love.graphics.print(string.format("%d.", p.num), lx + 16, rowY)

            if viewPly == wPly then
                love.graphics.setColor(ui.btnActive)
                love.graphics.rectangle("fill", lx + 50, rowY - 2, 62, 19, 4, 4)
            end
            love.graphics.setColor(ui.textMain)
            love.graphics.print(p.white, lx + 56, rowY)
            table.insert(uiButtons, {
                id = "ply_w_" .. tostring(wPly),
                x = lx + 48, y = rowY - 2, w = 66, h = 20,
                onClick = function()
                    Sound.play("hover")
                    viewPly = wPly
                end
            })

            if #p.black > 0 then
                if viewPly == bPly then
                    love.graphics.setColor(ui.btnActive)
                    love.graphics.rectangle("fill", lx + 122, rowY - 2, 62, 19, 4, 4)
                end
                love.graphics.setColor((viewPly == bPly) and ui.textMain or ui.textSub)
                love.graphics.print(p.black, lx + 128, rowY)
                table.insert(uiButtons, {
                    id = "ply_b_" .. tostring(bPly),
                    x = lx + 120, y = rowY - 2, w = 66, h = 20,
                    onClick = function()
                        Sound.play("hover")
                        viewPly = bPly
                    end
                })
            end
            rowY = rowY + 21
        end
        setUIScissor()

        -- Visual scrollbar for Move Log
        if maxScroll > 0 then
            local sbX = lx + logW - 8
            local sbY = ly + 40
            local sbH = logH - 48
            love.graphics.setColor(ui.panelBorder)
            love.graphics.rectangle("fill", sbX, sbY, 4, sbH, 2, 2)
            local thumbH = math.max(16, sbH * (maxVisible / #pairsList))
            local thumbY = sbY + (sbH - thumbH) * (moveLogScroll / maxScroll)
            love.graphics.setColor(ui.accentText)
            love.graphics.rectangle("fill", sbX, thumbY, 4, thumbH, 2, 2)
        end
    end

    -- Кнопка выхода в главное меню появляется под списком ходов только в конце партии и если окно победы скрыто
    if gameLogic.isGameOver and not activeDrop and hideWinModal then
        local exitY = ly + logH + 10
        local exitH = 38
        drawButton("hud_main_menu", lx, exitY, logW, exitH, "  " .. I18N.t("main_menu"), {
            font = fonts.small,
            onClick = function()
                Sound.play("click")
                isReplayMode = false
                if localOnlineRoom then
                    Firebase.closeFriendRoom(localOnlineRoom.code)
                    localOnlineRoom = nil
                end
                currentScreen = "menu"
            end
        })
        do
            local ix, iy = lx + 16, exitY + 10
            love.graphics.setColor(ui.textMain)
            love.graphics.setLineWidth(1.8)
            love.graphics.line(ix + 8, iy, ix, iy, ix, iy + 18, ix + 8, iy + 18)
            love.graphics.line(ix + 5, iy + 9, ix + 15, iy + 9)
            love.graphics.line(ix + 11, iy + 5, ix + 15, iy + 9, ix + 11, iy + 13)
            love.graphics.setLineWidth(1)
        end
    end

    -- 3. CENTER SCREEN POPUP AFTER VICTORY / DRAW (Toggle with F / А or [X] to inspect board!)
    if gameLogic.isGameOver and not activeDrop then
        if not hideWinModal then
            love.graphics.setColor(0.05, 0.05, 0.06, 0.62)
            love.graphics.rectangle("fill", 0, 0, sw, sh)

            local pw, ph = 520, 276
            local px, py = (sw - pw) * 0.5, (sh - ph) * 0.5
            drawPanel(px, py, pw, ph)

            drawButton("win_close_x", px + pw - 44, py + 12, 32, 32, "X", {
                font = fonts.small,
                onClick = function()
                    Sound.play("click")
                    hideWinModal = true
                end
            })

            love.graphics.setFont(fonts.h2)
            love.graphics.setColor(ui.textMain)

            local titleText = ""
            local subText = ""
            if gameLogic.isDraw then
                titleText = I18N.t("win_draw")
            elseif gameLogic.timeoutWinner ~= BoardLogic.Player.NONE then
                titleText = (gameLogic.timeoutWinner == BoardLogic.Player.BLACK)
                    and I18N.t("timeout_white")
                    or  I18N.t("timeout_black")
            else
                titleText = (gameLogic.winner == BoardLogic.Player.WHITE)
                    and I18N.t("win_white")
                    or  I18N.t("win_black")
                subText = I18N.t(gameLogic.winningLineType)
            end

            love.graphics.printf(titleText, px + 48, py + 24, pw - 96, "center")

            love.graphics.setFont(fonts.body)
            love.graphics.setColor(ui.textSub)
            love.graphics.printf(subText, px + 28, py + 68, pw - 56, "center")

            if lastRatingDelta ~= 0 then
                local sign = (lastRatingDelta > 0) and "+" or ""
                love.graphics.setFont(fonts.btn)
                love.graphics.setColor(ui.accentText)
                love.graphics.printf(I18N.t("rating_change", Config.profile.rating, sign), px, py + 106, pw, "center")
            end

            love.graphics.setFont(fonts.small)
            love.graphics.setColor(ui.textSub)
            love.graphics.printf(I18N.t("inspect_board_hint"), px + 20, py + 144, pw - 40, "center")
            table.insert(uiButtons, {
                id = "win_inspect_toggle",
                x = px + 20, y = py + 136, w = pw - 40, h = 38,
                onClick = function()
                    Sound.play("click")
                    hideWinModal = true
                end
            })

            drawButton("win_again", px + 38, py + ph - 66, 205, 46, I18N.t("play_again"), {
                primary = true,
                onClick = function()
                    Sound.play("click")
                    startNewGame(Config.currentMode, Config.botDifficulty)
                end
            })
            drawButton("win_menu", px + pw - 243, py + ph - 66, 205, 46, I18N.t("main_menu"), {
                onClick = function()
                    Sound.play("click")
                    if localOnlineRoom then
                        Firebase.closeFriendRoom(localOnlineRoom.code)
                        localOnlineRoom = nil
                    end
                    currentScreen = "menu"
                end
            })
        else
            -- Subtle bottom pill when inspecting the final 3D board position (also clickable on mobile/touch!)
            local pillW, pillH = 440, 38
            local pillX, pillY = (sw - pillW) * 0.5, sh - pillH - 16
            drawPanel(pillX, pillY, pillW, pillH)
            love.graphics.setFont(fonts.small)
            love.graphics.setColor(ui.textMain)
            love.graphics.printf(I18N.t("show_result_hint"), pillX + 12, pillY + 11, pillW - 24, "center")
            table.insert(uiButtons, {
                id = "win_show_result_pill",
                x = pillX, y = pillY, w = pillW, h = pillH,
                onClick = function()
                    Sound.play("click")
                    hideWinModal = false
                end
            })
        end
    end
end

function love.draw()
    local sw, sh, uiScale, realW, realH = getUIScaleAndDims()
    local ui = Config.getUITheme()
    local clearCol = (currentScreen == "game" and Config.activeBoardSkin == "manhattan")
        and { 0.015, 0.020, 0.038, 1.0 }
        or ui.bgClear
    love.graphics.clear(clearCol[1], clearCol[2], clearCol[3], 1.0, true, true)
    uiButtons = {}

    if currentScreen == "game" then
        renderer:renderScene(realW, realH, {
            config        = Config,
            logic         = gameLogic,
            maxPly        = viewPly,
            hoveredX      = hoveredX,
            hoveredZ      = hoveredZ,
            hoveredY      = hoveredY,
            activeDrop    = activeDrop,
            showScattered = false,
            showCoords    = true,
            coordFont     = fonts.coord,
            clipOffsetX   = 0.0,
            clipOffsetY   = 0.04
        })
        love.graphics.push()
        love.graphics.scale(uiScale, uiScale)
        drawCleanGameHUD(sw, sh)
        love.graphics.pop()

    elseif currentScreen == "shop" then
        love.graphics.push()
        love.graphics.scale(uiScale, uiScale)
        drawShopScreen(sw, sh)
        love.graphics.pop()

    else
        local isPortrait = (realW < realH)
        renderer:renderScene(realW, realH, {
            config        = Config,
            logic         = menuDemoLogic,
            hoveredX      = nil,
            hoveredZ      = nil,
            activeDrop    = nil,
            showScattered = true,
            showCoords    = false,
            coordFont     = fonts.coord,
            clipOffsetX   = isPortrait and 0.0 or 0.27,
            clipOffsetY   = isPortrait and 0.36 or 0.10
        })

        love.graphics.push()
        love.graphics.scale(uiScale, uiScale)
        if currentScreen == "menu" then
            drawLeftMainMenu(sw, sh)
        else
            love.graphics.setColor(0.05, 0.05, 0.06, 0.65)
            love.graphics.rectangle("fill", 0, 0, sw, sh)
            if currentScreen == "bot_modal" then
                drawBotModal(sw, sh)
            elseif currentScreen == "online_modal" then
                drawOnlineModal(sw, sh)
            elseif currentScreen == "lan_modal" then
                drawLanModal(sw, sh)
            elseif currentScreen == "profile_modal" then
                drawProfileModal(sw, sh)
            elseif currentScreen == "auth_modal" then
                drawAuthModal(sw, sh)
            elseif currentScreen == "settings_modal" then
                drawSettingsModal(sw, sh)
            elseif currentScreen == "rules_modal" then
                drawRulesModal(sw, sh)
            elseif currentScreen == "tournament_modal" then
                drawTournamentModal(sw, sh)
            elseif currentScreen == "friend_game_modal" then
                drawFriendGameModal(sw, sh)
            elseif currentScreen == "friend_profile_modal" then
                drawFriendProfileModal(sw, sh)
            end
        end
        love.graphics.pop()
    end

    -- Новогодний лёгкий снежок и морозная окантовка по краям экрана
    if Config.selectedUITheme == "new_year" then
        for _, sf in ipairs(snowflakes) do
            love.graphics.setColor(0.94, 0.98, 1.0, 0.72)
            love.graphics.circle("fill", sf.x * realW, sf.y * realH, sf.r)
        end
        love.graphics.setColor(0.76, 0.90, 1.0, 0.22)
        love.graphics.setLineWidth(14)
        love.graphics.rectangle("line", 2, 2, realW - 4, realH - 4, 18, 18)
        love.graphics.setColor(0.88, 0.96, 1.0, 0.35)
        love.graphics.setLineWidth(4)
        love.graphics.rectangle("line", 0, 0, realW, realH, 16, 16)
    elseif Config.selectedUITheme == "halloween" then
        love.graphics.setColor(0.95, 0.42, 0.08, 0.14)
        love.graphics.setLineWidth(10)
        love.graphics.rectangle("line", 2, 2, realW - 4, realH - 4, 14, 14)
    end
end

function love.mousepressed(x, y, button)
    local sw, sh, uiScale = getUIScaleAndDims()
    local ux, uy = x / uiScale, y / uiScale
    if button == 1 then
        mouseState.leftDown = true
        mouseState.pressX = ux
        mouseState.pressY = uy
        mouseState.dragged = false
        mouseState.scrollAccumY = 0
        mouseState.inMoveLog = false
        mouseState.inProfileMatches = false

        if currentScreen == "shop" and uy > 80 then
            shopDragging = true
        elseif currentScreen == "game" then
            local logW, logH = 225, 250
            local lx, ly = sw - logW - 18, 14
            if ux >= lx and ux <= lx + logW and uy >= ly and uy <= ly + logH then
                mouseState.inMoveLog = true
            end
        elseif currentScreen == "profile_modal" then
            local pw, ph = 820, 560
            local px, py = (sw - pw) * 0.5, (sh - ph) * 0.5
            local rx, ry, rw, rh = px + 388, py + 178, 398, 184
            if ux >= rx and ux <= rx + rw and uy >= ry and uy <= ry + rh then
                mouseState.inProfileMatches = true
            end
        end
    elseif button == 2 or button == 3 then
        mouseState.rightDown = true
    end
end

function love.mousemoved(x, y, dx, dy)
    if pinchActive then return end
    local sw, sh, uiScale = getUIScaleAndDims()
    local ux, uy = x / uiScale, y / uiScale
    local udx, udy = dx / uiScale, dy / uiScale

    if mouseState.leftDown and not mouseState.dragged then
        local dist = math.sqrt((ux - mouseState.pressX)^2 + (uy - mouseState.pressY)^2)
        if dist > DRAG_THRESHOLD then
            mouseState.dragged = true
        end
    end

    if currentScreen == "shop" and shopDragging and mouseState.dragged then
        local maxScroll = getShopMaxScrollX(sw)
        shopTargetScrollX = math.max(0, math.min(maxScroll, shopTargetScrollX - udx * 1.25))
        return
    end

    if currentScreen == "profile_modal" and mouseState.leftDown and mouseState.inProfileMatches and mouseState.dragged then
        mouseState.scrollAccumY = mouseState.scrollAccumY - udy
        if math.abs(mouseState.scrollAccumY) >= 24 then
            local step = math.floor(mouseState.scrollAccumY / 24)
            mouseState.scrollAccumY = mouseState.scrollAccumY - step * 24
            local maxScroll = math.max(0, #Config.profile.recentMatches - 4)
            profileMatchScroll = math.max(0, math.min(maxScroll, profileMatchScroll + step))
        end
        return
    end

    if currentScreen == "bot_modal" and mouseState.leftDown then
        local pw, ph = 520, 390
        local px, py = (sw - pw) * 0.5, (sh - ph) * 0.5
        local trackX = px + 76
        local trackW = pw - 152
        local trackY = py + 112
        if math.abs(uy - trackY) < 36 and ux >= trackX - 30 and ux <= trackX + trackW + 30 then
            local ratio = math.max(0, math.min(1, (ux - trackX) / trackW))
            Config.botDifficulty = math.floor(ratio * 2 + 0.5) + 1
        end
        return
    end

    if currentScreen == "game" then
        if mouseState.leftDown and mouseState.inMoveLog and mouseState.dragged then
            mouseState.scrollAccumY = mouseState.scrollAccumY - udy
            if math.abs(mouseState.scrollAccumY) >= 18 then
                local step = math.floor(mouseState.scrollAccumY / 18)
                mouseState.scrollAccumY = mouseState.scrollAccumY - step * 18
                local totalPairs = math.ceil(#gameLogic.moveHistory / 2)
                local maxScroll = math.max(0, totalPairs - 9)
                moveLogScroll = math.max(0, math.min(maxScroll, moveLogScroll + step))
            end
            return
        end
        if mouseState.rightDown or (mouseState.leftDown and mouseState.dragged) then
            local sens = Config.cameraSensitivity
            renderer:rotateCamera(-dx * 0.34 * sens, -dy * 0.26 * sens)
        end
    end
end

function love.mousereleased(x, y, button)
    local _, _, uiScale, realW, realH = getUIScaleAndDims()
    local ux, uy = x / uiScale, y / uiScale
    if button == 1 then
        local wasDragged = mouseState.dragged
        local wasPinched = pinchActive
        mouseState.leftDown = false
        mouseState.dragged = false
        mouseState.inMoveLog = false
        mouseState.inProfileMatches = false
        shopDragging = false

        if not wasDragged and not wasPinched then
            for _, btn in ipairs(uiButtons) do
                if ux >= btn.x and ux <= btn.x + btn.w and uy >= btn.y and uy <= btn.y + btn.h then
                    if btn.onClick then btn.onClick() end
                    return
                end
            end

            if currentScreen == "game" and not isReplayMode and not gameLogic.isGameOver and not activeDrop and isLocalPlayerTurn() then
                local gx, gz, gy = renderer:pickPegAtScreenPos(x, y, realW, realH, gameLogic)
                if gx and gz then
                    if isTouchDevice then
                        if hoveredX == gx and hoveredZ == gz and hoveredY == gy then
                            triggerMove(gx, gz, false, gy)
                        else
                            Sound.play("hover")
                            hoveredX, hoveredZ, hoveredY = gx, gz, gy
                        end
                    else
                        triggerMove(gx, gz, false, gy)
                    end
                elseif isTouchDevice then
                    hoveredX, hoveredZ, hoveredY = nil, nil, nil
                end
            end
        end
    elseif button == 2 or button == 3 then
        mouseState.rightDown = false
    end
end

-- Multi-touch Pinch-to-Zoom & Touch Mode detection for Android, iOS, and Touch Displays
local function countActiveTouches()
    local c = 0
    local pts = {}
    for _, pt in pairs(activeTouches) do
        c = c + 1
        table.insert(pts, pt)
    end
    return c, pts
end

function love.touchpressed(id, x, y)
    isTouchDevice = true
    activeTouches[id] = { x = x, y = y }
    local c, pts = countActiveTouches()
    if c >= 2 then
        pinchActive = true
        lastPinchDist = math.sqrt((pts[1].x - pts[2].x)^2 + (pts[1].y - pts[2].y)^2)
    end
end

function love.touchmoved(id, x, y)
    isTouchDevice = true
    activeTouches[id] = { x = x, y = y }
    local c, pts = countActiveTouches()
    if c >= 2 and currentScreen == "game" then
        pinchActive = true
        local dist = math.sqrt((pts[1].x - pts[2].x)^2 + (pts[1].y - pts[2].y)^2)
        if lastPinchDist then
            local delta = dist - lastPinchDist
            renderer:zoomCamera(-delta * 0.025)
        end
        lastPinchDist = dist
    end
end

function love.touchreleased(id, x, y)
    activeTouches[id] = nil
    local c = countActiveTouches()
    if c < 2 then
        lastPinchDist = nil
        if c == 0 then
            pinchActive = false
        end
    end
end

function love.wheelmoved(wx, wy)
    if currentScreen == "game" and wy ~= 0 then
        local sw, _ = getUIScaleAndDims()
        local mx, my = getUIMousePos()
        local logW, logH = 225, 250
        local lx, ly = sw - logW - 18, 14
        -- If cursor is over the Move Log box, scroll the Move Log up/down!
        if mx >= lx and mx <= lx + logW and my >= ly and my <= ly + logH then
            local totalPairs = math.ceil(#gameLogic.moveHistory / 2)
            local maxScroll = math.max(0, totalPairs - 9)
            moveLogScroll = math.max(0, math.min(maxScroll, moveLogScroll - (wy > 0 and 1 or -1)))
        else
            renderer:zoomCamera(-wy * 0.65)
        end
    elseif currentScreen == "profile_modal" and wy ~= 0 then
        local maxScroll = math.max(0, #Config.profile.recentMatches - 4)
        profileMatchScroll = math.max(0, math.min(maxScroll, profileMatchScroll - (wy > 0 and 1 or -1)))
    elseif currentScreen == "friend_game_modal" and friendGameUI.view == "list" and wy ~= 0 then
        local maxScroll = math.max(0, #(Config.profile.friends or {}) - 6)
        friendGameUI.listScroll = math.max(0, math.min(maxScroll, (friendGameUI.listScroll or 0) - (wy > 0 and 1 or -1)))
    elseif currentScreen == "rules_modal" and wy ~= 0 then
        rulesScrollOffset = math.max(0, rulesScrollOffset - wy * 34)
    elseif currentScreen == "shop" and wy ~= 0 then
        local sw = getUIScaleAndDims()
        local maxScroll = getShopMaxScrollX(sw)
        shopTargetScrollX = math.max(0, math.min(maxScroll, shopTargetScrollX - wy * 90))
    end
end

function love.textinput(text)
    if currentScreen == "tournament_modal" and tournamentUI.view == "join" then
        if #tournamentUI.joinCode < 6 and text:match("^[a-zA-Z0-9]+$") then
            tournamentUI.joinCode = tournamentUI.joinCode .. text:upper()
            tournamentUI.errorMsg = nil
        end
        return
    end
    if currentScreen == "profile_modal" then
        if Config.profile.isRegistered and #friendSearchText < 12 and text:match("^[a-zA-Z0-9_]+$") then
            friendSearchText = friendSearchText .. text
        end
        return
    end
    if currentScreen == "friend_game_modal" then
        if friendGameUI.view == "join" then
            if #friendGameUI.joinCode < 6 and text:match("^[a-zA-Z0-9]+$") then
                friendGameUI.joinCode = friendGameUI.joinCode .. text:upper()
                friendGameUI.errorMsg = nil
            end
        elseif friendGameUI.view == "list" and Config.profile.isRegistered then
            if #friendSearchText < 12 and text:match("^[a-zA-Z0-9_]+$") then
                friendSearchText = friendSearchText .. text
                friendStatusFeedback = nil
            end
        end
        return
    end
    if currentScreen == "lan_modal" and lanIpFocused then
        if #LAN.joinIP < 24 and text:match("^[0-9%.a-zA-Z%-]+$") then
            LAN.joinIP = LAN.joinIP .. text
        end
        return
    end
    if currentScreen ~= "auth_modal" then return end
    local f = authState.activeField
    if not f then return end

    local cur = authState[f] or ""
    local maxLen = (f == "username" and 12) or (f == "email" and 42) or ((f == "password" or f == "confirmPassword") and 28) or 50
    if utf8.len(cur) and utf8.len(cur) < maxLen then
        authState[f] = cur .. text
        authState.errorKey = nil
    end
end

function love.filedropped(file)
    if currentScreen == "auth_modal" or currentScreen == "profile_modal" then
        local fname = file:getFilename() or ""
        local lower = fname:lower()
        if lower:match("%.png$") or lower:match("%.jpg$") or lower:match("%.jpeg$") then
            file:open("r")
            local data = file:read()
            file:close()
            if data then
                local ext = lower:match("%.png$") and ".png" or ".jpg"
                local savedName = "custom_avatar" .. ext
                local ok = pcall(love.filesystem.write, savedName, data)
                if ok then
                    authState.customAvatarFile = savedName
                    Config.profile.customAvatarFile = savedName
                    reloadCustomAvatarImage()
                    Storage.save()
                    Sound.play("win")
                end
            end
        end
    end
end

function love.keypressed(key, scancode)
    if currentScreen == "tournament_modal" and tournamentUI.view == "join" and key == "backspace" then
        tournamentUI.joinCode = tournamentUI.joinCode:sub(1, math.max(0, #tournamentUI.joinCode - 1))
        return
    end
    if currentScreen == "profile_modal" and key == "backspace" then
        if Config.profile.isRegistered then
            friendSearchText = friendSearchText:sub(1, math.max(0, #friendSearchText - 1))
        end
        return
    end
    if currentScreen == "friend_game_modal" and key == "backspace" then
        if friendGameUI.view == "join" then
            friendGameUI.joinCode = friendGameUI.joinCode:sub(1, math.max(0, #friendGameUI.joinCode - 1))
        elseif friendGameUI.view == "list" and Config.profile.isRegistered then
            friendSearchText = friendSearchText:sub(1, math.max(0, #friendSearchText - 1))
        end
        return
    end
    if currentScreen == "lan_modal" and lanIpFocused then
        if key == "backspace" then
            LAN.joinIP = LAN.joinIP:sub(1, math.max(0, #LAN.joinIP - 1))
            return
        elseif key == "return" or key == "kpenter" then
            lanIpFocused = false
            return
        end
    end

    if currentScreen == "auth_modal" then
        if key == "backspace" then
            local f = authState.activeField
            local cur = authState[f] or ""
            local byteoffset = utf8.offset(cur, -1)
            if byteoffset then
                authState[f] = string.sub(cur, 1, byteoffset - 1)
                authState.errorKey = nil
            end
            return
        elseif key == "tab" then
            local order
            if authState.mode == "login" then
                order = { "username", "password" }
            elseif authState.mode == "register" then
                order = { "username", "password", "confirmPassword" }
            else
                order = { "username", "password", "bio" }
            end
            for i, name in ipairs(order) do
                if name == authState.activeField then
                    authState.activeField = order[(i % #order) + 1]
                    break
                end
            end
            return
        elseif key == "escape" or scancode == "escape" or key == "acback" then
            Sound.play("click")
            pcall(love.keyboard.setTextInput, false)
            currentScreen = "profile_modal"
            return
        end
    end

    -- In-game Arrow Keys to rewind / step through move history:
    -- Left  = 1 move back
    -- Right = 1 move forward
    -- Up    = jump to latest move (very end)
    -- Down  = jump to 1st move (very beginning)
    if currentScreen == "game" and not activeDrop then
        local total = #gameLogic.moveHistory
        if key == "left" or scancode == "left" then
            if total > 0 then
                Sound.play("hover")
                viewPly = math.max(1, viewPly - 1)
                syncMoveLogScrollToPly()
            end
            return
        elseif key == "right" or scancode == "right" then
            if total > 0 then
                Sound.play("hover")
                viewPly = math.min(total, viewPly + 1)
                syncMoveLogScrollToPly()
            end
            return
        elseif key == "up" or scancode == "up" then
            if total > 0 then
                Sound.play("hover")
                viewPly = total
                syncMoveLogScrollToPly()
            end
            return
        elseif key == "down" or scancode == "down" then
            if total > 0 then
                Sound.play("hover")
                viewPly = 1
                syncMoveLogScrollToPly()
            end
            return
        end
    elseif currentScreen == "profile_modal" then
        local maxScroll = math.max(0, #Config.profile.recentMatches - 4)
        if key == "down" or scancode == "down" then
            profileMatchScroll = math.min(maxScroll, profileMatchScroll + 1)
            return
        elseif key == "up" or scancode == "up" then
            profileMatchScroll = math.max(0, profileMatchScroll - 1)
            return
        end
    end

    -- Post-game F (English) / А (Russian) hotkey to hide/show result window and inspect final board position
    if currentScreen == "game" and gameLogic.isGameOver and (key == "f" or scancode == "f") then
        Sound.play("click")
        hideWinModal = not hideWinModal
        return
    end

    if key == "escape" or scancode == "escape" or key == "acback" then
        Sound.play("click")
        pcall(love.keyboard.setTextInput, false)
        if currentScreen == "rules_modal" then
            currentScreen = "settings_modal"
        elseif currentScreen == "lan_modal" then
            LAN.stop()
            lanIpFocused = false
            currentScreen = "online_modal"
        elseif currentScreen == "friend_profile_modal" then
            selectedAchievementId = nil
            currentScreen = friendProfileReturnScreen or "profile_modal"
        elseif currentScreen == "friend_game_modal" then
            if friendGameUI.room then
                Firebase.closeFriendRoom(friendGameUI.room.code)
                friendGameUI.room = nil
            end
            currentScreen = "online_modal"
        elseif currentScreen ~= "menu" then
            LAN.stop()
            currentScreen = "menu"
        else
            love.event.quit()
        end
    elseif (key == "r" or scancode == "r") and currentScreen == "game" then
        Sound.play("click")
        startNewGame(Config.currentMode, Config.botDifficulty)
    end
end
