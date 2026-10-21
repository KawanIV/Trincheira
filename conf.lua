-- conf.lua
function love.conf(t)
    t.window.title = "Trincheira"
    t.window.width = 16 * 64          -- 1024
    t.window.height = 6 * 64 + 260    -- 644 (painel superior 260px + grid 384px + UI)
    t.version = "11.5"
end