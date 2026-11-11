local Config     = require("src.config")
local I18N       = require("src.i18n")
local BoardLogic = require("src.board_logic")
local Renderer3D = require("src.renderer3d")
local BotAI      = require("src.bot_ai")
local Sound      = require("src.sound")
local Storage    = require("src.storage")
local LAN        = require("src.lan")
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
local hoveredX, hoveredZ = nil, nil
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
    end
    return true
end

local function startNewGame(mode, difficulty, lanRole)
    Config.currentMode = mode or Config.GameMode.LOCAL_PVP
    if difficulty then
        Config.botDifficulty = difficulty
    end

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
    else
        Config.humanPlayer = BoardLogic.Player.WHITE
    end

    gameLogic:reset()
    hoveredX, hoveredZ = nil, nil
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
    Sound.play("win")
    local elapsedSec = math.max(1, math.floor(love.timer.getTime() - matchStartTime))
    lastRatingDelta = Config.recordMatchResult(
        Config.currentMode,
        gameLogic.winner,
        gameLogic.isDraw,
        gameLogic.winningLineType,
        #gameLogic.moveHistory,
        elapsedSec
    )
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

local function triggerMove(gx, gz, fromNetwork)
    -- If user was inspecting an earlier move, snap back to live before dropping a new piece
    viewPly = #gameLogic.moveHistory
    if not gameLogic:canDrop(gx, gz) then return end
    local res = gameLogic:dropPiece(gx, gz)
    if not res.ok then return end

    viewPly = #gameLogic.moveHistory
    syncMoveLogScrollToPly()

    if Config.currentMode == Config.GameMode.LAN and not fromNetwork then
        LAN.sendMove(gx, gz)
    end

    hoveredX, hoveredZ = nil, nil
    turnBannerPulse = 1.0
    local _, targetY, _ = renderer:gridToWorldXYZ(res.pos.x, res.pos.y, res.pos.z)

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
        triggerMove(pick.x, pick.z)
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
end

function love.update(dt)
    local sw, sh = love.graphics.getDimensions()
    shopSpinAngle = shopSpinAngle + dt * 1.35
    shopScrollX = shopScrollX + (shopTargetScrollX - shopScrollX) * math.min(1.0, dt * 12.0)

    LAN.update()

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
        if not gameLogic.isGameOver and not activeDrop and isLocalPlayerTurn() and not mouseState.dragged then
            local nx, nz = renderer:pickPegAtScreenPos(mx, my, sw, sh, gameLogic)
            if (nx ~= hoveredX or nz ~= hoveredZ) and nx ~= nil then
                Sound.play("hover")
            end
            hoveredX, hoveredZ = nx, nz
        else
            hoveredX, hoveredZ = nil, nil
        end
    end
end

local function drawButton(id, x, y, w, h, label, opts)
    opts = opts or {}
    local ui = Config.getUITheme()
    local mx, my = getUIMousePos()
    local hovered = mx >= x and mx <= x + w and my >= y and my <= y + h

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
    local pw, ph = 520, 390
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

    -- Bottom-left Back & Bottom-right Play
    drawButton("bot_back", px + 34, py + ph - 66, 155, 44, I18N.t("back_btn"), {
        onClick = function()
            Sound.play("click")
            currentScreen = "menu"
        end
    })
    drawButton("bot_play", px + pw - 189, py + ph - 66, 155, 44, I18N.t("play_btn"), {
        primary = true,
        onClick = function()
            Sound.play("click")
            startNewGame(Config.GameMode.VS_BOT, Config.botDifficulty)
        end
    })
end

local function drawOnlineModal(sw, sh)
    local ui = Config.getUITheme()
    local pw, ph = 550, 456
    local px, py = (sw - pw) * 0.5, (sh - ph) * 0.5
    drawPanel(px, py, pw, ph)

    love.graphics.setFont(fonts.h2)
    love.graphics.setColor(ui.textMain)
    love.graphics.printf(I18N.t("online_title"), px, py + 18, pw, "center")

    -- Subtle mini online players counter in the top-right corner of the modal (Icon + Number)
    local badgeW, badgeH = 78, 28
    local badgeX, badgeY = px + pw - badgeW - 18, py + 16
    love.graphics.setColor(ui.bgClear)
    love.graphics.rectangle("fill", badgeX, badgeY, badgeW, badgeH, 14, 14)
    love.graphics.setColor(ui.panelBorder)
    love.graphics.setLineWidth(1.2)
    love.graphics.rectangle("line", badgeX, badgeY, badgeW, badgeH, 14, 14)

    -- Pulsing green online dot
    local pulse = 0.75 + 0.25 * math.sin(love.timer.getTime() * 3.2)
    love.graphics.setColor(0.24, 0.86, 0.48, pulse)
    love.graphics.circle("fill", badgeX + 13, badgeY + 14, 3.8)

    -- Mini vector person icon (head + shoulders)
    love.graphics.setColor(ui.textSub)
    love.graphics.circle("fill", badgeX + 27, badgeY + 10.5, 3.2)
    love.graphics.arc("fill", badgeX + 27, badgeY + 20.5, 5.8, math.pi * 1.12, math.pi * 1.88)

    -- Active online count number
    local onlineCount = Config.onlinePlayersCount + math.floor(math.sin(love.timer.getTime() * 0.18) * 2.5)
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(ui.textMain)
    love.graphics.printf(tostring(math.max(1, onlineCount)), badgeX + 35, badgeY + 7, badgeW - 40, "center")

    love.graphics.setFont(fonts.body)
    love.graphics.setColor(ui.textSub)
    love.graphics.printf(I18N.t("online_desc"), px + 32, py + 54, pw - 64, "center")

    local bx, bw = px + 46, pw - 92
    local halfW = (bw - 12) * 0.5

    -- Time Control selection: 5 minutes (5:00) vs 1 minute (1:00)
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(ui.textSub)
    love.graphics.printf(I18N.t("time_control_label"), bx, py + 104, bw, "center")

    drawButton("online_time_5m", bx, py + 124, halfW, 40, I18N.t("time_5m"), {
        active = (Config.onlineTimeMinutes == 5),
        font = fonts.small,
        onClick = function()
            Sound.play("click")
            Config.onlineTimeMinutes = 5
            Storage.save()
        end
    })
    drawButton("online_time_1m", bx + halfW + 12, py + 124, halfW, 40, I18N.t("time_1m"), {
        active = (Config.onlineTimeMinutes == 1),
        font = fonts.small,
        onClick = function()
            Sound.play("click")
            Config.onlineTimeMinutes = 1
            Storage.save()
        end
    })

    drawButton("online_reg", bx, py + 178, halfW, 44, I18N.t("register_btn"), {
        accent = true,
        onClick = function()
            Sound.play("click")
            openAuthModal("register")
        end
    })
    drawButton("online_signin", bx + halfW + 12, py + 178, halfW, 44, I18N.t("signin_btn"), {
        onClick = function()
            Sound.play("click")
            openAuthModal("login")
        end
    })

    drawButton("online_guest", bx, py + 234, bw, 46, I18N.t("play_guest_btn"), {
        primary = true,
        onClick = function()
            Sound.play("click")
            startNewGame(Config.GameMode.ONLINE)
        end
    })

    drawButton("online_lan", bx, py + 292, bw, 46, I18N.t("lan_btn"), {
        active = true,
        onClick = function()
            Sound.play("click")
            LAN.stop()
            lanIpFocused = false
            currentScreen = "lan_modal"
        end
    })

    love.graphics.setFont(fonts.small)
    love.graphics.setColor(ui.textSub)
    love.graphics.printf(I18N.t("online_stub_note"), px + 28, py + 350, pw - 56, "center")

    drawButton("online_back", px + pw * 0.5 - 80, py + ph - 52, 160, 40, I18N.t("back_btn"), {
        onClick = function()
            Sound.play("click")
            currentScreen = "menu"
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
    local pw, ph = 820, 560
    local px, py = (sw - pw) * 0.5, (sh - ph) * 0.5
    drawPanel(px, py, pw, ph)

    local p = Config.profile

    love.graphics.setFont(fonts.h2)
    love.graphics.setColor(ui.textMain)
    love.graphics.printf(I18N.t("profile_title"), px, py + 18, pw, "center")

    -- Avatar
    local ax, ay = px + 64, py + 94
    drawUserAvatar(ax, ay, 34)

    love.graphics.setFont(fonts.h2)
    love.graphics.setColor(ui.textMain)
    love.graphics.print(p.username, px + 114, py + 58)

    if p.isRegistered and p.email and #p.email > 0 then
        love.graphics.setFont(fonts.small)
        love.graphics.setColor(ui.accentText)
        love.graphics.print(I18N.t("profile_email") .. " " .. p.email, px + 114, py + 86)
    end

    love.graphics.setFont(fonts.small)
    love.graphics.setColor(ui.textSub)
    local bioText = (#p.bio > 0) and p.bio or I18N.t("profile_bio_empty")
    love.graphics.print(I18N.t("profile_bio") .. " " .. bioText, px + 114, py + 108)

    -- ELO Rating box (Always 800 until registered!)
    local rBoxX, rBoxY, rBoxW, rBoxH = px + pw - 220, py + 56, 186, 70
    love.graphics.setColor(ui.btnDefault)
    love.graphics.rectangle("fill", rBoxX, rBoxY, rBoxW, rBoxH, 10, 10)
    love.graphics.setColor(ui.panelBorder)
    love.graphics.rectangle("line", rBoxX, rBoxY, rBoxW, rBoxH, 10, 10)

    love.graphics.setFont(fonts.small)
    love.graphics.setColor(ui.textSub)
    love.graphics.printf(I18N.t("profile_rating"), rBoxX, rBoxY + 8, rBoxW, "center")

    drawStarIcon(rBoxX + 48, rBoxY + 45, 8, { 0.95, 0.78, 0.28, 1.0 })
    love.graphics.setFont(fonts.h2)
    love.graphics.setColor(ui.textMain)
    love.graphics.print("ELO " .. tostring(p.rating), rBoxX + 62, rBoxY + 32)

    love.graphics.setFont(fonts.btn)
    love.graphics.setColor(ui.textMain)
    love.graphics.print(I18N.t("profile_games", p.gamesPlayed, p.wins, p.losses, p.draws), px + 34, py + 146)

    -- Left Column: Rating History Graph
    local gx, gy, gw, gh = px + 34, py + 178, 340, 184
    love.graphics.setColor(ui.bgClear)
    love.graphics.rectangle("fill", gx, gy, gw, gh, 8, 8)
    love.graphics.setColor(ui.panelBorder)
    love.graphics.rectangle("line", gx, gy, gw, gh, 8, 8)

    love.graphics.setFont(fonts.small)
    love.graphics.setColor(ui.textSub)
    love.graphics.print(I18N.t("profile_graph"), gx + 12, gy + 8)

    local hist = p.ratingHistory
    local minR, maxR = 760, 840
    for _, r in ipairs(hist) do
        if r - 20 < minR then minR = r - 20 end
        if r + 20 > maxR then maxR = r + 20 end
    end
    local plotX, plotY, plotW, plotH = gx + 42, gy + 34, gw - 58, gh - 48
    love.graphics.setColor(ui.panelBorder)
    love.graphics.line(plotX, plotY + plotH * 0.5, plotX + plotW, plotY + plotH * 0.5)
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

    -- Right Column: Scrollable Previous Matches (clipped inside frame, with Date/Time & PvP Duration!)
    local rx, ry, rw, rh = px + 388, py + 178, 398, 184
    love.graphics.setColor(ui.bgClear)
    love.graphics.rectangle("fill", rx, ry, rw, rh, 8, 8)
    love.graphics.setColor(ui.panelBorder)
    love.graphics.rectangle("line", rx, ry, rw, rh, 8, 8)

    love.graphics.setFont(fonts.small)
    love.graphics.setColor(ui.textSub)
    love.graphics.print(I18N.t("profile_recent") .. string.format(" (%d)", #p.recentMatches), rx + 12, ry + 8)

    if #p.recentMatches == 0 then
        love.graphics.setColor(ui.textSub)
        love.graphics.printf(I18N.t("profile_no_games"), rx + 12, ry + 80, rw - 24, "center")
    else
        local listX, listY, listW, listH = rx + 6, ry + 30, rw - 16, rh - 34
        local itemH = 36
        local visibleItems = math.floor(listH / itemH)
        local maxScroll = math.max(0, #p.recentMatches - visibleItems)
        profileMatchScroll = math.max(0, math.min(maxScroll, profileMatchScroll))

        setUIScissor(listX, listY, listW, listH)
        local myY = listY + 2
        for idx = profileMatchScroll + 1, math.min(#p.recentMatches, profileMatchScroll + visibleItems + 1) do
            local m = p.recentMatches[idx]
            local formatted = Config.formatMatchRecord(m)
            local metaStr   = Config.formatMatchMeta(m)

            love.graphics.setFont(fonts.small)
            love.graphics.setColor(ui.textMain)
            love.graphics.print(formatted, listX + 6, myY)

            if #metaStr > 0 then
                love.graphics.setColor(ui.textSub)
                love.graphics.print(metaStr, listX + 6, myY + 16)
                myY = myY + itemH
            else
                myY = myY + 24
            end
        end
        setUIScissor()

        -- Visual scrollbar on the right of the Previous Matches box
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

    -- Achievements
    love.graphics.setFont(fonts.btn)
    love.graphics.setColor(ui.textMain)
    love.graphics.print(I18N.t("profile_achievements"), px + 34, py + 374)

    local achList = {
        { key = "ach_first_win", done = p.achievements.first_win },
        { key = "ach_3d_diag",   done = p.achievements.diag_3d   },
        { key = "ach_veteran",   done = p.achievements.veteran   }
    }
    local achW = (pw - 68 - 28) / 3
    for i, a in ipairs(achList) do
        local abx = px + 34 + (i - 1) * (achW + 14)
        local aby = py + 402
        love.graphics.setColor(a.done and ui.btnActive or ui.btnDefault)
        love.graphics.rectangle("fill", abx, aby, achW, 46, 8, 8)
        love.graphics.setColor(ui.panelBorder)
        love.graphics.rectangle("line", abx, aby, achW, 46, 8, 8)

        love.graphics.setFont(fonts.small)
        love.graphics.setColor(ui.textMain)
        love.graphics.printf(I18N.t(a.key), abx + 8, aby + 15, achW - 16, "center")
    end

    -- Bottom Buttons: Register / Sign In / Edit Profile / Log Out + Close
    local btnY = py + ph - 58
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
        -- Register mode: Username, Email, Password (with Eye), Confirm Password (with Eye). NO Bio field here!
        drawInputBox("username", "field_username", py + 60, authState.username, false)
        drawInputBox("email",    "field_email",    py + 132, authState.email,    false)
        drawInputBox("password", "field_password", py + 204, authState.password, not authState.showPassword, {
            isOpen = authState.showPassword,
            onToggle = function() authState.showPassword = not authState.showPassword end
        })
        drawInputBox("confirmPassword", "field_password_confirm", py + 276, authState.confirmPassword, not authState.showConfirmPassword, {
            isOpen = authState.showConfirmPassword,
            onToggle = function() authState.showConfirmPassword = not authState.showConfirmPassword end
        })
    elseif isEdit then
        -- Edit Profile mode: Avatar Photo Upload/Selector + Username + Email + Password (with Eye) + Profile Bio!
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
        drawInputBox("email",    "field_email",    py + 184, authState.email,    false)
        drawInputBox("password", "field_password", py + 254, authState.password, not authState.showPassword, {
            isOpen = authState.showPassword,
            onToggle = function() authState.showPassword = not authState.showPassword end
        })
        drawInputBox("bio",      "field_bio",      py + 324, authState.bio,      false)
    end

    -- Error message banner if validation failed
    if authState.errorKey then
        love.graphics.setFont(fonts.small)
        love.graphics.setColor(0.95, 0.38, 0.38, 1.0)
        love.graphics.printf(I18N.t(authState.errorKey), bx, py + ph - 104, bw, "center")
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
            local ok, errKey
            if isRegister then
                ok, errKey = Config.registerAccount(
                    authState.username,
                    authState.email,
                    authState.password,
                    authState.confirmPassword
                )
            elseif isLogin then
                ok, errKey = Config.loginAccount(
                    authState.username,
                    authState.password
                )
            else
                ok, errKey = Config.updateRegisteredProfile(
                    authState.username,
                    authState.email,
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
    local pw, ph = 640, 470
    local px, py = (sw - pw) * 0.5, (sh - ph) * 0.5
    drawPanel(px, py, pw, ph)

    love.graphics.setFont(fonts.h2)
    love.graphics.setColor(ui.textMain)
    love.graphics.printf(I18N.t("rules_title"), px, py + 22, pw, "center")

    love.graphics.setFont(fonts.body)
    love.graphics.setColor(ui.textSub)
    love.graphics.printf(I18N.t("rules_body"), px + 34, py + 68, pw - 68, "left")

    drawButton("rules_back", px + pw * 0.5 - 85, py + ph - 58, 170, 42, I18N.t("back_btn"), {
        primary = true,
        onClick = function()
            Sound.play("click")
            currentScreen = "settings_modal"
        end
    })
end

local function drawShopScreen(sw, sh)
    local ui = Config.getUITheme()
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

    local cardW, cardH = 260, 430
    local cardGap = 26
    local rowY = (sh - cardH) * 0.5 + 20

    if shopTab == "pieces" then
        love.graphics.setFont(fonts.small)
        love.graphics.setColor(ui.textSub)
        love.graphics.printf(I18N.t("swipe_hint"), 0, 94, sw, "center")

        for i, skinId in ipairs(Config.pieceSkinOrder) do
            local skin = Config.pieceSkins[skinId]
            local cx = 64 + (i - 1) * (cardW + cardGap) - shopScrollX
            if cx + cardW >= -20 and cx <= sw + 20 then
                drawPanel(cx, rowY, cardW, cardH)

                love.graphics.setFont(fonts.btn)
                love.graphics.setColor(ui.textMain)
                love.graphics.printf(I18N.t(skin.nameKey), cx + 12, rowY + 18, cardW - 24, "center")

                local prevX, prevY, prevW, prevH = cx + 18, rowY + 62, cardW - 36, 250
                love.graphics.setColor(ui.bgClear)
                love.graphics.rectangle("fill", prevX, prevY, prevW, prevH, 10, 10)
                renderer:renderShopPreview(prevX, prevY, prevW, prevH, sw, sh, "pieces", skin, shopSpinAngle + i * 0.5)

                local isSelected = (Config.activePieceSkin == skinId)
                local btnY = rowY + cardH - 68
                if skin.unlocked then
                    drawButton("pskin_" .. skinId, cx + 24, btnY, cardW - 48, 46,
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
                    drawButton("pskin_buy_" .. skinId, cx + 24, btnY, cardW - 48, 46,
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

    elseif shopTab == "board" then
        love.graphics.setFont(fonts.small)
        love.graphics.setColor(ui.textSub)
        love.graphics.printf(I18N.t("swipe_hint"), 0, 94, sw, "center")

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
            local cx = 64 + idx * (cardW + cardGap) - shopScrollX
            if cx + cardW >= -20 and cx <= sw + 20 then
                drawPanel(cx, rowY, cardW, cardH)

                love.graphics.setFont(fonts.btn)
                love.graphics.setColor(ui.textMain)
                love.graphics.printf(I18N.t(bSkin.nameKey), cx + 12, rowY + 18, cardW - 24, "center")

                local prevX, prevY, prevW, prevH = cx + 18, rowY + 62, cardW - 36, 250
                love.graphics.setColor(ui.bgClear)
                love.graphics.rectangle("fill", prevX, prevY, prevW, prevH, 10, 10)
                renderer:renderShopPreview(prevX, prevY, prevW, prevH, sw, sh, "board_skin", {
                    isRound = (Config.boardShape == "round"),
                    style = bSkin.style,
                    baseColor = bSkin.baseColor,
                    pegColor = bSkin.pegColor,
                    woodStrength = bSkin.woodStrength
                }, shopSpinAngle + idx * 0.4)

                local isSelected = (Config.activeBoardSkin == bSkinId)
                local btnY = rowY + cardH - 68
                if bSkin.unlocked then
                    drawButton("bskin_" .. bSkinId, cx + 24, btnY, cardW - 48, 46,
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
                    drawButton("bskin_buy_" .. bSkinId, cx + 24, btnY, cardW - 48, 46,
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
                    drawButton("bskin_ach_" .. bSkinId, cx + 24, btnY, cardW - 48, 46, I18N.t("btn_ach_stub"), {
                        font = fonts.small,
                        onClick = function() Sound.play("click") end
                    })
                end
            end
        end

    elseif shopTab == "themes" then
        love.graphics.setFont(fonts.small)
        love.graphics.setColor(ui.textSub)
        love.graphics.printf(I18N.t("swipe_hint"), 0, 94, sw, "center")

        for i, themeId in ipairs(Config.uiThemeOrder) do
            local th = Config.uiThemes[themeId]
            local cx = 64 + (i - 1) * (cardW + cardGap) - shopScrollX
            if cx + cardW >= -20 and cx <= sw + 20 then
                drawPanel(cx, rowY, cardW, cardH)

                love.graphics.setFont(fonts.btn)
                love.graphics.setColor(ui.textMain)
                love.graphics.printf(I18N.t(th.nameKey), cx + 12, rowY + 18, cardW - 24, "center")

                local prevX, prevY, prevW, prevH = cx + 22, rowY + 66, cardW - 44, 240
                love.graphics.setColor(th.bgClear)
                love.graphics.rectangle("fill", prevX, prevY, prevW, prevH, 10, 10)
                love.graphics.setColor(th.panelBg)
                love.graphics.rectangle("fill", prevX + 18, prevY + 22, prevW - 36, prevH - 44, 10, 10)
                love.graphics.setColor(th.panelBorder)
                love.graphics.rectangle("line", prevX + 18, prevY + 22, prevW - 36, prevH - 44, 10, 10)

                love.graphics.setColor(th.btnPrimary)
                love.graphics.rectangle("fill", prevX + 34, prevY + 52, prevW - 68, 42, 8, 8)
                love.graphics.setColor(th.btnDefault)
                love.graphics.rectangle("fill", prevX + 34, prevY + 106, prevW - 68, 38, 8, 8)
                love.graphics.setColor(th.btnAccent)
                love.graphics.rectangle("fill", prevX + 34, prevY + 154, prevW - 68, 38, 8, 8)

                local isSelected = (Config.activeUITheme == themeId)
                local btnY = rowY + cardH - 68
                if th.unlocked then
                    drawButton("uitheme_" .. themeId, cx + 24, btnY, cardW - 48, 46,
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
                    drawButton("uitheme_buy_" .. themeId, cx + 24, btnY, cardW - 48, 46,
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
                    drawButton("uitheme_ach_" .. themeId, cx + 24, btnY, cardW - 48, 46, I18N.t("btn_ach_stub"), {
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

    -- Rewind banner if user stepped back in history using arrow keys
    if totalHalfMoves > 0 and viewPly < totalHalfMoves then
        local rbW, rbH = 420, 34
        local rbX, rbY = (sw - rbW) * 0.5, 80
        drawPanel(rbX, rbY, rbW, rbH)
        love.graphics.setFont(fonts.small)
        love.graphics.setColor(ui.accentText)
        love.graphics.printf(I18N.t("rewound_banner", viewPly, totalHalfMoves), rbX + 10, rbY + 9, rbW - 20, "center")
    end

    -- 3. CENTER SCREEN POPUP AFTER VICTORY / DRAW (Toggle with F / А to inspect board!)
    if gameLogic.isGameOver and not activeDrop then
        if not hideWinModal then
            love.graphics.setColor(0.05, 0.05, 0.06, 0.62)
            love.graphics.rectangle("fill", 0, 0, sw, sh)

            local pw, ph = 520, 276
            local px, py = (sw - pw) * 0.5, (sh - ph) * 0.5
            drawPanel(px, py, pw, ph)

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

            love.graphics.printf(titleText, px + 20, py + 24, pw - 40, "center")

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
    love.graphics.clear(ui.bgClear[1], ui.bgClear[2], ui.bgClear[3], 1.0, true, true)
    uiButtons = {}

    if currentScreen == "game" then
        renderer:renderScene(realW, realH, {
            config        = Config,
            logic         = gameLogic,
            maxPly        = viewPly,
            hoveredX      = hoveredX,
            hoveredZ      = hoveredZ,
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
            end
        end
        love.graphics.pop()
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
        shopTargetScrollX = math.max(0, math.min(1850, shopTargetScrollX - udx * 1.25))
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

            if currentScreen == "game" and not gameLogic.isGameOver and not activeDrop and isLocalPlayerTurn() then
                local gx, gz = renderer:pickPegAtScreenPos(x, y, realW, realH, gameLogic)
                if gx and gz then
                    if isTouchDevice then
                        -- On mobile / touch screens: 1st tap highlights peg, 2nd tap on same peg drops piece!
                        if hoveredX == gx and hoveredZ == gz then
                            triggerMove(gx, gz)
                        else
                            Sound.play("hover")
                            hoveredX, hoveredZ = gx, gz
                        end
                    else
                        triggerMove(gx, gz)
                    end
                elseif isTouchDevice then
                    hoveredX, hoveredZ = nil, nil
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
    elseif currentScreen == "shop" and wy ~= 0 then
        shopTargetScrollX = math.max(0, math.min(1850, shopTargetScrollX - wy * 90))
    end
end

function love.textinput(text)
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
                order = { "username", "email", "password", "confirmPassword" }
            else
                order = { "username", "email", "password", "bio" }
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
