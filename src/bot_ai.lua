local BoardLogic = require("src.board_logic")
local Config     = require("src.config")

local BotAI = {}

local WIN_SCORE = 100000

local function getValidMoves(logic)
    local moves = {}
    if logic.ruleMode == "free" then
        for x = 1, 4 do
            for y = 1, 4 do
                for z = 1, 4 do
                    if logic:canPlace(x, y, z) then
                        table.insert(moves, { x = x, y = y, z = z })
                    end
                end
            end
        end
    else
        for x = 1, 4 do
            for z = 1, 4 do
                if logic:canDrop(x, z) then
                    table.insert(moves, { x = x, y = #logic.pegs[x][z] + 1, z = z })
                end
            end
        end
    end
    return moves
end

local function pushTempMove(logic, m, player)
    if logic.ruleMode == "free" then
        logic.grid[m.x][m.y][m.z] = player
    else
        table.insert(logic.pegs[m.x][m.z], player)
    end
end

local function popTempMove(logic, m)
    if logic.ruleMode == "free" then
        logic.grid[m.x][m.y][m.z] = BoardLogic.Player.NONE
    else
        table.remove(logic.pegs[m.x][m.z])
    end
end

local function wouldMoveWin(logic, m, player)
    if not logic:canPlace(m.x, m.y, m.z) then return false end
    pushTempMove(logic, m, player)
    local wins = logic:_checkWinForPlayer(player)
    popTempMove(logic, m)
    logic.winningLine = nil
    logic.winningLineType = ""
    return wins
end

-- Оценка всех 76 выигрышных линий куба 4x4x4
local function evaluateBoard(logic, botPlayer, humanPlayer)
    local score = 0
    for _, entry in ipairs(logic.allWinningLines) do
        local botCount = 0
        local humanCount = 0
        for _, c in ipairs(entry.coords) do
            local cell = logic:getCell(c.x, c.y, c.z)
            if cell == botPlayer then
                botCount = botCount + 1
            elseif cell == humanPlayer then
                humanCount = humanCount + 1
            end
        end

        if botCount > 0 and humanCount == 0 then
            if botCount == 1 then score = score + 2
            elseif botCount == 2 then score = score + 18
            elseif botCount == 3 then score = score + 170
            elseif botCount == 4 then score = score + WIN_SCORE end
        elseif humanCount > 0 and botCount == 0 then
            if humanCount == 1 then score = score - 2
            elseif humanCount == 2 then score = score - 22
            elseif humanCount == 3 then score = score - 210
            elseif humanCount == 4 then score = score - WIN_SCORE end
        end
    end
    return score
end

local function alphabeta(logic, depth, alpha, beta, maximizing, botPlayer, humanPlayer)
    if depth <= 0 then
        return evaluateBoard(logic, botPlayer, humanPlayer)
    end

    local moves = getValidMoves(logic)
    if #moves == 0 then
        return 0
    end

    local maxBranch = (logic.ruleMode == "free") and 16 or #moves
    if maximizing then
        local value = -9999999
        for i = 1, math.min(#moves, maxBranch) do
            local m = moves[i]
            pushTempMove(logic, m, botPlayer)
            local s
            if logic:_checkWinForPlayer(botPlayer) then
                s = WIN_SCORE + depth * 100
                logic.winningLine = nil
                logic.winningLineType = ""
            else
                s = alphabeta(logic, depth - 1, alpha, beta, false, botPlayer, humanPlayer)
            end
            popTempMove(logic, m)

            if s > value then value = s end
            if value > alpha then alpha = value end
            if alpha >= beta then break end
        end
        return value
    else
        local value = 9999999
        for i = 1, math.min(#moves, maxBranch) do
            local m = moves[i]
            pushTempMove(logic, m, humanPlayer)
            local s
            if logic:_checkWinForPlayer(humanPlayer) then
                s = -WIN_SCORE - depth * 100
                logic.winningLine = nil
                logic.winningLineType = ""
            else
                s = alphabeta(logic, depth - 1, alpha, beta, true, botPlayer, humanPlayer)
            end
            popTempMove(logic, m)

            if s < value then value = s end
            if value < beta then beta = value end
            if beta <= alpha then break end
        end
        return value
    end
end

function BotAI.chooseMove(logic, difficulty)
    local validMoves = getValidMoves(logic)
    if #validMoves == 0 then return nil end

    local botPlayer = logic.currentPlayer
    local humanPlayer = (botPlayer == BoardLogic.Player.WHITE)
        and BoardLogic.Player.BLACK
        or  BoardLogic.Player.WHITE

    -- 1. Если бот может победить одним ходом — всегда выигрываем
    for _, m in ipairs(validMoves) do
        if wouldMoveWin(logic, m, botPlayer) then
            return m
        end
    end

    -- 2. Легкая сложность: с вероятностью 55% блокирует победный ход игрока, иначе случайный ход
    if difficulty == Config.BotDifficulty.EASY then
        if love.math.random() < 0.55 then
            for _, m in ipairs(validMoves) do
                if wouldMoveWin(logic, m, humanPlayer) then
                    return m
                end
            end
        end
        return validMoves[love.math.random(1, #validMoves)]
    end

    -- 3. На Средней и Сложной всегда блокируем немедленную угрозу 4-в-ряд соперника
    for _, m in ipairs(validMoves) do
        if wouldMoveWin(logic, m, humanPlayer) then
            return m
        end
    end

    -- 4. Поиск лучшего хода с оценкой 76 линий
    local searchDepth = (difficulty == Config.BotDifficulty.HARD) and ((logic.ruleMode == "free") and 2 or 3) or 2

    -- Сортируем ходы ближе к центру куба для лучшего отсечения
    table.sort(validMoves, function(a, b)
        local da = math.abs(a.x - 2.5) + math.abs((a.y or 2.5) - 2.5) + math.abs(a.z - 2.5)
        local db = math.abs(b.x - 2.5) + math.abs((b.y or 2.5) - 2.5) + math.abs(b.z - 2.5)
        return da < db
    end)

    local bestScore = -9999999
    local bestMoves = {}
    local maxRoot = (logic.ruleMode == "free") and 24 or #validMoves

    for i = 1, math.min(#validMoves, maxRoot) do
        local m = validMoves[i]
        pushTempMove(logic, m, botPlayer)
        local score = alphabeta(logic, searchDepth - 1, -9999999, 9999999, false, botPlayer, humanPlayer)
        popTempMove(logic, m)

        if score > bestScore then
            bestScore = score
            bestMoves = { m }
        elseif score == bestScore then
            table.insert(bestMoves, m)
        end
    end

    if #bestMoves > 0 then
        return bestMoves[love.math.random(1, #bestMoves)]
    end
    return validMoves[1]
end

return BotAI

