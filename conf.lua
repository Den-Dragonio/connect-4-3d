function love.conf(t)
    t.identity = "connect4_3d"
    t.version = "11.4" -- 11.4 совместим с 11.5 на ПК и убирает предупреждение в веб-версии (love.js = 11.4)
    t.window.title = "Connect 4 — 3D (4×4×4)"
    t.window.width = 1280
    t.window.height = 800
    t.window.minwidth = 360
    t.window.minheight = 360
    t.window.resizable = true
    t.window.highdpi = true
    t.window.msaa = 4
    t.window.depth = 24
    t.window.vsync = 1
    t.accelerometerjoystick = false
end
