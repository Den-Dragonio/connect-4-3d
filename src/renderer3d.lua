local BoardLogic = require("src.board_logic")

local Renderer3D = {}
Renderer3D.__index = Renderer3D

Renderer3D.GRID_SIZE      = 4
Renderer3D.PEG_SPACING    = 1.42
Renderer3D.PEG_RADIUS     = 0.135
Renderer3D.PEG_HEIGHT     = 2.68
Renderer3D.BASE_THICKNESS = 0.38
Renderer3D.SLOT_START_Y   = 0.44
Renderer3D.SLOT_STEP_Y    = 0.54
Renderer3D.DROP_SPAWN_Y   = 3.45

local VERTEX_FORMAT = {
    { "VertexPosition", "float", 3 },
    { "VertexNormal",   "float", 3 }
}

local SHADER_VERTEX = [[
    uniform vec3 u_camPos;
    uniform vec3 u_camRight;
    uniform vec3 u_camUp;
    uniform vec3 u_camFwd;
    uniform vec2 u_projScale;
    uniform vec2 u_clipOffset; // Смещение центра проекции (например, вправо для главного меню)

    uniform vec3 u_modelPos;
    uniform vec3 u_modelX;
    uniform vec3 u_modelY;
    uniform vec3 u_modelZ;

    attribute vec3 VertexNormal;

    varying LOVE_HIGHP_OR_MEDIUMP vec3 v_worldPos;
    varying LOVE_HIGHP_OR_MEDIUMP vec3 v_localPos;
    varying LOVE_HIGHP_OR_MEDIUMP vec3 v_normal;

    vec4 position(mat4 transform_projection, vec4 vertex_position) {
        vec3 localPos = vertex_position.xyz;
        v_localPos = localPos;

        vec3 worldPos = u_modelPos
                      + u_modelX * localPos.x
                      + u_modelY * localPos.y
                      + u_modelZ * localPos.z;
        v_worldPos = worldPos;

        vec3 worldNorm = normalize(
            normalize(u_modelX) * VertexNormal.x +
            normalize(u_modelY) * VertexNormal.y +
            normalize(u_modelZ) * VertexNormal.z
        );
        v_normal = worldNorm;

        vec3 rel = worldPos - u_camPos;
        float vx = dot(rel, u_camRight);
        float vy = dot(rel, u_camUp);
        float vz = dot(rel, u_camFwd);

        float zNear = 0.2;
        float zFar  = 60.0;
        float clipX = vx * u_projScale.x + u_clipOffset.x * vz;
        float clipY = vy * u_projScale.y + u_clipOffset.y * vz;
        float clipZ = vz * ((zFar + zNear) / (zFar - zNear)) - (2.0 * zFar * zNear) / (zFar - zNear);

        return vec4(clipX, clipY, clipZ, vz);
    }
]]

local SHADER_PIXEL = [[
    uniform LOVE_HIGHP_OR_MEDIUMP vec3  u_eyePos; // отдельная uniform для пиксельного шейдера (WebGL требует одинаковую точность общих uniform)
    uniform vec2  u_camHorizRight;
    uniform vec2  u_camHorizFwd;
    uniform vec4  u_baseColor;
    uniform vec3  u_emissive;
    uniform float u_specular;
    uniform float u_woodStrength;
    uniform float u_woodScale;
    uniform float u_materialType; // 0=wood, 1=donut, 2=pine, 3=uranium, 4=graphite, 5=forest_grass, 6=tree_bark, ..., 18=manhattan_clouds
    uniform LOVE_HIGHP_OR_MEDIUMP float u_time;
    uniform LOVE_HIGHP_OR_MEDIUMP float u_cloudTime;
    uniform LOVE_HIGHP_OR_MEDIUMP vec3  u_moonRayDir;

    varying LOVE_HIGHP_OR_MEDIUMP vec3 v_worldPos;
    varying LOVE_HIGHP_OR_MEDIUMP vec3 v_localPos;
    varying LOVE_HIGHP_OR_MEDIUMP vec3 v_normal;

    // Процедурный 3D-шум для текстуры древесных волокон и годовых колец
    float woodHash3(vec3 p) {
        p = fract(p * vec3(0.1031, 0.1030, 0.0973));
        p += dot(p, p.yxz + 33.33);
        return fract((p.x + p.y) * p.z);
    }

    float woodNoise3(vec3 p) {
        vec3 i = floor(p);
        vec3 f = fract(p);
        f = f * f * (3.0 - 2.0 * f);

        float n000 = woodHash3(i + vec3(0.0, 0.0, 0.0));
        float n100 = woodHash3(i + vec3(1.0, 0.0, 0.0));
        float n010 = woodHash3(i + vec3(0.0, 1.0, 0.0));
        float n110 = woodHash3(i + vec3(1.0, 1.0, 0.0));
        float n001 = woodHash3(i + vec3(0.0, 0.0, 1.0));
        float n101 = woodHash3(i + vec3(1.0, 0.0, 1.0));
        float n011 = woodHash3(i + vec3(0.0, 1.0, 1.0));
        float n111 = woodHash3(i + vec3(1.0, 1.0, 1.0));

        float nx00 = mix(n000, n100, f.x);
        float nx10 = mix(n010, n110, f.x);
        float nx01 = mix(n001, n101, f.x);
        float nx11 = mix(n011, n111, f.x);

        float nxy0 = mix(nx00, nx10, f.y);
        float nxy1 = mix(nx01, nx11, f.y);

        return mix(nxy0, nxy1, f.z);
    }

    float woodPattern(vec3 p) {
        float n = woodNoise3(p * 2.2) * 0.65 + woodNoise3(p * 6.5) * 0.35;
        float dist = length(p.xz + vec2(0.35, -0.25)) * 11.0 + n * 4.2;
        float rings = sin(dist) * 0.5 + 0.5;
        rings = smoothstep(0.15, 0.88, rings);
        float fibers = woodNoise3(vec3(p.x * 24.0, p.y * 5.0, p.z * 24.0));
        return mix(rings, fibers, 0.32);
    }

    float cloudHash2(vec2 p) {
        p = fract(p * vec2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }

    float cloudNoise2(vec2 p) {
        vec2 i = floor(p);
        vec2 f = fract(p);
        f = f * f * (3.0 - 2.0 * f);
        float a = cloudHash2(i);
        float b = cloudHash2(i + vec2(1.0, 0.0));
        float c = cloudHash2(i + vec2(0.0, 1.0));
        float d = cloudHash2(i + vec2(1.0, 1.0));
        return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
    }

    vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
        vec3 N = normalize(v_normal);
        vec3 V = normalize(u_eyePos - v_worldPos);

        vec3 samplePos = (v_worldPos * 0.65 + v_localPos * 0.85) * u_woodScale;
        float grain = woodPattern(samplePos);
        vec3 darkGrain  = u_baseColor.rgb * 0.70;
        vec3 lightGrain = u_baseColor.rgb * 1.18 + vec3(0.03, 0.02, 0.01);
        vec3 surfaceAlbedo = mix(u_baseColor.rgb, mix(darkGrain, lightGrain, grain), u_woodStrength);
        float specFactor = u_specular * mix(1.0, 0.6 + 0.6 * grain, u_woodStrength);
        vec3 extraGlow = vec3(0.0);
        float outAlpha = u_baseColor.a;

        if (u_materialType > 0.5 && u_materialType < 1.5) {
            // 1: Пончик с глазурью (Glazed Donut)
            float ang = atan(v_localPos.z, v_localPos.x);
            float dripWave = 0.022 * sin(ang * 7.0) + 0.012 * cos(ang * 11.0);
            float icingMask = smoothstep(dripWave - 0.022, dripWave + 0.022, v_localPos.y);
            float crumbNoise = woodNoise3(v_localPos * 16.0);
            bool isDarkGlaze = (u_baseColor.r < 0.5);
            vec3 doughColor = isDarkGlaze
                ? mix(vec3(0.56, 0.36, 0.20), vec3(0.72, 0.48, 0.28), crumbNoise)
                : mix(vec3(0.76, 0.52, 0.26), vec3(0.90, 0.68, 0.38), crumbNoise);
            vec3 glazeColor = u_baseColor.rgb;
            surfaceAlbedo = mix(doughColor, glazeColor, icingMask);
            specFactor = mix(0.14, 0.92, icingMask);
        } else if (u_materialType > 1.5 && u_materialType < 2.5) {
            // 2: Глубокая текстура хвои с лёгкой гирляндой и игрушками
            float rFrac = clamp(length(v_localPos.xz) / 0.49, 0.0, 1.0);
            float ang = atan(v_localPos.z, v_localPos.x);
            float needle = woodNoise3(vec3(v_localPos.x * 36.0, v_localPos.y * 22.0, v_localPos.z * 36.0));
            float fineFrond = 0.5 + 0.5 * sin(ang * 40.0 + rFrac * 18.0);
            float boughAO = mix(0.32, 0.96, pow(rFrac, 0.72));
            vec3 pineCol = u_baseColor.rgb * boughAO * (0.68 + 0.24 * needle + 0.14 * fineFrond);
            // Мини-шарики/огоньки ближе к краям ярусов
            float seg = mod(ang + 3.14159, 1.256637) - 0.628318;
            float dBauble = length(vec3(rFrac - 0.74, seg * 0.74, (v_localPos.y + 0.12) * 1.45));
            if (rFrac > 0.56 && dBauble < 0.088) {
                float idx = floor((ang + 3.14159) / 1.256637);
                float isAlt = mod(idx, 2.0);
                float twinkle = 0.65 + 0.35 * sin(u_time * 3.6 + idx * 1.7 + v_worldPos.y * 4.0);
                vec3 baubleCol = (isAlt < 0.5) ? vec3(1.00, 0.80, 0.18) : vec3(0.96, 0.20, 0.22);
                surfaceAlbedo = baubleCol;
                extraGlow += baubleCol * (0.28 * twinkle);
                specFactor = 0.92;
            } else {
                surfaceAlbedo = pineCol;
                specFactor = 0.16;
            }
        } else if (u_materialType > 2.5 && u_materialType < 3.5) {
            // 3: Ядерный Уран (Glowing & Blinking Radioactive Uranium-235)
            float radPulse = 0.55 + 0.45 * sin(u_time * 5.2);
            float geigerFlicker = 0.88 + 0.12 * sin(u_time * 23.0 + v_localPos.x * 9.0);
            float veins = smoothstep(0.35, 0.78, woodNoise3(v_localPos * 9.5 + vec3(0.0, u_time * 0.6, 0.0)));
            surfaceAlbedo = mix(vec3(0.10, 0.38, 0.12), vec3(0.38, 1.00, 0.24), veins);
            extraGlow = vec3(0.18, 0.82, 0.14) * (0.42 + 0.58 * radPulse * geigerFlicker) * (0.55 + 0.65 * veins);
            specFactor = 0.72;
        } else if (u_materialType > 3.5 && u_materialType < 4.5) {
            // 4: Ядерный Графит (Reactor Graphite Moderator)
            float carbon = woodNoise3(v_localPos * 26.0) * 0.6 + woodNoise3(v_localPos * 55.0) * 0.4;
            surfaceAlbedo = mix(vec3(0.14, 0.15, 0.18), vec3(0.30, 0.33, 0.38), carbon);
            specFactor = 0.68 * (0.5 + 0.7 * carbon);
        } else if (u_materialType > 4.5 && u_materialType < 5.5) {
            // 5: Лесная поляна — трава и мох вокруг стволов деревьев (Forest Grass Base)
            if (N.y > 0.5) {
                float blade1 = woodNoise3(v_worldPos * 6.5);
                float blade2 = woodNoise3(v_worldPos * 22.0);
                vec3 grassDark  = vec3(0.12, 0.34, 0.11);
                vec3 grassLight = vec3(0.28, 0.62, 0.20);
                vec3 grassCol   = mix(grassDark, grassLight, blade1 * 0.65 + blade2 * 0.35);

                // Кольца сочной травы и мха вокруг 16 стволов-штыков
                vec2 pegGrid = fract((v_worldPos.xz / 1.42) + vec2(0.5)) - vec2(0.5);
                float dPeg = length(pegGrid) * 1.42;
                float mossRing = smoothstep(0.52, 0.16, dPeg);
                vec3 mossCol = mix(vec3(0.22, 0.54, 0.14), vec3(0.38, 0.74, 0.24), blade2);
                surfaceAlbedo = mix(grassCol, mossCol, mossRing * 0.75);
                specFactor = 0.14;
            } else {
                // Боковой срез лесной земли и корней
                float bark = woodNoise3(vec3(v_worldPos.x * 8.0, v_worldPos.y * 14.0, v_worldPos.z * 8.0));
                surfaceAlbedo = mix(vec3(0.22, 0.14, 0.08), vec3(0.36, 0.24, 0.14), bark);
                specFactor = 0.12;
            }
        } else if (u_materialType > 5.5 && u_materialType < 6.5) {
            // 6: Стволы деревьев для штыков (Tree Trunk Bark)
            float barkRidges = woodNoise3(vec3(v_localPos.x * 22.0, v_localPos.y * 2.4, v_localPos.z * 22.0));
            float barkKnots  = woodNoise3(v_localPos * 9.0);
            float barkVal    = barkRidges * 0.72 + barkKnots * 0.28;
            surfaceAlbedo = mix(u_baseColor.rgb * 0.62, u_baseColor.rgb * 1.28, barkVal);
            specFactor = 0.16;
        } else if (u_materialType > 6.5 && u_materialType < 7.5) {
            // 7: Шлифованная сталь и хром (Brushed Steel & Chrome Metal)
            float radialGrooves = sin(length(v_localPos.xz) * 140.0) * 0.5 + 0.5;
            float microBrush    = woodNoise3(vec3(v_localPos.x * 65.0, v_localPos.y * 12.0, v_localPos.z * 65.0));
            float metalSheen    = mix(radialGrooves, microBrush, 0.55);
            vec3 envReflect     = mix(vec3(0.32, 0.36, 0.42), vec3(0.88, 0.93, 1.00), clamp(N.y * 0.5 + 0.5, 0.0, 1.0));
            surfaceAlbedo = mix(u_baseColor.rgb * (0.82 + 0.32 * metalSheen), envReflect * u_baseColor.rgb * 1.35, 0.38);
            specFactor = 0.95;
        } else if (u_materialType > 7.5 && u_materialType < 8.5) {
            // 8: Сладкий Торт / Пирог с клубнично-сливочной глазурью, бисквитом и посыпкой (Sweet Cake Base)
            if (N.y > 0.45) {
                float swirl = sin(length(v_worldPos.xz) * 5.2 + atan(v_worldPos.z, v_worldPos.x) * 2.0) * 0.5 + 0.5;
                vec3 pinkIcing  = vec3(0.98, 0.72, 0.82);
                vec3 creamIcing = vec3(1.00, 0.95, 0.90);
                vec3 icingCol   = mix(pinkIcing, creamIcing, smoothstep(0.25, 0.75, swirl));

                // Взбитые сливочные розетки вокруг каждого из 16 столбиков-вафель
                vec2 pegGrid = fract((v_worldPos.xz / 1.42) + vec2(0.5)) - vec2(0.5);
                float dPeg = length(pegGrid) * 1.42;
                float whipRing = smoothstep(0.46, 0.16, dPeg);
                icingCol = mix(icingCol, vec3(1.00, 0.97, 0.93), whipRing * 0.80);

                // Разноцветная кондитерская посыпка (конфетти) сверху торта
                vec3 spCell = floor(v_worldPos * 12.5);
                float spHash = woodHash3(spCell);
                if (spHash > 0.80 && dPeg > 0.24) {
                    vec3 spCol = (spHash > 0.95) ? vec3(0.98, 0.84, 0.22) :
                                 (spHash > 0.90) ? vec3(0.32, 0.86, 0.94) :
                                 (spHash > 0.85) ? vec3(0.96, 0.34, 0.52) : vec3(0.36, 0.20, 0.12);
                    icingCol = mix(icingCol, spCol, 0.90);
                }
                surfaceAlbedo = icingCol;
                specFactor = 0.82;
            } else {
                // Боковой разрез торта: золотистый бисквит + сливочная прослойка посередине + потеки глазури сверху
                float ang = atan(v_localPos.z, v_localPos.x);
                float dripWave = 0.10 + 0.14 * sin(ang * 11.0) + 0.08 * cos(ang * 17.0);
                float topDripMask = smoothstep(dripWave - 0.05, dripWave + 0.05, v_localPos.y);
                float creamLayer  = smoothstep(0.14, 0.04, abs(v_localPos.y + 0.04));
                float crumb       = woodNoise3(v_worldPos * 18.0);
                vec3 spongeCol    = mix(vec3(0.76, 0.50, 0.24), vec3(0.90, 0.66, 0.36), crumb);
                vec3 sideCol      = mix(spongeCol, vec3(0.99, 0.96, 0.90), creamLayer * 0.88);
                surfaceAlbedo     = mix(sideCol, vec3(0.98, 0.70, 0.80), topDripMask);
                specFactor        = mix(0.16, 0.84, topDripMask);
            }
        } else if (u_materialType > 8.5 && u_materialType < 9.5) {
            // 9: Хрустящие вафельные трубочки с шоколадно-карамельной спиралью для столбиков торта (Wafer Roll Pegs)
            float ang = atan(v_localPos.z, v_localPos.x);
            float spiral = sin(v_localPos.y * 15.0 + ang * 2.0);
            float chocoStripe = smoothstep(0.45, 0.72, spiral);
            float waferGrid = sin(v_localPos.y * 65.0) * sin(ang * 14.0) * 0.5 + 0.5;
            vec3 waferCol = mix(vec3(0.80, 0.56, 0.30), vec3(0.93, 0.72, 0.44), waferGrid);
            vec3 chocoCol = vec3(0.32, 0.16, 0.08);
            surfaceAlbedo = mix(waferCol, chocoCol, chocoStripe * 0.78);
            specFactor = mix(0.22, 0.65, chocoStripe);
        } else if (u_materialType > 9.5 && u_materialType < 10.5) {
            // 10: Снеговик — искристый плотный снег
            float sparkle = step(0.92, woodHash3(floor(v_worldPos * 26.0)));
            float grain = woodNoise3(v_worldPos * 14.0);
            surfaceAlbedo = mix(u_baseColor.rgb * 0.90, u_baseColor.rgb * 1.08, grain) + vec3(sparkle * 0.22);
            specFactor = 0.45 + sparkle * 0.4;
        } else if (u_materialType > 10.5 && u_materialType < 11.5) {
            // 11: Реалистичные небоскрёбы Манхэттена (остекление, стальные колонны, перекрытия, тёплые и холодные окна + уход в ночные тучи)
            float lowMist = smoothstep(-0.75, -3.40, v_worldPos.y);
            float winFade = 1.0 - smoothstep(-0.95, -2.65, v_worldPos.y);
            if (N.y > 0.5) {
                float roofTex = woodNoise3(v_worldPos * 7.0);
                float edgeRim = step(0.42, max(abs(v_localPos.x), abs(v_localPos.z)));
                surfaceAlbedo = mix(vec3(0.08, 0.09, 0.13), vec3(0.16, 0.18, 0.24), roofTex * 0.6 + edgeRim * 0.4);
                specFactor = 0.28;
            } else {
                float uFace = (abs(N.x) > 0.5) ? v_localPos.z : v_localPos.x;
                float cornerPier = step(0.43, abs(uFace));
                float cols = (uFace + 0.5) * 6.0;
                float rows = v_worldPos.y * 5.8;
                float wx = fract(cols);
                float wy = fract(rows);
                float winPane = step(0.18, wx) * step(wx, 0.82) * step(0.24, wy) * step(wy, 0.78);
                vec3 cellId = floor(vec3(cols, rows, v_worldPos.x * 3.1 + v_worldPos.z * 5.7));
                float litRand = woodHash3(cellId);
                float roomGlow = smoothstep(0.36, 0.92, litRand) * step(0.38, litRand);
                float isLit = roomGlow * winPane * (1.0 - cornerPier) * winFade;
                vec3 glassCol = mix(vec3(0.04, 0.06, 0.11), vec3(0.10, 0.15, 0.24), N.y * 0.5 + 0.5);
                vec3 winTint = (litRand > 0.82) ? vec3(0.70, 0.88, 1.00) : mix(vec3(1.00, 0.78, 0.36), vec3(1.00, 0.90, 0.62), fract(litRand * 13.0));
                surfaceAlbedo = mix(glassCol, vec3(0.05, 0.06, 0.09), cornerPier);
                surfaceAlbedo = mix(surfaceAlbedo, winTint, isLit * 0.90);
                extraGlow += winTint * isLit * 0.68;
                specFactor = mix(0.86, 0.18, isLit);
            }
            vec3 nightHazeCol = vec3(0.036, 0.052, 0.118);
            surfaceAlbedo = mix(surfaceAlbedo, nightHazeCol, lowMist * 0.94);
            extraGlow *= (1.0 - lowMist * 0.95);
            specFactor *= (1.0 - lowMist);
            outAlpha *= (1.0 - smoothstep(-3.3, -7.8, v_worldPos.y));
        } else if (u_materialType > 11.5 && u_materialType < 12.5) {
            // 12: Авиационный красный маячок на вершинах шпилей (плавное медленное дыхание света)
            float pulse = pow(0.5 + 0.5 * sin(u_time * 1.15), 1.5);
            surfaceAlbedo = vec3(1.00, 0.14, 0.10);
            extraGlow += vec3(1.00, 0.12, 0.08) * (0.30 + 0.95 * pulse);
            specFactor = 0.95;
        } else if (u_materialType > 12.5 && u_materialType < 13.5) {
            // 13: Традиционная японская черепичная крыша (Кавара) по фото-референсу
            if (abs(N.z) > 0.65) {
                // Фронтоны (хафу): белая штукатурка стен (сиккуи) + киноварные красные деревянные балки (бэнгара)
                float beamV = (abs(fract(v_localPos.x * 2.4) - 0.5) < 0.14) ? 1.0 : 0.0;
                float beamH = (abs(v_localPos.y + 0.04) < 0.08 || v_localPos.y > 0.38) ? 1.0 : 0.0;
                float isTimber = max(beamV, beamH);
                surfaceAlbedo = mix(vec3(0.92, 0.90, 0.88), vec3(0.82, 0.20, 0.14), isTimber);
                specFactor = 0.22;
            } else if (N.y > 0.18) {
                // Скаты крыши: темная сланцевая/глиняная черепица (кавара), ряды полукруглых желобков
                float tileWave = sin(v_worldPos.z * 16.0);
                float tileShade = 0.5 + 0.5 * tileWave;
                float rowStep = fract(v_worldPos.x * 3.4);
                vec3 darkKawara   = vec3(0.14, 0.16, 0.20);
                vec3 glazedKawara = vec3(0.26, 0.30, 0.36);
                surfaceAlbedo = mix(darkKawara, glazedKawara, tileShade * 0.75 + rowStep * 0.25);
                specFactor = 0.48;
            } else {
                // Карнизы и торцы
                surfaceAlbedo = vec3(0.18, 0.12, 0.10);
                specFactor = 0.28;
            }
        } else if (u_materialType > 13.5 && u_materialType < 14.5) {
            // 14: Хэллоуинская тыква с рёбрами и светящейся рожицей
            float ang = atan(v_localPos.z, v_localPos.x);
            float ribs = 0.5 + 0.5 * cos(ang * 10.0);
            surfaceAlbedo = mix(u_baseColor.rgb * 0.72, u_baseColor.rgb * 1.15, ribs);
            if (v_localPos.z > 0.22 && abs(v_localPos.x) < 0.26 && v_localPos.y > -0.15 && v_localPos.y < 0.22) {
                float eyeL = length(vec2(v_localPos.x + 0.11, v_localPos.y - 0.08));
                float eyeR = length(vec2(v_localPos.x - 0.11, v_localPos.y - 0.08));
                float mouth = (v_localPos.y < -0.02 && v_localPos.y > -0.12 && abs(v_localPos.x) < 0.16) ? 1.0 : 0.0;
                float carve = max(step(eyeL, 0.055), max(step(eyeR, 0.055), mouth));
                if (carve > 0.5) {
                    surfaceAlbedo = vec3(1.0, 0.78, 0.22);
                    extraGlow += vec3(1.0, 0.62, 0.10) * 0.85;
                }
            }
            specFactor = 0.35;
        } else if (u_materialType > 14.5 && u_materialType < 15.5) {
            // 15: Заснеженная зимняя доска
            if (N.y > 0.45) {
                float drift = woodNoise3(v_worldPos * 3.5);
                float sparkle = step(0.93, woodHash3(floor(v_worldPos * 24.0)));
                surfaceAlbedo = mix(vec3(0.84, 0.91, 0.98), vec3(0.98, 0.99, 1.0), drift) + vec3(sparkle * 0.25);
                specFactor = 0.55;
            } else {
                surfaceAlbedo = vec3(0.45, 0.62, 0.80);
                specFactor = 0.65;
            }
        } else if (u_materialType > 15.5 && u_materialType < 16.5) {
            // 16: 3D травинки на лесном поле
            float h = clamp((v_localPos.y + 0.5), 0.0, 1.0);
            surfaceAlbedo = mix(vec3(0.10, 0.32, 0.09), vec3(0.38, 0.78, 0.22), h);
            specFactor = 0.18;
        } else if (u_materialType > 16.5 && u_materialType < 17.5) {
            // 17: Крылья легендарной бабочки (перелив)
            float shimmer = 0.5 + 0.5 * sin(u_time * 4.0 + v_localPos.x * 12.0);
            surfaceAlbedo = mix(u_baseColor.rgb, vec3(0.35, 0.92, 1.0), shimmer * 0.45);
            extraGlow += surfaceAlbedo * 0.28;
            specFactor = 0.85;
        } else if (u_materialType > 17.5 && u_materialType < 18.5) {
            // 18: Ночной туман/облака Манхэттена (не вращается с камерой, плывёт в 1 сторону, не "поедает" луну)
            vec2 relXZ = v_worldPos.xz - u_eyePos.xz;
            vec2 camCloudXZ = vec2(dot(relXZ, u_camHorizRight), dot(relXZ, u_camHorizFwd));
            vec2 windDir = vec2(0.14, 0.02);
            vec2 uv1 = camCloudXZ * 0.24 - windDir * u_cloudTime;
            vec2 uv2 = camCloudXZ * 0.54 - windDir * (u_cloudTime * 1.45) + vec2(3.7, 8.2);
            float n = cloudNoise2(uv1) * 0.66 + cloudNoise2(uv2) * 0.34;
            float distCenter = length(v_worldPos.xz);
            // Густой покров прямо под 16 башнями (радиус ~4) и плавное растворение к горизонту без резких границ и сплошной завесы неба
            float cityCloudMask = 1.0 - smoothstep(6.2, 20.5, distCenter);
            vec3 horizonCol = vec3(0.036, 0.052, 0.118);
            vec3 cloudDark  = vec3(0.046, 0.066, 0.136);
            vec3 cloudLight = vec3(0.19, 0.26, 0.42);
            float cityWarm = smoothstep(5.8, 0.6, distCenter) * 0.26;
            vec3 col = mix(cloudDark, cloudLight, smoothstep(0.26, 0.78, n));
            col += vec3(0.32, 0.24, 0.15) * cityWarm * (0.45 + 0.55 * n);
            col = mix(col, horizonCol, smoothstep(7.5, 19.0, distCenter) * 0.75);
            float wisps = smoothstep(0.24, 0.76, n);
            float isLowerSea = step(1.90, -v_worldPos.y);
            float layerA = mix(mix(0.14, 0.88, wisps), 0.96, isLowerSea);
            // Защита луны при любых наклонах и зуме камеры: мягко расступаемся в направлении луны
            vec3 viewDir = normalize(v_worldPos - u_eyePos);
            float moonClear = smoothstep(0.955, 0.992, dot(viewDir, normalize(u_moonRayDir)));
            outAlpha = clamp(u_baseColor.a * layerA * cityCloudMask * (1.0 - moonClear * 0.95), 0.0, 1.0);
            return vec4(col + u_emissive * 0.30, outAlpha);
        } else if (u_materialType > 18.5 && u_materialType < 19.5) {
            // 19: Бесшовные блоки небоскрёба (белые и чёрные имеют одинаковый фасад — отличается только вкл/выкл свет в окнах)
            bool lightsOn = (u_baseColor.r > 0.45);
            if (abs(N.y) > 0.5) {
                float roofTex = woodNoise3(v_localPos * 14.0 + v_worldPos * 2.0);
                float edgeRim = step(0.35, max(abs(v_localPos.x), abs(v_localPos.z)));
                surfaceAlbedo = mix(vec3(0.14, 0.16, 0.21), vec3(0.24, 0.27, 0.34), roofTex * 0.55 + edgeRim * 0.45);
                specFactor = 0.42;
            } else {
                float uFace = (abs(N.x) > 0.5) ? v_localPos.z : v_localPos.x;
                float cornerPier = step(0.36, abs(uFace));
                float cols = (uFace + 0.43) / 0.86 * 4.0;
                float rows = (v_localPos.y + 0.195) / 0.39 * 2.0;
                float wx = fract(cols);
                float wy = fract(rows);
                float winPane = step(0.16, wx) * step(wx, 0.84) * step(0.18, wy) * step(wy, 0.82);
                vec3 cellId = floor(vec3(cols, rows, v_worldPos.x * 2.3 + v_worldPos.z * 4.1));
                float cellRnd = woodHash3(cellId);
                vec3 pierCol = vec3(0.14, 0.17, 0.23);
                vec3 frameCol = vec3(0.22, 0.26, 0.34);
                vec3 unlitGlass = mix(vec3(0.08, 0.11, 0.17), vec3(0.14, 0.19, 0.28), cellRnd * 0.65);
                vec3 baseFacade = mix(mix(frameCol, unlitGlass, winPane), pierCol, cornerPier);
                if (lightsOn) {
                    float isLit = step(0.14, cellRnd) * winPane * (1.0 - cornerPier);
                    vec3 winTint = (cellRnd > 0.78)
                        ? vec3(0.76, 0.90, 1.00)
                        : mix(vec3(1.00, 0.82, 0.42), vec3(1.00, 0.94, 0.72), fract(cellRnd * 9.0));
                    surfaceAlbedo = mix(baseFacade, winTint, isLit * 0.96);
                    extraGlow += winTint * isLit * 0.88;
                    specFactor = mix(0.84, 0.25, isLit);
                } else {
                    surfaceAlbedo = baseFacade;
                    specFactor = mix(0.45, 0.86, winPane * (1.0 - cornerPier));
                }
            }
        } else if (u_materialType > 19.5 && u_materialType < 20.5) {
            // 20: Крыша ЧАЭС (ребристые бетонные плиты, битум/копоть, жёлто-чёрный радиационный бордюр)
            float nWear = woodNoise3(v_worldPos * 3.8);
            float slabJoint = step(0.91, fract(v_worldPos.x * 1.42)) + step(0.92, fract(v_worldPos.z * 1.42));
            float ribWave = 0.5 + 0.5 * sin(v_worldPos.z * 14.0);
            float soot = smoothstep(0.42, 0.78, woodNoise3(v_worldPos * 1.9 + vec3(4.1, 0.0, 2.3)));
            vec3 concreteCol = mix(vec3(0.28, 0.30, 0.31), vec3(0.42, 0.44, 0.45), ribWave * 0.55 + nWear * 0.45);
            concreteCol = mix(concreteCol, vec3(0.11, 0.12, 0.13), clamp(slabJoint * 0.65 + soot * 0.55, 0.0, 0.85));
            float edgeBand = step(0.44, max(abs(v_localPos.x), abs(v_localPos.z)));
            float stripe = step(0.5, fract((v_localPos.x + v_localPos.z) * 14.0));
            vec3 hazardCol = mix(vec3(0.10, 0.10, 0.11), vec3(0.94, 0.72, 0.10), stripe);
            float glowCrack = step(0.955, woodNoise3(v_worldPos * 4.5)) * (1.0 - edgeBand);
            surfaceAlbedo = mix(concreteCol, hazardCol, edgeBand * 0.85);
            extraGlow += vec3(0.18, 0.92, 0.42) * glowCrack * 0.32;
            specFactor = mix(0.18, 0.42, edgeBand);
        } else if (u_materialType > 20.5 && u_materialType < 21.5) {
            // 21: Промышленные трубы ЧАЭС (бетон и сталь с красно-белыми авиационными кольцами и копотью сверху)
            float hNorm = clamp(v_localPos.y / 2.68, 0.0, 1.0);
            float grime = woodNoise3(v_worldPos * 7.5);
            float bandPos = fract(hNorm * 7.0);
            float redWhiteArea = step(0.54, hNorm) * (1.0 - step(0.95, hNorm));
            float isRedBand = step(0.50, bandPos);
            vec3 concretePipe = mix(vec3(0.36, 0.38, 0.40), vec3(0.52, 0.54, 0.56), grime);
            vec3 warnCol = mix(vec3(0.86, 0.86, 0.84), vec3(0.78, 0.16, 0.12), isRedBand);
            surfaceAlbedo = mix(concretePipe, warnCol, redWhiteArea * 0.88);
            // Копоть у устья трубы
            float topSoot = smoothstep(0.86, 1.0, hNorm);
            surfaceAlbedo = mix(surfaceAlbedo, vec3(0.10, 0.10, 0.11), topSoot * 0.78);
            specFactor = 0.24;
        }

        vec3 L1 = normalize(vec3(0.55, 0.78, 0.48));
        vec3 L2 = normalize(vec3(-0.62, 0.45, -0.58));

        float diff1 = max(dot(N, L1), 0.0);
        float diff2 = max(dot(N, L2), 0.0);

        float hemi = N.y * 0.5 + 0.5;
        vec3 ambient = mix(vec3(0.19, 0.18, 0.22), vec3(0.46, 0.44, 0.48), hemi);

        vec3 H1 = normalize(L1 + V);
        float spec = pow(max(dot(N, H1), 0.0), 32.0) * specFactor;

        float fresnel = pow(1.0 - max(dot(N, V), 0.0), 3.2) * 0.12;

        vec3 litColor = surfaceAlbedo * (ambient + diff1 * 0.74 + diff2 * 0.25)
                      + vec3(spec)
                      + vec3(fresnel * 0.7, fresnel * 0.65, fresnel * 0.6)
                      + extraGlow
                      + u_emissive;

        return vec4(litColor, outAlpha);
    }
]]

local function vec3(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
local function vSub(a, b) return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z } end
local function vDot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
local function vCross(a, b)
    return {
        x = a.y * b.z - a.z * b.y,
        y = a.z * b.x - a.x * b.z,
        z = a.x * b.y - a.y * b.x
    }
end
local function vLen(a) return math.sqrt(vDot(a, a)) end
local function vNorm(a)
    local l = vLen(a)
    if l < 1e-8 then return { x = 0, y = 1, z = 0 } end
    return { x = a.x / l, y = a.y / l, z = a.z / l }
end

function Renderer3D.new()
    local self = setmetatable({}, Renderer3D)

    self.shader = love.graphics.newShader(SHADER_PIXEL, SHADER_VERTEX)

    -- Процедурные 3D-меши
    self.meshTorus     = self:_buildTorusMesh(0.335, 0.165, 36, 22)
    self.meshPineTier  = self:_buildPineTierMesh(36, 18)
    self.meshPeg       = self:_buildPegMesh(Renderer3D.PEG_RADIUS, Renderer3D.PEG_HEIGHT, 24)
    self.meshCylinder  = self:_buildUnitCylinderMesh(24)
    self.meshRoundBase    = self:_buildCappedDiscMesh(64)
    self.meshBox          = self:_buildUnitBoxMesh()
    self.meshSquareBlock  = self:_buildSquareBlockPieceMesh()
    self.meshPineConeTip  = self:_buildPineConeTipMesh(32)
    self.meshStar         = self:_buildStarMesh(0.24, 0.10, 0.075)
    self.meshThinTorus    = self:_buildTorusMesh(0.355, 0.082, 36, 18)
    self.meshBead         = self:_buildTorusMesh(0.24, 0.20, 32, 20)
    self.meshSphere       = self:_buildSphereMesh(22, 14)
    self.meshPumpkin      = self:_buildPumpkinMesh(28, 16)
    self.meshTopHat       = self:_buildTopHatMesh(24)
    self.meshGrassTuft    = self:_buildGrassTuftMesh()
    self.meshJapaneseRoof = self:_buildJapaneseRoofMesh(16)
    self.meshButterflyWing = self:_buildButterflyWingMesh()

    -- Разбросанные фишки рядом с полем (полностью за пределами и круглого, и квадратного основания)
    local baseY = -Renderer3D.BASE_THICKNESS + 0.21
    self.scatteredPieces = {
        { x = -4.35, y = baseY,        z =  1.35, player = 1, tiltX = 0.0, tiltZ = 0.0 },
        { x = -4.22, y = baseY + 0.42, z =  1.25, player = 2, tiltX = 0.0, tiltZ = 0.0 },
        { x =  4.35, y = baseY,        z = -1.25, player = 2, tiltX = 0.0, tiltZ = 0.0 },
        { x =  1.45, y = baseY,        z =  4.35, player = 1, tiltX = 0.0, tiltZ = 0.0 },
        { x = -1.35, y = baseY,        z = -4.35, player = 2, tiltX = 0.0, tiltZ = 0.0 }
    }

    self.yawDeg   = 35.0
    self.pitchDeg = -30.0
    self.distance = 12.4
    self.target   = vec3(0.0, 0.98, 0.0)
    self.fovRad   = math.rad(44.0)

    self:_updateCameraBasis()
    return self
end

function Renderer3D:resetCamera()
    self.yawDeg   = 35.0
    self.pitchDeg = -30.0
    self.distance = 11.4
    self:_updateCameraBasis()
end

function Renderer3D:rotateCamera(dYaw, dPitch)
    self.yawDeg   = self.yawDeg + dYaw
    self.pitchDeg = math.max(-78.0, math.min(-10.0, self.pitchDeg + dPitch))
    self:_updateCameraBasis()
end

function Renderer3D:zoomCamera(dDist)
    self.distance = math.max(5.8, math.min(16.0, self.distance + dDist))
    self:_updateCameraBasis()
end

function Renderer3D:_updateCameraBasis()
    local yaw   = math.rad(self.yawDeg)
    local pitch = math.rad(self.pitchDeg)

    local cosP = math.cos(-pitch)
    local sinP = math.sin(-pitch)
    local sinY = math.sin(yaw)
    local cosY = math.cos(yaw)

    self.camPos = {
        x = self.target.x + self.distance * cosP * sinY,
        y = self.target.y + self.distance * sinP,
        z = self.target.z + self.distance * cosP * cosY
    }

    self.camFwd   = vNorm(vSub(self.target, self.camPos))
    self.camRight = vNorm(vCross(self.camFwd, { x = 0, y = 1, z = 0 }))
    self.camUp    = vNorm(vCross(self.camRight, self.camFwd))
end

function Renderer3D:pieceWorldY(gy, pieceSkin)
    local style = pieceSkin and pieceSkin.style or "wood"
    if style == "pine" then
        return 0.335 + (gy - 1) * 0.67
    elseif style == "snowman" then
        local ys = { 0.40, 1.10, 1.74, 2.02 }
        return ys[gy] or (Renderer3D.SLOT_START_Y + (gy - 1) * Renderer3D.SLOT_STEP_Y)
    end
    return Renderer3D.SLOT_START_Y + (gy - 1) * Renderer3D.SLOT_STEP_Y
end

function Renderer3D:gridToWorldXZ(gx, gz)
    local half = (Renderer3D.GRID_SIZE + 1) * 0.5
    return (gx - half) * Renderer3D.PEG_SPACING, (gz - half) * Renderer3D.PEG_SPACING
end

function Renderer3D:gridToWorldXYZ(gx, gy, gz, pieceSkin)
    local wx, wz = self:gridToWorldXZ(gx, gz)
    local wy = self:pieceWorldY(gy, pieceSkin)
    return wx, wy, wz
end

-- Проекция 3D-точки в 2D экранные координаты (для отрисовки разметки a,b,c,d и 1,2,3,4)
function Renderer3D:worldToScreen(wx, wy, wz, screenW, screenH, clipOffsetX, clipOffsetY)
    clipOffsetX = clipOffsetX or 0.0
    clipOffsetY = clipOffsetY or 0.0
    local aspect = screenW / screenH
    local f = 1.0 / math.tan(self.fovRad * 0.5)

    local rel = { x = wx - self.camPos.x, y = wy - self.camPos.y, z = wz - self.camPos.z }
    local vx = vDot(rel, self.camRight)
    local vy = vDot(rel, self.camUp)
    local vz = vDot(rel, self.camFwd)
    if vz <= 0.2 then return nil, nil end

    local ndcX = (vx * (f / aspect)) / vz + clipOffsetX
    local ndcY = (vy * f) / vz + clipOffsetY

    local sx = (ndcX + 1.0) * 0.5 * screenW
    local sy = (1.0 - ndcY) * 0.5 * screenH
    return sx, sy
end

function Renderer3D:_buildTorusMesh(majorR, minorR, ringSegs, tubeSegs)
    local verts = {}
    local yStretch = 1.28

    local function getPoint(u, v)
        local cu, su = math.cos(u), math.sin(u)
        local cv, sv = math.cos(v), math.sin(v)
        local r = majorR + minorR * cv
        local px = r * cu
        local py = minorR * sv * yStretch
        local pz = r * su

        local nx = cv * cu
        local ny = sv / yStretch
        local nz = cv * su
        local nl = math.sqrt(nx*nx + ny*ny + nz*nz)
        return { px, py, pz, nx/nl, ny/nl, nz/nl }
    end

    for i = 0, ringSegs - 1 do
        local u0 = (i / ringSegs) * math.pi * 2
        local u1 = ((i + 1) / ringSegs) * math.pi * 2
        for j = 0, tubeSegs - 1 do
            local v0 = (j / tubeSegs) * math.pi * 2
            local v1 = ((j + 1) / tubeSegs) * math.pi * 2

            local p00 = getPoint(u0, v0)
            local p10 = getPoint(u1, v0)
            local p11 = getPoint(u1, v1)
            local p01 = getPoint(u0, v1)

            table.insert(verts, p00)
            table.insert(verts, p10)
            table.insert(verts, p11)

            table.insert(verts, p00)
            table.insert(verts, p11)
            table.insert(verts, p01)
        end
    end

    return love.graphics.newMesh(VERTEX_FORMAT, verts, "triangles", "static")
end

-- Конусообразный ярус пышных еловых лап
function Renderer3D:_buildPineTierMesh(ringSegs, tubeSegs)
    local verts = {}
    local innerR = 0.156 -- плотно прилегает к штырю (радиус штыря 0.15)
    local outerR = 0.495 -- размах еловых лап
    local yTop   = 0.345
    local yBot   = -0.335

    local function getPoint(u, v)
        local cu, su = math.cos(u), math.sin(u)
        local wave = 1.0 + 0.14 * math.cos(u * 10.0) + 0.04 * math.cos(u * 20.0)
        local r = innerR + (outerR * wave - innerR) * v
        local px = r * cu
        local py = yTop + (yBot - yTop) * (v ^ 1.35) + 0.025 * math.sin(v * math.pi)
        local pz = r * su

        local slope = (yBot - yTop) / (outerR - innerR)
        local nx = cu * (-slope) + 0.14 * math.sin(u * 10.0) * (-su)
        local ny = 1.0
        local nz = su * (-slope) + 0.14 * math.sin(u * 10.0) * cu
        local nl = math.sqrt(nx*nx + ny*ny + nz*nz)
        return { px, py, pz, nx/nl, ny/nl, nz/nl }
    end

    local uSteps = ringSegs or 36
    local vSteps = tubeSegs or 10
    for i = 0, uSteps - 1 do
        local u0 = (i / uSteps) * math.pi * 2
        local u1 = ((i + 1) / uSteps) * math.pi * 2
        for j = 0, vSteps - 1 do
            local v0 = j / vSteps
            local v1 = (j + 1) / vSteps

            local p00 = getPoint(u0, v0)
            local p10 = getPoint(u1, v0)
            local p11 = getPoint(u1, v1)
            local p01 = getPoint(u0, v1)

            table.insert(verts, p00); table.insert(verts, p10); table.insert(verts, p11)
            table.insert(verts, p00); table.insert(verts, p11); table.insert(verts, p01)

            local drop = 0.055
            table.insert(verts, { p00[1], p00[2] - drop, p00[3], 0, -1, 0 })
            table.insert(verts, { p11[1], p11[2] - drop, p11[3], 0, -1, 0 })
            table.insert(verts, { p10[1], p10[2] - drop, p10[3], 0, -1, 0 })

            table.insert(verts, { p00[1], p00[2] - drop, p00[3], 0, -1, 0 })
            table.insert(verts, { p01[1], p01[2] - drop, p01[3], 0, -1, 0 })
            table.insert(verts, { p11[1], p11[2] - drop, p11[3], 0, -1, 0 })
        end
    end

    return love.graphics.newMesh(VERTEX_FORMAT, verts, "triangles", "static")
end

function Renderer3D:_buildPegMesh(radius, height, segs)
    local verts = {}

    for i = 0, segs - 1 do
        local a0 = (i / segs) * math.pi * 2
        local a1 = ((i + 1) / segs) * math.pi * 2
        local c0, s0 = math.cos(a0), math.sin(a0)
        local c1, s1 = math.cos(a1), math.sin(a1)

        local x0, z0 = c0 * radius, s0 * radius
        local x1, z1 = c1 * radius, s1 * radius

        table.insert(verts, { x0, 0,      z0, c0, 0, s0 })
        table.insert(verts, { x1, 0,      z1, c1, 0, s1 })
        table.insert(verts, { x1, height, z1, c1, 0, s1 })

        table.insert(verts, { x0, 0,      z0, c0, 0, s0 })
        table.insert(verts, { x1, height, z1, c1, 0, s1 })
        table.insert(verts, { x0, height, z0, c0, 0, s0 })
    end

    local rings = 6
    for r = 0, rings - 1 do
        local p0 = (r / rings) * (math.pi * 0.5)
        local p1 = ((r + 1) / rings) * (math.pi * 0.5)
        local cp0, sp0 = math.cos(p0), math.sin(p0)
        local cp1, sp1 = math.cos(p1), math.sin(p1)

        for i = 0, segs - 1 do
            local a0 = (i / segs) * math.pi * 2
            local a1 = ((i + 1) / segs) * math.pi * 2
            local c0, s0 = math.cos(a0), math.sin(a0)
            local c1, s1 = math.cos(a1), math.sin(a1)

            local v00 = { c0*cp0*radius, height + sp0*radius, s0*cp0*radius, c0*cp0, sp0, s0*cp0 }
            local v10 = { c1*cp0*radius, height + sp0*radius, s1*cp0*radius, c1*cp0, sp0, s1*cp0 }
            local v11 = { c1*cp1*radius, height + sp1*radius, s1*cp1*radius, c1*cp1, sp1, s1*cp1 }
            local v01 = { c0*cp1*radius, height + sp1*radius, s0*cp1*radius, c0*cp1, sp1, s0*cp1 }

            table.insert(verts, v00)
            table.insert(verts, v10)
            table.insert(verts, v11)

            table.insert(verts, v00)
            table.insert(verts, v11)
            table.insert(verts, v01)
        end
    end

    return love.graphics.newMesh(VERTEX_FORMAT, verts, "triangles", "static")
end

-- Круглый цилиндрический диск (радиус 0.5, высота от -0.5 до +0.5) с крышками для круглого поля
function Renderer3D:_buildCappedDiscMesh(segs)
    local verts = {}
    local r = 0.5
    for i = 0, segs - 1 do
        local a0 = (i / segs) * math.pi * 2
        local a1 = ((i + 1) / segs) * math.pi * 2
        local c0, s0 = math.cos(a0), math.sin(a0)
        local c1, s1 = math.cos(a1), math.sin(a1)

        local x0, z0 = c0 * r, s0 * r
        local x1, z1 = c1 * r, s1 * r

        -- Боковая грань
        table.insert(verts, { x0, -0.5, z0, c0, 0, s0 })
        table.insert(verts, { x1, -0.5, z1, c1, 0, s1 })
        table.insert(verts, { x1,  0.5, z1, c1, 0, s1 })

        table.insert(verts, { x0, -0.5, z0, c0, 0, s0 })
        table.insert(verts, { x1,  0.5, z1, c1, 0, s1 })
        table.insert(verts, { x0,  0.5, z0, c0, 0, s0 })

        -- Верхняя крышка (+Y)
        table.insert(verts, { 0,  0.5, 0,  0, 1, 0 })
        table.insert(verts, { x1, 0.5, z1, 0, 1, 0 })
        table.insert(verts, { x0, 0.5, z0, 0, 1, 0 })

        -- Нижняя крышка (-Y)
        table.insert(verts, { 0,  -0.5, 0,  0, -1, 0 })
        table.insert(verts, { x0, -0.5, z0, 0, -1, 0 })
        table.insert(verts, { x1, -0.5, z1, 0, -1, 0 })
    end
    return love.graphics.newMesh(VERTEX_FORMAT, verts, "triangles", "static")
end

function Renderer3D:_buildUnitCylinderMesh(segs)
    local verts = {}
    for i = 0, segs - 1 do
        local a0 = (i / segs) * math.pi * 2
        local a1 = ((i + 1) / segs) * math.pi * 2
        local c0, s0 = math.cos(a0), math.sin(a0)
        local c1, s1 = math.cos(a1), math.sin(a1)

        table.insert(verts, { c0, -0.5, s0, c0, 0, s0 })
        table.insert(verts, { c1, -0.5, s1, c1, 0, s1 })
        table.insert(verts, { c1,  0.5, s1, c1, 0, s1 })

        table.insert(verts, { c0, -0.5, s0, c0, 0, s0 })
        table.insert(verts, { c1,  0.5, s1, c1, 0, s1 })
        table.insert(verts, { c0,  0.5, s0, c0, 0, s0 })
    end
    return love.graphics.newMesh(VERTEX_FORMAT, verts, "triangles", "static")
end

function Renderer3D:_buildUnitBoxMesh()
    local faces = {
        { n = { 0,  1,  0}, v = { {-0.5, 0.5,-0.5}, { 0.5, 0.5,-0.5}, { 0.5, 0.5, 0.5}, {-0.5, 0.5, 0.5} } },
        { n = { 0, -1,  0}, v = { {-0.5,-0.5, 0.5}, { 0.5,-0.5, 0.5}, { 0.5,-0.5,-0.5}, {-0.5,-0.5,-0.5} } },
        { n = { 1,  0,  0}, v = { { 0.5,-0.5,-0.5}, { 0.5, 0.5,-0.5}, { 0.5, 0.5, 0.5}, { 0.5,-0.5, 0.5} } },
        { n = {-1,  0,  0}, v = { {-0.5,-0.5, 0.5}, {-0.5, 0.5, 0.5}, {-0.5, 0.5,-0.5}, {-0.5,-0.5,-0.5} } },
        { n = { 0,  0,  1}, v = { {-0.5,-0.5, 0.5}, { 0.5,-0.5, 0.5}, { 0.5, 0.5, 0.5}, {-0.5, 0.5, 0.5} } },
        { n = { 0,  0, -1}, v = { { 0.5,-0.5,-0.5}, {-0.5,-0.5,-0.5}, {-0.5, 0.5,-0.5}, { 0.5, 0.5,-0.5} } }
    }
    local verts = {}
    for _, f in ipairs(faces) do
        local n = f.n
        local v = f.v
        table.insert(verts, { v[1][1], v[1][2], v[1][3], n[1], n[2], n[3] })
        table.insert(verts, { v[2][1], v[2][2], v[2][3], n[1], n[2], n[3] })
        table.insert(verts, { v[3][1], v[3][2], v[3][3], n[1], n[2], n[3] })

        table.insert(verts, { v[1][1], v[1][2], v[1][3], n[1], n[2], n[3] })
        table.insert(verts, { v[3][1], v[3][2], v[3][3], n[1], n[2], n[3] })
        table.insert(verts, { v[4][1], v[4][2], v[4][3], n[1], n[2], n[3] })
    end
    return love.graphics.newMesh(VERTEX_FORMAT, verts, "triangles", "static")
end

-- Квадратный блок-фишка со сквозным круглым отверстием под штырь (для Железных блоков и Блоков небоскрёбов)
function Renderer3D:_buildSquareBlockPieceMesh()
    local verts = {}
    local halfW  = 0.43
    local halfH  = 0.195
    local innerR = 0.165
    local segs   = 32 -- кратно 8, чтобы точно попадать в 45° углы квадрата

    local function outerPt(a)
        local ca, sa = math.cos(a), math.sin(a)
        local denom = math.max(math.abs(ca), math.abs(sa), 1e-6)
        local d = halfW / denom
        return ca * d, sa * d
    end

    for i = 0, segs - 1 do
        local a0 = (i / segs) * math.pi * 2
        local a1 = ((i + 1) / segs) * math.pi * 2
        local c0, s0 = math.cos(a0), math.sin(a0)
        local c1, s1 = math.cos(a1), math.sin(a1)
        local ix0, iz0 = c0 * innerR, s0 * innerR
        local ix1, iz1 = c1 * innerR, s1 * innerR
        local ox0, oz0 = outerPt(a0)
        local ox1, oz1 = outerPt(a1)

        -- Верхняя грань (y = +halfH, N = +Y)
        table.insert(verts, { ix0,  halfH, iz0, 0,  1, 0 })
        table.insert(verts, { ox0,  halfH, oz0, 0,  1, 0 })
        table.insert(verts, { ox1,  halfH, oz1, 0,  1, 0 })
        table.insert(verts, { ix0,  halfH, iz0, 0,  1, 0 })
        table.insert(verts, { ox1,  halfH, oz1, 0,  1, 0 })
        table.insert(verts, { ix1,  halfH, iz1, 0,  1, 0 })

        -- Нижняя грань (y = -halfH, N = -Y)
        table.insert(verts, { ix0, -halfH, iz0, 0, -1, 0 })
        table.insert(verts, { ox1, -halfH, oz1, 0, -1, 0 })
        table.insert(verts, { ox0, -halfH, oz0, 0, -1, 0 })
        table.insert(verts, { ix0, -halfH, iz0, 0, -1, 0 })
        table.insert(verts, { ix1, -halfH, iz1, 0, -1, 0 })
        table.insert(verts, { ox1, -halfH, oz1, 0, -1, 0 })

        -- Внутренний цилиндрический канал под штырь
        table.insert(verts, { ix0, -halfH, iz0, -c0, 0, -s0 })
        table.insert(verts, { ix0,  halfH, iz0, -c0, 0, -s0 })
        table.insert(verts, { ix1,  halfH, iz1, -c1, 0, -s1 })
        table.insert(verts, { ix0, -halfH, iz0, -c0, 0, -s0 })
        table.insert(verts, { ix1,  halfH, iz1, -c1, 0, -s1 })
        table.insert(verts, { ix1, -halfH, iz1, -c1, 0, -s1 })
    end

    -- 4 ровные внешние боковые грани квадратного блока
    local hw, hh = halfW, halfH
    local sideFaces = {
        { n = {  0, 0,  1 }, v = { { -hw, -hh,  hw }, {  hw, -hh,  hw }, {  hw,  hh,  hw }, { -hw,  hh,  hw } } },
        { n = {  0, 0, -1 }, v = { {  hw, -hh, -hw }, { -hw, -hh, -hw }, { -hw,  hh, -hw }, {  hw,  hh, -hw } } },
        { n = {  1, 0,  0 }, v = { {  hw, -hh,  hw }, {  hw, -hh, -hw }, {  hw,  hh, -hw }, {  hw,  hh,  hw } } },
        { n = { -1, 0,  0 }, v = { { -hw, -hh, -hw }, { -hw, -hh,  hw }, { -hw,  hh,  hw }, { -hw,  hh, -hw } } },
    }
    for _, f in ipairs(sideFaces) do
        local v, n = f.v, f.n
        table.insert(verts, { v[1][1], v[1][2], v[1][3], n[1], n[2], n[3] })
        table.insert(verts, { v[2][1], v[2][2], v[2][3], n[1], n[2], n[3] })
        table.insert(verts, { v[3][1], v[3][2], v[3][3], n[1], n[2], n[3] })
        table.insert(verts, { v[1][1], v[1][2], v[1][3], n[1], n[2], n[3] })
        table.insert(verts, { v[3][1], v[3][2], v[3][3], n[1], n[2], n[3] })
        table.insert(verts, { v[4][1], v[4][2], v[4][3], n[1], n[2], n[3] })
    end
    return love.graphics.newMesh(VERTEX_FORMAT, verts, "triangles", "static")
end

-- Закрытая пушистая конусная верхушка ёлки (полностью накрывает штырь и купол сверху, без отверстия)
function Renderer3D:_buildPineConeTipMesh(segs)
    local verts = {}
    local baseR = 0.52
    local yBot, yTop = -0.335, 0.66
    local nSegs = segs or 36
    local nRings = 7

    local function pt(a, t)
        local c, s = math.cos(a), math.sin(a)
        local wave = 1.0 + 0.12 * math.cos(a * 10.0) * (1.0 - t * 0.65)
        local profile = (1.0 - t) ^ 0.58
        local r = baseR * wave * profile
        local y = yBot + (yTop - yBot) * t
        local nx, ny, nz = c * 0.85, 0.52, s * 0.85
        return { c * r, y, s * r, nx, ny, nz }
    end

    for i = 0, nSegs - 1 do
        local a0 = (i / nSegs) * math.pi * 2
        local a1 = ((i + 1) / nSegs) * math.pi * 2
        for j = 0, nRings - 1 do
            local t0 = j / nRings
            local t1 = (j + 1) / nRings
            if j < nRings - 1 then
                local p00 = pt(a0, t0); local p10 = pt(a1, t0)
                local p11 = pt(a1, t1); local p01 = pt(a0, t1)
                table.insert(verts, p00); table.insert(verts, p10); table.insert(verts, p11)
                table.insert(verts, p00); table.insert(verts, p11); table.insert(verts, p01)
            else
                local p00 = pt(a0, t0); local p10 = pt(a1, t0)
                table.insert(verts, p00)
                table.insert(verts, p10)
                table.insert(verts, { 0, yTop, 0, (p00[4]+p10[4])*0.5, 0.7, (p00[6]+p10[6])*0.5 })
            end
        end

        -- Глухая нижняя плоскость
        local b0 = pt(a0, 0.0); local b1 = pt(a1, 0.0)
        table.insert(verts, { 0, yBot, 0, 0, -1, 0 })
        table.insert(verts, { b0[1], yBot, b0[3], 0, -1, 0 })
        table.insert(verts, { b1[1], yBot, b1[3], 0, -1, 0 })
    end
    return love.graphics.newMesh(VERTEX_FORMAT, verts, "triangles", "static")
end

-- Объёмная 5-конечная звезда на макушку ёлки
function Renderer3D:_buildStarMesh(outerR, innerR, depth)
    local verts = {}
    local R = outerR or 0.24
    local r = innerR or 0.10
    local d = depth or 0.075
    local pts = {}
    for k = 0, 9 do
        local a = (k / 10) * math.pi * 2 + math.pi * 0.5
        local rad = (k % 2 == 0) and R or r
        pts[k + 1] = { math.cos(a) * rad, math.sin(a) * rad }
    end
    local function addTri(a, b, c)
        local ux, uy, uz = b[1]-a[1], b[2]-a[2], b[3]-a[3]
        local vx, vy, vz = c[1]-a[1], c[2]-a[2], c[3]-a[3]
        local nx, ny, nz = uy*vz - uz*vy, uz*vx - ux*vz, ux*vy - uy*vx
        local nl = math.sqrt(nx*nx + ny*ny + nz*nz)
        if nl < 1e-6 then nl = 1 end
        nx, ny, nz = nx/nl, ny/nl, nz/nl
        table.insert(verts, { a[1], a[2], a[3], nx, ny, nz })
        table.insert(verts, { b[1], b[2], b[3], nx, ny, nz })
        table.insert(verts, { c[1], c[2], c[3], nx, ny, nz })
    end
    for k = 1, 10 do
        local p0 = pts[k]
        local p1 = pts[(k % 10) + 1]
        addTri({ 0, 0,  d }, { p0[1], p0[2], 0 }, { p1[1], p1[2], 0 })
        addTri({ 0, 0, -d }, { p1[1], p1[2], 0 }, { p0[1], p0[2], 0 })
    end
    return love.graphics.newMesh(VERTEX_FORMAT, verts, "triangles", "static")
end

function Renderer3D:_buildSphereMesh(segs, rings)
    local verts = {}
    local r = 0.5
    for j = 0, rings - 1 do
        local p0 = (j / rings) * math.pi - math.pi * 0.5
        local p1 = ((j + 1) / rings) * math.pi - math.pi * 0.5
        local cp0, sp0 = math.cos(p0), math.sin(p0)
        local cp1, sp1 = math.cos(p1), math.sin(p1)
        for i = 0, segs - 1 do
            local t0 = (i / segs) * math.pi * 2
            local t1 = ((i + 1) / segs) * math.pi * 2
            local c0, s0 = math.cos(t0), math.sin(t0)
            local c1, s1 = math.cos(t1), math.sin(t1)
            local v00 = { c0*cp0*r, sp0*r, s0*cp0*r, c0*cp0, sp0, s0*cp0 }
            local v10 = { c1*cp0*r, sp0*r, s1*cp0*r, c1*cp0, sp0, s1*cp0 }
            local v11 = { c1*cp1*r, sp1*r, s1*cp1*r, c1*cp1, sp1, s1*cp1 }
            local v01 = { c0*cp1*r, sp1*r, s0*cp1*r, c0*cp1, sp1, s0*cp1 }
            table.insert(verts, v00); table.insert(verts, v10); table.insert(verts, v11)
            table.insert(verts, v00); table.insert(verts, v11); table.insert(verts, v01)
        end
    end
    return love.graphics.newMesh(VERTEX_FORMAT, verts, "triangles", "static")
end

function Renderer3D:_buildPumpkinMesh(segs, rings)
    local verts = {}
    local function pPoint(t, p)
        local rib = 1.0 + 0.09 * math.cos(t * 10.0)
        local rx = 0.48 * math.cos(p) * rib
        local ry = 0.34 * math.sin(p)
        return math.cos(t)*rx, ry, math.sin(t)*rx, math.cos(t)*math.cos(p), math.sin(p), math.sin(t)*math.cos(p)
    end
    for j = 0, rings - 1 do
        local p0 = (j / rings) * math.pi - math.pi * 0.5
        local p1 = ((j + 1) / rings) * math.pi - math.pi * 0.5
        for i = 0, segs - 1 do
            local t0 = (i / segs) * math.pi * 2
            local t1 = ((i + 1) / segs) * math.pi * 2
            local v00 = { pPoint(t0, p0) }
            local v10 = { pPoint(t1, p0) }
            local v11 = { pPoint(t1, p1) }
            local v01 = { pPoint(t0, p1) }
            table.insert(verts, v00); table.insert(verts, v10); table.insert(verts, v11)
            table.insert(verts, v00); table.insert(verts, v11); table.insert(verts, v01)
        end
    end
    return love.graphics.newMesh(VERTEX_FORMAT, verts, "triangles", "static")
end

-- Чёрный цилиндр-шляпа для верхушки снеговика (сидит на голове и полностью прячет верхушку штыря)
function Renderer3D:_buildTopHatMesh(segs)
    local verts = {}
    local function addRing(rBot, rTop, yBot, yTop)
        for i = 0, segs - 1 do
            local a0 = (i / segs) * math.pi * 2
            local a1 = ((i + 1) / segs) * math.pi * 2
            local c0, s0 = math.cos(a0), math.sin(a0)
            local c1, s1 = math.cos(a1), math.sin(a1)
            table.insert(verts, { c0*rBot, yBot, s0*rBot, c0, 0, s0 })
            table.insert(verts, { c1*rBot, yBot, s1*rBot, c1, 0, s1 })
            table.insert(verts, { c1*rTop, yTop, s1*rTop, c1, 0, s1 })
            table.insert(verts, { c0*rBot, yBot, s0*rBot, c0, 0, s0 })
            table.insert(verts, { c1*rTop, yTop, s1*rTop, c1, 0, s1 })
            table.insert(verts, { c0*rTop, yTop, s0*rTop, c0, 0, s0 })
            table.insert(verts, { 0, yTop, 0, 0, 1, 0 })
            table.insert(verts, { c1*rTop, yTop, s1*rTop, 0, 1, 0 })
            table.insert(verts, { c0*rTop, yTop, s0*rTop, 0, 1, 0 })
            table.insert(verts, { 0, yBot, 0, 0, -1, 0 })
            table.insert(verts, { c0*rBot, yBot, s0*rBot, 0, -1, 0 })
            table.insert(verts, { c1*rBot, yBot, s1*rBot, 0, -1, 0 })
        end
    end
    addRing(0.45, 0.45, -0.04, 0.05) -- Широкие поля шляпы
    addRing(0.27, 0.31,  0.05, 0.85) -- Высокая тулья цилиндра (закрывает штырь y=2.83)
    return love.graphics.newMesh(VERTEX_FORMAT, verts, "triangles", "static")
end

-- Пучок 3D-травинок для лесного поля
function Renderer3D:_buildGrassTuftMesh()
    local verts = {}
    local blades = {
        { ang = 0.0, lean = 0.22, h = 0.95, w = 0.14 },
        { ang = 2.1, lean = 0.28, h = 0.85, w = 0.13 },
        { ang = 4.2, lean = 0.20, h = 1.00, w = 0.12 },
    }
    for _, b in ipairs(blades) do
        local ca, sa = math.cos(b.ang), math.sin(b.ang)
        local px, pz = -sa * b.w, ca * b.w
        local tx, tz = ca * b.lean, sa * b.lean
        local v1 = { -px, -0.5, -pz, ca, 0.3, sa }
        local v2 = {  px, -0.5,  pz, ca, 0.3, sa }
        local v3 = {  tx,  b.h - 0.5, tz, ca, 0.5, sa }
        table.insert(verts, v1); table.insert(verts, v2); table.insert(verts, v3)
        table.insert(verts, v1); table.insert(verts, v3); table.insert(verts, v2)
    end
    return love.graphics.newMesh(VERTEX_FORMAT, verts, "triangles", "static")
end

-- Традиционная японская храмовая крыша (Киридзума / Иримоя) по фото-референсу
function Renderer3D:_buildJapaneseRoofMesh(gridN)
    local verts = {}
    local halfSpanX = 2.95
    local halfSpanZ = 3.10
    local baseFloorY = -0.26
    local ridgeY = 0.52

    local function roofSurface(x, z)
        local u = math.min(1.0, math.abs(x) / halfSpanX)
        -- Аутентичный японский прогиб "сори": крутой спуск от конька с мягким подъемом на краях карниза
        local y = ridgeY - 0.68 * math.pow(u, 1.25) + 0.12 * math.pow(u, 4.0)
        local dy_du = -0.68 * 1.25 * math.pow(math.max(0.001, u), 0.25) + 0.12 * 4.0 * math.pow(u, 3.0)
        local dy_dx = (x >= 0 and 1 or -1) * (dy_du / halfSpanX)
        local nx, ny, nz = -dy_dx, 1.0, 0.0
        local nl = math.sqrt(nx*nx + ny*ny + nz*nz)
        return x, y, z, nx/nl, ny/nl, nz/nl
    end

    local nxSteps = 24
    local nzSteps = 20

    -- 1. Скаты крыши с черепицей
    for i = 0, nxSteps - 1 do
        local x0 = -halfSpanX + (i / nxSteps) * (halfSpanX * 2)
        local x1 = -halfSpanX + ((i + 1) / nxSteps) * (halfSpanX * 2)
        for j = 0, nzSteps - 1 do
            local z0 = -halfSpanZ + (j / nzSteps) * (halfSpanZ * 2)
            local z1 = -halfSpanZ + ((j + 1) / nzSteps) * (halfSpanZ * 2)

            local px0, py0, pz0, nx0, ny0, nz0 = roofSurface(x0, z0)
            local px1, py1, pz1, nx1, ny1, nz1 = roofSurface(x1, z0)
            local px2, py2, pz2, nx2, ny2, nz2 = roofSurface(x1, z1)
            local px3, py3, pz3, nx3, ny3, nz3 = roofSurface(x0, z1)

            table.insert(verts, { px0, py0, pz0, nx0, ny0, nz0 })
            table.insert(verts, { px1, py1, pz1, nx1, ny1, nz1 })
            table.insert(verts, { px2, py2, pz2, nx2, ny2, nz2 })

            table.insert(verts, { px0, py0, pz0, nx0, ny0, nz0 })
            table.insert(verts, { px2, py2, pz2, nx2, ny2, nz2 })
            table.insert(verts, { px3, py3, pz3, nx3, ny3, nz3 })
        end
    end

    -- 2. Фронтоны (хафу) с белой штукатуркой и красными балками спереди и сзади
    for _, zSign in ipairs({ -1, 1 }) do
        local zGable = zSign * halfSpanZ
        local nzGable = zSign
        for i = 0, nxSteps - 1 do
            local x0 = -halfSpanX + (i / nxSteps) * (halfSpanX * 2)
            local x1 = -halfSpanX + ((i + 1) / nxSteps) * (halfSpanX * 2)
            local _, yRoof0 = roofSurface(x0, zGable)
            local _, yRoof1 = roofSurface(x1, zGable)

            if zSign < 0 then
                table.insert(verts, { x0, baseFloorY, zGable, 0, 0, nzGable })
                table.insert(verts, { x0, yRoof0,      zGable, 0, 0, nzGable })
                table.insert(verts, { x1, yRoof1,      zGable, 0, 0, nzGable })

                table.insert(verts, { x0, baseFloorY, zGable, 0, 0, nzGable })
                table.insert(verts, { x1, yRoof1,      zGable, 0, 0, nzGable })
                table.insert(verts, { x1, baseFloorY, zGable, 0, 0, nzGable })
            else
                table.insert(verts, { x0, baseFloorY, zGable, 0, 0, nzGable })
                table.insert(verts, { x1, yRoof1,      zGable, 0, 0, nzGable })
                table.insert(verts, { x0, yRoof0,      zGable, 0, 0, nzGable })

                table.insert(verts, { x0, baseFloorY, zGable, 0, 0, nzGable })
                table.insert(verts, { x1, baseFloorY, zGable, 0, 0, nzGable })
                table.insert(verts, { x1, yRoof1,      zGable, 0, 0, nzGable })
            end
        end
    end

    -- 3. Боковые карнизные планки (слева и справа)
    for _, xSign in ipairs({ -1, 1 }) do
        local xEave = xSign * halfSpanX
        local nxEave = xSign
        for j = 0, nzSteps - 1 do
            local z0 = -halfSpanZ + (j / nzSteps) * (halfSpanZ * 2)
            local z1 = -halfSpanZ + ((j + 1) / nzSteps) * (halfSpanZ * 2)
            local _, yRoof = roofSurface(xEave, z0)
            if xSign > 0 then
                table.insert(verts, { xEave, baseFloorY, z0, nxEave, 0, 0 })
                table.insert(verts, { xEave, yRoof,      z0, nxEave, 0, 0 })
                table.insert(verts, { xEave, yRoof,      z1, nxEave, 0, 0 })

                table.insert(verts, { xEave, baseFloorY, z0, nxEave, 0, 0 })
                table.insert(verts, { xEave, yRoof,      z1, nxEave, 0, 0 })
                table.insert(verts, { xEave, baseFloorY, z1, nxEave, 0, 0 })
            else
                table.insert(verts, { xEave, baseFloorY, z0, nxEave, 0, 0 })
                table.insert(verts, { xEave, yRoof,      z1, nxEave, 0, 0 })
                table.insert(verts, { xEave, yRoof,      z0, nxEave, 0, 0 })

                table.insert(verts, { xEave, baseFloorY, z0, nxEave, 0, 0 })
                table.insert(verts, { xEave, baseFloorY, z1, nxEave, 0, 0 })
                table.insert(verts, { xEave, yRoof,      z1, nxEave, 0, 0 })
            end
        end
    end

    -- 4. Центральный конёк крыши (Мунэ-кавара) — полуцилиндрический валик вдоль Z
    local ridgeR = 0.14
    local ridgeSegs = 10
    for j = 0, nzSteps - 1 do
        local z0 = -halfSpanZ - 0.08 + (j / nzSteps) * ((halfSpanZ + 0.08) * 2)
        local z1 = -halfSpanZ - 0.08 + ((j + 1) / nzSteps) * ((halfSpanZ + 0.08) * 2)
        for s = 0, ridgeSegs - 1 do
            local a0 = (s / ridgeSegs) * math.pi
            local a1 = ((s + 1) / ridgeSegs) * math.pi
            local rx0, ry0 = math.cos(a0) * ridgeR, ridgeY + math.sin(a0) * ridgeR
            local rx1, ry1 = math.cos(a1) * ridgeR, ridgeY + math.sin(a1) * ridgeR
            local nr0x, nr0y = math.cos(a0), math.sin(a0)
            local nr1x, nr1y = math.cos(a1), math.sin(a1)

            table.insert(verts, { rx0, ry0, z0, nr0x, nr0y, 0 })
            table.insert(verts, { rx1, ry1, z0, nr1x, nr1y, 0 })
            table.insert(verts, { rx1, ry1, z1, nr1x, nr1y, 0 })

            table.insert(verts, { rx0, ry0, z0, nr0x, nr0y, 0 })
            table.insert(verts, { rx1, ry1, z1, nr1x, nr1y, 0 })
            table.insert(verts, { rx0, ry0, z1, nr0x, nr0y, 0 })
        end
    end

    -- 5. Нижняя плоскость основания (закрытый пол)
    table.insert(verts, { -halfSpanX, baseFloorY, -halfSpanZ, 0, -1, 0 })
    table.insert(verts, {  halfSpanX, baseFloorY,  halfSpanZ, 0, -1, 0 })
    table.insert(verts, {  halfSpanX, baseFloorY, -halfSpanZ, 0, -1, 0 })

    table.insert(verts, { -halfSpanX, baseFloorY, -halfSpanZ, 0, -1, 0 })
    table.insert(verts, { -halfSpanX, baseFloorY,  halfSpanZ, 0, -1, 0 })
    table.insert(verts, {  halfSpanX, baseFloorY,  halfSpanZ, 0, -1, 0 })

    return love.graphics.newMesh(VERTEX_FORMAT, verts, "triangles", "static")
end

-- Крыло бабочки для легендарного скина
function Renderer3D:_buildButterflyWingMesh()
    local verts = {
        { 0.0, 0.0,  0.0, 0, 1, 0 },
        { 0.9, 0.1, -0.5, 0, 1, 0 },
        { 1.0, 0.0,  0.2, 0, 1, 0 },
        { 0.0, 0.0,  0.0, 0, 1, 0 },
        { 1.0, 0.0,  0.2, 0, 1, 0 },
        { 0.65, 0.0, 0.75, 0, 1, 0 },
    }
    return love.graphics.newMesh(VERTEX_FORMAT, verts, "triangles", "static")
end

function Renderer3D:pickPegAtScreenPos(mx, my, screenW, screenH, boardLogic, clipOffsetX, clipOffsetY, pieceSkin)
    local aspect = screenW / screenH
    local f = 1.0 / math.tan(self.fovRad * 0.5)

    local ndcX = ((mx / screenW) * 2.0 - 1.0) - (clipOffsetX or 0.0)
    local ndcY = (1.0 - (my / screenH) * 2.0) - (clipOffsetY or 0.0)

    local rayDir = vNorm({
        x = self.camFwd.x + self.camRight.x * (ndcX * aspect / f) + self.camUp.x * (ndcY / f),
        y = self.camFwd.y + self.camRight.y * (ndcX * aspect / f) + self.camUp.y * (ndcY / f),
        z = self.camFwd.z + self.camRight.z * (ndcX * aspect / f) + self.camUp.z * (ndcY / f)
    })

    local bestX, bestZ, bestY = nil, nil, nil
    local bestT = 1e9
    local isFree = boardLogic and (boardLogic.ruleMode == "free")

    -- В вольном режиме (без гравитации) сначала проверяем точное 3D-попадание луча в пустые слоты на штырях
    if isFree then
        local bestSlotScore = 1e9
        local slotRadius = 0.44
        for gx = 1, 4 do
            for gz = 1, 4 do
                local px, pz = self:gridToWorldXZ(gx, gz)
                for ty = 1, 4 do
                    if boardLogic:canPlace(gx, ty, gz) then
                        local py = self:pieceWorldY(ty, pieceSkin)
                        local ux = px - self.camPos.x
                        local uy = py - self.camPos.y
                        local uz = pz - self.camPos.z
                        local tProj = ux * rayDir.x + uy * rayDir.y + uz * rayDir.z
                        if tProj > 0.2 then
                            local rx = ux - rayDir.x * tProj
                            local ry = (uy - rayDir.y * tProj) * 1.32
                            local rz = uz - rayDir.z * tProj
                            local dSlot = math.sqrt(rx * rx + ry * ry + rz * rz)
                            if dSlot <= slotRadius then
                                -- Точность наведения по лучу (dSlot) главнее глубины tProj:
                                -- передние штыри больше не перехватывают курсор, наведённый на 2–4 ряды
                                local score = dSlot * 8.0 + tProj * 0.25
                                if score < bestSlotScore then
                                    bestSlotScore = score
                                    bestX, bestZ, bestY = gx, gz, ty
                                end
                            end
                        end
                    end
                end
            end
        end
        if bestX then
            return bestX, bestZ, bestY
        end
    end

    local hitRadius = isFree and 0.28 or 0.36

    for gx = 1, 4 do
        for gz = 1, 4 do
            local pegAvailable = false
            if not boardLogic then
                pegAvailable = true
            elseif isFree then
                for ty = 1, 4 do
                    if boardLogic:canPlace(gx, ty, gz) then pegAvailable = true; break end
                end
            else
                pegAvailable = boardLogic:canDrop(gx, gz)
            end

            if pegAvailable then
                local px, pz = self:gridToWorldXZ(gx, gz)
                local ox = self.camPos.x - px
                local oz = self.camPos.z - pz

                local a = rayDir.x * rayDir.x + rayDir.z * rayDir.z
                local b = 2.0 * (ox * rayDir.x + oz * rayDir.z)
                local c = ox * ox + oz * oz - hitRadius * hitRadius
                local disc = b * b - 4.0 * a * c

                if disc >= 0 and a > 1e-6 then
                    local sqrtD = math.sqrt(disc)
                    local t1 = (-b - sqrtD) / (2.0 * a)
                    local t2 = (-b + sqrtD) / (2.0 * a)
                    local tCenter = -b / (2.0 * a)
                    local hitT = (t1 > 0.1) and t1 or ((t2 > 0.1) and t2 or nil)
                    if hitT and hitT < bestT then
                        local evalT = (tCenter > 0.1) and tCenter or hitT
                        local hitY = self.camPos.y + rayDir.y * evalT
                        if hitY >= -0.35 and hitY <= Renderer3D.PEG_HEIGHT + 0.45 then
                            bestT = hitT
                            bestX, bestZ = gx, gz
                            if isFree then
                                local bestDist = 1e9
                                local chosenY = nil
                                for ty = 1, 4 do
                                    if boardLogic:canPlace(gx, ty, gz) then
                                        local py = self:pieceWorldY(ty, pieceSkin)
                                        local d = math.abs(hitY - py)
                                        if d < bestDist then
                                            bestDist = d
                                            chosenY = ty
                                        end
                                    end
                                end
                                bestY = chosenY
                            else
                                bestY = boardLogic and boardLogic:getNextEmptyY(gx, gz) or 1
                            end
                        end
                    end
                end
            end
        end
    end

    return bestX, bestZ, bestY
end

function Renderer3D:_getPieceMaterialAndMesh(pieceSkin, player, gy)
    local style = pieceSkin and pieceSkin.style or "wood"
    if style == "donut" then
        return 1.0, self.meshTorus
    elseif style == "pine" then
        if gy == 4 then
            return 2.0, self.meshPineConeTip
        end
        return 2.0, self.meshPineTier
    elseif style == "nuclear" then
        return (player == 1) and 3.0 or 4.0, self.meshTorus
    elseif style == "thin" then
        return 7.0, self.meshThinTorus
    elseif style == "beads" then
        return 0.0, self.meshBead
    elseif style == "pumpkin" then
        return 14.0, self.meshPumpkin
    elseif style == "snowman" then
        if gy == 4 then
            return 0.0, self.meshTopHat
        end
        return 10.0, self.meshSphere
    elseif style == "metal" then
        return 7.0, self.meshTorus
    elseif style == "iron_block" then
        return 7.0, self.meshSquareBlock
    elseif style == "skyscraper_block" then
        return 19.0, self.meshSquareBlock
    end
    return 0.0, self.meshTorus
end

-- Безопасная отправка uniform: пропускает переменные, удалённые оптимизатором GLSL (важно для WebGL / мобильных GPU)
function Renderer3D:_send(name, value)
    if self.shader:hasUniform(name) then
        self.shader:send(name, value)
    end
end

function Renderer3D:_drawMeshTransform(mesh, pos, axisX, axisY, axisZ, baseColor, emissive, specular, woodStrength, woodScale, materialType)
    self:_send("u_modelPos",     pos)
    self:_send("u_modelX",       axisX)
    self:_send("u_modelY",       axisY)
    self:_send("u_modelZ",       axisZ)
    self:_send("u_baseColor",    baseColor)
    self:_send("u_emissive",     emissive or { 0.0, 0.0, 0.0 })
    self:_send("u_specular",     specular or 0.28)
    self:_send("u_woodStrength", woodStrength or 0.85)
    self:_send("u_woodScale",    woodScale or 1.0)
    self:_send("u_materialType", materialType or 0.0)
    love.graphics.draw(mesh)
end

function Renderer3D:renderScene(screenW, screenH, state)
    self:_updateCameraBasis()
    local aspect = screenW / screenH
    local f = 1.0 / math.tan(self.fovRad * 0.5)

    local clipOffsetX = state.clipOffsetX or 0.0
    local clipOffsetY = state.clipOffsetY or 0.0

    love.graphics.setDepthMode("lequal", true)
    love.graphics.setShader(self.shader)

    local animTime = state.staticBoardAnim and 0.0 or love.timer.getTime()
    local hrLen = math.sqrt(self.camRight.x * self.camRight.x + self.camRight.z * self.camRight.z)
    local hfLen = math.sqrt(self.camFwd.x * self.camFwd.x + self.camFwd.z * self.camFwd.z)
    local hrX = (hrLen > 1e-4) and (self.camRight.x / hrLen) or 1.0
    local hrZ = (hrLen > 1e-4) and (self.camRight.z / hrLen) or 0.0
    local hfX = (hfLen > 1e-4) and (self.camFwd.x / hfLen) or 0.0
    local hfZ = (hfLen > 1e-4) and (self.camFwd.z / hfLen) or -1.0

    self:_send("u_time",       animTime)
    self:_send("u_cloudTime",  love.timer.getTime())
    local moonRay = { 0.0, 1.0, 0.0 }
    if state.moonScreenX and state.moonScreenY and screenW > 0 and screenH > 0 then
        local mNdcX = ((state.moonScreenX / screenW) * 2.0 - 1.0) - clipOffsetX
        local mNdcY = (1.0 - (state.moonScreenY / screenH) * 2.0) - clipOffsetY
        local mr = vNorm({
            x = self.camFwd.x + self.camRight.x * (mNdcX * aspect / f) + self.camUp.x * (mNdcY / f),
            y = self.camFwd.y + self.camRight.y * (mNdcX * aspect / f) + self.camUp.y * (mNdcY / f),
            z = self.camFwd.z + self.camRight.z * (mNdcX * aspect / f) + self.camUp.z * (mNdcY / f)
        })
        moonRay = { mr.x, mr.y, mr.z }
    end
    self:_send("u_moonRayDir", moonRay)
    self:_send("u_camPos",     { self.camPos.x,   self.camPos.y,   self.camPos.z   })
    self:_send("u_eyePos",     { self.camPos.x,   self.camPos.y,   self.camPos.z   })
    self:_send("u_camHorizRight", { hrX, hrZ })
    self:_send("u_camHorizFwd",   { hfX, hfZ })
    self:_send("u_camRight",   { self.camRight.x, self.camRight.y, self.camRight.z })
    self:_send("u_camUp",      { self.camUp.x,    self.camUp.y,    self.camUp.z    })
    self:_send("u_camFwd",     { self.camFwd.x,   self.camFwd.y,   self.camFwd.z   })
    self:_send("u_projScale",  { f / aspect, f })
    self:_send("u_clipOffset", { clipOffsetX, clipOffsetY })

    local boardSkin  = state.boardSkinOverride or state.config.getBoardSkin()
    local pieceSkin  = state.config.getPieceSkin()
    local pieceSkinW = state.whitePieceSkin or pieceSkin
    local pieceSkinB = state.blackPieceSkin or pieceSkin
    local bStyle     = boardSkin.style or "wood"
    local isForestBoard     = (bStyle == "forest")
    local isMetalBoard      = (bStyle == "metal")
    local isCakeBoard       = (bStyle == "cake")
    local isSnowyBoard      = (bStyle == "snow" or bStyle == "snowy")
    local isJapaneseBoard   = (bStyle == "japanese_roof")
    local isSkyscraperBoard = (bStyle == "skyscraper")
    local isManhattanBoard  = (bStyle == "manhattan")
    local isChernobylBoard  = (bStyle == "chernobyl")
    local isRound   = (state.config.boardShape == "round") and (not boardSkin.forceSquare) and (not isChernobylBoard) and (not isManhattanBoard)
    local baseMatType = isForestBoard and 5.0
        or (isMetalBoard and 7.0)
        or (isCakeBoard and 8.0)
        or (isSnowyBoard and 15.0)
        or (isJapaneseBoard and 13.0)
        or ((isSkyscraperBoard or isManhattanBoard) and 11.0)
        or (isChernobylBoard and 20.0)
        or 0.0
    local pegMatType = isForestBoard and 6.0
        or ((isMetalBoard or isSkyscraperBoard or isManhattanBoard) and 7.0)
        or (isCakeBoard and 9.0)
        or (isChernobylBoard and 21.0)
        or 0.0
    local rimMatType = isForestBoard and 6.0
        or ((isMetalBoard or isSkyscraperBoard or isChernobylBoard) and 7.0)
        or (isCakeBoard and 9.0)
        or (isJapaneseBoard and 13.0)
        or 0.0

    -- 1. Отрисовка базы поля (или 16 небоскрёбов для Манхэттена / крыша пагоды / башня)
    local baseMesh = isRound and self.meshRoundBase or self.meshBox
    local baseSpan = isRound
        and ((Renderer3D.GRID_SIZE - 1) * Renderer3D.PEG_SPACING + 2.95)
        or  ((Renderer3D.GRID_SIZE - 1) * Renderer3D.PEG_SPACING + 2.05)
    local baseH = Renderer3D.BASE_THICKNESS

    if isManhattanBoard then
        -- 16 высоких многоуровневых небоскрёбов (без пола — уходят глубоко в ночной туман и тучи)
        local towerHeights = {
            10.6,  9.8, 11.0, 10.1,
            10.2, 11.2, 10.7, 10.5,
            10.8, 10.5, 10.0, 11.1,
            10.1, 10.6, 10.7,  9.9
        }
        local roofOffsets = {
            -0.14, -0.44, -0.06, -0.34,
            -0.36, -0.02, -0.22, -0.16,
            -0.10, -0.26, -0.42, -0.04,
            -0.32, -0.18, -0.12, -0.40
        }
        for gx = 1, 4 do
            for gz = 1, 4 do
                local idx = (gx - 1) * 4 + gz
                local wx, wz = self:gridToWorldXZ(gx, gz)
                local th = towerHeights[idx]
                local roofY = roofOffsets[idx]
                local topH = 0.52
                local mainH = th - topH
                local mainCenterY = (roofY - topH) - mainH * 0.5

                -- Нижняя основная башня (стекло и сталь)
                self:_drawMeshTransform(
                    self.meshBox,
                    { wx, mainCenterY, wz },
                    { 1.04, 0, 0 }, { 0, mainH, 0 }, { 0, 0, 1.04 },
                    boardSkin.baseColor, { 0, 0, 0 },
                    0.75, 0.0, 0.85, 11.0
                )
                -- Верхний архитектурный ярус с уступом (Art Deco setback)
                self:_drawMeshTransform(
                    self.meshBox,
                    { wx, roofY - topH * 0.5, wz },
                    { 0.82, 0, 0 }, { 0, topH, 0 }, { 0, 0, 0.82 },
                    boardSkin.baseColor, { 0, 0, 0 },
                    0.82, 0.0, 0.90, 11.0
                )
                -- Металлический парапет крыши и основание шпиля
                self:_drawMeshTransform(
                    self.meshBox,
                    { wx, roofY + 0.015, wz },
                    { 0.86, 0, 0 }, { 0, 0.045, 0 }, { 0, 0, 0.86 },
                    { 0.16, 0.19, 0.25, 1.0 }, { 0, 0, 0 },
                    0.85, 0.0, 1.0, 7.0
                )
                self:_drawMeshTransform(
                    self.meshBox,
                    { wx, roofY + 0.06, wz },
                    { 0.36, 0, 0 }, { 0, 0.08, 0 }, { 0, 0, 0.36 },
                    { 0.24, 0.28, 0.36, 1.0 }, { 0, 0, 0 },
                    0.88, 0.0, 1.0, 7.0
                )
            end
        end
    elseif isJapaneseBoard then
        self:_drawMeshTransform(
            self.meshJapaneseRoof,
            { 0.0, -0.18, 0.0 },
            { baseSpan * 1.12, 0, 0 },
            { 0, 1.05, 0 },
            { 0, 0, baseSpan * 1.12 },
            boardSkin.baseColor,
            { 0, 0, 0 },
            0.38,
            0.0,
            1.0,
            13.0
        )
    elseif isSkyscraperBoard then
        -- Высокий небоскрёб (круглый или квадратный)
        self:_drawMeshTransform(
            baseMesh,
            { 0.0, -3.6, 0.0 },
            { baseSpan * 0.96, 0, 0 },
            { 0, 7.25, 0 },
            { 0, 0, baseSpan * 0.96 },
            boardSkin.baseColor,
            { 0, 0, 0 },
            0.72,
            0.0,
            0.8,
            11.0
        )
        local rimSpan = baseSpan + 0.14
        self:_drawMeshTransform(
            baseMesh,
            { 0.0, -0.02, 0.0 },
            { rimSpan, 0, 0 },
            { 0, 0.22, 0 },
            { 0, 0, rimSpan },
            { 0.22, 0.26, 0.34, 1.0 },
            { 0, 0, 0 },
            0.85,
            0.0,
            1.0,
            7.0
        )
    else
        self:_drawMeshTransform(
            baseMesh,
            { 0.0, -baseH * 0.5 + 0.02, 0.0 },
            { baseSpan, 0, 0 },
            { 0, baseH, 0 },
            { 0, 0, baseSpan },
            boardSkin.baseColor,
            { 0, 0, 0 },
            isMetalBoard and 0.78 or 0.22,
            boardSkin.woodStrength,
            0.75,
            baseMatType
        )

        local rimSpan = baseSpan + 0.22
        self:_drawMeshTransform(
            baseMesh,
            { 0.0, -baseH * 0.5 - 0.05, 0.0 },
            { rimSpan, 0, 0 },
            { 0, baseH * 0.82, 0 },
            { 0, 0, rimSpan },
            { boardSkin.baseColor[1] * 0.72, boardSkin.baseColor[2] * 0.72, boardSkin.baseColor[3] * 0.72, 1.0 },
            { 0, 0, 0 },
            isMetalBoard and 0.65 or 0.18,
            boardSkin.woodStrength,
            0.75,
            rimMatType
        )
    end

    -- 1b. 3D-травинки для лесного поля / вентиляционный парапет ЧАЭС
    if isChernobylBoard then
        -- Промзона: бетонный короб саркофага и вентканал вдоль задней кромки крыши ЧАЭС
        self:_drawMeshTransform(
            self.meshBox,
            { 0.0, 0.11, -3.02 },
            { 5.6, 0, 0 }, { 0, 0.24, 0 }, { 0, 0, 0.42 },
            { 0.24, 0.26, 0.28, 1.0 }, { 0, 0, 0 }, 0.25, 0.0, 1.0, 20.0
        )
        self:_drawMeshTransform(
            self.meshBox,
            { -2.98, 0.08, 0.0 },
            { 0.34, 0, 0 }, { 0, 0.18, 0 }, { 0, 0, 5.6 },
            { 0.22, 0.24, 0.26, 1.0 }, { 0, 0, 0 }, 0.25, 0.0, 1.0, 7.0
        )
    end
    if isForestBoard then
        for gx = 1, 4 do
            for gz = 1, 4 do
                local wx, wz = self:gridToWorldXZ(gx, gz)
                for k = 1, 4 do
                    local ang = (gx * 1.7 + gz * 2.3 + k * 1.57)
                    local rad = 0.28 + (k % 2) * 0.18
                    local tx = wx + math.cos(ang) * rad
                    local tz = wz + math.sin(ang) * rad
                    self:_drawMeshTransform(
                        self.meshGrassTuft,
                        { tx, 0.12, tz },
                        { math.cos(ang) * 0.28, 0, math.sin(ang) * 0.28 },
                        { 0, 0.30, 0 },
                        { -math.sin(ang) * 0.28, 0, math.cos(ang) * 0.28 },
                        { 0.24, 0.68, 0.18, 1.0 },
                        { 0, 0, 0 },
                        0.15,
                        0.0,
                        1.0,
                        16.0
                    )
                end
            end
        end
    end

    -- 2. Отрисовка 16 столбиков (или антенн / стволов деревьев)
    local roofOffsetsManhattan = {
        -0.14, -0.44, -0.06, -0.34,
        -0.36, -0.02, -0.22, -0.16,
        -0.10, -0.26, -0.42, -0.04,
        -0.32, -0.18, -0.12, -0.40
    }
    for gx = 1, 4 do
        for gz = 1, 4 do
            local wx, wz = self:gridToWorldXZ(gx, gz)
            local isHovered = (state.hoveredX == gx and state.hoveredZ == gz)
            local pColor    = isHovered and boardSkin.pegHover or boardSkin.pegColor
            local pEmissive = isHovered and { 0.28, 0.20, 0.06 } or { 0.0, 0.0, 0.0 }
            local pegScaleXZ = isManhattanBoard and 0.24 or (isSkyscraperBoard and 0.52 or (isChernobylBoard and 1.18 or 1.0))

            if isManhattanBoard then
                local idx = (gx - 1) * 4 + gz
                local roofY = roofOffsetsManhattan[idx]
                local topY = Renderer3D.PEG_HEIGHT
                local spireH = topY - roofY
                local spireScaleY = spireH / Renderer3D.PEG_HEIGHT
                -- Рассинхронное попеременное свечение и полное затухание каждого штыря/маячка
                local spirePhases = { 0.00, 2.71, 5.14, 1.38, 4.22, 0.79, 3.65, 5.89, 2.04, 4.91, 1.12, 3.31, 5.47, 0.43, 2.44, 4.58 }
                local spireFreqs  = { 0.85, 1.24, 0.71, 1.43, 0.96, 1.57, 0.79, 1.18, 1.07, 0.66, 1.36, 0.88, 1.29, 0.74, 1.12, 0.92 }
                local t = state.staticBoardAnim and 0.0 or love.timer.getTime()
                local rawWave = math.sin(t * spireFreqs[idx] + spirePhases[idx])
                local beaconPulse = state.staticBoardAnim and ((idx % 3 == 0) and 0.92 or 0.0) or math.pow(math.max(0.0, rawWave), 1.35)

                local spireColor = pColor
                local spireEmissive = pEmissive
                if not isHovered and beaconPulse > 0.01 then
                    spireColor = {
                        math.min(1.0, pColor[1] + 0.34 * beaconPulse),
                        math.max(0.0, pColor[2] * (1.0 - 0.35 * beaconPulse) + 0.04 * beaconPulse),
                        math.max(0.0, pColor[3] * (1.0 - 0.38 * beaconPulse) + 0.03 * beaconPulse),
                        1.0
                    }
                    spireEmissive = { 0.62 * beaconPulse, 0.09 * beaconPulse, 0.06 * beaconPulse }
                end

                self:_drawMeshTransform(
                    self.meshPeg,
                    { wx, roofY, wz },
                    { pegScaleXZ, 0, 0 },
                    { 0, spireScaleY, 0 },
                    { 0, 0, pegScaleXZ },
                    spireColor,
                    spireEmissive,
                    0.92,
                    0.0,
                    1.35,
                    7.0
                )
                -- Маячок на вершине шпиля (загорается и полностью тухнет в рассинхрон)
                local tipCol = {
                    0.18 + 0.82 * beaconPulse,
                    0.05 + 0.11 * beaconPulse,
                    0.05 + 0.06 * beaconPulse,
                    1.0
                }
                self:_drawMeshTransform(
                    self.meshSphere,
                    { wx, topY + 0.05, wz },
                    { 0.092, 0, 0 },
                    { 0, 0.092, 0 },
                    { 0, 0, 0.092 },
                    tipCol,
                    { 1.55 * beaconPulse, 0.16 * beaconPulse, 0.10 * beaconPulse },
                    0.95,
                    0.0,
                    1.0,
                    12.0
                )
                if beaconPulse > 0.03 then
                    self:_drawMeshTransform(
                        self.meshSphere,
                        { wx, topY + 0.05, wz },
                        { 0.175, 0, 0 },
                        { 0, 0.175, 0 },
                        { 0, 0, 0.175 },
                        { 1.00, 0.16, 0.12, 0.28 * beaconPulse },
                        { 0.95 * beaconPulse, 0.10 * beaconPulse, 0.06 * beaconPulse },
                        0.0,
                        0.0,
                        1.0,
                        0.0
                    )
                end
            else
                self:_drawMeshTransform(
                    self.meshPeg,
                    { wx, 0.0, wz },
                    { pegScaleXZ, 0, 0 },
                    { 0, 1, 0 },
                    { 0, 0, pegScaleXZ },
                    pColor,
                    pEmissive,
                    (isMetalBoard or isSkyscraperBoard) and 0.88 or 0.32,
                    boardSkin.woodStrength,
                    1.35,
                    pegMatType
                )
                if isChernobylBoard then
                    -- Уверенное широкое основание трубы на крыше и закопчённый раструб на вершине
                    self:_drawMeshTransform(
                        self.meshCylinder,
                        { wx, 0.11, wz },
                        { 0.24, 0, 0 }, { 0, 0.22, 0 }, { 0, 0, 0.24 },
                        { 0.28, 0.30, 0.32, 1.0 }, pEmissive,
                        0.28, 0.0, 1.0, 7.0
                    )
                    self:_drawMeshTransform(
                        self.meshCylinder,
                        { wx, Renderer3D.PEG_HEIGHT - 0.04, wz },
                        { 0.195, 0, 0 }, { 0, 0.11, 0 }, { 0, 0, 0.195 },
                        { 0.14, 0.14, 0.15, 1.0 }, pEmissive,
                        0.20, 0.0, 1.0, 0.0
                    )
                end
            end
        end
    end

    -- 3. Если это демо-сцена миттельшпиля в меню — рисуем разбросанные рядом с полем фишки (кроме Манхэттена без пола)
    if state.showScattered and not isManhattanBoard then
        for _, sp in ipairs(self.scatteredPieces) do
            local col = (sp.player == 1) and pieceSkin.player1Color or pieceSkin.player2Color
            local matType, pMesh = self:_getPieceMaterialAndMesh(pieceSkin, sp.player)
            self:_drawMeshTransform(
                pMesh,
                { sp.x, sp.y, sp.z },
                { 1, sp.tiltX, 0 },
                { -sp.tiltX, 1, sp.tiltZ },
                { 0, -sp.tiltZ, 1 },
                col,
                { 0, 0, 0 },
                pieceSkin.specular,
                pieceSkin.woodStrength,
                1.8,
                matType
            )
        end
    end

    local totalMoves = state.logic and #state.logic.moveHistory or 0
    local maxPly = (state.maxPly ~= nil) and math.max(0, math.min(totalMoves, state.maxPly)) or totalMoves
    local isRewound = (maxPly < totalMoves)

    local winSet = {}
    if state.logic and state.logic.winningLine and not isRewound then
        for _, c in ipairs(state.logic.winningLine) do
            winSet[c.x .. ":" .. c.y .. ":" .. c.z] = true
        end
    end

    local pulse = state.staticBoardAnim and 0.5 or (0.5 + 0.5 * math.sin(love.timer.getTime() * 6.0))

    -- 4. Отрисовка нанизанных на столбики фишек (с учетом отмотки ходов maxPly, вольного режима и особых скинов)
    if state.logic then
        local function drawSinglePiece(gx, gy, gz, player, isCurrentRewindHead, overrideAlpha)
            local pSkin = (player == 1) and pieceSkinW or pieceSkinB
            local wx, wy, wz = self:gridToWorldXYZ(gx, gy, gz, pSkin)
            local isDropping = (not overrideAlpha and not isRewound and state.activeDrop and state.activeDrop.x == gx and state.activeDrop.y == gy and state.activeDrop.z == gz)
            if isDropping then
                wy = state.activeDrop.currentY
            end

            local baseCol = (player == 1) and pSkin.player1Color or pSkin.player2Color
            if overrideAlpha then
                baseCol = { baseCol[1], baseCol[2], baseCol[3], overrideAlpha }
            end
            local key = gx .. ":" .. gy .. ":" .. gz
            local isWinPiece = (not overrideAlpha) and winSet[key]
            local matType, pMesh = self:_getPieceMaterialAndMesh(pSkin, player, gy)

            local taperXZ = 1.0
            local scaleY = 1.0
            local spinAngle = 0.0
            local dockFlash = 0.0
            if pSkin.style == "pine" then
                -- Ёлка: нижний ярус широкий, верхушка пушистым конусом закрывает штырь
                taperXZ = 1.24 - (gy - 1) * 0.14
                scaleY = 1.0
            elseif pSkin.style == "snowman" then
                if gy == 1 then
                    taperXZ, scaleY = 1.04, 0.80
                elseif gy == 2 then
                    taperXZ, scaleY = 0.88, 0.72
                elseif gy == 3 then
                    taperXZ, scaleY = 0.74, 0.64
                elseif gy == 4 then
                    taperXZ, scaleY = 0.88, 1.00
                    baseCol = { 0.08, 0.08, 0.10, overrideAlpha or 1.0 }
                end
            elseif pSkin.style == "skyscraper_block" then
                -- Бесшовный рост башни: стыки ровно на половине шага, а 1-й блок ложится прямо на крышу
                local targetWy = self:pieceWorldY(gy, pSkin)
                local slotTop = targetWy + Renderer3D.SLOT_STEP_Y * 0.5
                local slotBot
                if gy == 1 then
                    local idxM = (gx - 1) * 4 + gz
                    slotBot = isManhattanBoard and ((roofOffsetsManhattan[idxM] or 0.0) + 0.035) or 0.0
                else
                    slotBot = slotTop - Renderer3D.SLOT_STEP_Y
                end
                local blockH = math.max(0.39, slotTop - slotBot)
                local finalWy = (slotTop + slotBot) * 0.5
                wy = isDropping and (finalWy + (state.activeDrop.currentY - targetWy)) or finalWy
                scaleY = blockH / 0.39
                taperXZ = isManhattanBoard and 0.90 or 1.0
                if isDropping then
                    local dur = math.max(0.05, state.activeDrop.duration or 0.35)
                    local el = math.max(0.0, state.activeDrop.elapsed or 0.0)
                    local fallT = math.min(1.0, el / (dur * 0.45))
                    local rem = 1.0 - fallT
                    -- Плавное нанизывание по шпилю с доворотом на 90°, вытяжением в полёте и мягкой вспышкой стыковки
                    spinAngle = (rem * rem) * (math.pi * 0.5)
                    local dropSpan = math.max(0.1, (state.activeDrop.startY or Renderer3D.DROP_SPAWN_Y) - targetWy)
                    local hFrac = math.max(0.0, (state.activeDrop.currentY - targetWy) / dropSpan)
                    scaleY = scaleY * (1.0 + hFrac * 0.15)
                    taperXZ = taperXZ * (1.0 - hFrac * 0.06)
                    if fallT > 0.72 then
                        dockFlash = math.sin(((el / dur) - 0.32) / 0.68 * math.pi)
                        dockFlash = math.max(0.0, dockFlash)
                    end
                end
            elseif pSkin.taperByHeight then
                taperXZ = 1.28 - (gy - 1) * 0.19
            end

            local scale = 1.0
            local emissive = { 0.0, 0.0, 0.0 }
            if isWinPiece then
                scale = 1.0 + 0.08 * pulse
                emissive = { 0.45 * pulse + 0.15, 0.34 * pulse + 0.10, 0.05 }
            elseif isCurrentRewindHead then
                emissive = { 0.18 * pulse, 0.18 * pulse, 0.08 * pulse }
            elseif dockFlash > 0.01 then
                emissive = { 0.28 * dockFlash, 0.24 * dockFlash, 0.12 * dockFlash }
            elseif overrideAlpha then
                local gp = 0.82 + 0.18 * pulse
                emissive = {
                    math.max(0.26, baseCol[1] * 0.45) * gp,
                    math.max(0.26, baseCol[2] * 0.45) * gp,
                    math.max(0.28, baseCol[3] * 0.45) * gp
                }
            end

            local cSpin, sSpin = math.cos(spinAngle), math.sin(spinAngle)
            self:_drawMeshTransform(
                pMesh,
                { wx, wy, wz },
                { scale * taperXZ * cSpin, 0, scale * taperXZ * sSpin },
                { 0, scale * scaleY, 0 },
                { -scale * taperXZ * sSpin, 0, scale * taperXZ * cSpin },
                baseCol,
                emissive,
                pSkin.specular,
                pSkin.woodStrength,
                1.8,
                matType
            )

            -- Золотая 3D-звезда на макушке собранной ёлки (gy == 4)
            if pSkin.style == "pine" and gy == 4 and not overrideAlpha then
                local sa = math.rad(35) + (state.staticBoardAnim and 0.0 or love.timer.getTime() * 0.75)
                local cS, sS = math.cos(sa), math.sin(sa)
                self:_drawMeshTransform(
                    self.meshStar,
                    { wx, wy + 0.78, wz },
                    { cS, 0, -sS },
                    { 0, 1.0, 0 },
                    { sS, 0, cS },
                    { 1.00, 0.82, 0.16, 1.0 },
                    { 0.35 + 0.12 * pulse, 0.24 + 0.08 * pulse, 0.04 },
                    0.95, 0.0, 1.0, 7.0
                )
            end

            -- Детали снеговика: шарф + пуговицы (gy=2), лицо с морковкой (gy=3), лента на цилиндре (gy=4)
            if pSkin.style == "snowman" and not overrideAlpha then
                -- Лицом к базовой камере (yaw = 35 deg): вперёд (fx, fz), вправо (rx, rz)
                local fx, fz = 0.5736, 0.8192
                local rx, rz = 0.8192, -0.5736
                local accentCol = (player == 1) and { 0.88, 0.14, 0.18, 1.0 } or { 0.14, 0.40, 0.92, 1.0 }

                if gy == 2 then
                    -- Уютный шарфик на верхней части туловища
                    self:_drawMeshTransform(
                        self.meshTorus,
                        { wx, wy + 0.31, wz },
                        { 0.74, 0, 0 }, { 0, 0.36, 0 }, { 0, 0, 0.74 },
                        accentCol, { 0, 0, 0 }, 0.22, 0.0, 1.0, 0.0
                    )
                    -- Хвостик шарфа спереди справа
                    self:_drawMeshTransform(
                        self.meshBox,
                        { wx + fx * 0.28 + rx * 0.14, wy + 0.15, wz + fz * 0.28 + rz * 0.14 },
                        { rx * 0.12, 0, rz * 0.12 },
                        { fx * 0.04, 0.24, fz * 0.04 },
                        { fx * 0.07, 0, fz * 0.07 },
                        accentCol, { 0, 0, 0 }, 0.20, 0.0, 1.0, 0.0
                    )
                    -- 3 угольные пуговицы на груди
                    for _, bInfo in ipairs({ { -0.14, 0.41 }, { -0.02, 0.43 }, { 0.10, 0.42 } }) do
                        local dy, rad = bInfo[1], bInfo[2]
                        self:_drawMeshTransform(
                            self.meshSphere,
                            { wx + fx * rad, wy + dy, wz + fz * rad },
                            { 0.068, 0, 0 }, { 0, 0.068, 0 }, { 0, 0, 0.068 },
                            { 0.04, 0.04, 0.05, 1.0 }, { 0, 0, 0 }, 0.7, 0.0, 1.0, 0.0
                        )
                    end
                elseif gy == 3 then
                    -- 2 блестящих угольных глазика
                    for _, side in ipairs({ -1, 1 }) do
                        local ex = wx + fx * 0.33 + rx * (side * 0.115)
                        local ez = wz + fz * 0.33 + rz * (side * 0.115)
                        self:_drawMeshTransform(
                            self.meshSphere,
                            { ex, wy + 0.09, ez },
                            { 0.065, 0, 0 }, { 0, 0.065, 0 }, { 0, 0, 0.065 },
                            { 0.03, 0.03, 0.04, 1.0 }, { 0, 0, 0 }, 0.85, 0.0, 1.0, 0.0
                        )
                    end
                    -- Румянец на щеках
                    for _, side in ipairs({ -1, 1 }) do
                        local cx = wx + fx * 0.29 + rx * (side * 0.185)
                        local cz = wz + fz * 0.29 + rz * (side * 0.185)
                        self:_drawMeshTransform(
                            self.meshSphere,
                            { cx, wy - 0.01, cz },
                            { 0.055, 0, 0 }, { 0, 0.045, 0 }, { 0, 0, 0.055 },
                            { 0.96, 0.42, 0.46, 1.0 }, { 0, 0, 0 }, 0.20, 0.0, 1.0, 0.0
                        )
                    end
                    -- Ярко-оранжевая морковка-нос, смотрящая прямо вперёд
                    self:_drawMeshTransform(
                        self.meshPineConeTip,
                        { wx + fx * 0.40, wy - 0.01, wz + fz * 0.40 },
                        { rx * 0.11, 0, rz * 0.11 },
                        { fx * 0.30, 0, fz * 0.30 },
                        { 0, -0.11, 0 },
                        { 1.00, 0.46, 0.04, 1.0 }, { 0.14, 0.05, 0.0 }, 0.45, 0.0, 1.0, 0.0
                    )
                    -- Улыбка из 5 угольков
                    for _, m in ipairs({
                        { -0.14, -0.075, 0.31 },
                        { -0.07, -0.105, 0.33 },
                        {  0.00, -0.115, 0.34 },
                        {  0.07, -0.105, 0.33 },
                        {  0.14, -0.075, 0.31 }
                    }) do
                        self:_drawMeshTransform(
                            self.meshSphere,
                            { wx + fx * m[3] + rx * m[1], wy + m[2], wz + fz * m[3] + rz * m[1] },
                            { 0.040, 0, 0 }, { 0, 0.040, 0 }, { 0, 0, 0.040 },
                            { 0.03, 0.03, 0.04, 1.0 }, { 0, 0, 0 }, 0.65, 0.0, 1.0, 0.0
                        )
                    end
                elseif gy == 4 then
                    -- Цветная атласная лента плотно у основания цилиндра-шляпы (радиус тульи 0.27*0.88 = 0.24)
                    self:_drawMeshTransform(
                        self.meshCylinder,
                        { wx, wy + 0.11, wz },
                        { 0.252, 0, 0 }, { 0, 0.11, 0 }, { 0, 0, 0.252 },
                        accentCol, { 0, 0, 0 }, 0.55, 0.0, 1.0, 0.0
                    )
                end
            end
        end

        if isRewound and #state.logic.moveHistory > 0 then
            for idx = 1, maxPly do
                local m = state.logic.moveHistory[idx]
                if m then
                    drawSinglePiece(m.x, m.y, m.z, m.player, idx == maxPly)
                end
            end
        else
            for gx = 1, 4 do
                for gz = 1, 4 do
                    for gy = 1, 4 do
                        local p = state.logic.grid[gx][gy][gz]
                        if p and p ~= 0 then
                            drawSinglePiece(gx, gy, gz, p, false)
                        end
                    end
                end
            end
        end

        -- Полупрозрачный предосмотр будущей фишки и уровня на штыре в режиме без гравитации (Вольный режим)
        if state.logic.ruleMode == "free" and state.hoveredX and state.hoveredZ and state.hoveredY
           and not state.activeDrop and not isRewound and not state.logic.isGameOver then
            if state.logic:canPlace(state.hoveredX, state.hoveredY, state.hoveredZ) then
                local pSkin = (state.logic.currentPlayer == 1) and pieceSkinW or pieceSkinB
                local gx, gy, gz = state.hoveredX, state.hoveredY, state.hoveredZ
                local wx, wy, wz = self:gridToWorldXYZ(gx, gy, gz, pSkin)
                love.graphics.setDepthMode("lequal", false)
                love.graphics.setBlendMode("alpha")
                drawSinglePiece(gx, gy, gz, state.logic.currentPlayer, false, 0.72)
                self:_drawMeshTransform(
                    self.meshThinTorus,
                    { wx, wy, wz },
                    { 1.16, 0, 0 }, { 0, 0.36, 0 }, { 0, 0, 1.16 },
                    { 1.00, 0.90, 0.42, 0.26 },
                    { 0.45, 0.36, 0.08 },
                    0.2, 0.0, 1.0, 0.0
                )
                love.graphics.setDepthMode("lequal", true)
            end
        end
    end

    -- 4b. Легендарная 3D-бабочка для травяного поля (открывается при 10 победах на поле forest_glade)
    local prof = (state.config and state.config.profile) or {}
    local bWins = (prof.boardWins and prof.boardWins.forest_glade)
               or (prof.skinWins and prof.skinWins.forest_glade)
               or 0
    if boardSkin.style == "forest" and bWins >= 10 then
        local t = love.timer.getTime()
        local bx = math.cos(t * 0.85) * 3.1
        local bz = math.sin(t * 0.85) * 3.1
        local by = 2.15 + math.sin(t * 2.2) * 0.45
        local flap = math.sin(t * 14.0) * 0.65
        local cf, sf = math.cos(flap), math.sin(flap)
        -- Тельце бабочки
        self:_drawMeshTransform(
            self.meshSphere,
            { bx, by, bz },
            { 0.08, 0, 0 }, { 0, 0.08, 0 }, { 0, 0, 0.28 },
            { 0.12, 0.10, 0.14, 1.0 }, { 0, 0, 0 }, 0.6, 0.0, 1.0, 0.0
        )
        -- Левое и правое крыло
        self:_drawMeshTransform(
            self.meshButterflyWing,
            { bx, by, bz },
            { 0.45 * cf, 0.45 * sf, 0 }, { -0.45 * sf, 0.45 * cf, 0 }, { 0, 0, 0.45 },
            { 0.98, 0.78, 0.18, 1.0 }, { 0.25, 0.18, 0.04 }, 0.85, 0.0, 1.0, 17.0
        )
        self:_drawMeshTransform(
            self.meshButterflyWing,
            { bx, by, bz },
            { -0.45 * cf, 0.45 * sf, 0 }, { 0.45 * sf, 0.45 * cf, 0 }, { 0, 0, 0.45 },
            { 0.98, 0.78, 0.18, 1.0 }, { 0.25, 0.18, 0.04 }, 0.85, 0.0, 1.0, 17.0
        )
    end

    -- 5. Победный луч через 4 собранные фишки
    if state.logic and state.logic.winningLine and not state.activeDrop and not isRewound then
        local c1 = state.logic.winningLine[1]
        local c4 = state.logic.winningLine[4]
        local x1, y1, z1 = self:gridToWorldXYZ(c1.x, c1.y, c1.z)
        local x2, y2, z2 = self:gridToWorldXYZ(c4.x, c4.y, c4.z)

        local mid = { (x1 + x2) * 0.5, (y1 + y2) * 0.5, (z1 + z2) * 0.5 }
        local diff = { x = x2 - x1, y = y2 - y1, z = z2 - z1 }
        local len = vLen(diff) + 0.65
        local dirY = vNorm(diff)

        local upRef = math.abs(dirY.y) > 0.95 and { x = 1, y = 0, z = 0 } or { x = 0, y = 1, z = 0 }
        local dirX = vNorm(vCross(upRef, dirY))
        local dirZ = vNorm(vCross(dirY, dirX))
        local beamR = 0.075

        self:_drawMeshTransform(
            self.meshCylinder,
            mid,
            { dirX.x * beamR, dirX.y * beamR, dirX.z * beamR },
            { dirY.x * len,   dirY.y * len,   dirY.z * len   },
            { dirZ.x * beamR, dirZ.y * beamR, dirZ.z * beamR },
            { 1.0, 0.86, 0.22, 1.0 },
            { 0.55, 0.42, 0.08 },
            0.8,
            0.0,
            1.0
        )
    end

    -- 5b. Ночной туман/облака Манхэттена (окутывает башни снизу и мягко растворяется к небу, не перекрывая луну)
    if isManhattanBoard then
        love.graphics.setDepthMode("lequal", false)
        love.graphics.setBlendMode("alpha")
        self:_drawMeshTransform(
            self.meshBox,
            { 0.0, -2.30, 0.0 },
            { 140.0, 0, 0 }, { 0, 0.01, 0 }, { 0, 0, 140.0 },
            { 0.18, 0.24, 0.38, 0.96 },
            { 0.01, 0.02, 0.04 },
            0.0, 0.0, 1.0, 18.0
        )
        self:_drawMeshTransform(
            self.meshBox,
            { 0.0, -1.55, 0.0 },
            { 140.0, 0, 0 }, { 0, 0.01, 0 }, { 0, 0, 140.0 },
            { 0.20, 0.28, 0.44, 0.56 },
            { 0.01, 0.02, 0.04 },
            0.0, 0.0, 1.0, 18.0
        )
        love.graphics.setDepthMode("lequal", true)
    end

    -- 5d. Медленное плавное непрерывное падение снега на снежном поле (snowy_winter)
    if isSnowyBoard then
        love.graphics.setDepthMode("lequal", false)
        love.graphics.setBlendMode("alpha")
        local snowT = love.timer.getTime()
        local snowCount = 54
        for i = 1, snowCount do
            local s1 = ((i * 73.13) % 1.0)
            local s2 = ((i * 41.79) % 1.0)
            local s3 = ((i * 19.47) % 1.0)
            local speed = 0.075 + s3 * 0.055
            local phase = (snowT * speed + s1) % 1.0
            local sy = 5.1 - phase * 5.45
            local baseX = (s1 - 0.5) * 12.6
            local baseZ = (s2 - 0.5) * 12.6
            local swayA = snowT * (0.45 + s3 * 0.35) + i * 1.13
            local sx = baseX + math.sin(swayA) * 0.42
            local sz = baseZ + math.cos(swayA * 0.85) * 0.42
            local edgeFade = math.min(phase / 0.14, (1.0 - phase) / 0.16, 1.0)
            local alpha = math.max(0.0, math.min(1.0, edgeFade)) * (0.68 + 0.28 * s3)
            if alpha > 0.01 then
                local rad = 0.036 + s3 * 0.028
                self:_drawMeshTransform(
                    self.meshSphere,
                    { sx, sy, sz },
                    { rad, 0, 0 }, { 0, rad * 0.9, 0 }, { 0, 0, rad },
                    { 0.95, 0.98, 1.00, alpha },
                    { 0.48, 0.60, 0.82 },
                    0.15, 0.0, 1.0, 0.0
                )
            end
        end
        love.graphics.setDepthMode("lequal", true)
    end

    -- 5c. Густой промышленный дым, поднимающийся из широких труб ЧАЭС
    if isChernobylBoard then
        love.graphics.setDepthMode("lequal", false)
        love.graphics.setBlendMode("alpha")
        local smokeT = state.staticBoardAnim and 1.25 or love.timer.getTime()
        for gx = 1, 4 do
            for gz = 1, 4 do
                local wx, wz = self:gridToWorldXZ(gx, gz)
                local seed = (gx - 1) * 4 + gz
                for k = 0, 2 do
                    local phase = (smokeT * 0.42 + seed * 0.23 + k * 0.333) % 1.0
                    local sy = Renderer3D.PEG_HEIGHT + 0.14 + phase * 1.65
                    local sx = wx + phase * 0.68 + math.sin(phase * 4.5 + seed) * 0.08
                    local sz = wz - phase * 0.28 + math.cos(phase * 3.8 + seed) * 0.07
                    local rad = 0.12 + phase * 0.29
                    local alpha = (1.0 - phase) * (0.28 + 0.22 * math.sin(phase * math.pi))
                    if alpha > 0.01 then
                        self:_drawMeshTransform(
                            self.meshSphere,
                            { sx, sy, sz },
                            { rad, 0, 0 }, { 0, rad * 0.78, 0 }, { 0, 0, rad },
                            { 0.56, 0.58, 0.60, alpha },
                            { 0.03, 0.03, 0.035 },
                            0.0, 0.0, 1.0, 0.0
                        )
                    end
                end
            end
        end
        love.graphics.setDepthMode("lequal", true)
    end

    love.graphics.setShader()
    love.graphics.setDepthMode("always", false)

    -- 6. Отрисовка координат поля (a, b, c, d и 1, 2, 3, 4) на доске
    if state.showCoords and state.coordFont then
        self:drawBoardCoordinates(screenW, screenH, state.coordFont, clipOffsetX, clipOffsetY)
    end
end

function Renderer3D:drawBoardCoordinates(screenW, screenH, font, clipOffsetX, clipOffsetY)
    love.graphics.setFont(font)
    local edgeDist = 3.05

    -- Буквы рядов a, b, c, d вдоль переднего края доски
    for gx = 1, 4 do
        local wx, _ = self:gridToWorldXZ(gx, 1)
        local sx, sy = self:worldToScreen(wx, -0.02, edgeDist, screenW, screenH, clipOffsetX, clipOffsetY)
        if sx and sy then
            local lbl = BoardLogic.COL_NAMES[gx]
            love.graphics.setColor(0.10, 0.10, 0.12, 0.85)
            love.graphics.circle("fill", sx, sy, 12)
            love.graphics.setColor(0.92, 0.92, 0.95, 1.0)
            love.graphics.printf(lbl, sx - 12, sy - font:getHeight() * 0.5, 24, "center")
        end
    end

    -- Цифры линий 1, 2, 3, 4 вдоль левого края доски
    for gz = 1, 4 do
        local _, wz = self:gridToWorldXZ(1, gz)
        local sx, sy = self:worldToScreen(-edgeDist, -0.02, wz, screenW, screenH, clipOffsetX, clipOffsetY)
        if sx and sy then
            local lbl = BoardLogic.ROW_NAMES[gz]
            love.graphics.setColor(0.10, 0.10, 0.12, 0.85)
            love.graphics.circle("fill", sx, sy, 12)
            love.graphics.setColor(0.92, 0.92, 0.95, 1.0)
            love.graphics.printf(lbl, sx - 12, sy - font:getHeight() * 0.5, 24, "center")
        end
    end
end

-- Отрисовка 3D-превью внутри витринной карточки Магазина
function Renderer3D:renderShopPreview(cx, cy, cw, ch, screenW, screenH, previewType, itemData, angle)
    local centerX = cx + cw * 0.5
    local centerY = cy + ch * 0.5
    local clipOffX = (centerX / screenW) * 2.0 - 1.0
    local clipOffY = 1.0 - (centerY / screenH) * 2.0

    local aspect = screenW / screenH
    local f = 1.0 / math.tan(self.fovRad * 0.5)

    -- Временная камера для витрины
    local camPos   = { x = 0.0, y = 4.2, z = 11.5 }
    local camTarget = { x = 0.0, y = 0.0, z = 0.0 }
    local camFwd   = vNorm(vSub(camTarget, camPos))
    local camRight = vNorm(vCross(camFwd, { x = 0, y = 1, z = 0 }))
    local camUp    = vNorm(vCross(camRight, camFwd))

    local sx1, sy1 = love.graphics.transformPoint(cx, cy)
    local sx2, sy2 = love.graphics.transformPoint(cx + cw, cy + ch)
    love.graphics.setScissor(sx1, sy1, math.max(1, sx2 - sx1), math.max(1, sy2 - sy1))
    love.graphics.setDepthMode("lequal", true)
    love.graphics.setShader(self.shader)

    self:_send("u_time",       love.timer.getTime())
    self:_send("u_cloudTime",  love.timer.getTime())
    self:_send("u_moonRayDir", { 0.0, 1.0, 0.0 })
    self:_send("u_camPos",     { camPos.x,   camPos.y,   camPos.z   })
    self:_send("u_eyePos",     { camPos.x,   camPos.y,   camPos.z   })
    self:_send("u_camHorizRight", { 1.0, 0.0 })
    self:_send("u_camHorizFwd",   { 0.0, -1.0 })
    self:_send("u_camRight",   { camRight.x, camRight.y, camRight.z })
    self:_send("u_camUp",      { camUp.x,    camUp.y,    camUp.z    })
    self:_send("u_camFwd",     { camFwd.x,   camFwd.y,   camFwd.z   })
    self:_send("u_projScale",  { (f / aspect) * 0.55, f * 0.55 })
    self:_send("u_clipOffset", { clipOffX, clipOffY })

    local ca, sa = math.cos(angle), math.sin(angle)
    local isSil = (itemData and itemData.silhouette == true)
    local function drawPrev(mesh, pos, axX, axY, axZ, col, em, spec, wood, wScale, mat)
        if isSil then
            self:_drawMeshTransform(
                mesh, pos, axX, axY, axZ,
                { 0.03, 0.03, 0.035, 1.0 }, { 0, 0, 0 },
                0.03, 0.0, 1.0, 0.0
            )
        else
            self:_drawMeshTransform(mesh, pos, axX, axY, axZ, col, em, spec, wood, wScale, mat)
        end
    end

    if previewType == "pieces" then
        local mat1, mesh1 = self:_getPieceMaterialAndMesh(itemData, 1)
        local mat2, mesh2 = self:_getPieceMaterialAndMesh(itemData, 2)

        if itemData.style == "snowman" then
            -- Вращающийся 3D-снеговик с шарфиком, пуговицами, морковкой, глазами и цилиндром
            local tiers = {
                { py = -0.68, sXZ = 1.04, sY = 0.80, gy = 1 },
                { py = -0.22, sXZ = 0.88, sY = 0.72, gy = 2 },
                { py =  0.22, sXZ = 0.74, sY = 0.64, gy = 3 },
                { py =  0.42, sXZ = 0.88, sY = 0.95, gy = 4 },
            }
            for _, t in ipairs(tiers) do
                local matG, meshG = self:_getPieceMaterialAndMesh(itemData, 1, t.gy)
                local col = (t.gy == 4) and { 0.08, 0.08, 0.10, 1.0 } or itemData.player1Color
                drawPrev(
                    meshG,
                    { 0.0, t.py, 0.0 },
                    { ca * t.sXZ, 0, -sa * t.sXZ },
                    { 0, t.sY, 0 },
                    { sa * t.sXZ, 0, ca * t.sXZ },
                    col, { 0, 0, 0 }, itemData.specular or 0.35, 0.0, 1.8, matG
                )
            end
            if not isSil then
                -- Ось «вперёд» и «вправо», вращающиеся вместе со снеговиком
                local fx, fz = sa, ca
                local rx, rz = ca, -sa
                -- Шарфик + пуговицы
                drawPrev(
                    self.meshTorus,
                    { 0.0, 0.00, 0.0 },
                    { ca * 0.74, 0, -sa * 0.74 }, { 0, 0.36, 0 }, { sa * 0.74, 0, ca * 0.74 },
                    { 0.88, 0.14, 0.18, 1.0 }, { 0, 0, 0 }, 0.25, 0.0, 1.0, 0.0
                )
                for _, dy in ipairs({ -0.34, -0.22, -0.10 }) do
                    drawPrev(
                        self.meshSphere,
                        { fx * 0.42, dy, fz * 0.42 },
                        { 0.068, 0, 0 }, { 0, 0.068, 0 }, { 0, 0, 0.068 },
                        { 0.04, 0.04, 0.05, 1.0 }, { 0, 0, 0 }, 0.7, 0.0, 1.0, 0.0
                    )
                end
                -- Глаза
                for _, side in ipairs({ -1, 1 }) do
                    drawPrev(
                        self.meshSphere,
                        { fx * 0.33 + rx * (side * 0.115), 0.31, fz * 0.33 + rz * (side * 0.115) },
                        { 0.065, 0, 0 }, { 0, 0.065, 0 }, { 0, 0, 0.065 },
                        { 0.03, 0.03, 0.04, 1.0 }, { 0, 0, 0 }, 0.85, 0.0, 1.0, 0.0
                    )
                end
                -- Оранжевый нос-морковка
                drawPrev(
                    self.meshPineConeTip,
                    { fx * 0.40, 0.21, fz * 0.40 },
                    { rx * 0.11, 0, rz * 0.11 },
                    { fx * 0.30, 0, fz * 0.30 },
                    { 0, -0.11, 0 },
                    { 1.00, 0.46, 0.04, 1.0 }, { 0.14, 0.05, 0.0 }, 0.45, 0.0, 1.0, 0.0
                )
                -- Улыбка
                for _, m in ipairs({ { -0.12, 0.14, 0.31 }, { -0.05, 0.11, 0.33 }, { 0.05, 0.11, 0.33 }, { 0.12, 0.14, 0.31 } }) do
                    drawPrev(
                        self.meshSphere,
                        { fx * m[3] + rx * m[1], m[2], fz * m[3] + rz * m[1] },
                        { 0.038, 0, 0 }, { 0, 0.038, 0 }, { 0, 0, 0.038 },
                        { 0.03, 0.03, 0.04, 1.0 }, { 0, 0, 0 }, 0.65, 0.0, 1.0, 0.0
                    )
                end
                -- Лента плотно на тулье шляпы (радиус тульи 0.27 * 0.88 = 0.24)
                drawPrev(
                    self.meshCylinder,
                    { 0.0, 0.52, 0.0 },
                    { 0.252, 0, 0 }, { 0, 0.10, 0 }, { 0, 0, 0.252 },
                    { 0.88, 0.14, 0.18, 1.0 }, { 0, 0, 0 }, 0.55, 0.0, 1.0, 0.0
                )
            end
        elseif itemData.style == "pine" or itemData.taperByHeight then
            -- Собранная 4-ярусная ёлочка с макушкой-звездой
            for gy = 1, 4 do
                local matG, meshG = self:_getPieceMaterialAndMesh(itemData, 1, gy)
                local taper = (1.24 - (gy - 1) * 0.14) * 1.08
                local py = -0.68 + (gy - 1) * 0.42
                local col = (gy % 2 == 1) and itemData.player1Color or itemData.player2Color
                drawPrev(
                    meshG,
                    { 0.0, py, 0.0 },
                    { ca * taper, 0, sa * taper },
                    { 0, 1.0, 0 },
                    { -sa * taper, 0, ca * taper },
                    col,
                    { 0, 0, 0 },
                    itemData.specular or 0.35,
                    itemData.woodStrength or 0.8,
                    1.8,
                    matG
                )
            end
            if not isSil then
                drawPrev(
                    self.meshStar,
                    { 0.0, 0.96, 0.0 },
                    { ca, 0, -sa }, { 0, 1.0, 0 }, { sa, 0, ca },
                    { 1.00, 0.82, 0.16, 1.0 }, { 0.38, 0.26, 0.04 }, 0.95, 0.0, 1.0, 7.0
                )
            end
        else
            -- Два крутящихся 3D-бублика или квадратных блока (первый и второй игрок) с увеличенным зазором, чтобы не пересекались при вращении
            local s = (itemData.style == "iron_block" or itemData.style == "skyscraper_block") and 1.04 or 1.15
            local ct, st = math.cos(0.45), math.sin(0.45)
            local axX = { ca * s, 0, -sa * s }
            local axY = { sa * st * s, ct * s, ca * st * s }
            local axZ = { sa * ct * s, -st * s, ca * ct * s }

            drawPrev(
                mesh1,
                { -0.74, 0.46, 0.0 },
                axX, axY, axZ,
                itemData.player1Color,
                { 0, 0, 0 },
                itemData.specular or 0.35,
                itemData.woodStrength or 0.8,
                1.8,
                mat1
            )
            drawPrev(
                mesh2,
                { 0.74, -0.46, 0.0 },
                axX, axY, axZ,
                itemData.player2Color,
                { 0, 0, 0 },
                itemData.specular or 0.35,
                itemData.woodStrength or 0.8,
                1.8,
                mat2
            )
        end
    elseif previewType == "board_shape" then
        local mesh = (itemData.shape == "round") and self.meshRoundBase or self.meshBox
        local span = (itemData.shape == "round") and 1.35 or 1.15
        drawPrev(
            mesh,
            { 0.0, 0.0, 0.0 },
            { ca * span, 0, sa * span },
            { 0, 0.24, 0 },
            { -sa * span, 0, ca * span },
            itemData.baseColor,
            { 0, 0, 0 },
            0.25,
            itemData.woodStrength or 0.9,
            1.2,
            0.0
        )
    elseif previewType == "board_skin" then
        local bStyle = itemData.style or "wood"
        local isManh   = (bStyle == "manhattan")
        local isChern  = (bStyle == "chernobyl")
        local mesh = (bStyle == "japanese_roof") and self.meshJapaneseRoof
            or ((isManh or isChern) and self.meshBox)
            or ((itemData.isRound ~= false) and self.meshRoundBase or self.meshBox)
        local span = 1.45
        local isForest = (bStyle == "forest")
        local isMetal  = (bStyle == "metal")
        local isCake   = (bStyle == "cake")
        local isSnowy  = (bStyle == "snow" or bStyle == "snowy")
        local isJap    = (bStyle == "japanese_roof")
        local isCity   = (bStyle == "skyscraper" or isManh)
        local matId    = isForest and 5.0
            or (isMetal and 7.0)
            or (isCake and 8.0)
            or (isSnowy and 15.0)
            or (isJap and 13.0)
            or (isCity and 11.0)
            or (isChern and 20.0)
            or 0.0
        drawPrev(
            mesh,
            { 0.0, -0.15, 0.0 },
            { ca * span, 0, sa * span },
            { 0, isJap and 0.55 or (isCity and 0.65 or 0.26), 0 },
            { -sa * span, 0, ca * span },
            itemData.baseColor,
            { 0, 0, 0 },
            isMetal and 0.82 or 0.25,
            itemData.woodStrength or 0.9,
            1.2,
            matId
        )
        -- Пара мини-столбиков сверху (или шпили с красными огоньками для Манхэттена / широкие трубы с дымом для ЧАЭС)
        local prevTime = love.timer.getTime()
        for pIdx, off in ipairs({ {-0.3, -0.3}, {0.3, -0.3}, {-0.3, 0.3}, {0.3, 0.3} }) do
            local rx = off[1] * ca - off[2] * sa
            local rz = off[1] * sa + off[2] * ca
            local pegScale = isCity and 0.22 or (isChern and 0.62 or 0.35)
            drawPrev(
                self.meshPeg,
                { rx, -0.02, rz },
                { pegScale, 0, 0 },
                { 0, isCity and 0.28 or (isChern and 0.32 or 0.22), 0 },
                { 0, 0, pegScale },
                itemData.pegColor,
                { 0, 0, 0 },
                (isMetal or isCity) and 0.90 or 0.3,
                itemData.woodStrength or 0.9,
                1.5,
                isForest and 6.0 or ((isMetal or isCity) and 7.0 or (isCake and 9.0 or (isChern and 21.0 or 0.0)))
            )
            if isManh and not isSil then
                local prevPhases = { 0.0, 2.3, 4.1, 1.2 }
                local prevFreqs  = { 0.95, 1.32, 0.78, 1.15 }
                local bp = math.pow(math.max(0.0, math.sin(prevTime * prevFreqs[pIdx] + prevPhases[pIdx])), 1.35)
                drawPrev(
                    self.meshSphere,
                    { rx, 0.74, rz },
                    { 0.08, 0, 0 }, { 0, 0.08, 0 }, { 0, 0, 0.08 },
                    { 0.22 + 0.78 * bp, 0.08 + 0.08 * bp, 0.06 + 0.05 * bp, 1.0 },
                    { 1.35 * bp, 0.14 * bp, 0.09 * bp },
                    0.9, 0.0, 1.0, 12.0
                )
            elseif isChern and not isSil then
                for sk = 0, 1 do
                    local spPhase = (prevTime * 0.48 + pIdx * 0.27 + sk * 0.5) % 1.0
                    local sRad = 0.10 + spPhase * 0.16
                    drawPrev(
                        self.meshSphere,
                        { rx + spPhase * 0.22, 0.88 + spPhase * 0.55, rz },
                        { sRad, 0, 0 }, { 0, sRad * 0.8, 0 }, { 0, 0, sRad },
                        { 0.58, 0.60, 0.62, (1.0 - spPhase) * 0.42 },
                        { 0.02, 0.02, 0.02 },
                        0.0, 0.0, 1.0, 0.0
                    )
                end
            end
        end
        if isSnowy and not isSil then
            love.graphics.setDepthMode("lequal", false)
            love.graphics.setBlendMode("alpha")
            for k = 1, 14 do
                local s1 = ((k * 53.17) % 1.0)
                local s2 = ((k * 29.61) % 1.0)
                local sp = (prevTime * (0.12 + s2 * 0.07) + s1) % 1.0
                local fx = (s1 - 0.5) * 2.8 + math.sin(prevTime * 0.7 + k) * 0.14
                local fy = 1.65 - sp * 2.15
                local fz = (s2 - 0.5) * 2.2
                local ef = math.min(sp / 0.15, (1.0 - sp) / 0.18, 1.0)
                drawPrev(
                    self.meshSphere,
                    { fx, fy, fz },
                    { 0.042, 0, 0 }, { 0, 0.042, 0 }, { 0, 0, 0.042 },
                    { 0.96, 0.99, 1.00, math.max(0.0, ef) * 0.85 },
                    { 0.45, 0.58, 0.78 },
                    0.15, 0.0, 1.0, 0.0
                )
            end
            love.graphics.setDepthMode("lequal", true)
        end
    end

    love.graphics.setShader()
    love.graphics.setDepthMode("always", false)
    love.graphics.setScissor()
end

return Renderer3D
