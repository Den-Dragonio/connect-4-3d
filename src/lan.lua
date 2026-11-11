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
    onMoveReceived = nil,
    onMatchStart = nil
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

    -- Send HELLO handshake to targetIP and LAN broadcast
    pcall(function()
        LAN.udp:sendto("C4_HELLO", LAN.peerIP, LAN.PORT)
        LAN.udp:setoption("broadcast", true)
        LAN.udp:sendto("C4_HELLO", "255.255.255.255", LAN.PORT)
    end)
    return true
end

function LAN.sendMove(gx, gz)
    if not LAN.udp or not LAN.connected or not LAN.peerIP or not LAN.peerPort then
        return
    end
    local msg = string.format("C4_MOVE:%d:%d", gx, gz)
    pcall(function()
        LAN.udp:sendto(msg, LAN.peerIP, LAN.peerPort)
    end)
end

function LAN.update()
    if not LAN.udp then return end
    while true do
        local data, ip, port = LAN.udp:receivefrom()
        if not data then break end

        if LAN.role == "host" and data == "C4_HELLO" then
            LAN.connected = true
            LAN.peerIP = ip
            LAN.peerPort = port
            LAN.udp:sendto("C4_WELCOME", ip, port)
            if LAN.onMatchStart then
                LAN.onMatchStart("host") -- Host plays White (1st)
            end
        elseif LAN.role == "client" and data == "C4_WELCOME" then
            LAN.connected = true
            LAN.peerIP = ip
            LAN.peerPort = port
            if LAN.onMatchStart then
                LAN.onMatchStart("client") -- Client plays Black (2nd)
            end
        elseif data:sub(1, 8) == "C4_MOVE:" then
            local gx, gz = data:match("^C4_MOVE:(%d+):(%d+)$")
            if gx and gz and LAN.onMoveReceived then
                LAN.onMoveReceived(tonumber(gx), tonumber(gz))
            end
        end
    end
end

return LAN

