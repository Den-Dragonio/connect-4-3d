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
    lastSyncInfo = "Connected (connect4-a2f21)"
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

-- Fetch user profile from Realtime Database (for cross-device login & uniqueness check)
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
    local email       = resp:match('"email"%s*:%s*"([^"]*)"') or ""
    local bio         = resp:match('"bio"%s*:%s*"([^"]*)"') or ""
    local rating      = tonumber(resp:match('"rating"%s*:%s*(%d+)')) or 800
    local gamesPlayed = tonumber(resp:match('"gamesPlayed"%s*:%s*(%d+)')) or 0
    local wins        = tonumber(resp:match('"wins"%s*:%s*(%d+)')) or 0
    local losses      = tonumber(resp:match('"losses"%s*:%s*(%d+)')) or 0
    local draws       = tonumber(resp:match('"draws"%s*:%s*(%d+)')) or 0
    return {
        username    = uname,
        email       = email,
        bio         = bio,
        rating      = rating,
        gamesPlayed = gamesPlayed,
        wins        = wins,
        losses      = losses,
        draws       = draws
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

-- Sync user profile (username, ELO, stats, bio) to Realtime Database asynchronously
function FirebaseClient.syncProfile(username, profileData)
    if not FirebaseClient.isConfigured() or not username or username == "" then return end
    local safeKey = username:gsub("[^A-Za-z0-9_]", "")
    if safeKey == "" then return end

    local payload = {
        username    = profileData.username,
        email       = profileData.email or "",
        bio         = profileData.bio or "",
        rating      = profileData.rating or 800,
        gamesPlayed = profileData.gamesPlayed or 0,
        wins        = profileData.wins or 0,
        losses      = profileData.losses or 0,
        draws       = profileData.draws or 0,
        updatedAt   = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
    local url = FirebaseClient.getDatabaseUrl("users/" .. safeKey)
    httpRequest("PUT", url, encodeSimpleJson(payload), true)
end

-- Push completed match record to Realtime Database asynchronously
function FirebaseClient.pushMatchRecord(matchRecord)
    if not FirebaseClient.isConfigured() then return end
    local url = FirebaseClient.getDatabaseUrl("matches")
    httpRequest("POST", url, encodeSimpleJson(matchRecord), true)
end

return FirebaseClient
