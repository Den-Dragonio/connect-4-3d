local okSocket, socket = pcall(require, "socket")
if not okSocket then
    socket = nil
end

local LAN = {
    PORT = 24444,
    role = nil,      -- "host" or "client"
    udp = nil,
    connected = false,
    peerIP = nil,
    peerPort = nil,
    joinIP = "127.0.0.1",
    statusMsg = "",
    localPieceSkin = "classic_bw",
    localBoardSkin = "dark_wood",
    peerPieceSkin = "classic_bw",
    peerBoardSkin = "dark_wood",
    onMoveReceived = nil,
    onMatchStart = nil,
    onRematchReceived = nil
}

function LAN.stop()
    if LAN.udp then
        pcall(function() LAN.udp:close() end)
        LAN.udp = nil
    end
    LAN.role = nil
    LAN.connected = false
    LAN.peerIP = nil
    LAN.peerPort = nil
    LAN.statusMsg = ""
end

function LAN.startHost()
    LAN.stop()
    if not socket or not socket.udp then
        LAN.statusMsg = "LAN UDP is available in Desktop app only."
        return false
    end
    local udp, err = socket.udp()
    if not udp then
        LAN.statusMsg = "UDP Error: " .. tostring(err)
        return false
    end
    udp:settimeout(0)
    local ok, bindErr = udp:setsockname("*", LAN.PORT)
    if not ok then
        LAN.statusMsg = "Port " .. LAN.PORT .. " busy: " .. tostring(bindErr)
        udp:close()
        return false
    end
    LAN.udp = udp
    LAN.role = "host"
    LAN.connected = false
    LAN.statusMsg = "Waiting for player on LAN (Port " .. LAN.PORT .. ")..."
    return true
end

function LAN.startClient(targetIP)
    LAN.stop()
    if not socket or not socket.udp then
        LAN.statusMsg = "LAN UDP is available in Desktop app only."
        return false
    end
    local udp, err = socket.udp()
    if not udp then
        LAN.statusMsg = "UDP Error: " .. tostring(err)
        return false
    end
    udp:settimeout(0)
    udp:setsockname("*", 0)
    LAN.udp = udp
    LAN.role = "client"
    LAN.connected = false
    LAN.peerIP = (targetIP and #targetIP > 0) and targetIP or "127.0.0.1"
    LAN.peerPort = LAN.PORT
    LAN.statusMsg = "Connecting to " .. LAN.peerIP .. ":" .. LAN.PORT .. "..."

    -- Send HELLO handshake with equipped skins to targetIP and LAN broadcast
    local helloMsg = string.format("C4_HELLO:%s:%s", tostring(LAN.localPieceSkin or "classic_bw"), tostring(LAN.localBoardSkin or "dark_wood"))
    pcall(function()
        LAN.udp:sendto(helloMsg, LAN.peerIP, LAN.PORT)
        LAN.udp:setoption("broadcast", true)
        LAN.udp:sendto(helloMsg, "255.255.255.255", LAN.PORT)
    end)
    return true
end

function LAN.sendMove(gx, gz, gy)
    if not LAN.udp or not LAN.connected or not LAN.peerIP or not LAN.peerPort then
        return
    end
    local msg = string.format("C4_MOVE:%d:%d:%d", gx, gz, gy or 0)
    pcall(function()
        LAN.udp:sendto(msg, LAN.peerIP, LAN.peerPort)
    end)
end

function LAN.sendRematch()
    if not LAN.udp or not LAN.connected or not LAN.peerIP or not LAN.peerPort then
        return
    end
    pcall(function()
        LAN.udp:sendto("C4_REMATCH", LAN.peerIP, LAN.peerPort)
    end)
end

function LAN.update()
    if not LAN.udp then return end
    while true do
        local data, ip, port = LAN.udp:receivefrom()
        if not data then break end

        if LAN.role == "host" and (data == "C4_HELLO" or data:sub(1, 9) == "C4_HELLO:") then
            local pSkin, bSkin = data:match("^C4_HELLO:([^:]+):([^:]+)$")
            LAN.peerPieceSkin = pSkin or "classic_bw"
            LAN.peerBoardSkin = bSkin or "dark_wood"
            LAN.connected = true
            LAN.peerIP = ip
            LAN.peerPort = port
            local welcomeMsg = string.format("C4_WELCOME:%s:%s", tostring(LAN.localPieceSkin or "classic_bw"), tostring(LAN.localBoardSkin or "dark_wood"))
            LAN.udp:sendto(welcomeMsg, ip, port)
            if LAN.onMatchStart then
                LAN.onMatchStart("host") -- Host plays White (1st)
            end
        elseif LAN.role == "client" and (data == "C4_WELCOME" or data:sub(1, 11) == "C4_WELCOME:") then
            local pSkin, bSkin = data:match("^C4_WELCOME:([^:]+):([^:]+)$")
            LAN.peerPieceSkin = pSkin or "classic_bw"
            LAN.peerBoardSkin = bSkin or "dark_wood"
            LAN.connected = true
            LAN.peerIP = ip
            LAN.peerPort = port
            if LAN.onMatchStart then
                LAN.onMatchStart("client") -- Client plays Black (2nd)
            end
        elseif data == "C4_REMATCH" then
            if LAN.onRematchReceived then
                LAN.onRematchReceived()
            end
        elseif data:sub(1, 8) == "C4_MOVE:" then
            local gx, gz, gy = data:match("^C4_MOVE:(%d+):(%d+):?(%d*)$")
            local nGy = tonumber(gy)
            if nGy == 0 then nGy = nil end
            if gx and gz and LAN.onMoveReceived then
                LAN.onMoveReceived(tonumber(gx), tonumber(gz), nGy)
            end
        end
    end
end

return LAN

