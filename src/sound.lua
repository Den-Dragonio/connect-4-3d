local Sound = {
    enabled = true,
    sources = {}
}

local function makeTone(duration, sampleFn)
    local rate = 44100
    local samples = math.floor(duration * rate)
    local data = love.sound.newSoundData(samples, rate, 16, 1)
    for i = 0, samples - 1 do
        local t = i / rate
        local v = math.max(-1.0, math.min(1.0, sampleFn(t, duration)))
        data:setSample(i, v)
    end
    return love.audio.newSource(data, "static")
end

function Sound.init()
    -- 1. Тёмное дерево (глубокий тёплый деревянный стук)
    Sound.sources.drop_wood = makeTone(0.15, function(t, dur)
        local env = math.exp(-t * 26.0)
        local f1 = 235 - t * 820
        local f2 = 470 - t * 1100
        return (math.sin(2 * math.pi * f1 * t) * 0.72 + math.sin(2 * math.pi * f2 * t) * 0.28) * env * 0.48
    end)

    -- 2. Светлое дерево / Ясень (звонкий сухой деревянный щелчок)
    Sound.sources.drop_light_wood = makeTone(0.12, function(t, dur)
        local env = math.exp(-t * 34.0)
        local f1 = 360 - t * 950
        local f2 = 740 - t * 1400
        return (math.sin(2 * math.pi * f1 * t) * 0.65 + math.sin(2 * math.pi * f2 * t) * 0.35) * env * 0.45
    end)

    -- 3. Лесная поляна / Кора и трава (мягкий шорох хвои/травы + глухой стук по коре)
    Sound.sources.drop_forest = makeTone(0.18, function(t, dur)
        local rustleEnv = math.exp(-t * 38.0)
        local thudEnv   = math.exp(-t * 20.0)
        local noise = (math.sin(t * 14321.0) * math.cos(t * 8713.0)) * rustleEnv * 0.22
        local bark  = math.sin(2 * math.pi * (185 - t * 520) * t) * thudEnv * 0.42
        return noise + bark
    end)

    -- 4. Металлическое / Стальное / Золотое поле (звонкий металлический лязг и резонанс по штырю)
    Sound.sources.drop_metal = makeTone(0.32, function(t, dur)
        local strikeEnv = math.exp(-t * 45.0)
        local ringEnv   = math.exp(-t * 11.5)
        -- Скользящий металлический шелест по штырю в первые 40 мс + звонкий удар
        local slide = math.sin(2 * math.pi * (1800 + t * 4200) * t) * math.exp(-t * 55.0) * 0.16
        local p1 = math.sin(2 * math.pi * 1080 * t) * 0.42
        local p2 = math.sin(2 * math.pi * 1740 * t) * 0.30
        local p3 = math.sin(2 * math.pi * 2560 * t) * 0.20
        local p4 = math.sin(2 * math.pi * 3410 * t) * 0.12
        local clink = (p1 + p2 + p3 + p4) * (strikeEnv * 0.55 + ringEnv * 0.45)
        return (slide + clink) * 0.44
    end)

    -- 5. Мрамор / Камень / Обсидиан (плотный каменный цокот с тяжёлым басом)
    Sound.sources.drop_stone = makeTone(0.16, function(t, dur)
        local clickEnv = math.exp(-t * 52.0)
        local bodyEnv  = math.exp(-t * 24.0)
        local stoneClick = math.sin(2 * math.pi * (680 - t * 1800) * t) * clickEnv * 0.38
        local stoneSub   = math.sin(2 * math.pi * (155 - t * 380) * t) * bodyEnv * 0.42
        return stoneClick + stoneSub
    end)

    -- 6. Сладкий Торт / Крем и Вафельные трубочки (мягкий кремовый «пуф» с вафельным хрустом)
    Sound.sources.drop_cake = makeTone(0.17, function(t, dur)
        local puffEnv   = math.exp(-t * 22.0)
        local crunchEnv = math.exp(-t * 48.0)
        -- Мягкий пружинящий звук крема/бисквита (восходяще-нисходящий мягкий тон)
        local freq = 290 + math.sin(t * 45.0) * 65 - t * 420
        local creamPuff = math.sin(2 * math.pi * freq * t) * puffEnv * 0.40
        -- Лёгкий сахарный/вафельный хруст
        local waferCrunch = math.sin(2 * math.pi * 1150 * t) * math.cos(2 * math.pi * 430 * t) * crunchEnv * 0.22
        return creamPuff + waferCrunch
    end)

    -- Дефолтный алиас
    Sound.sources.drop = Sound.sources.drop_wood

    -- Легкий щелчок при наведении на столбик
    Sound.sources.hover = makeTone(0.04, function(t, dur)
        local env = math.exp(-t * 75.0)
        return math.sin(2 * math.pi * 680 * t) * env * 0.16
    end)

    -- Клик кнопки меню
    Sound.sources.click = makeTone(0.06, function(t, dur)
        local env = math.exp(-t * 50.0)
        return math.sin(2 * math.pi * 520 * t) * env * 0.25
    end)

    -- Победный мажорный аккорд
    Sound.sources.win = makeTone(0.65, function(t, dur)
        local env = math.exp(-t * 3.8)
        local c5 = math.sin(2 * math.pi * 523.25 * t)
        local e5 = math.sin(2 * math.pi * 659.25 * t)
        local g5 = math.sin(2 * math.pi * 783.99 * t)
        return (c5 + e5 + g5) * 0.18 * env
    end)
end

function Sound.play(name)
    if not Sound.enabled then return end
    local s = Sound.sources[name]
    if s then
        s:stop()
        s:play()
    end
end

function Sound.playDrop(soundType)
    if not Sound.enabled then return end
    local key = "drop_" .. tostring(soundType or "wood")
    local s = Sound.sources[key] or Sound.sources.drop_wood
    if s then
        s:stop()
        s:play()
    end
end

return Sound
