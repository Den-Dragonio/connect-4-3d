-- Firebase REST Client Module for Connect 4 — 3D
-- Connected to project: connect4-a2f21 (Realtime Database + Firebase Auth)

local FirebaseClient = {
    config = {
        apiKey            = "AIzaSyAp_s9pugfzgUUsJ_5gG89nHL4VnsMtrng",
        authDomain        = "connect4-a2f21.firebaseapp.com",
        databaseURL       = "https://connect4-a2f21-default-rtdb.europe-west1.firebasedatabase.app",
        projectId         = "connect4-a2f21",
        storageBucket     = "connect4-a2f21.firebasestorage.app",
        messagingSenderId = "205994611008",
        appId             = "1:205994611008:web:78cbdbe91aca20fb00aaa5",
        measurementId     = "G-5ZVNVJ1TDB"
    },
    idToken      = nil,
    localId      = nil,
    lastSyncInfo = "Connected (connect4-a2f21)",
    sessionId    = "s_" .. tostring(math.random(100000, 999999)) .. "_" .. tostring(os.time()),
    cachedOnlinePlayers = 1,
    cachedActiveGames   = 0,
    lastPresenceFetch   = -100
}

local function jsonEscape(str)
    if type(str) ~= "string" then return "" end
    return (str:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'))
end

local function encodeSimpleJson(val)
    local tv = type(val)
    if tv == "string" then
        return '"' .. jsonEscape(val) .. '"'
    elseif tv == "number" or tv == "boolean" then
        return tostring(val)
    elseif tv == "table" then
        local isArray = (#val > 0)
        if isArray then
            local items = {}
            for i = 1, #val do
                table.insert(items, encodeSimpleJson(val[i]))
            end
            return "[" .. table.concat(items, ",") .. "]"
        else
            local parts = {}
            for k, v in pairs(val) do
                if type(k) == "string" and type(v) ~= "function" then
                    table.insert(parts, '"' .. jsonEscape(k) .. '":' .. encodeSimpleJson(v))
                end
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    end
    return "null"
end

-- Execute a fast non-blocking or short-timeout HTTPS request via system curl (macOS / Windows 10-11 / Linux)
local function httpRequest(method, url, jsonBody, async)
    if love and love.system and love.system.getOS() == "Web" then
        return nil
    end
    local isWin = (package.config:sub(1, 1) == "\\")
    local bodyFile = nil
    if jsonBody and love and love.filesystem then
        pcall(love.filesystem.write, "fb_tmp_payload.json", jsonBody)
        local saveDir = love.filesystem.getSaveDirectory()
        if saveDir and saveDir ~= "" then
            bodyFile = saveDir .. "/fb_tmp_payload.json"
        end
    end

    local cmd
    if isWin then
        if bodyFile then
            cmd = string.format(
                'curl.exe -s -m 3 -X %s -H "Content-Type: application/json" --data-binary @"%s" "%s"',
                method, bodyFile, url
            )
        else
            cmd = string.format('curl.exe -s -m 3 -X %s "%s"', method, url)
        end
        if async then
            pcall(os.execute, 'start /B "" ' .. cmd .. ' >NUL 2>&1')
            return nil
        end
    else
        if bodyFile then
            cmd = string.format(
                "curl -s -m 3 -X %s -H 'Content-Type: application/json' --data-binary @'%s' '%s'",
                method, bodyFile, url
            )
        else
            cmd = string.format("curl -s -m 3 -X %s '%s'", method, url)
        end
        if async then
            pcall(os.execute, cmd .. " >/dev/null 2>&1 &")
            return nil
        end
    end

    local ok, handle = pcall(io.popen, cmd)
    if not ok or not handle then return nil end
    local resp = handle:read("*a")
    handle:close()
    return resp
end

function FirebaseClient.isConfigured()
    return FirebaseClient.config.apiKey ~= ""
       and FirebaseClient.config.databaseURL ~= ""
end

function FirebaseClient.getAuthUrl(action)
    return string.format(
        "https://identitytoolkit.googleapis.com/v1/accounts:%s?key=%s",
        action,
        FirebaseClient.config.apiKey
    )
end

function FirebaseClient.getDatabaseUrl(path)
    local base = FirebaseClient.config.databaseURL:gsub("/+$", "")
    local authQuery = FirebaseClient.idToken and ("?auth=" .. FirebaseClient.idToken) or ""
    return string.format("%s/%s.json%s", base, path, authQuery)
end

-- Register user in Firebase Authentication (Email/Password) and sync profile to RTDB
function FirebaseClient.registerUser(username, email, password, profileData)
    if not FirebaseClient.isConfigured() then return end
    local url = FirebaseClient.getAuthUrl("signUp")
    local body = encodeSimpleJson({
        email             = email,
        password          = password,
        returnSecureToken = true
    })
    local resp = httpRequest("POST", url, body, false)
    if resp then
        local token = resp:match('"idToken"%s*:%s*"([^"]+)"')
        local uid   = resp:match('"localId"%s*:%s*"([^"]+)"')
        if token then
            FirebaseClient.idToken = token
            FirebaseClient.localId = uid
        end
    end
    FirebaseClient.syncProfile(username, profileData)
end

-- Fetch user profile from Realtime Database (for cross-device login, uniqueness & friend profile viewing)
function FirebaseClient.fetchUserProfile(username)
    if not FirebaseClient.isConfigured() or not username or username == "" then return nil end
    local safeKey = username:gsub("[^A-Za-z0-9_]", "")
    if safeKey == "" then return nil end
    local url = FirebaseClient.getDatabaseUrl("users/" .. safeKey)
    local resp = httpRequest("GET", url, nil, false)
    if not resp or resp == "" or resp == "null" or resp:match('"error"') then
        return nil
    end
    local uname = resp:match('"username"%s*:%s*"([^"]*)"')
    if not uname then return nil end
    local email        = resp:match('"email"%s*:%s*"([^"]*)"') or ""
    local bio          = resp:match('"bio"%s*:%s*"([^"]*)"') or ""
    local rating       = tonumber(resp:match('"rating"%s*:%s*(%d+)')) or 800
    local gamesPlayed  = tonumber(resp:match('"gamesPlayed"%s*:%s*(%d+)')) or 0
    local wins         = tonumber(resp:match('"wins"%s*:%s*(%d+)')) or 0
    local losses       = tonumber(resp:match('"losses"%s*:%s*(%d+)')) or 0
    local draws        = tonumber(resp:match('"draws"%s*:%s*(%d+)')) or 0
    local userNumber   = tonumber(resp:match('"userNumber"%s*:%s*(%d+)')) or 9999
    local createdAt    = tonumber(resp:match('"createdAt"%s*:%s*(%d+)')) or 0
    local createdAtStr = resp:match('"createdAtStr"%s*:%s*"([^"]*)"') or ""
    local lastSeen     = tonumber(resp:match('"lastSeen"%s*:%s*(%d+)')) or 0
    local avatarPreset = tonumber(resp:match('"avatarPreset"%s*:%s*(%d+)')) or 1

    local ratingsBlock = resp:match('"ratings"%s*:%s*(%b{})') or ""
    local ratings = {
        std_bullet  = tonumber(ratingsBlock:match('"std_bullet"%s*:%s*(%d+)'))  or 800,
        std_blitz   = tonumber(ratingsBlock:match('"std_blitz"%s*:%s*(%d+)'))   or rating,
        free_bullet = tonumber(ratingsBlock:match('"free_bullet"%s*:%s*(%d+)')) or 800,
        free_blitz  = tonumber(ratingsBlock:match('"free_blitz"%s*:%s*(%d+)'))  or 800
    }

    local achBlock = resp:match('"achievements"%s*:%s*(%b{})') or ""
    local achievements = {}
    for k, v in achBlock:gmatch('"([A-Za-z0-9_]+)"%s*:%s*(%a+)') do
        achievements[k] = (v == "true")
    end

    return {
        username     = uname,
        email        = email,
        bio          = bio,
        rating       = rating,
        ratings      = ratings,
        gamesPlayed  = gamesPlayed,
        wins         = wins,
        losses       = losses,
        draws        = draws,
        userNumber   = userNumber,
        createdAt    = createdAt,
        createdAtStr = createdAtStr,
        lastSeen     = lastSeen,
        avatarPreset = avatarPreset,
        achievements = achievements
    }
end

-- Sign in user via Firebase Authentication (Email/Password)
function FirebaseClient.signInUser(email, password)
    if not FirebaseClient.isConfigured() or not email or email == "" then return false end
    local url = FirebaseClient.getAuthUrl("signInWithPassword")
    local body = encodeSimpleJson({
        email             = email,
        password          = password,
        returnSecureToken = true
    })
    local resp = httpRequest("POST", url, body, false)
    if resp then
        local token = resp:match('"idToken"%s*:%s*"([^"]+)"')
        local uid   = resp:match('"localId"%s*:%s*"([^"]+)"')
        if token then
            FirebaseClient.idToken = token
            FirebaseClient.localId = uid
            return true
        end
    end
    return false
end

-- Sync user profile (username, ELO, stats, bio, registration date, achievements) to RTDB
function FirebaseClient.syncProfile(username, profileData)
    if not FirebaseClient.isConfigured() or not username or username == "" then return end
    local safeKey = username:gsub("[^A-Za-z0-9_]", "")
    if safeKey == "" then return end

    local payload = {
        username     = profileData.username,
        email        = profileData.email or "",
        bio          = profileData.bio or "",
        rating       = profileData.rating or 800,
        ratings      = profileData.ratings or { std_bullet = 800, std_blitz = profileData.rating or 800, free_bullet = 800, free_blitz = 800 },
        gamesPlayed  = profileData.gamesPlayed or 0,
        wins         = profileData.wins or 0,
        losses       = profileData.losses or 0,
        draws        = profileData.draws or 0,
        userNumber   = profileData.userNumber or 1,
        avatarPreset = profileData.avatarPreset or 1,
        createdAt    = profileData.createdAt or os.time(),
        createdAtStr = profileData.createdAtStr or os.date("%d.%m.%Y"),
        lastSeen     = os.time(),
        achievements = profileData.achievements or {},
        updatedAt    = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
    local url = FirebaseClient.getDatabaseUrl("users/" .. safeKey)
    httpRequest("PUT", url, encodeSimpleJson(payload), true)
end

-- Real online presence heartbeat & active players/games counter
function FirebaseClient.sendPresenceHeartbeat(username, inGame, isRegistered)
    if not FirebaseClient.isConfigured() then return end
    local nowTs = os.time()
    local url = FirebaseClient.getDatabaseUrl("presence/" .. FirebaseClient.sessionId)
    local payload = {
        username = username or "Guest",
        inGame   = inGame and true or false,
        ts       = nowTs
    }
    httpRequest("PUT", url, encodeSimpleJson(payload), true)

    if isRegistered and username and username ~= "" then
        local safeKey = username:gsub("[^A-Za-z0-9_]", "")
        if safeKey ~= "" then
            local uUrl = FirebaseClient.getDatabaseUrl("userPresence/" .. safeKey)
            httpRequest("PUT", uUrl, encodeSimpleJson(payload), true)
            local userPatchUrl = FirebaseClient.getDatabaseUrl("users/" .. safeKey)
            httpRequest("PATCH", userPatchUrl, encodeSimpleJson({ lastSeen = nowTs }), true)
        end
    end
end

function FirebaseClient.fetchOnlineStats(force)
    local now = os.time()
    if not force and (now - FirebaseClient.lastPresenceFetch) < 12 then
        return FirebaseClient.cachedOnlinePlayers, FirebaseClient.cachedActiveGames
    end
    FirebaseClient.lastPresenceFetch = now
    if not FirebaseClient.isConfigured() then
        return 1, 0
    end
    local url = FirebaseClient.getDatabaseUrl("presence")
    local resp = httpRequest("GET", url, nil, false)
    if not resp or resp == "" or resp == "null" or resp:match('"error"') then
        FirebaseClient.cachedOnlinePlayers = 1
        FirebaseClient.cachedActiveGames = 0
        return 1, 0
    end
    local countPlayers = 0
    local countGames = 0
    for tsStr, inGameStr in resp:gmatch('"inGame"%s*:%s*(%a+)%s*,%s*"ts"%s*:%s*(%d+)') do
        local ts = tonumber(tsStr) or 0
        if (now - ts) <= 90 then
            countPlayers = countPlayers + 1
            if inGameStr == "true" then
                countGames = countGames + 1
            end
        end
    end
    -- Also match reverse key order {"ts":..., "inGame":...}
    if countPlayers == 0 then
        for tsStr in resp:gmatch('"ts"%s*:%s*(%d+)') do
            local ts = tonumber(tsStr) or 0
            if (now - ts) <= 90 then
                countPlayers = countPlayers + 1
            end
        end
    end
    FirebaseClient.cachedOnlinePlayers = math.max(1, countPlayers)
    FirebaseClient.cachedActiveGames   = countGames
    return FirebaseClient.cachedOnlinePlayers, FirebaseClient.cachedActiveGames
end

function FirebaseClient.claimNextUserNumber()
    if not FirebaseClient.isConfigured() then return 1 end
    local url = FirebaseClient.getDatabaseUrl("meta/userCount")
    local resp = httpRequest("GET", url, nil, false)
    local cur = tonumber(resp) or 0
    local nextNum = cur + 1
    httpRequest("PUT", url, tostring(nextNum), true)
    return nextNum
end

-- Push completed match record to Realtime Database asynchronously
function FirebaseClient.pushMatchRecord(matchRecord)
    if not FirebaseClient.isConfigured() then return end
    local url = FirebaseClient.getDatabaseUrl("matches")
    httpRequest("POST", url, encodeSimpleJson(matchRecord), true)
end

-- Batch fetch online/lastSeen presence for all registered users in a single GET
function FirebaseClient.fetchAllUserPresences()
    local map = {}
    if not FirebaseClient.isConfigured() then return map end
    local url = FirebaseClient.getDatabaseUrl("userPresence")
    local resp = httpRequest("GET", url, nil, false)
    if not resp or resp == "" or resp == "null" or resp:match('"error"') then
        return map
    end
    for key, block in resp:gmatch('"([A-Za-z0-9_]+)"%s*:%s*(%b{})') do
        local uname = block:match('"username"%s*:%s*"([^"]*)"') or key
        local ts = tonumber(block:match('"ts"%s*:%s*(%d+)')) or 0
        local inGame = (block:match('"inGame"%s*:%s*(%a+)') == "true")
        map[uname:lower()] = { ts = ts, inGame = inGame, username = uname }
    end
    return map
end

-- Friend Mailbox Sync (requests, accepts, removals, game invites)
function FirebaseClient.sendFriendRequestRemote(fromUser, toUser)
    if not FirebaseClient.isConfigured() then return end
    local sFrom = tostring(fromUser or ""):gsub("[^A-Za-z0-9_]", "")
    local sTo   = tostring(toUser or ""):gsub("[^A-Za-z0-9_]", "")
    if sFrom == "" or sTo == "" then return end
    local url = FirebaseClient.getDatabaseUrl("friendBoxes/" .. sTo .. "/incoming/" .. sFrom)
    httpRequest("PUT", url, encodeSimpleJson({ from = fromUser, ts = os.time() }), true)
end

function FirebaseClient.acceptFriendRequestRemote(myUser, fromUser)
    if not FirebaseClient.isConfigured() then return end
    local sMe   = tostring(myUser or ""):gsub("[^A-Za-z0-9_]", "")
    local sFrom = tostring(fromUser or ""):gsub("[^A-Za-z0-9_]", "")
    if sMe == "" or sFrom == "" then return end
    httpRequest("DELETE", FirebaseClient.getDatabaseUrl("friendBoxes/" .. sMe .. "/incoming/" .. sFrom), nil, true)
    httpRequest("PUT", FirebaseClient.getDatabaseUrl("friendBoxes/" .. sFrom .. "/accepted/" .. sMe), encodeSimpleJson({ from = myUser, ts = os.time() }), true)
end

function FirebaseClient.declineFriendRequestRemote(myUser, fromUser)
    if not FirebaseClient.isConfigured() then return end
    local sMe   = tostring(myUser or ""):gsub("[^A-Za-z0-9_]", "")
    local sFrom = tostring(fromUser or ""):gsub("[^A-Za-z0-9_]", "")
    if sMe == "" or sFrom == "" then return end
    httpRequest("DELETE", FirebaseClient.getDatabaseUrl("friendBoxes/" .. sMe .. "/incoming/" .. sFrom), nil, true)
end

function FirebaseClient.removeFriendRemote(myUser, targetUser)
    if not FirebaseClient.isConfigured() then return end
    local sMe = tostring(myUser or ""):gsub("[^A-Za-z0-9_]", "")
    local sTo = tostring(targetUser or ""):gsub("[^A-Za-z0-9_]", "")
    if sMe == "" or sTo == "" then return end
    httpRequest("PUT", FirebaseClient.getDatabaseUrl("friendBoxes/" .. sTo .. "/removed/" .. sMe), encodeSimpleJson({ from = myUser, ts = os.time() }), true)
end

function FirebaseClient.sendGameInvite(targetUser, fromUser, roomCode, ruleMode, timeMinutes)
    if not FirebaseClient.isConfigured() then return end
    local sTo = tostring(targetUser or ""):gsub("[^A-Za-z0-9_]", "")
    local sCode = tostring(roomCode or ""):gsub("[^A-Za-z0-9]", "")
    if sTo == "" or sCode == "" then return end
    local url = FirebaseClient.getDatabaseUrl("friendBoxes/" .. sTo .. "/invites/" .. sCode)
    httpRequest("PUT", url, encodeSimpleJson({
        code = sCode,
        from = fromUser,
        ruleMode = ruleMode or "standard",
        timeMinutes = timeMinutes or 5,
        ts = os.time()
    }), true)
end

function FirebaseClient.clearGameInvite(myUser, roomCode)
    if not FirebaseClient.isConfigured() then return end
    local sMe = tostring(myUser or ""):gsub("[^A-Za-z0-9_]", "")
    local sCode = tostring(roomCode or ""):gsub("[^A-Za-z0-9]", "")
    if sMe == "" or sCode == "" then return end
    httpRequest("DELETE", FirebaseClient.getDatabaseUrl("friendBoxes/" .. sMe .. "/invites/" .. sCode), nil, true)
end

function FirebaseClient.pollFriendBox(myUser)
    local out = { incoming = {}, accepted = {}, removed = {}, invites = {} }
    if not FirebaseClient.isConfigured() or not myUser or myUser == "" then return out end
    local sMe = myUser:gsub("[^A-Za-z0-9_]", "")
    if sMe == "" then return out end
    local url = FirebaseClient.getDatabaseUrl("friendBoxes/" .. sMe)
    local resp = httpRequest("GET", url, nil, false)
    if not resp or resp == "" or resp == "null" or resp:match('"error"') then
        return out
    end

    local incBlock = resp:match('"incoming"%s*:%s*(%b{})')
    if incBlock then
        for _, blk in incBlock:gmatch('"([A-Za-z0-9_]+)"%s*:%s*(%b{})') do
            local fromName = blk:match('"from"%s*:%s*"([^"]*)"')
            if fromName and fromName ~= "" then table.insert(out.incoming, fromName) end
        end
    end

    local accBlock = resp:match('"accepted"%s*:%s*(%b{})')
    if accBlock then
        for k, blk in accBlock:gmatch('"([A-Za-z0-9_]+)"%s*:%s*(%b{})') do
            local fromName = blk:match('"from"%s*:%s*"([^"]*)"') or k
            table.insert(out.accepted, fromName)
            httpRequest("DELETE", FirebaseClient.getDatabaseUrl("friendBoxes/" .. sMe .. "/accepted/" .. k), nil, true)
        end
    end

    local remBlock = resp:match('"removed"%s*:%s*(%b{})')
    if remBlock then
        for k, blk in remBlock:gmatch('"([A-Za-z0-9_]+)"%s*:%s*(%b{})') do
            local fromName = blk:match('"from"%s*:%s*"([^"]*)"') or k
            table.insert(out.removed, fromName)
            httpRequest("DELETE", FirebaseClient.getDatabaseUrl("friendBoxes/" .. sMe .. "/removed/" .. k), nil, true)
        end
    end

    local invBlock = resp:match('"invites"%s*:%s*(%b{})')
    if invBlock then
        local nowTs = os.time()
        for codeKey, blk in invBlock:gmatch('"([A-Za-z0-9_]+)"%s*:%s*(%b{})') do
            local ts = tonumber(blk:match('"ts"%s*:%s*(%d+)')) or 0
            if (nowTs - ts) <= 300 then
                table.insert(out.invites, {
                    code = blk:match('"code"%s*:%s*"([^"]*)"') or codeKey,
                    from = blk:match('"from"%s*:%s*"([^"]*)"') or "Player",
                    ruleMode = blk:match('"ruleMode"%s*:%s*"([^"]*)"') or "standard",
                    timeMinutes = tonumber(blk:match('"timeMinutes"%s*:%s*(%d+)')) or 5,
                    ts = ts
                })
            else
                httpRequest("DELETE", FirebaseClient.getDatabaseUrl("friendBoxes/" .. sMe .. "/invites/" .. codeKey), nil, true)
            end
        end
    end

    return out
end

-- Real 2-Player Online Friend Rooms (Create / Join by Code / Move Sync)
local function genRoomCode6()
    local chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    local code = {}
    for i = 1, 6 do
        local idx = math.random(1, #chars)
        code[i] = chars:sub(idx, idx)
    end
    return table.concat(code)
end

local function parseFriendRoomJson(resp, fallbackCode)
    if not resp or resp == "" or resp == "null" or resp:match('"error"') then
        return nil
    end
    local host = resp:match('"host"%s*:%s*"([^"]*)"')
    if not host or host == "" then return nil end
    return {
        code        = resp:match('"code"%s*:%s*"([^"]*)"') or fallbackCode,
        host        = host,
        guest       = resp:match('"guest"%s*:%s*"([^"]*)"') or "",
        ruleMode    = resp:match('"ruleMode"%s*:%s*"([^"]*)"') or "standard",
        timeMinutes = tonumber(resp:match('"timeMinutes"%s*:%s*(%d+)')) or 5,
        status      = resp:match('"status"%s*:%s*"([^"]*)"') or "waiting",
        moveCount   = tonumber(resp:match('"moveCount"%s*:%s*(%d+)')) or 0,
        moves       = resp:match('"moves"%s*:%s*"([^"]*)"') or "",
        ts          = tonumber(resp:match('"ts"%s*:%s*(%d+)')) or 0
    }
end

function FirebaseClient.createFriendRoom(opts)
    opts = opts or {}
    local code = genRoomCode6()
    local room = {
        code        = code,
        host        = opts.host or "Player",
        guest       = "",
        ruleMode    = (opts.ruleMode == "free") and "free" or "standard",
        timeMinutes = (opts.timeMinutes == 1) and 1 or 5,
        status      = "waiting",
        moveCount   = 0,
        moves       = "",
        ts          = os.time()
    }
    if FirebaseClient.isConfigured() then
        local url = FirebaseClient.getDatabaseUrl("friendRooms/" .. code)
        httpRequest("PUT", url, encodeSimpleJson(room), false)
    end
    return room
end

function FirebaseClient.fetchFriendRoom(code)
    code = tostring(code or ""):upper():gsub("[^A-Z0-9]", "")
    if #code < 4 or not FirebaseClient.isConfigured() then return nil end
    local url = FirebaseClient.getDatabaseUrl("friendRooms/" .. code)
    local resp = httpRequest("GET", url, nil, false)
    return parseFriendRoomJson(resp, code)
end

function FirebaseClient.joinFriendRoom(code, guestName)
    code = tostring(code or ""):upper():gsub("[^A-Z0-9]", "")
    if #code < 4 then return nil, "friend_room_not_found" end
    if not FirebaseClient.isConfigured() or (love and love.system and love.system.getOS() == "Web") then
        return nil, "friend_no_net"
    end
    local room = FirebaseClient.fetchFriendRoom(code)
    if not room then
        return nil, "friend_room_not_found"
    end
    if room.guest ~= "" and room.guest:lower() ~= tostring(guestName or ""):lower() then
        return nil, "friend_room_not_found"
    end
    if room.host:lower() == tostring(guestName or ""):lower() then
        return nil, "friend_room_not_found"
    end
    local patch = {
        guest  = guestName,
        status = "playing",
        ts     = os.time()
    }
    local url = FirebaseClient.getDatabaseUrl("friendRooms/" .. code)
    httpRequest("PATCH", url, encodeSimpleJson(patch), false)
    room.guest = guestName
    room.status = "playing"
    return room, nil
end

function FirebaseClient.pushFriendRoomMove(code, movesStr, moveCount)
    code = tostring(code or ""):upper():gsub("[^A-Za-z0-9]", "")
    if code == "" or not FirebaseClient.isConfigured() then return end
    local url = FirebaseClient.getDatabaseUrl("friendRooms/" .. code)
    httpRequest("PATCH", url, encodeSimpleJson({
        moves     = movesStr or "",
        moveCount = moveCount or 0,
        ts        = os.time()
    }), true)
end

function FirebaseClient.closeFriendRoom(code)
    code = tostring(code or ""):upper():gsub("[^A-Za-z0-9]", "")
    if code == "" or not FirebaseClient.isConfigured() then return end
    local url = FirebaseClient.getDatabaseUrl("friendRooms/" .. code)
    httpRequest("DELETE", url, nil, true)
end

return FirebaseClient
