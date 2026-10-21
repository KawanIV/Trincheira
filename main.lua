if os.getenv("LOVE2D_TOOLS") then pcall(require, "_love2d_tools_bridge") end
local Jogo = require("src.estados.jogo")

function love.load()
    Jogo:load()
end

function love.update(dt)
    Jogo:update(dt)
end

function love.draw()
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("DRAW OK", 10, 10)
    Jogo:draw()
end

function love.mousepressed(x, y, botao)
    Jogo:mousepressed(x, y, botao)
end

function love.keypressed(tecla)
    Jogo:keypressed(tecla)
end