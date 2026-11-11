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
    uniform vec4  u_baseColor;
    uniform vec3  u_emissive;
    uniform float u_specular;
    uniform float u_woodStrength;
    uniform float u_woodScale;
    uniform float u_materialType; // 0=wood, 1=donut, 2=pine, 3=uranium, 4=graphite, 5=forest_grass, 6=tree_bark
    uniform LOVE_HIGHP_OR_MEDIUMP float u_time;

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
            // 2: Веточки Ёлки (Pine Tree Tier with needles & snowy frost tips)
            float rad = length(v_localPos.xz);
            float needle = woodNoise3(vec3(v_localPos.x * 28.0, v_localPos.y * 18.0, v_localPos.z * 28.0));
            vec3 pineBase = mix(u_baseColor.rgb * 0.72, u_baseColor.rgb * 1.24, needle);
            float snowTip = smoothstep(0.34, 0.50, rad + needle * 0.08) * smoothstep(-0.02, 0.12, N.y);
            surfaceAlbedo = mix(pineBase, vec3(0.92, 0.96, 1.00), snowTip * 0.58);
            specFactor = mix(0.22, 0.55, snowTip);
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

        return vec4(litColor, u_baseColor.a);
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
    self.meshRoundBase = self:_buildCappedDiscMesh(64)
    self.meshBox       = self:_buildUnitBoxMesh()

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

function Renderer3D:gridToWorldXZ(gx, gz)
    local half = (Renderer3D.GRID_SIZE + 1) * 0.5
    return (gx - half) * Renderer3D.PEG_SPACING, (gz - half) * Renderer3D.PEG_SPACING
end

function Renderer3D:gridToWorldXYZ(gx, gy, gz)
    local wx, wz = self:gridToWorldXZ(gx, gz)
    local wy = Renderer3D.SLOT_START_Y + (gy - 1) * Renderer3D.SLOT_STEP_Y
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

-- Конусообразный ярус еловых веток с волнистыми иголками по краю
function Renderer3D:_buildPineTierMesh(ringSegs, tubeSegs)
    local verts = {}
    local majorR = 0.34
    local minorR = 0.175

    local function getPoint(u, v)
        local cu, su = math.cos(u), math.sin(u)
        local cv, sv = math.cos(v), math.sin(v)
        -- Зубчатая форма еловых лап (10 веточек по кругу) + наклон конусом вниз
        local branchWave = 1.0 + 0.11 * math.cos(u * 10.0) * math.max(0.0, cv)
        local coneSlope  = -0.09 * math.max(0.0, cv)
        local r = (majorR + minorR * cv * (1.15 - 0.35 * sv)) * branchWave
        local px = r * cu
        local py = minorR * sv * 1.25 + coneSlope
        local pz = r * su

        local nx = cv * cu
        local ny = sv * 0.85 + 0.25
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

function Renderer3D:pickPegAtScreenPos(mx, my, screenW, screenH, boardLogic)
    local aspect = screenW / screenH
    local f = 1.0 / math.tan(self.fovRad * 0.5)

    local ndcX = (mx / screenW) * 2.0 - 1.0
    local ndcY = 1.0 - (my / screenH) * 2.0

    local rayDir = vNorm({
        x = self.camFwd.x + self.camRight.x * (ndcX * aspect / f) + self.camUp.x * (ndcY / f),
        y = self.camFwd.y + self.camRight.y * (ndcX * aspect / f) + self.camUp.y * (ndcY / f),
        z = self.camFwd.z + self.camRight.z * (ndcX * aspect / f) + self.camUp.z * (ndcY / f)
    })

    local bestX, bestZ = nil, nil
    local bestT = 1e9
    local hitRadius = 0.36

    for gx = 1, 4 do
        for gz = 1, 4 do
            if not boardLogic or boardLogic:canDrop(gx, gz) then
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
                    for _, t in ipairs({ t1, t2 }) do
                        if t > 0.1 and t < bestT then
                            local hitY = self.camPos.y + rayDir.y * t
                            if hitY >= -0.2 and hitY <= Renderer3D.PEG_HEIGHT + 0.35 then
                                bestT = t
                                bestX, bestZ = gx, gz
                                break
                            end
                        end
                    end
                end
            end
        end
    end

    return bestX, bestZ
end

function Renderer3D:_getPieceMaterialAndMesh(pieceSkin, player)
    local style = pieceSkin and pieceSkin.style or "wood"
    if style == "donut" then
        return 1.0, self.meshTorus
    elseif style == "pine" then
        return 2.0, self.meshPineTier
    elseif style == "nuclear" then
        return (player == 1) and 3.0 or 4.0, self.meshTorus
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

    self:_send("u_time",       love.timer.getTime())
    self:_send("u_camPos",     { self.camPos.x,   self.camPos.y,   self.camPos.z   })
    self:_send("u_eyePos",     { self.camPos.x,   self.camPos.y,   self.camPos.z   })
    self:_send("u_camRight",   { self.camRight.x, self.camRight.y, self.camRight.z })
    self:_send("u_camUp",      { self.camUp.x,    self.camUp.y,    self.camUp.z    })
    self:_send("u_camFwd",     { self.camFwd.x,   self.camFwd.y,   self.camFwd.z   })
    self:_send("u_projScale",  { f / aspect, f })
    self:_send("u_clipOffset", { clipOffsetX, clipOffsetY })

    local boardSkin = state.config.getBoardSkin()
    local pieceSkin = state.config.getPieceSkin()
    local isRound   = (state.config.boardShape == "round")
    local isForestBoard = (boardSkin.style == "forest")
    local isMetalBoard  = (boardSkin.style == "metal")
    local isCakeBoard   = (boardSkin.style == "cake")
    local baseMatType   = isForestBoard and 5.0 or (isMetalBoard and 7.0 or (isCakeBoard and 8.0 or 0.0))
    local pegMatType    = isForestBoard and 6.0 or (isMetalBoard and 7.0 or (isCakeBoard and 9.0 or 0.0))
    local rimMatType    = isForestBoard and 6.0 or (isMetalBoard and 7.0 or (isCakeBoard and 9.0 or 0.0))

    -- 1. Отрисовка базы поля (Круглое по дефолту или Квадратное)
    local baseMesh = isRound and self.meshRoundBase or self.meshBox
    local baseSpan = isRound
        and ((Renderer3D.GRID_SIZE - 1) * Renderer3D.PEG_SPACING + 2.95)
        or  ((Renderer3D.GRID_SIZE - 1) * Renderer3D.PEG_SPACING + 2.05)
    local baseH = Renderer3D.BASE_THICKNESS

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

    -- 2. Отрисовка 16 столбиков (или стволов деревьев в лесном скине)
    for gx = 1, 4 do
        for gz = 1, 4 do
            local wx, wz = self:gridToWorldXZ(gx, gz)
            local isHovered = (state.hoveredX == gx and state.hoveredZ == gz)
            local pColor    = isHovered and boardSkin.pegHover or boardSkin.pegColor
            local pEmissive = isHovered and { 0.28, 0.20, 0.06 } or { 0.0, 0.0, 0.0 }

            self:_drawMeshTransform(
                self.meshPeg,
                { wx, 0.0, wz },
                { 1, 0, 0 },
                { 0, 1, 0 },
                { 0, 0, 1 },
                pColor,
                pEmissive,
                isMetalBoard and 0.88 or 0.32,
                boardSkin.woodStrength,
                1.35,
                pegMatType
            )
        end
    end

    -- 3. Если это демо-сцена миттельшпиля в меню — рисуем разбросанные рядом с полем фишки
    if state.showScattered then
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

    local pulse = 0.5 + 0.5 * math.sin(love.timer.getTime() * 6.0)

    -- 4. Отрисовка нанизанных на столбики фишек (с учетом отмотки ходов maxPly и конусности для Ёлочки!)
    if state.logic then
        local function drawSinglePiece(gx, gy, gz, player, isCurrentRewindHead)
            local wx, wy, wz = self:gridToWorldXYZ(gx, gy, gz)
            if not isRewound and state.activeDrop and state.activeDrop.x == gx and state.activeDrop.y == gy and state.activeDrop.z == gz then
                wy = state.activeDrop.currentY
            end

            local baseCol = (player == 1) and pieceSkin.player1Color or pieceSkin.player2Color
            local key = gx .. ":" .. gy .. ":" .. gz
            local isWinPiece = winSet[key]
            local matType, pMesh = self:_getPieceMaterialAndMesh(pieceSkin, player)

            -- Для скина «Веточки Ёлки» нижние фишки шире, а верхние уже — получается 3D-ёлочка!
            local taperXZ = 1.0
            if pieceSkin.taperByHeight then
                taperXZ = 1.28 - (gy - 1) * 0.19
            end

            local scale = 1.0
            local emissive = { 0.0, 0.0, 0.0 }
            if isWinPiece then
                scale = 1.0 + 0.08 * pulse
                emissive = { 0.45 * pulse + 0.15, 0.34 * pulse + 0.10, 0.05 }
            elseif isCurrentRewindHead then
                emissive = { 0.18 * pulse, 0.18 * pulse, 0.08 * pulse }
            end

            self:_drawMeshTransform(
                pMesh,
                { wx, wy, wz },
                { scale * taperXZ, 0, 0 },
                { 0, scale, 0 },
                { 0, 0, scale * taperXZ },
                baseCol,
                emissive,
                pieceSkin.specular,
                pieceSkin.woodStrength,
                1.8,
                matType
            )
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
                    local stack = state.logic.pegs[gx][gz]
                    for gy = 1, #stack do
                        drawSinglePiece(gx, gy, gz, stack[gy], false)
                    end
                end
            end
        end
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
    self:_send("u_camPos",     { camPos.x,   camPos.y,   camPos.z   })
    self:_send("u_eyePos",     { camPos.x,   camPos.y,   camPos.z   })
    self:_send("u_camRight",   { camRight.x, camRight.y, camRight.z })
    self:_send("u_camUp",      { camUp.x,    camUp.y,    camUp.z    })
    self:_send("u_camFwd",     { camFwd.x,   camFwd.y,   camFwd.z   })
    self:_send("u_projScale",  { (f / aspect) * 0.55, f * 0.55 })
    self:_send("u_clipOffset", { clipOffX, clipOffY })

    local ca, sa = math.cos(angle), math.sin(angle)

    if previewType == "pieces" then
        local mat1, mesh1 = self:_getPieceMaterialAndMesh(itemData, 1)
        local mat2, mesh2 = self:_getPieceMaterialAndMesh(itemData, 2)

        if itemData.taperByHeight then
            -- Для «Веточек Ёлки» в витрине магазина рисуем собранную 4-ярусную конусную ёлочку!
            for gy = 1, 4 do
                local taper = (1.28 - (gy - 1) * 0.20) * 1.12
                local py = -0.60 + (gy - 1) * 0.38
                local col = (gy % 2 == 1) and itemData.player1Color or itemData.player2Color
                self:_drawMeshTransform(
                    mesh1,
                    { 0.0, py, 0.0 },
                    { ca * taper, 0, sa * taper },
                    { 0, 1.05, 0 },
                    { -sa * taper, 0, ca * taper },
                    col,
                    { 0, 0, 0 },
                    itemData.specular or 0.35,
                    itemData.woodStrength or 0.8,
                    1.8,
                    mat1
                )
            end
        else
            -- Два крутящихся 3D-бублика (первый и второй игрок)
            local s = 1.35
            local axX = { ca * s, 0, sa * s }
            local axY = { -sa * 0.35 * s, 0.92 * s, ca * 0.35 * s }
            local axZ = { -sa * s, -0.35 * s, ca * s }

            self:_drawMeshTransform(
                mesh1,
                { -0.45, 0.22, 0.0 },
                axX, axY, axZ,
                itemData.player1Color,
                { 0, 0, 0 },
                itemData.specular or 0.35,
                itemData.woodStrength or 0.8,
                1.8,
                mat1
            )
            self:_drawMeshTransform(
                mesh2,
                { 0.45, -0.22, 0.25 },
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
        self:_drawMeshTransform(
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
        local mesh = (itemData.isRound ~= false) and self.meshRoundBase or self.meshBox
        local span = 1.45
        local isForest = (itemData.style == "forest")
        local isMetal  = (itemData.style == "metal")
        local isCake   = (itemData.style == "cake")
        self:_drawMeshTransform(
            mesh,
            { 0.0, -0.15, 0.0 },
            { ca * span, 0, sa * span },
            { 0, 0.26, 0 },
            { -sa * span, 0, ca * span },
            itemData.baseColor,
            { 0, 0, 0 },
            isMetal and 0.82 or 0.25,
            itemData.woodStrength or 0.9,
            1.2,
            isForest and 5.0 or (isMetal and 7.0 or (isCake and 8.0 or 0.0))
        )
        -- Пара мини-столбиков сверху
        for _, off in ipairs({ {-0.3, -0.3}, {0.3, -0.3}, {-0.3, 0.3}, {0.3, 0.3} }) do
            local rx = off[1] * ca - off[2] * sa
            local rz = off[1] * sa + off[2] * ca
            self:_drawMeshTransform(
                self.meshPeg,
                { rx, -0.02, rz },
                { 0.35, 0, 0 },
                { 0, 0.22, 0 },
                { 0, 0, 0.35 },
                itemData.pegColor,
                { 0, 0, 0 },
                isMetal and 0.90 or 0.3,
                itemData.woodStrength or 0.9,
                1.5,
                isForest and 6.0 or (isMetal and 7.0 or (isCake and 9.0 or 0.0))
            )
        end
    end

    love.graphics.setShader()
    love.graphics.setDepthMode("always", false)
    love.graphics.setScissor()
end

return Renderer3D
