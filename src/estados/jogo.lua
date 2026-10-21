-- src/estados/jogo.lua
local Jogo = {}

local CELL = 64
local COLS, ROWS = 16, 6
local RANGE_TIRO = 3
local MOVIMENTO_PADRAO = 3
local MOVIMENTO_APOS_CAVAR = 1   -- no turno seguinte, quem cavou só anda 1

local PAINEL_H = 260
local GRID_OFFSET_Y = PAINEL_H

local unidades = {}
local turnoAtual = 1
local selecionada = nil
local vencedor = nil

local menuAberto = false
local modoMover = false
local cena = nil
local botoesMenu = {}

-- ========== PROJEÇÃO DE PERSPECTIVA ==========

-- Escala por profundidade: y=1 (fundo) menor, y=ROWS (frente) maior
local function escalaPorLinha(y)
    if ROWS <= 1 then return 1.0 end
    local t = (y - 1) / (ROWS - 1)   -- 0 no fundo, 1 na frente
    return 0.55 + 0.45 * t
end

-- Y na tela do painel superior para a faixa da linha y
local function yTelaDaLinha(y)
    -- margem vertical dentro do painel
    local margemTopo = PAINEL_H * 0.12
    local margemBase = PAINEL_H * 0.92
    local t = (y - 1) / math.max(ROWS - 1, 1)
    return margemTopo + (margemBase - margemTopo) * t
end

-- X na tela do painel superior para a coluna x na linha y
local function xTelaDaColuna(x, y)
    local larguraMax = love.graphics.getWidth() * 0.9
    local larguraFaixa = larguraMax * escalaPorLinha(y)
    local esquerda = (love.graphics.getWidth() - larguraFaixa) / 2
    local t = (x - 1) / math.max(COLS - 1, 1)
    return esquerda + larguraFaixa * t
end

-- Tamanho do quadrado na tela para a linha y
local function tamanhoNaLinha(y)
    return 44 * escalaPorLinha(y)
end

-- ========== LÓGICA ==========

function Jogo:load()
    unidades = {}
    turnoAtual = 1
    selecionada = nil
    vencedor = nil
    menuAberto = false
    modoMover = false
    cena = nil
    botoesMenu = {}

    for i = 1, 3 do
        table.insert(unidades, {
            x=1, y=i+1, hp=10, faccao=1, jaAgiu=false, entrincheirada=false,
            movimentoMax = MOVIMENTO_PADRAO,
            movimentoRestante = MOVIMENTO_PADRAO,
        })
        table.insert(unidades, {
            x=COLS, y=i+1, hp=10, faccao=2, jaAgiu=false, entrincheirada=false,
            movimentoMax = MOVIMENTO_PADRAO,
            movimentoRestante = MOVIMENTO_PADRAO,
        })
    end
end

-- distância de Manhattan entre duas células
local function distManhattan(ax, ay, bx, by)
    return math.abs(ax - bx) + math.abs(ay - by)
end

-- célula alcançável? dentro do grid, sem unidade, e dentro do orçamento
local function celulaAlcancavel(u, cx, cy)
    if cx < 1 or cx > COLS or cy < 1 or cy > ROWS then return false end
    if unidadeEm(cx, cy) then return false end
    return distManhattan(u.x, u.y, cx, cy) <= u.movimentoRestante
end

-- executa o movimento até (cx, cy), gastando orçamento
local function moverAte(u, cx, cy)
    local custo = distManhattan(u.x, u.y, cx, cy)
    if custo > u.movimentoRestante then return false end
    if unidadeEm(cx, cy) then return false end
    u.x = cx
    u.y = cy
    u.movimentoRestante = u.movimentoRestante - custo
    -- se acabou o movimento, a unidade não pode mais agir neste turno
    if u.movimentoRestante <= 0 then
        u.jaAgiu = true
    end
    return true
end

function Jogo:update(dt)
    if vencedor then return end

    if cena then
        cena.t = cena.t + dt
        if cena.t >= cena.duracao then
            if cena.tipo == "tiro" and cena.alvo then
                cena.alvo.hp = cena.alvo.hp - 3
            elseif cena.tipo == "carga" and cena.alvo then
                cena.alvo.hp = cena.alvo.hp - 5
            elseif cena.tipo == "cavar" and cena.atacante then
                cena.atacante.entrincheirada = true
            end
            if cena.atacante then cena.atacante.jaAgiu = true end
            cena = nil
            selecionada = nil
            menuAberto = false
            modoMover = false
        end
        return
    end

    local vivos1, vivos2 = 0, 0
    for _, u in ipairs(unidades) do
        if u.hp > 0 then
            if u.faccao == 1 then vivos1 = vivos1 + 1
            else vivos2 = vivos2 + 1 end
        end
    end
    if vivos1 == 0 then vencedor = 2
    elseif vivos2 == 0 then vencedor = 1 end
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

local function alvoNoRangeTiro(atacante, alvo)
    if atacante.x ~= alvo.x and atacante.y ~= alvo.y then return false end
    local dist = math.abs(atacante.x - alvo.x) + math.abs(atacante.y - alvo.y)
    if dist > RANGE_TIRO or dist == 0 then return false end
    local dx = (alvo.x > atacante.x) and 1 or (alvo.x < atacante.x and -1 or 0)
    local dy = (alvo.y > atacante.y) and 1 or (alvo.y < atacante.y and -1 or 0)
    local cx, cy = atacante.x + dx, atacante.y + dy
    while cx ~= alvo.x or cy ~= alvo.y do
        if unidadeEm(cx, cy) then return false end
        cx, cy = cx + dx, cy + dy
    end
    return true
end

local function temInimigoAdjacente(u)
    for _, o in ipairs(unidades) do
        if o.hp > 0 and o.faccao ~= u.faccao
           and math.abs(o.x - u.x) <= 1 and math.abs(o.y - u.y) <= 1 then
            return true
        end
    end
    return false
end

local function inimigoNoRangeTiro(u)
    for _, o in ipairs(unidades) do
        if o.hp > 0 and o.faccao ~= u.faccao and alvoNoRangeTiro(u, o) then
            return true
        end
    end
    return false
end

local function calcularBotoesMenu(u)
    botoesMenu = {}
    local cx = (u.x - 1) * CELL + CELL/2
    local cy = (u.y - 1) * CELL + CELL/2 + GRID_OFFSET_Y
    local off = CELL * 0.9

    local candidatos = {
        {id="mover", label="Mover", dx=0,  dy=-1, sempre=true},
        {id="carga", label="Carga", dx=0,  dy=1,  valido=temInimigoAdjacente(u)},
        {id="tiro",  label="Tiro",  dx=-1, dy=0,  valido=inimigoNoRangeTiro(u)},
        {id="cavar", label="Cavar", dx=1,  dy=0,  sempre=true},
    }

    for _, c in ipairs(candidatos) do
        table.insert(botoesMenu, {
            id = c.id,
            label = c.label,
            x = cx + c.dx * off,
            y = cy + c.dy * off,
            w = 60, h = 28,
            habilitado = c.sempre or c.valido,
        })
    end
end

-- ========== DESENHO DO PAINEL SUPERIOR (MIRROR COM PERSPECTIVA) ==========

local function desenharPainelSuperior()
    -- céu e chão
    love.graphics.setColor(0.55, 0.65, 0.75)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), PAINEL_H)
    love.graphics.setColor(0.35, 0.45, 0.30)
    love.graphics.rectangle("fill", 0, PAINEL_H * 0.5, love.graphics.getWidth(), PAINEL_H * 0.5)

    -- faixas de profundidade (linhas guias)
    for y = 1, ROWS do
        local yTela = yTelaDaLinha(y)
        local x1 = xTelaDaColuna(1, y)
        local x2 = xTelaDaColuna(COLS, y)
        love.graphics.setColor(1, 1, 1, 0.15)
        love.graphics.line(x1, yTela, x2, yTela)
    end

    -- projeta todas as unidades do grid (incluindo as que estão na cena de ação)
    for _, u in ipairs(unidades) do
        if u.hp > 0 then
            local px = xTelaDaColuna(u.x, u.y)
            local py = yTelaDaLinha(u.y)
            local tam = tamanhoNaLinha(u.y)

            -- se a unidade é o atacante de uma carga, desloca na animação
            if cena and cena.tipo == "carga" and cena.atacante == u and cena.alvo then
                local progresso = math.min(cena.t / cena.duracao, 1)
                local ax = xTelaDaColuna(cena.atacante.x, cena.atacante.y)
                local ay = yTelaDaLinha(cena.atacante.y)
                local bx = xTelaDaColuna(cena.alvo.x, cena.alvo.y)
                local by = yTelaDaLinha(cena.alvo.y)
                px = ax + (bx - ax) * progresso
                py = ay + (by - ay) * progresso
            end

            local cor = u.faccao == 1 and {0.2,0.4,0.9} or {0.9,0.2,0.2}
            if u.jaAgiu then cor = {0.5,0.5,0.5} end
            love.graphics.setColor(cor)
            love.graphics.rectangle("fill", px - tam/2, py - tam/2, tam, tam)

            if u.entrincheirada then
                love.graphics.setColor(0.5, 0.35, 0.15)
                love.graphics.rectangle("line", px - tam/2 - 3, py - tam/2 - 3, tam + 6, tam + 6)
            end

            love.graphics.setColor(1,1,1)
            love.graphics.print(tostring(u.hp), px - tam/2 + 2, py - tam/2)
        end
    end

    -- projétil do tiro: viaja entre as posições projetadas reais
    if cena and cena.tipo == "tiro" and cena.atacante and cena.alvo then
        local progresso = math.min(cena.t / cena.duracao, 1)
        local ax = xTelaDaColuna(cena.atacante.x, cena.atacante.y)
        local ay = yTelaDaLinha(cena.atacante.y)
        local bx = xTelaDaColuna(cena.alvo.x, cena.alvo.y)
        local by = yTelaDaLinha(cena.alvo.y)
        local px = ax + (bx - ax) * progresso
        local py = ay + (by - ay) * progresso
        love.graphics.setColor(1,1,0)
        love.graphics.circle("fill", px, py, 6)
    end

    -- terra subindo na cova (cavar)
    if cena and cena.tipo == "cavar" and cena.atacante then
        local progresso = math.min(cena.t / cena.duracao, 1)
        local px = xTelaDaColuna(cena.atacante.x, cena.atacante.y)
        local py = yTelaDaLinha(cena.atacante.y)
        local tam = tamanhoNaLinha(cena.atacante.y)
        love.graphics.setColor(0.5, 0.35, 0.15)
        love.graphics.rectangle("fill", px - tam/2, py + tam/2 - tam * progresso, tam, tam * progresso)
    end

    love.graphics.setColor(1,1,1)
    love.graphics.print("Painel superior (perspectiva) - espelho do grid", 10, 10)
end

function Jogo:draw()
    desenharPainelSuperior()

    -- painel tático
    love.graphics.push()
    love.graphics.translate(0, GRID_OFFSET_Y)

    love.graphics.setColor(1, 1, 1)
    for x = 0, COLS do
        love.graphics.line(x*CELL, 0, x*CELL, ROWS*CELL)
    end
    for y = 0, ROWS do
        love.graphics.line(0, y*CELL, COLS*CELL, y*CELL)
    end

    if selecionada and not menuAberto then
        love.graphics.setColor(1, 1, 0, 0.15)
        for _, u in ipairs(unidades) do
            if u.hp > 0 and u.faccao ~= selecionada.faccao and alvoNoRangeTiro(selecionada, u) then
                love.graphics.rectangle("fill", (u.x-1)*CELL, (u.y-1)*CELL, CELL, CELL)
            end
        end
    end

    if modoMover and selecionada then
        love.graphics.setColor(0, 1, 0, 0.2)
        for _, d in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
            local nx, ny = selecionada.x + d[1], selecionada.y + d[2]
            if nx >= 1 and nx <= COLS and ny >= 1 and ny <= ROWS and not unidadeEm(nx, ny) then
                love.graphics.rectangle("fill", (nx-1)*CELL, (ny-1)*CELL, CELL, CELL)
            end
        end
    end

    for _, u in ipairs(unidades) do
        if u.hp > 0 then
            local cor = u.faccao == 1 and {0.2,0.4,0.9} or {0.9,0.2,0.2}
            if u.jaAgiu then cor = {0.5,0.5,0.5} end
            love.graphics.setColor(cor)
            love.graphics.rectangle("fill", (u.x-1)*CELL+4, (u.y-1)*CELL+4, CELL-8, CELL-8)
            if u.entrincheirada then
                love.graphics.setColor(0.5, 0.35, 0.15)
                love.graphics.rectangle("line", (u.x-1)*CELL+2, (u.y-1)*CELL+2, CELL-4, CELL-4)
            end
            love.graphics.setColor(1,1,1)
            love.graphics.print(tostring(u.hp), (u.x-1)*CELL+6, (u.y-1)*CELL+4)
        end
    end

    if selecionada then
        love.graphics.setColor(1,1,0)
        love.graphics.rectangle("line", (selecionada.x-1)*CELL, (selecionada.y-1)*CELL, CELL, CELL)
    end

    love.graphics.pop()

    -- botões do menu ao redor da unidade
    if menuAberto and selecionada then
        for _, b in ipairs(botoesMenu) do
            love.graphics.setColor(b.habilitado and {0.2,0.2,0.2,0.9} or {0.15,0.15,0.15,0.6})
            love.graphics.rectangle("fill", b.x - b.w/2, b.y - b.h/2, b.w, b.h, 4)
            love.graphics.setColor(b.habilitado and {1,1,1} or {0.5,0.5,0.5})
            love.graphics.rectangle("line", b.x - b.w/2, b.y - b.h/2, b.w, b.h, 4)
            love.graphics.printf(b.label, b.x - b.w/2, b.y - 8, b.w, "center")
        end
    end

    -- UI inferior
    love.graphics.setColor(1,1,1)
    if vencedor then
        love.graphics.print(vencedor == 1 and "Jogador venceu!" or "Inimigo venceu!",
            10, GRID_OFFSET_Y + ROWS*CELL + 10)
    else
        love.graphics.print("Turno: " .. (turnoAtual == 1 and "Jogador" or "Inimigo"),
            10, GRID_OFFSET_Y + ROWS*CELL + 10)
        if modoMover then
            love.graphics.print("Clique numa célula verde para mover | ESC cancela",
                10, GRID_OFFSET_Y + ROWS*CELL + 30)
        else
            love.graphics.print("Clique numa unidade para abrir ações | Espaço = passar turno",
                10, GRID_OFFSET_Y + ROWS*CELL + 30)
        end
    end
end

function Jogo:mousepressed(mx, my, botao)
    if vencedor or cena then return end

    if menuAberto and selecionada then
        for _, b in ipairs(botoesMenu) do
            if mx >= b.x - b.w/2 and mx <= b.x + b.w/2
               and my >= b.y - b.h/2 and my <= b.y + b.h/2 then
                if b.habilitado then
                    if b.id == "mover" then
                        modoMover = true
                        menuAberto = false
                    elseif b.id == "cavar" then
                        cena = {tipo="cavar", atacante=selecionada, alvo=nil, t=0, duracao=0.8}
                        menuAberto = false
                    elseif b.id == "carga" then
                        local alvo = nil
                        for _, o in ipairs(unidades) do
                            if o.hp > 0 and o.faccao ~= selecionada.faccao
                               and math.abs(o.x - selecionada.x) <= 1
                               and math.abs(o.y - selecionada.y) <= 1 then
                                alvo = o; break
                            end
                        end
                        cena = {tipo="carga", atacante=selecionada, alvo=alvo, t=0, duracao=0.8}
                        menuAberto = false
                    elseif b.id == "tiro" then
                        local alvo = nil
                        for _, o in ipairs(unidades) do
                            if o.hp > 0 and o.faccao ~= selecionada.faccao
                               and alvoNoRangeTiro(selecionada, o) then
                                alvo = o; break
                            end
                        end
                        cena = {tipo="tiro", atacante=selecionada, alvo=alvo, t=0, duracao=0.8}
                        menuAberto = false
                    end
                end
                return
            end
        end
        menuAberto = false
        selecionada = nil
        return
    end

    if my < GRID_OFFSET_Y then return end
    local cx = math.floor(mx / CELL) + 1
    local cy = math.floor((my - GRID_OFFSET_Y) / CELL) + 1
    local alvo = unidadeEm(cx, cy)

    if modoMover and selecionada then
        local dx = math.max(-1, math.min(1, cx - selecionada.x))
        local dy = math.max(-1, math.min(1, cy - selecionada.y))
        if podeMover(selecionada, dx, dy) then
            selecionada.x = selecionada.x + dx
            selecionada.y = selecionada.y + dy
            selecionada.jaAgiu = true
            selecionada = nil
            modoMover = false
        end
        return
    end

    if alvo and alvo.faccao == turnoAtual and not alvo.jaAgiu then
        selecionada = alvo
        menuAberto = true
        modoMover = false
        calcularBotoesMenu(alvo)
        return
    end
end

function Jogo:keypressed(tecla)
    if tecla == "escape" then
        menuAberto = false
        modoMover = false
        selecionada = nil
        return
    end
    if tecla == "space" and not vencedor and not cena and not menuAberto and not modoMover then
        turnoAtual = (turnoAtual == 1) and 2 or 1
        for _, u in ipairs(unidades) do
            u.jaAgiu = false
            -- quem cavou no turno anterior começa com menos movimento
            if u.entrincheirada then
                u.movimentoRestante = MOVIMENTO_APOS_CAVAR
                u.entrincheirada = false   -- consome o efeito (opcional: manter a trincheira visual?)
            else
                u.movimentoRestante = MOVIMENTO_PADRAO
            end
        end
        selecionada = nil
    end
end

return Jogo