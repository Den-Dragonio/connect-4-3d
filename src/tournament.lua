local Tournament = {}

Tournament.active = nil
Tournament.joinCodeInput = ""
Tournament.statusMsg = ""

local function genRoomCode()
    local chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    local code = {}
    for i = 1, 6 do
        local idx = math.random(1, #chars)
        code[i] = chars:sub(idx, idx)
    end
    return table.concat(code)
end

local BOT_NAMES = {
    "AlphaBot", "CubeMind", "PegMaster", "VoxelAI",
    "DeepFour", "GridBot", "TorusAI", "ZenBot",
    "NovaAI", "SparkBot", "ApexCube", "Logic4",
    "SkyBot", "FrostAI", "Shadow4"
}

local DIFF_MAP = { easy = 1, medium = 2, hard = 3 }

function Tournament.create(opts)
    opts = opts or {}
    local system = (opts.system == "bracket") and "bracket" or "swiss"
    local maxPlayers = tonumber(opts.maxPlayers) or 8
    if maxPlayers ~= 4 and maxPlayers ~= 8 and maxPlayers ~= 16 then
        maxPlayers = 8
    end
    local timeMinutes = (opts.timeMinutes == 1) and 1 or 5
    local ruleMode = (opts.ruleMode == "free") and "free" or "standard"
    local isBotTournament = opts.isBotTournament and true or false
    local botDiff = DIFF_MAP[opts.botDifficulty] or tonumber(opts.botDifficulty) or 2
    local hostName = opts.hostName or "Player"

    local prizeMode = opts.prizeMode
    if prizeMode ~= "host" and prizeMode ~= "entry_fee" then
        prizeMode = "none"
    end
    local hostFund = (prizeMode == "host") and math.max(0, math.floor(tonumber(opts.hostFund) or 0)) or 0
    local entryFee = (prizeMode == "entry_fee") and math.max(0, math.floor(tonumber(opts.entryFee) or 0)) or 0
    if prizeMode == "host" and hostFund <= 0 then
        prizeMode = "none"
    elseif prizeMode == "entry_fee" and entryFee <= 0 then
        prizeMode = "none"
    end

    local paidPlayers = {}
    local initialPool = 0
    if prizeMode == "host" then
        initialPool = hostFund
        paidPlayers[hostName] = hostFund
    elseif prizeMode == "entry_fee" then
        initialPool = entryFee
        paidPlayers[hostName] = entryFee
    end

    local t = {
        code = genRoomCode(),
        system = system,             -- "swiss" or "bracket"
        maxPlayers = maxPlayers,
        timeMinutes = timeMinutes,   -- 1 or 5
        ruleMode = ruleMode,         -- "standard" or "free"
        isBotTournament = isBotTournament,
        botDifficulty = botDiff,
        hostName = hostName,
        prizeMode = prizeMode,       -- "none", "host", "entry_fee"
        hostFund = hostFund,
        entryFee = entryFee,
        prizePool = initialPool,
        paidPlayers = paidPlayers,
        prizePaid = false,
        status = "lobby",            -- "lobby", "active", "finished"
        currentRound = 0,
        totalRounds = (system == "bracket")
            and math.floor(math.log(maxPlayers) / math.log(2) + 0.5)
            or math.min(4, maxPlayers - 1),
        players = {
            { name = hostName, isBot = false, score = 0, wins = 0, draws = 0, losses = 0, playedAgainst = {} }
        },
        rounds = {},                 -- rounds[r] = list of matches
        champion = nil,
        humanMatches = {}            -- detailed stats of human's battles
    }

    if isBotTournament then
        for i = 1, maxPlayers - 1 do
            local bName = (BOT_NAMES[i] or ("Bot_" .. i)) .. " (B" .. botDiff .. ")"
            table.insert(t.players, {
                name = bName,
                isBot = true,
                score = 0,
                wins = 0,
                draws = 0,
                losses = 0,
                playedAgainst = {}
            })
            if t.prizeMode == "entry_fee" then
                t.prizePool = t.prizePool + t.entryFee
            end
        end
        Tournament.active = t
        Tournament.startTournament()
    else
        Tournament.active = t
        Tournament.statusMsg = "Room created: " .. t.code
    end

    return t
end

function Tournament.getJoinEntryFee(code)
    code = tostring(code or ""):upper():gsub("%s+", "")
    local t = Tournament.active
    if t and t.code == code and t.status == "lobby" and t.prizeMode == "entry_fee" then
        return t.entryFee or 0
    end
    return 0
end

function Tournament.joinByCode(code, playerName)
    code = tostring(code or ""):upper():gsub("%s+", "")
    if #code < 4 then
        Tournament.statusMsg = "Invalid room code"
        return false
    end
    if Tournament.active and Tournament.active.code == code and Tournament.active.status == "lobby" then
        for _, p in ipairs(Tournament.active.players) do
            if p.name == playerName then
                return true
            end
        end
        if #Tournament.active.players < Tournament.active.maxPlayers then
            table.insert(Tournament.active.players, {
                name = playerName, isBot = false, score = 0, wins = 0, draws = 0, losses = 0, playedAgainst = {}
            })
            if Tournament.active.prizeMode == "entry_fee" and (Tournament.active.entryFee or 0) > 0 then
                if not Tournament.active.paidPlayers[playerName] then
                    Tournament.active.paidPlayers[playerName] = Tournament.active.entryFee
                    Tournament.active.prizePool = (Tournament.active.prizePool or 0) + Tournament.active.entryFee
                end
            end
            return true
        end
        Tournament.statusMsg = "Tournament is full"
        return false
    end
    -- Create a simulated joined online lobby for that code if not locally hosted
    local t = Tournament.create({
        system = "swiss",
        maxPlayers = 4,
        timeMinutes = 5,
        ruleMode = "standard",
        isBotTournament = false,
        hostName = "Host_" .. code:sub(1, 3)
    })
    t.code = code
    table.insert(t.players, {
        name = playerName, isBot = false, score = 0, wins = 0, draws = 0, losses = 0, playedAgainst = {}
    })
    Tournament.statusMsg = "Joined room " .. code
    return true
end

function Tournament.startTournament()
    local t = Tournament.active
    if not t then return false end
    -- Fill empty seats with bots if human online lobby starts early
    local idx = 1
    while #t.players < t.maxPlayers do
        local bName = (BOT_NAMES[idx] or ("Bot_" .. idx)) .. " (B" .. (t.botDifficulty or 2) .. ")"
        idx = idx + 1
        table.insert(t.players, {
            name = bName, isBot = true, score = 0, wins = 0, draws = 0, losses = 0, playedAgainst = {}
        })
        if t.prizeMode == "entry_fee" and (t.entryFee or 0) > 0 then
            t.prizePool = (t.prizePool or 0) + t.entryFee
        end
    end
    t.status = "active"
    t.currentRound = 1
    if t.system == "bracket" then
        Tournament._initBracketTree()
    end
    Tournament._generateRound(1)
    Tournament._advanceRoundsIfReady()
    return true
end

function Tournament._initBracketTree()
    local t = Tournament.active
    if not t or t.system ~= "bracket" then return end
    t.rounds = {}
    local matchCount = math.floor(#t.players / 2)
    for r = 1, t.totalRounds do
        local rMatches = {}
        for mIdx = 1, math.max(1, matchCount) do
            table.insert(rMatches, {
                id = string.format("R%d_M%d", r, mIdx),
                round = r,
                p1 = nil,
                p2 = nil,
                winner = nil,
                done = false
            })
        end
        t.rounds[r] = rMatches
        matchCount = math.floor(matchCount / 2)
    end
end

function Tournament._propagateBracketWinners(fromRound)
    local t = Tournament.active
    if not t or t.system ~= "bracket" then return end
    local prev = t.rounds[fromRound]
    local nextRound = t.rounds[fromRound + 1]
    if not prev or not nextRound then return end
    for i, nm in ipairs(nextRound) do
        local m1 = prev[2 * i - 1]
        local m2 = prev[2 * i]
        if m1 and m1.done and m1.winner and m1.winner ~= "DRAW" then
            nm.p1 = m1.winner
        end
        if m2 and m2.done and m2.winner and m2.winner ~= "DRAW" then
            nm.p2 = m2.winner
        end
    end
end

function Tournament._advanceRoundsIfReady()
    local t = Tournament.active
    if not t then return end
    local guard = 0
    while t.status == "active" and guard < 16 do
        guard = guard + 1
        local curMatches = t.rounds[t.currentRound] or {}
        local allDone = (#curMatches > 0)
        for _, rm in ipairs(curMatches) do
            if not rm.done then
                allDone = false
                break
            end
        end
        if not allDone then
            break
        end
        if t.currentRound < t.totalRounds then
            t.currentRound = t.currentRound + 1
            Tournament._generateRound(t.currentRound)
        else
            Tournament.finishTournament()
            break
        end
    end
end

function Tournament._findPlayer(name)
    if not Tournament.active or not name then return nil end
    for _, p in ipairs(Tournament.active.players) do
        if p.name == name then return p end
    end
    return nil
end

function Tournament._generateRound(roundNum)
    local t = Tournament.active
    if not t then return end

    if t.system == "swiss" then
        local roundMatches = {}
        local sorted = {}
        for _, p in ipairs(t.players) do table.insert(sorted, p) end
        table.sort(sorted, function(a, b)
            if a.score ~= b.score then return a.score > b.score end
            if a.wins ~= b.wins then return a.wins > b.wins end
            return a.name < b.name
        end)
        local paired = {}
        for i = 1, #sorted do
            if not paired[i] then
                local p1 = sorted[i]
                local bestJ = nil
                for j = i + 1, #sorted do
                    if not paired[j] then
                        if not bestJ then bestJ = j end
                        if not p1.playedAgainst[sorted[j].name] then
                            bestJ = j
                            break
                        end
                    end
                end
                if bestJ then
                    paired[i] = true
                    paired[bestJ] = true
                    local p2 = sorted[bestJ]
                    p1.playedAgainst[p2.name] = true
                    p2.playedAgainst[p1.name] = true
                    -- Alternate White/Black for human every other round for fairness
                    local firstPlayer, secondPlayer = p1.name, p2.name
                    if (roundNum % 2 == 0) and (not p1.isBot or not p2.isBot) then
                        firstPlayer, secondPlayer = p2.name, p1.name
                    end
                    table.insert(roundMatches, {
                        id = string.format("R%d_M%d", roundNum, #roundMatches + 1),
                        round = roundNum,
                        p1 = firstPlayer,
                        p2 = secondPlayer,
                        winner = nil, -- player name or "DRAW"
                        done = false
                    })
                end
            end
        end
        t.rounds[roundNum] = roundMatches
    else
        -- Knockout Bracket (pre-allocated tree across all rounds)
        if not t.rounds[roundNum] then
            Tournament._initBracketTree()
        end
        if roundNum == 1 then
            local r1 = t.rounds[1] or {}
            local mIdx = 1
            for i = 1, #t.players, 2 do
                local p1 = t.players[i]
                local p2 = t.players[i + 1]
                if p1 and p2 and r1[mIdx] then
                    r1[mIdx].p1 = p1.name
                    r1[mIdx].p2 = p2.name
                    mIdx = mIdx + 1
                end
            end
        else
            Tournament._propagateBracketWinners(roundNum - 1)
        end
    end

    Tournament._autoResolveBotMatches(roundNum)
    if t.system == "bracket" then
        Tournament._propagateBracketWinners(roundNum)
    end
end

function Tournament._autoResolveBotMatches(roundNum)
    local t = Tournament.active
    if not t then return end
    local rMatches = t.rounds[roundNum] or {}
    for _, m in ipairs(rMatches) do
        if not m.done then
            local p1 = Tournament._findPlayer(m.p1)
            local p2 = Tournament._findPlayer(m.p2)
            if p1 and p2 and p1.isBot and p2.isBot then
                local roll = math.random()
                if t.system == "swiss" and roll < 0.12 then
                    Tournament._applyMatchResult(m, "DRAW")
                elseif roll < 0.56 then
                    Tournament._applyMatchResult(m, p1.name)
                else
                    Tournament._applyMatchResult(m, p2.name)
                end
            end
        end
    end
end

function Tournament._applyMatchResult(m, winnerName)
    if m.done then return end
    m.done = true
    m.winner = winnerName
    local p1 = Tournament._findPlayer(m.p1)
    local p2 = Tournament._findPlayer(m.p2)
    if not p1 or not p2 then return end

    if winnerName == "DRAW" then
        p1.score = p1.score + 0.5
        p2.score = p2.score + 0.5
        p1.draws = p1.draws + 1
        p2.draws = p2.draws + 1
    elseif winnerName == p1.name then
        p1.score = p1.score + 1.0
        p1.wins = p1.wins + 1
        p2.losses = p2.losses + 1
    else
        p2.score = p2.score + 1.0
        p2.wins = p2.wins + 1
        p1.losses = p1.losses + 1
    end
end

function Tournament.getHumanPendingMatch(humanName)
    local t = Tournament.active
    if not t or t.status ~= "active" then return nil end
    local rMatches = t.rounds[t.currentRound] or {}
    for _, m in ipairs(rMatches) do
        if not m.done and (m.p1 == humanName or m.p2 == humanName) then
            return m
        end
    end
    return nil
end

function Tournament.isHumanEliminated(humanName)
    local t = Tournament.active
    if not t or t.system ~= "bracket" then return false, nil end
    for rIdx, rMatches in ipairs(t.rounds) do
        for _, m in ipairs(rMatches) do
            if m.done and (m.p1 == humanName or m.p2 == humanName) then
                if m.winner and m.winner ~= humanName then
                    return true, rIdx
                end
            end
        end
    end
    return false, nil
end

function Tournament.getRoundLabel(roundNum, totalRounds, system, i18n)
    if system == "bracket" then
        local fromEnd = (totalRounds or 1) - (roundNum or 1)
        if fromEnd == 0 then
            return i18n.t("tourn_round_final")
        elseif fromEnd == 1 then
            return i18n.t("tourn_round_semi")
        elseif fromEnd == 2 then
            return i18n.t("tourn_round_quarter")
        end
    end
    return i18n.t("tourn_round_num", roundNum or 1, totalRounds or 1)
end

function Tournament.recordHumanMatchResult(humanName, winnerIsHuman, isDraw, movesCount)
    local t = Tournament.active
    if not t or t.status ~= "active" then return false end
    local m = Tournament.getHumanPendingMatch(humanName)
    if not m then return false end

    local roundPlayed = t.currentRound
    local oppName = (m.p1 == humanName) and m.p2 or m.p1
    local resName
    if isDraw and t.system == "swiss" then
        resName = "DRAW"
    elseif isDraw then
        -- Knockout tiebreak: award human on draw
        resName = humanName
    elseif winnerIsHuman then
        resName = humanName
    else
        resName = oppName
    end

    Tournament._applyMatchResult(m, resName)
    table.insert(t.humanMatches, {
        round = roundPlayed,
        opponent = oppName,
        won = (resName == humanName),
        draw = (resName == "DRAW"),
        moves = movesCount or 1
    })

    if t.system == "bracket" then
        Tournament._propagateBracketWinners(roundPlayed)
    end
    Tournament._advanceRoundsIfReady()

    local elim, elimRound = Tournament.isHumanEliminated(humanName)
    return {
        recorded = true,
        roundPlayed = roundPlayed,
        currentRound = t.currentRound,
        totalRounds = t.totalRounds,
        wonMatch = (resName == humanName),
        eliminated = elim,
        eliminatedRound = elimRound,
        nextMatch = Tournament.getHumanPendingMatch(humanName),
        finished = (t.status == "finished"),
        champion = t.champion,
        prizePool = t.prizePool or 0,
        prizePaid = t.prizePaid and true or false
    }
end

function Tournament.claimChampionPrize(humanName)
    local t = Tournament.active
    if not t or t.status ~= "finished" or t.prizePaid then
        return 0
    end
    local pool = t.prizePool or 0
    if pool > 0 and t.champion == humanName then
        t.prizePaid = true
        return pool
    end
    return 0
end

function Tournament.cancelOrRefund(humanName)
    local t = Tournament.active
    if not t then
        Tournament.leave()
        return 0
    end
    local refund = 0
    if t.status == "lobby" and humanName and t.paidPlayers and t.paidPlayers[humanName] then
        refund = t.paidPlayers[humanName] or 0
    end
    Tournament.leave()
    return refund
end

function Tournament.finishTournament()
    local t = Tournament.active
    if not t then return nil end
    t.status = "finished"
    if t.system == "bracket" then
        local finalRound = t.rounds[t.totalRounds]
        if finalRound and finalRound[1] and finalRound[1].winner then
            t.champion = finalRound[1].winner
        end
    end
    if not t.champion then
        local lb = Tournament.getLeaderboard()
        t.champion = lb[1] and lb[1].name or t.hostName
    end
    return t.champion
end

function Tournament.getLeaderboard()
    local t = Tournament.active
    if not t then return {} end
    local list = {}
    for _, p in ipairs(t.players) do
        table.insert(list, p)
    end
    table.sort(list, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if a.wins ~= b.wins then return a.wins > b.wins end
        return a.name < b.name
    end)
    return list
end

function Tournament.leave()
    Tournament.active = nil
    Tournament.statusMsg = ""
end

return Tournament

