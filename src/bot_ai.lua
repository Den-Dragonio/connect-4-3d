local BoardLogic = require("src.board_logic")
local Config     = require("src.config")

local BotAI = {}

local WIN_SCORE = 100000

local function getValidMoves(logic)
    local moves = {}
    for x = 1, 4 do
        for z = 1, 4 do
            if logic:canDrop(x, z) then
                table.insert(moves, { x = x, z = z })
            end
        end
    end
    return moves
end

local function wouldMoveWin(logic, x, z, player)
    local stack = logic.pegs[x][z]
    if #stack >= 4 then return false end
    table.insert(stack, player)
    local wins = logic:_checkWinForPlayer(player)
    table.remove(stack)
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

    if maximizing then
        local value = -9999999
        for _, m in ipairs(moves) do
            local stack = logic.pegs[m.x][m.z]
            table.insert(stack, botPlayer)
            local s
            if logic:_checkWinForPlayer(botPlayer) then
                s = WIN_SCORE + depth * 100
                logic.winningLine = nil
                logic.winningLineType = ""
            else
                s = alphabeta(logic, depth - 1, alpha, beta, false, botPlayer, humanPlayer)
            end
            table.remove(stack)

            if s > value then value = s end
            if value > alpha then alpha = value end
            if alpha >= beta then break end
        end
        return value
    else
        local value = 9999999
        for _, m in ipairs(moves) do
            local stack = logic.pegs[m.x][m.z]
            table.insert(stack, humanPlayer)
            local s
            if logic:_checkWinForPlayer(humanPlayer) then
                s = -WIN_SCORE - depth * 100
                logic.winningLine = nil
                logic.winningLineType = ""
            else
                s = alphabeta(logic, depth - 1, alpha, beta, true, botPlayer, humanPlayer)
            end
            table.remove(stack)

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
        if wouldMoveWin(logic, m.x, m.z, botPlayer) then
            return m
        end
    end

    -- 2. Легкая сложность: с вероятностью 55% блокирует победный ход игрока, иначе случайный ход
    if difficulty == Config.BotDifficulty.EASY then
        if love.math.random() < 0.55 then
            for _, m in ipairs(validMoves) do
                if wouldMoveWin(logic, m.x, m.z, humanPlayer) then
                    return m
                end
            end
        end
        return validMoves[love.math.random(1, #validMoves)]
    end

    -- 3. На Средней и Сложной всегда блокируем немедленную угрозу 4-в-ряд соперника
    for _, m in ipairs(validMoves) do
        if wouldMoveWin(logic, m.x, m.z, humanPlayer) then
            return m
        end
    end

    -- 4. Поиск лучшего хода с оценкой 76 линий (глубина 2 для Среднего, глубина 3 для Сложного)
    local searchDepth = (difficulty == Config.BotDifficulty.HARD) and 3 or 2

    -- Сортируем ходы ближе к центру куба для лучшего отсечения
    table.sort(validMoves, function(a, b)
        local da = math.abs(a.x - 2.5) + math.abs(a.z - 2.5)
        local db = math.abs(b.x - 2.5) + math.abs(b.z - 2.5)
        return da < db
    end)

    local bestScore = -9999999
    local bestMoves = {}

    for _, m in ipairs(validMoves) do
        local stack = logic.pegs[m.x][m.z]
        table.insert(stack, botPlayer)
        local score = alphabeta(logic, searchDepth - 1, -9999999, 9999999, false, botPlayer, humanPlayer)
        table.remove(stack)

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

