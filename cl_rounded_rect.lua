/***
 *   @addon         DrawOutlinedRoundedRect
 *   @component     UI Rendering
 *   @license       MIT License
 *   @version       2.0.0
 *   @release_date  13/07/2026
 *   @author        DDI Scripts
 *
 *   @contact
 *                  Discord:  https://discord.gg/CND6B5sH3j
 *                  GitHub:   https://github.com/denchik5133/gmod-rounded-rect-outline
 *
 *   @description   Draws rounded rectangle outlines on the client 2D
 *                  surface with antialiased outer and inner edges. The
 *                  outline is rendered as a triangle mesh with per-vertex
 *                  alpha ramps; no stencil cut is used.
 *
 *   @functions
 *                  - DrawOutlinedRoundedRect: Draws a rounded rectangle
 *                    outline with configurable radius, thickness, and color.
 *                  - _GetUnitArc (internal): Returns cached unit-circle
 *                    points for a quarter arc at the requested detail.
 *                  - _NormalizeRectArguments (internal): Rounds and clamps
 *                    rectangle dimensions and outline parameters.
 *
 *   @example
 *                  hook.Add('HUDPaint', 'MyRoundedRect', function()
 *                      surface.DrawOutlinedRoundedRect(100, 100, 200, 100, 16, 2, color_white)
 *                  end)
 *
 *   @notes         The outline is built from three radial bands for each
 *                  rounded corner (outer fade, solid stroke, inner fade)
 *                  and matching horizontal/vertical bands for the straight
 *                  edges. The alpha transition is interpolated across mesh
 *                  triangles, smoothing both contours without the hard
 *                  pass/fail edge of a stencil test.
 *
 *                  Quarter-circle coordinates are cached by segment count
 *                  (32-96 segments) and reused across draw calls. A single
 *                  material is created when this file loads; no render
 *                  targets or stencil buffer are used.
 *
 *                  The antialiasing ramp can extend the visible outline by
 *                  up to 0.5 pixels beyond the supplied rectangle. When
 *                  radius is 0, a simple rectangular outline fast path is
 *                  used instead of a mesh.
 */



local _cos = math.cos
local _sin = math.sin
local _rad = math.rad
local _min = math.min
local _max = math.max
local _floor = math.floor
local _ceil = math.ceil
local _Round = math.Round

local _MeshBegin = mesh.Begin
local _MeshEnd = mesh.End
local _MeshPosition = mesh.Position
local _MeshColor = mesh.Color
local _MeshAdvanceVertex = mesh.AdvanceVertex
local _RenderSetMaterial = render.SetMaterial
local _SetDrawColor = surface.SetDrawColor
local _DrawRect = surface.DrawRect

local MIN_SEGMENTS = 32
local MAX_SEGMENTS = 96
local ARC_CACHE = { }

local function _GetUnitArc(segments)
    local arc = ARC_CACHE[segments]
    if (arc) then
        return arc
    end

    arc = { }
    local angleStep = math.pi * 0.5 / segments

    for i = 0, segments do
        local angle = i * angleStep
        arc[i + 1] = {
            x = _cos(angle),
            y = _sin(angle)
        }
    end

    ARC_CACHE[segments] = arc
    return arc
end

local function _NormalizeRectArguments(x, y, w, h, radius, thickness, color)
    x = _Round(x)
    y = _Round(y)
    w = _max(_Round(w), 0)
    h = _max(_Round(h), 0)
    radius = _min(_max(_Round(radius or 0), 0), _floor(w * 0.5), _floor(h * 0.5))
    thickness = _min(_max(_Round(thickness or 1), 0), radius > 0 and radius or _floor(_min(w, h) * 0.5))
    return x, y, w, h, radius, thickness, color or color_white
end

local function _DrawPlainOutline(x, y, w, h, thickness, color)
    if (thickness <= 0 or w <= 0 or h <= 0) then
        return
    end

    _SetDrawColor(color)
    _DrawRect(x, y, w, thickness)
    _DrawRect(x, y + h - thickness, w, thickness)

    local sideHeight = h - thickness * 2
    if (sideHeight > 0) then
        _DrawRect(x, y + thickness, thickness, sideHeight)
        _DrawRect(x + w - thickness, y + thickness, thickness, sideHeight)
    end
end

local OUTLINE_MATERIAL = CreateMaterial('DanLib_RoundedRectAA_VertexAlpha', 'UnlitGeneric', {
    ['$basetexture'] = 'color/white',
    ['$translucent'] = '1',
    ['$vertexalpha'] = '1',
    ['$vertexcolor'] = '1',
    ['$nocull'] = '1'
})

-- All mesh vertices use alpha 0 or 1; raster interpolation creates the edge
-- fade, so no per-vertex alpha multiplication or rounding is necessary.
local function _EmitVertex(x, y, color, alpha)
    _MeshPosition(x, y, 0)
    _MeshColor(color.r, color.g, color.b, alpha == 0 and 0 or (color.a or 255))
    _MeshAdvanceVertex()
end

local function _EmitQuad(x1, y1, a1, x2, y2, a2, x3, y3, a3, x4, y4, a4, color)
    _EmitVertex(x1, y1, color, a1)
    _EmitVertex(x2, y2, color, a2)
    _EmitVertex(x3, y3, color, a3)

    _EmitVertex(x1, y1, color, a1)
    _EmitVertex(x3, y3, color, a3)
    _EmitVertex(x4, y4, color, a4)
end

local function _EmitRoundedCorner(cx, cy, outerRadius, outerFullRadius, innerFullRadius, innerZeroRadius, startAngle, segments, color)
    local arc = _GetUnitArc(segments)
    local startRadians = _rad(startAngle)
    local startCos = _cos(startRadians)
    local startSin = _sin(startRadians)

    for i = 1, segments do
        local unit1 = arc[i]
        local unit2 = arc[i + 1]
        local cos1 = unit1.x * startCos - unit1.y * startSin
        local sin1 = unit1.x * startSin + unit1.y * startCos
        local cos2 = unit2.x * startCos - unit2.y * startSin
        local sin2 = unit2.x * startSin + unit2.y * startCos

        local outerX1 = cx + cos1 * outerRadius
        local outerY1 = cy + sin1 * outerRadius
        local outerX2 = cx + cos2 * outerRadius
        local outerY2 = cy + sin2 * outerRadius
        local outerFullX1 = cx + cos1 * outerFullRadius
        local outerFullY1 = cy + sin1 * outerFullRadius
        local outerFullX2 = cx + cos2 * outerFullRadius
        local outerFullY2 = cy + sin2 * outerFullRadius
        local innerFullX1 = cx + cos1 * innerFullRadius
        local innerFullY1 = cy + sin1 * innerFullRadius
        local innerFullX2 = cx + cos2 * innerFullRadius
        local innerFullY2 = cy + sin2 * innerFullRadius
        local innerZeroX1 = cx + cos1 * innerZeroRadius
        local innerZeroY1 = cy + sin1 * innerZeroRadius
        local innerZeroX2 = cx + cos2 * innerZeroRadius
        local innerZeroY2 = cy + sin2 * innerZeroRadius

        -- Fade the outside edge, draw the solid stroke body, then fade into
        -- the transparent hole.
        _EmitQuad(outerX1, outerY1, 0, outerX2, outerY2, 0, outerFullX2, outerFullY2, 1, outerFullX1, outerFullY1, 1, color)
        _EmitQuad(outerFullX1, outerFullY1, 1, outerFullX2, outerFullY2, 1, innerFullX2, innerFullY2, 1, innerFullX1, innerFullY1, 1, color)
        _EmitQuad(innerFullX1, innerFullY1, 1, innerFullX2, innerFullY2, 1, innerZeroX2, innerZeroY2, 0, innerZeroX1, innerZeroY1, 0, color)
    end
end

local function _EmitHorizontalBand(x1, x2, y1, alpha1, y2, alpha2, color)
    _EmitQuad(x1, y1, alpha1, x2, y1, alpha1, x2, y2, alpha2, x1, y2, alpha2, color)
end

local function _EmitVerticalBand(y1, y2, x1, alpha1, x2, alpha2, color)
    _EmitQuad(x1, y1, alpha1, x2, y1, alpha2, x2, y2, alpha2, x1, y2, alpha1, color)
end

--- surface.DrawOutlinedRoundedRect(x, y, w, h, radius, thickness, color)
--
-- Draws a rounded rectangular outline with a soft alpha transition at both
-- edges. Radius and thickness are rounded to whole pixels and clamped to
-- the rectangle's size. Defaults: radius 0, thickness 1, color_white.
function surface.DrawOutlinedRoundedRect(x, y, w, h, radius, thickness, color)
    x, y, w, h, radius, thickness, color =
        _NormalizeRectArguments(x, y, w, h, radius, thickness, color)

    if (thickness <= 0 or w <= 0 or h <= 0) then
        return
    end

    if (radius <= 0) then
        _DrawPlainOutline(x, y, w, h, thickness, color)
        return
    end

    local edgeFade = _min(0.5, thickness * 0.5)
    local innerRadius = _max(radius - thickness, 0)
    local outerFullRadius = radius - edgeFade
    local innerFullRadius = innerRadius + edgeFade
    local innerZeroRadius = _max(innerRadius - edgeFade, 0)
    local segments = _min(MAX_SEGMENTS, _max(MIN_SEGMENTS, _ceil(radius / 5)))
    local triangleCount = segments * 24 + 24

    _RenderSetMaterial(OUTLINE_MATERIAL)
    _MeshBegin(MATERIAL_TRIANGLES, triangleCount)

    -- Straight sections: each has an outside fade, a solid band, and an
    -- inside fade. Rounded corners use the matching three radial bands.
    _EmitHorizontalBand(x + radius, x + w - radius, y - edgeFade, 0, y + edgeFade, 1, color)
    _EmitHorizontalBand(x + radius, x + w - radius, y + edgeFade, 1, y + thickness - edgeFade, 1, color)
    _EmitHorizontalBand(x + radius, x + w - radius, y + thickness - edgeFade, 1, y + thickness + edgeFade, 0, color)

    _EmitHorizontalBand(x + radius, x + w - radius, y + h - thickness - edgeFade, 0, y + h - thickness + edgeFade, 1, color)
    _EmitHorizontalBand(x + radius, x + w - radius, y + h - thickness + edgeFade, 1, y + h - edgeFade, 1, color)
    _EmitHorizontalBand(x + radius, x + w - radius, y + h - edgeFade, 1, y + h + edgeFade, 0, color)

    _EmitVerticalBand(y + radius, y + h - radius, x - edgeFade, 0, x + edgeFade, 1, color)
    _EmitVerticalBand(y + radius, y + h - radius, x + edgeFade, 1, x + thickness - edgeFade, 1, color)
    _EmitVerticalBand(y + radius, y + h - radius, x + thickness - edgeFade, 1, x + thickness + edgeFade, 0, color)

    _EmitVerticalBand(y + radius, y + h - radius, x + w - thickness - edgeFade, 0, x + w - thickness + edgeFade, 1, color)
    _EmitVerticalBand(y + radius, y + h - radius, x + w - thickness + edgeFade, 1, x + w - edgeFade, 1, color)
    _EmitVerticalBand(y + radius, y + h - radius, x + w - edgeFade, 1, x + w + edgeFade, 0, color)

    _EmitRoundedCorner(x + radius, y + radius, radius + edgeFade, outerFullRadius, innerFullRadius, innerZeroRadius, 180, segments, color)
    _EmitRoundedCorner(x + w - radius, y + radius, radius + edgeFade, outerFullRadius, innerFullRadius, innerZeroRadius, 270, segments, color)
    _EmitRoundedCorner(x + w - radius, y + h - radius, radius + edgeFade, outerFullRadius, innerFullRadius, innerZeroRadius, 0, segments, color)
    _EmitRoundedCorner(x + radius, y + h - radius, radius + edgeFade, outerFullRadius, innerFullRadius, innerZeroRadius, 90, segments, color)

    _MeshEnd()
end
