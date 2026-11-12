local BoardLogic = {}
BoardLogic.__index = BoardLogic

BoardLogic.SIZE = 4
BoardLogic.MAX_MOVES = 64
BoardLogic.COL_NAMES = { "a", "b", "c", "d" }
BoardLogic.ROW_NAMES = { "1", "2", "3", "4" }

BoardLogic.Player = {
    NONE  = 0,
    WHITE = 1, -- White starts first
    BLACK = 2  -- Black moves second
}

local function inBounds(x, y, z)
    return x >= 1 and x <= 4 and y >= 1 and y <= 4 and z >= 1 and z <= 4
end

local function describeDirectionKey(dx, dy, dz)
    local nonZero = (dx ~= 0 and 1 or 0) + (dy ~= 0 and 1 or 0) + (dz ~= 0 and 1 or 0)
    if nonZero == 1 then
        if dy ~= 0 then
            return "line_vertical"
        else
            return "line_horizontal"
        end
    elseif nonZero == 2 then
        if dy == 0 then
            return "line_diag_flat"
        else
            return "line_diag_vert"
        end
    else
        return "line_diag_3d"
    end
end

function BoardLogic.formatCoord(x, y, z)
    local col = BoardLogic.COL_NAMES[x] or "?"
    local row = BoardLogic.ROW_NAMES[z] or "?"
    return string.format("%s%s.%d", col, row, y)
end

function BoardLogic.new(ruleMode)
    local self = setmetatable({}, BoardLogic)
    self.ruleMode = (ruleMode == "free") and "free" or "standard"
    self.allWinningLines = self:_precomputeWinningLines()
    self:reset(self.ruleMode)
    return self
end

function BoardLogic:_precomputeWinningLines()
    local lines = {}
    local dirs = {}

    for dx = -1, 1 do
        for dy = -1, 1 do
            for dz = -1, 1 do
                if not (dx == 0 and dy == 0 and dz == 0) then
                    if dx > 0 or (dx == 0 and dy > 0) or (dx == 0 and dy == 0 and dz > 0) then
                        table.insert(dirs, { dx = dx, dy = dy, dz = dz })
                    end
                end
            end
        end
    end

    for x = 1, 4 do
        for y = 1, 4 do
            for z = 1, 4 do
                for _, d in ipairs(dirs) do
                    local ex = x + d.dx * 3
                    local ey = y + d.dy * 3
                    local ez = z + d.dz * 3
                    if inBounds(ex, ey, ez) then
                        table.insert(lines, {
                            coords = {
                                { x = x,          y = y,          z = z          },
                                { x = x + d.dx,   y = y + d.dy,   z = z + d.dz   },
                                { x = x + d.dx*2, y = y + d.dy*2, z = z + d.dz*2 },
                                { x = ex,         y = ey,         z = ez         }
                            },
                            lineTypeKey = describeDirectionKey(d.dx, d.dy, d.dz)
                        })
                    end
                end
            end
        end
    end

    return lines
end

function BoardLogic:reset(ruleMode)
    if ruleMode == "free" or ruleMode == "standard" then
        self.ruleMode = ruleMode
    end
    self.pegs = {}
    self.grid = {}
    for x = 1, 4 do
        self.pegs[x] = {}
        self.grid[x] = {}
        for y = 1, 4 do
            self.grid[x][y] = {}
        end
        for z = 1, 4 do
            self.pegs[x][z] = {}
        end
    end
    self.currentPlayer = BoardLogic.Player.WHITE
    self.winner = BoardLogic.Player.NONE
    self.isGameOver = false
    self.isDraw = false
    self.timeoutWinner = BoardLogic.Player.NONE
    self.winningLine = nil
    self.winningLineType = ""
    self.moveHistory = {}
end

function BoardLogic:canDrop(x, z)
    if self.isGameOver then return false end
    if x < 1 or x > 4 or z < 1 or z > 4 then return false end
    if self.ruleMode == "free" then
        for y = 1, 4 do
            if self:getCell(x, y, z) == BoardLogic.Player.NONE then
                return true
            end
        end
        return false
    end
    return #self.pegs[x][z] < 4
end

function BoardLogic:canPlace(x, y, z)
    if self.isGameOver then return false end
    if not inBounds(x, y, z) then return false end
    if self.ruleMode == "free" then
        return self:getCell(x, y, z) == BoardLogic.Player.NONE
    else
        return y == (#self.pegs[x][z] + 1)
    end
end

function BoardLogic:getPegHeight(x, z)
    return #self.pegs[x][z]
end

function BoardLogic:getNextEmptyY(x, z)
    if not inBounds(x, 1, z) then return nil end
    if self.ruleMode == "free" then
        for y = 1, 4 do
            if self:getCell(x, y, z) == BoardLogic.Player.NONE then
                return y
            end
        end
        return nil
    end
    local h = #self.pegs[x][z]
    return (h < 4) and (h + 1) or nil
end

function BoardLogic:getCell(x, y, z)
    if not inBounds(x, y, z) then
        return BoardLogic.Player.NONE
    end
    if self.ruleMode == "free" then
        return self.grid[x][y][z] or BoardLogic.Player.NONE
    end
    return self.pegs[x][z][y] or BoardLogic.Player.NONE
end

function BoardLogic:placePiece(x, y, z)
    if self.ruleMode ~= "free" then
        return self:dropPiece(x, z)
    end
    if not self:canPlace(x, y, z) then
        return { ok = false }
    end

    local movedPlayer = self.currentPlayer
    self.grid[x][y][z] = movedPlayer

    local notation = BoardLogic.formatCoord(x, y, z)
    local placedPos = {
        x = x,
        y = y,
        z = z,
        player = movedPlayer,
        notation = notation
    }
    table.insert(self.moveHistory, placedPos)

    if self:_checkWinForPlayer(movedPlayer) then
        self.winner = movedPlayer
        self.isGameOver = true
    elseif #self.moveHistory >= BoardLogic.MAX_MOVES then
        self.isDraw = true
        self.isGameOver = true
    else
        if self.currentPlayer == BoardLogic.Player.WHITE then
            self.currentPlayer = BoardLogic.Player.BLACK
        else
            self.currentPlayer = BoardLogic.Player.WHITE
        end
    end

    return {
        ok = true,
        player = movedPlayer,
        pos = placedPos,
        notation = notation,
        winner = self.winner,
        isDraw = self.isDraw,
        isGameOver = self.isGameOver,
        winningLine = self.winningLine,
        winningLineType = self.winningLineType
    }
end

function BoardLogic:dropPiece(x, z)
    if self.ruleMode == "free" then
        for y = 1, 4 do
            if self:canPlace(x, y, z) then
                return self:placePiece(x, y, z)
            end
        end
        return { ok = false }
    end
    if not self:canDrop(x, z) then
        return { ok = false }
    end

    local movedPlayer = self.currentPlayer
    table.insert(self.pegs[x][z], movedPlayer)
    local y = #self.pegs[x][z]
    self.grid[x][y][z] = movedPlayer

    local notation = BoardLogic.formatCoord(x, y, z)
    local placedPos = {
        x = x,
        y = y,
        z = z,
        player = movedPlayer,
        notation = notation
    }
    table.insert(self.moveHistory, placedPos)

    if self:_checkWinForPlayer(movedPlayer) then
        self.winner = movedPlayer
        self.isGameOver = true
    elseif #self.moveHistory >= BoardLogic.MAX_MOVES then
        self.isDraw = true
        self.isGameOver = true
    else
        if self.currentPlayer == BoardLogic.Player.WHITE then
            self.currentPlayer = BoardLogic.Player.BLACK
        else
            self.currentPlayer = BoardLogic.Player.WHITE
        end
    end

    return {
        ok = true,
        player = movedPlayer,
        pos = placedPos,
        notation = notation,
        winner = self.winner,
        isDraw = self.isDraw,
        isGameOver = self.isGameOver,
        winningLine = self.winningLine,
        winningLineType = self.winningLineType
    }
end

-- Returns chess-style paired moves: { { num = 1, white = "a1.1", black = "b2.1" }, ... }
function BoardLogic:getChessMovePairs()
    local pairsList = {}
    for i = 1, #self.moveHistory, 2 do
        local wMove = self.moveHistory[i]
        local bMove = self.moveHistory[i + 1]
        table.insert(pairsList, {
            num   = math.floor((i - 1) / 2) + 1,
            white = wMove and wMove.notation or "",
            black = bMove and bMove.notation or ""
        })
    end
    return pairsList
end

function BoardLogic:_checkWinForPlayer(player)
    for _, entry in ipairs(self.allWinningLines) do
        local matched = true
        for _, c in ipairs(entry.coords) do
            if self:getCell(c.x, c.y, c.z) ~= player then
                matched = false
                break
            end
        end
        if matched then
            self.winningLine = entry.coords
            self.winningLineType = entry.lineTypeKey
            return true
        end
    end
    return false
end

return BoardLogic
