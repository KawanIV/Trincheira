-- src/estados/jogo.lua
local Jogo = {}

local CELL = 64
local COLS, ROWS = 16, 6
local RANGE_TIRO = 3
local MOVIMENTO_PADRAO = 3
local MOVIMENTO_NA_TRINCHEIRA = 1
local DANO_TIRO = 3
local DANO_CARGA = 5

local PAINEL_H = 260
local GRID_OFFSET_Y = PAINEL_H

local unidades = {}
local trincheiras = {}
local turnoAtual = 1
local selecionada = nil
local vencedor = nil

local menuAberto = false
local modoMover = false
local modoCarga = false
local cena = nil
local botoesMenu = {}

local resolvendo = false
local filaResolucao = {}
local indiceResolucao = 0

-- NOVO: Variáveis para o Sprite
local spriteSheet
local quads = {}

-- ========== PROJEÇÃO ==========
local function escalaPorLinha(y)
    if ROWS <= 1 then return 1.0 end
    local t = (y - 1) / (ROWS - 1)
    return 0.55 + 0.45 * t
end

local function yTelaDaLinha(y)
    local margemTopo = PAINEL_H * 0.12
    local margemBase = PAINEL_H * 0.92
    local t = (y - 1) / math.max(ROWS - 1, 1)
    return margemTopo + (margemBase - margemTopo) * t
end

local function xTelaDaColuna(x, y)
    local larguraMax = love.graphics.getWidth() * 0.9
    local larguraFaixa = larguraMax * escalaPorLinha(y)
    local esquerda = (love.graphics.getWidth() - larguraFaixa) / 2
    local t = (x - 1) / math.max(COLS - 1, 1)
    return esquerda + larguraFaixa * t
end

local function tamanhoNaLinha(y)
    return 44 * escalaPorLinha(y)
end

-- ========== TRINCHEIRAS ==========
local function temTrincheira(cx, cy)
    return trincheiras[cy] and trincheiras[cy][cx] == true
end

local function marcarTrincheira(cx, cy)
    trincheiras[cy] = trincheiras[cy] or {}
    trincheiras[cy][cx] = true
end

-- ========== HELPERS ==========
local function unidadeEm(cx, cy)
    for _, u in ipairs(unidades) do
        if u.x == cx and u.y == cy and u.hp > 0 then return u end
    end
end

local function distManhattan(ax, ay, bx, by)
    return math.abs(ax - bx) + math.abs(ay - by)
end

local function celulaAlcancavel(u, cx, cy)
    if cx < 1 or cx > COLS or cy < 1 or cy > ROWS then return false end
    if unidadeEm(cx, cy) then return false end
    return distManhattan(u.x, u.y, cx, cy) <= u.movimentoRestante
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
        {id="carga", label="Carga", dx=0,  dy=1,  sempre=true},
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

local function temOrdem(u)
    return u.ordem ~= nil
end

-- ========== LOAD / UPDATE ==========
function Jogo:load()
    unidades = {}
    trincheiras = {}
    turnoAtual = 1
    selecionada = nil
    vencedor = nil
    menuAberto = false
    modoMover = false
    modoCarga = false
    cena = nil
    botoesMenu = {}
    resolvendo = false
    filaResolucao = {}
    indiceResolucao = 0

    -- NOVO: Carrega a imagem e define os quadros
    -- Certifique-se de que a pasta 'assets' e a imagem 'infantaria.png' existam!
    spriteSheet = love.graphics.newImage("assets/imagens/infantariaalema.jpg")
    local w, h = 76, 76 -- Tamanho estimado de cada sprite
    local imgW, imgH = spriteSheet:getDimensions()
    
    quads.parado = love.graphics.newQuad(5, 0, w, h, imgW, imgH)
    quads.andando = love.graphics.newQuad(w, h, w, h, imgW, imgH) -- Ajuste as coordenadas conforme a imagem real

    for i = 1, 3 do
        table.insert(unidades, {
            x=1, y=i+1, hp=10, faccao=1, jaAgiu=false,
            movimentoMax = MOVIMENTO_PADRAO,
            movimentoRestante = MOVIMENTO_PADRAO,
            ordem = nil,
        })
        table.insert(unidades, {
            x=COLS, y=i+1, hp=10, faccao=2, jaAgiu=false,
            movimentoMax = MOVIMENTO_PADRAO,
            movimentoRestante = MOVIMENTO_PADRAO,
            ordem = nil,
        })
    end
end

local function montarFila()
    filaResolucao = {}
    for _, u in ipairs(unidades) do
        if u.hp > 0 and u.faccao == 1 and u.ordem then
            table.insert(filaResolucao, u)
        end
    end
    for _, u in ipairs(unidades) do
        if u.hp > 0 and u.faccao == 2 and u.ordem then
            table.insert(filaResolucao, u)
        end
    end
    indiceResolucao = 0
end

local function aplicarOrdem(u, o)
    if o.tipo == "mover" then
        local custo = distManhattan(u.x, u.y, o.x, o.y)
        u.x, u.y = o.x, o.y
        u.movimentoRestante = math.max(0, u.movimentoRestante - custo)
        u.jaAgiu = true
    elseif o.tipo == "cavar" then
        marcarTrincheira(u.x, u.y)
        u.jaAgiu = true
    elseif o.tipo == "tiro" and o.alvo and o.alvo.hp > 0 then
        if not temTrincheira(o.alvo.x, o.alvo.y) then
            o.alvo.hp = o.alvo.hp - DANO_TIRO
        end
        u.jaAgiu = true
    elseif o.tipo == "carga" then
        local dx = (o.x > u.x) and 1 or (o.x < u.x and -1 or 0)
        local dy = (o.y > u.y) and 1 or (o.y < u.y and -1 or 0)
        if dx == 0 and dy == 0 then u.jaAgiu = true; return end
        local cx, cy = u.x + dx, u.y + dy
        while cx >= 1 and cx <= COLS and cy >= 1 and cy <= ROWS do
            local alvo = unidadeEm(cx, cy)
            if alvo and alvo.faccao ~= u.faccao then
                alvo.hp = alvo.hp - DANO_CARGA
                break
            elseif alvo then
                break
            end
            u.x, u.y = cx, cy
            if cx == o.x and cy == o.y then break end
            cx, cy = cx + dx, cy + dy
        end
        u.jaAgiu = true
    end
    u.ordem = nil
end

local function avancarResolucao()
    indiceResolucao = indiceResolucao + 1
    local u = filaResolucao[indiceResolucao]
    if not u then
        resolvendo = false
        turnoAtual = (turnoAtual == 1) and 2 or 1
        for _, un in ipairs(unidades) do
            un.jaAgiu = false
            if temTrincheira(un.x, un.y) then
                un.movimentoRestante = MOVIMENTO_NA_TRINCHEIRA
            else
                un.movimentoRestante = MOVIMENTO_PADRAO
            end
            un.ordem = nil
        end
        selecionada = nil
        return
    end
    if u.ordem then
        local tipo = u.ordem.tipo
        local alvo = u.ordem.alvo
        cena = {tipo=tipo, atacante=u, alvo=alvo, t=0, duracao=0.6, ordem=u.ordem}
    else
        aplicarOrdem(u, u.ordem)
    end
end

function Jogo:update(dt)
    if vencedor then return end

    if resolvendo then
        if cena then
            cena.t = cena.t + dt
            if cena.t >= cena.duracao then
                if cena.ordem then
                    aplicarOrdem(cena.atacante, cena.ordem)
                end
                cena = nil
                avancarResolucao()
            end
        else
            avancarResolucao()
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

-- ========== DESENHO ==========
local function desenharTrincheirasSuperior()
    for cy, linha in pairs(trincheiras) do
        for cx, _ in pairs(linha) do
            local px = xTelaDaColuna(cx, cy)
            local py = yTelaDaLinha(cy)
            local tam = tamanhoNaLinha(cy)
            love.graphics.setColor(0.4, 0.28, 0.12, 0.85)
            love.graphics.rectangle("fill", px - tam/2, py - tam/2, tam, tam)
            love.graphics.setColor(0.5, 0.35, 0.15)
            love.graphics.rectangle("line", px - tam/2, py - tam/2, tam, tam)
        end
    end
end

local function desenharPainelSuperior()
    -- Céu com gradiente (amarelo/laranja)
    love.graphics.setColor(0.9, 0.8, 0.5)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), PAINEL_H * 0.6)
    -- Chão (terra escura)
    love.graphics.setColor(0.2, 0.15, 0.1)
    love.graphics.rectangle("fill", 0, PAINEL_H * 0.6, love.graphics.getWidth(), PAINEL_H * 0.4)

    -- Árvores/silhuetas no fundo
    love.graphics.setColor(0.1, 0.1, 0.1, 0.3)
    love.graphics.circle("fill", 150, PAINEL_H * 0.5, 80)
    love.graphics.rectangle("fill", 140, PAINEL_H * 0.5, 20, 100)

    desenharTrincheirasSuperior()

    -- Desenha as unidades do FUNDO para a FRENTE
    for cy = 1, ROWS do
        for _, u in ipairs(unidades) do
            if u.hp > 0 and u.y == cy then
                local px = xTelaDaColuna(u.x, u.y)
                local py = yTelaDaLinha(u.y)
                local escala = escalaPorLinha(u.y)

                if cena and cena.tipo == "carga" and cena.atacante == u and cena.ordem then
                    local progresso = math.min(cena.t / cena.duracao, 1)
                    local o = cena.ordem
                    local ax = xTelaDaColuna(u.x, u.y)
                    local ay = yTelaDaLinha(u.y)
                    local bx = xTelaDaColuna(o.x, o.y)
                    local by = yTelaDaLinha(o.y)
                    px = ax + (bx - ax) * progresso
                    py = ay + (by - ay) * progresso
                end

                local sombra = 1 - (escala - 0.55) * 0.8
                local alpha = 0.4 + (escala - 0.55) * 1.33
                
                if u.jaAgiu then
                    sombra = sombra * 0.6
                end

                -- NOVO: Desenho do Sprite no lugar do quadrado
                love.graphics.setColor(0.9 * sombra, 0.8 * sombra, 0.6 * sombra, alpha)
                
                local escalaX = (u.faccao == 1) and escala or -escala
                local escalaY = escala
                
                -- Usa o quadro 'parado' por padrão
                love.graphics.draw(spriteSheet, quads.parado, px, py, 0, escalaX, escalaY, 38, 38)

                if temOrdem(u) then
                    love.graphics.setColor(0, 1, 1, alpha)
                    local tam = 44 * escala
                    love.graphics.rectangle("line", px - tam/2, py - tam/2, tam, tam)
                end

                if escala > 0.8 or u.hp < 5 then
                    love.graphics.setColor(1, 1, 1, alpha)
                    love.graphics.print(tostring(u.hp), px - 16 * escala, py - 24 * escala)
                end
            end
        end
    end

    -- Projétil de tiro
    if cena and cena.tipo == "tiro" and cena.atacante and cena.alvo then
        local progresso = math.min(cena.t / cena.duracao, 1)
        local ax = xTelaDaColuna(cena.atacante.x, cena.atacante.y)
        local ay = yTelaDaLinha(cena.atacante.y)
        local bx = xTelaDaColuna(cena.alvo.x, cena.alvo.y)
        local by = yTelaDaLinha(cena.alvo.y)
        local px = ax + (bx - ax) * progresso
        local py = ay + (by - ay) * progresso
        
        love.graphics.setColor(1, 1, 0, 0.8)
        love.graphics.circle("fill", px, py, 4)
    end

    -- Terra subindo no cavar
    if cena and cena.tipo == "cavar" and cena.atacante then
        local progresso = math.min(cena.t / cena.duracao, 1)
        local px = xTelaDaColuna(cena.atacante.x, cena.atacante.y)
        local py = yTelaDaLinha(cena.atacante.y)
        local tam = tamanhoNaLinha(cena.atacante.y)
        love.graphics.setColor(0.5, 0.35, 0.15)
        love.graphics.rectangle("fill", px - tam/2, py + tam/2 - tam * progresso, tam, tam * progresso)
    end

    love.graphics.setColor(1,1,1, 0.7)
    love.graphics.print("Painel de Batalha", 10, 10)
end

local function desenharRotas()
    for _, u in ipairs(unidades) do
        if u.hp > 0 and u.ordem and (u.ordem.tipo == "mover" or u.ordem.tipo == "carga") then
            local o = u.ordem
            if o.tipo == "mover" then
                love.graphics.setColor(0, 1, 0, 0.6)
            else
                love.graphics.setColor(1, 0.5, 0, 0.6)
            end
            local x1 = (u.x - 1) * CELL + CELL/2
            local y1 = (u.y - 1) * CELL + CELL/2
            local x2 = (o.x - 1) * CELL + CELL/2
            local y2 = (o.y - 1) * CELL + CELL/2
            local passos = 12
            for i = 1, passos do
                local t = i / passos
                local px = x1 + (x2 - x1) * t
                local py = y1 + (y2 - y1) * t
                love.graphics.circle("fill", px, py, 2)
            end
        end
    end
end

function Jogo:draw()
    desenharPainelSuperior()

    love.graphics.push()
    love.graphics.translate(0, GRID_OFFSET_Y)

    love.graphics.setColor(1, 1, 1)
    for x = 0, COLS do
        love.graphics.line(x*CELL, 0, x*CELL, ROWS*CELL)
    end
    for y = 0, ROWS do
        love.graphics.line(0, y*CELL, COLS*CELL, y*CELL)
    end

    for cy, linha in pairs(trincheiras) do
        for cx, _ in pairs(linha) do
            love.graphics.setColor(0.4, 0.28, 0.12, 0.85)
            love.graphics.rectangle("fill", (cx-1)*CELL, (cy-1)*CELL, CELL, CELL)
            love.graphics.setColor(0.5, 0.35, 0.15)
            love.graphics.rectangle("line", (cx-1)*CELL+1, (cy-1)*CELL+1, CELL-2, CELL-2)
        end
    end

    if selecionada and not menuAberto and not modoMover and not modoCarga then
        love.graphics.setColor(1, 1, 0, 0.15)
        for _, u in ipairs(unidades) do
            if u.hp > 0 and u.faccao ~= selecionada.faccao and alvoNoRangeTiro(selecionada, u) then
                love.graphics.rectangle("fill", (u.x-1)*CELL, (u.y-1)*CELL, CELL, CELL)
            end
        end
    end

    if modoMover and selecionada then
        love.graphics.setColor(0, 1, 0, 0.25)
        for cy = 1, ROWS do
            for cx = 1, COLS do
                if celulaAlcancavel(selecionada, cx, cy) then
                    love.graphics.rectangle("fill", (cx-1)*CELL, (cy-1)*CELL, CELL, CELL)
                end
            end
        end
    end

    if modoCarga and selecionada then
        love.graphics.setColor(1, 0.5, 0, 0.25)
        for cy = 1, ROWS do
            for cx = 1, COLS do
                if celulaAlcancavel(selecionada, cx, cy) then
                    love.graphics.rectangle("fill", (cx-1)*CELL, (cy-1)*CELL, CELL, CELL)
                end
            end
        end
    end

    desenharRotas()

    -- Grid inferior continua com quadrados
    for _, u in ipairs(unidades) do
        if u.hp > 0 then
            local cor = u.faccao == 1 and {0.2,0.4,0.9} or {0.9,0.2,0.2}
            if u.jaAgiu then cor = {0.5,0.5,0.5} end
            love.graphics.setColor(cor)
            love.graphics.rectangle("fill", (u.x-1)*CELL+4, (u.y-1)*CELL+4, CELL-8, CELL-8)
            if temOrdem(u) then
                love.graphics.setColor(0, 1, 1)
                love.graphics.rectangle("line", (u.x-1)*CELL+1, (u.y-1)*CELL+1, CELL-2, CELL-2)
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

    if menuAberto and selecionada then
        for _, b in ipairs(botoesMenu) do
            love.graphics.setColor(b.habilitado and {0.2,0.2,0.2,0.9} or {0.15,0.15,0.15,0.6})
            love.graphics.rectangle("fill", b.x - b.w/2, b.y - b.h/2, b.w, b.h, 4)
            love.graphics.setColor(b.habilitado and {1,1,1} or {0.5,0.5,0.5})
            love.graphics.rectangle("line", b.x - b.w/2, b.y - b.h/2, b.w, b.h, 4)
            love.graphics.printf(b.label, b.x - b.w/2, b.y - 8, b.w, "center")
        end
    end

    love.graphics.setColor(1,1,1)
    if vencedor then
        love.graphics.print(vencedor == 1 and "Jogador venceu!" or "Inimigo venceu!",
            10, GRID_OFFSET_Y + ROWS*CELL + 10)
    elseif resolvendo then
        love.graphics.print("Resolvendo ordens...", 10, GRID_OFFSET_Y + ROWS*CELL + 10)
    else
        love.graphics.print("Turno: " .. (turnoAtual == 1 and "Jogador" or "Inimigo"),
            10, GRID_OFFSET_Y + ROWS*CELL + 10)
        if modoMover then
            love.graphics.print("Clique numa célula verde para enfileirar movimento | ESC cancela",
                10, GRID_OFFSET_Y + ROWS*CELL + 30)
        elseif modoCarga then
            love.graphics.print("Clique numa célula laranja para enfileirar carga | ESC cancela",
                10, GRID_OFFSET_Y + ROWS*CELL + 30)
        else
            love.graphics.print("Dê ordens e aperte ESPAÇO para resolver | ESC cancela",
                10, GRID_OFFSET_Y + ROWS*CELL + 30)
        end
    end
end

-- ========== INPUT ==========
function Jogo:mousepressed(mx, my, botao)
    if vencedor or cena or resolvendo then return end

    if menuAberto and selecionada then
        for _, b in ipairs(botoesMenu) do
            if mx >= b.x - b.w/2 and mx <= b.x + b.w/2
               and my >= b.y - b.h/2 and my <= b.y + b.h/2 then
                if b.habilitado then
                    if b.id == "mover" then
                        modoMover = true
                        menuAberto = false
                    elseif b.id == "carga" then
                        modoCarga = true
                        menuAberto = false
                    elseif b.id == "cavar" then
                        selecionada.ordem = {tipo="cavar"}
                        selecionada = nil
                        menuAberto = false
                    elseif b.id == "tiro" then
                        local alvo = nil
                        for _, o in ipairs(unidades) do
                            if o.hp > 0 and o.faccao ~= selecionada.faccao
                               and alvoNoRangeTiro(selecionada, o) then
                                alvo = o; break
                            end
                        end
                        selecionada.ordem = {tipo="tiro", alvo=alvo}
                        selecionada = nil
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
        if celulaAlcancavel(selecionada, cx, cy) then
            selecionada.ordem = {tipo="mover", x=cx, y=cy}
            selecionada = nil
            modoMover = false
        end
        return
    end

    if modoCarga and selecionada then
        if celulaAlcancavel(selecionada, cx, cy) then
            selecionada.ordem = {tipo="carga", x=cx, y=cy}
            selecionada = nil
            modoCarga = false
        end
        return
    end

    if alvo and alvo.faccao == turnoAtual and alvo.hp > 0 then
        selecionada = alvo
        menuAberto = true
        modoMover = false
        modoCarga = false
        calcularBotoesMenu(alvo)
        return
    end
end

function Jogo:keypressed(tecla)
    if tecla == "escape" then
        menuAberto = false
        modoMover = false
        modoCarga = false
        selecionada = nil
        return
    end
    if tecla == "space" and not vencedor and not cena and not resolvendo
       and not menuAberto and not modoMover and not modoCarga then
        if turnoAtual == 1 then
            montarFila()
            if #filaResolucao == 0 then
                turnoAtual = 2
                for _, u in ipairs(unidades) do
                    u.jaAgiu = false
                    if temTrincheira(u.x, u.y) then
                        u.movimentoRestante = MOVIMENTO_NA_TRINCHEIRA
                    else
                        u.movimentoRestante = MOVIMENTO_PADRAO
                    end
                end
            else
                resolvendo = true
            end
        else
            turnoAtual = 1
            for _, u in ipairs(unidades) do
                u.jaAgiu = false
                if temTrincheira(u.x, u.y) then
                    u.movimentoRestante = MOVIMENTO_NA_TRINCHEIRA
                else
                    u.movimentoRestante = MOVIMENTO_PADRAO
                end
            end
        end
        selecionada = nil
    end
end

return Jogo