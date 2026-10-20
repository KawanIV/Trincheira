-- src/estados/jogo.lua
local Jogo = {}

local CELL = 64
local COLS, ROWS = 16, 6   -- largo e baixo

local unidades = {}
local turnoAtual = 1
local selecionada = nil

function Jogo:load()
    unidades = {}
    turnoAtual = 1
    selecionada = nil

    -- facção 1 (jogador) na coluna 1, facção 2 (inimigo) na coluna COLS
    for i = 1, 3 do
        table.insert(unidades, {x=1,    y=i+1, hp=10, faccao=1, jaAgiu=false})
        table.insert(unidades, {x=COLS, y=i+1, hp=10, faccao=2, jaAgiu=false})
    end
end

function Jogo:update(dt)
end

local function unidadeEm(cx, cy)
    for _, u in ipairs(unidades) do
        if u.x == cx and u.y == cy and u.hp > 0 then return u end
    end
end

local function podeMover(u, dx, dy)
    local nx, ny = u.x + dx, u.y + dy
    if nx < 1 or nx > COLS or ny < 1 or ny > ROWS then return false end
    return unidadeEm(nx, ny) == nil
end

function Jogo:draw()
    -- grid
    love.graphics.setColor(1, 1, 1)
    for x = 0, COLS do
        love.graphics.line(x*CELL, 0, x*CELL, ROWS*CELL)
    end
    for y = 0, ROWS do
        love.graphics.line(0, y*CELL, COLS*CELL, y*CELL)
    end

    -- unidades
    for _, u in ipairs(unidades) do
        if u.hp > 0 then
            local cor = u.faccao == 1 and {0.2,0.4,0.9} or {0.9,0.2,0.2}
            if u.jaAgiu then cor = {0.5,0.5,0.5} end
            love.graphics.setColor(cor)
            love.graphics.rectangle("fill", (u.x-1)*CELL+4, (u.y-1)*CELL+4, CELL-8, CELL-8)
        end
    end

    -- seleção
    if selecionada then
        love.graphics.setColor(1,1,0)
        love.graphics.rectangle("line", (selecionada.x-1)*CELL, (selecionada.y-1)*CELL, CELL, CELL)
    end

    -- UI
    love.graphics.setColor(1,1,1)
    love.graphics.print("Turno: " .. (turnoAtual == 1 and "Jogador" or "Inimigo"), 10, ROWS*CELL + 10)
    love.graphics.print("Espaço = passar turno", 10, ROWS*CELL + 30)
end

function Jogo:mousepressed(mx, my, botao)
    local cx = math.floor(mx / CELL) + 1
    local cy = math.floor(my / CELL) + 1
    local alvo = unidadeEm(cx, cy)

    if alvo and alvo.faccao == turnoAtual and not alvo.jaAgiu then
        selecionada = alvo
    elseif selecionada and not alvo then
        local dx = math.max(-1, math.min(1, cx - selecionada.x))
        local dy = math.max(-1, math.min(1, cy - selecionada.y))
        if podeMover(selecionada, dx, dy) then
            selecionada.x = selecionada.x + dx
            selecionada.y = selecionada.y + dy
            selecionada.jaAgiu = true
            selecionada = nil
        end
    end
end

function Jogo:keypressed(tecla)
    if tecla == "space" then
        turnoAtual = (turnoAtual == 1) and 2 or 1
        for _, u in ipairs(unidades) do u.jaAgiu = false end
        selecionada = nil
    end
end

return Jogo