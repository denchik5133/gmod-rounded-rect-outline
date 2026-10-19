/***
 *   @addon         DrawOutlinedRoundedRect
 *   @component     UI Rendering
 *   @license       MIT License
 *   @version       2.2.1
 *   @release_date  19/10/2026
 *   @author        DDI Scripts
 *
 *   @contact
 *                  Discord:  https://discord.gg/CND6B5sH3j
 *                  GitHub:   https://github.com/denchik5133/gmod-rounded-rect-outline
 *
 *   @description   Draws rounded rectangle outlines on the client 2D
 *                  surface with antialiased outer and inner edges. The
 *                  rounded outline is rendered as a triangle mesh with
 *                  per-vertex alpha ramps; no stencil cut is used.
 *
 *   @functions
 *                  - surface.DrawOutlinedRoundedRect: Draws an outline
 *                    using screen-space coordinates.
 *                  - Panel:DrawOutlinedRoundedRect: Draws an outline from
 *                    panel-local coordinates inside a Paint method.
 *                  - _GetUnitArc (internal): Returns cached unit-circle
 *                    points for a quarter arc at the requested detail.
 *                  - _GetSegmentCount (internal): Selects curve detail
 *                    from the radius and a subpixel error target.
 *                  - _NormalizeRectArguments (internal): Rounds and clamps
 *                    rectangle dimensions and outline parameters.
 *
 *   @example
 *                  -- Screen-space coordinates in HUDPaint:
 *                  hook.Add('HUDPaint', 'MyRoundedRect', function()
 *                      surface.DrawOutlinedRoundedRect(100, 100, 200, 100, 16, 2, color_white)
 *                  end)
 *
 *                  -- Panel-local coordinates in a VGUI Paint method:
 *                  panel.Paint = function(self, w, h)
 *                      self:DrawOutlinedRoundedRect(0, 0, w, h, 16, 2, color_white)
 *                  end
 *
 *   @notes         Rounded outlines are built from three radial bands at
 *                  each corner (outer fade, solid stroke, inner fade) and
 *                  matching horizontal/vertical bands along straight edges.
 *                  Vertex alpha is interpolated across the mesh triangles,
 *                  smoothing both contours without a stencil cut.
 *
 *                  The Panel method is registered through
 *                  FindMetaTable('Panel'). It converts the origin to screen
 *                  coordinates for the rounded mesh path; width, height,
 *                  radius, thickness, and mesh geometry remain unchanged.
 *                  When the effective radius is zero, it keeps panel-local
 *                  coordinates so the surface fast path is offset only once.
 *                  For rounded mesh draws, the Panel method multiplies the
 *                  supplied color alpha by this panel's and its ancestors'
 *                  alpha values, so parent fade animations affect the outline.
 *
 *                  Quarter-circle coordinates are cached by segment count
 *                  (8-96 segments) and selected to keep chord error near
 *                  0.25 pixels. Transparent and fully off-screen mesh draws
 *                  return early. The material is created once when this
 *                  file loads; no render targets or stencil buffer are used.
 *
 *                  The antialiasing ramp can extend up to 0.5 pixels beyond
 *                  the supplied rectangle. The Panel method translates
 *                  coordinates but does not create an additional clipping
 *                  region; check behavior inside clipped or scrolling
 *                  parents.
 */



local _cos = math.cos
local _sin = math.sin
local _rad = math.rad
local _min = math.min
local _max = math.max
local _floor = math.floor
local _ceil = math.ceil
local _acos = math.acos
local _Round = math.Round
local _ScrW = ScrW
local _ScrH = ScrH

local _MeshBegin = mesh.Begin
local _MeshEnd = mesh.End
local _MeshPosition = mesh.Position
local _MeshColor = mesh.Color
local _MeshAdvanceVertex = mesh.AdvanceVertex
local _RenderSetMaterial = render.SetMaterial
local _SetDrawColor = surface.SetDrawColor
local _DrawRect = surface.DrawRect
local _IsValid = IsValid

local MIN_SEGMENTS = 8
local MAX_SEGMENTS = 96
local MAX_CURVE_ERROR = 0.25
local MAX_EDGE_FADE = 0.5
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

-- Choose enough straight segments per quarter-circle to keep the maximum
-- chord deviation below MAX_CURVE_ERROR pixels, within safe quality bounds.
local function _GetSegmentCount(radius)
    local curveRadius = radius + MAX_EDGE_FADE
    local maxHalfStep = _acos(1 - MAX_CURVE_ERROR / curveRadius)
    local segments = _ceil((math.pi * 0.25) / maxHalfStep)

    return _min(MAX_SEGMENTS, _max(MIN_SEGMENTS, segments))
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
-- edges. Direct calls use screen-space coordinates; use
-- Panel:DrawOutlinedRoundedRect for panel-local coordinates.
-- Radius and thickness are rounded to whole pixels and clamped to the
-- rectangle's size. Defaults: radius 0, thickness 1, color_white.
function surface.DrawOutlinedRoundedRect(x, y, w, h, radius, thickness, color)
    x, y, w, h, radius, thickness, color = _NormalizeRectArguments(x, y, w, h, radius, thickness, color)

    if (thickness <= 0 or w <= 0 or h <= 0 or (color.a or 255) <= 0) then
        return
    end

    if (radius <= 0) then
        _DrawPlainOutline(x, y, w, h, thickness, color)
        return
    end

    -- The mesh is in screen/viewport coordinates and its AA fringe reaches
    -- at most MAX_EDGE_FADE beyond the rectangle. Do not skip partially
    -- visible shapes.
    local viewportWidth = _ScrW()
    local viewportHeight = _ScrH()
    if (x + w + MAX_EDGE_FADE <= 0 or y + h + MAX_EDGE_FADE <= 0 or x - MAX_EDGE_FADE >= viewportWidth or y - MAX_EDGE_FADE >= viewportHeight) then
        return
    end

    local edgeFade = _min(0.5, thickness * 0.5)
    local innerRadius = _max(radius - thickness, 0)
    local outerFullRadius = radius - edgeFade
    local innerFullRadius = innerRadius + edgeFade
    local innerZeroRadius = _max(innerRadius - edgeFade, 0)
    local segments = _GetSegmentCount(radius)
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


-- VGUI panels use local coordinates in Paint. The rounded mesh needs
-- screen-space coordinates, while the radius-zero surface path already gets
-- VGUI's automatic local-to-screen offset. Branch using the same rounded
-- radius clamp as _NormalizeRectArguments to avoid applying the offset twice.
local PanelMeta = FindMetaTable('Panel')
if PanelMeta then
    function PanelMeta:DrawOutlinedRoundedRect(x, y, w, h, radius, thickness, color)
        if (color and (color.a or 255) <= 0) then
            return
        end

        local normalizedWidth = _max(_Round(w), 0)
        local normalizedHeight = _max(_Round(h), 0)
        local normalizedRadius = _min(_max(_Round(radius or 0), 0), _floor(normalizedWidth * 0.5), _floor(normalizedHeight * 0.5))
        if (normalizedRadius <= 0) then
            return surface.DrawOutlinedRoundedRect(x, y, w, h, radius, thickness, color)
        end

        -- Mesh vertices do not inherit VGUI's alpha multiplier. Reconstruct
        -- the effective opacity from this panel and its parents, as child
        -- panels can remain fully opaque while their parent is fading out.
        local panelAlpha = 255
        local alphaPanel = self
        while _IsValid(alphaPanel) do
            panelAlpha = panelAlpha * alphaPanel:GetAlpha() / 255
            if (panelAlpha <= 0) then
                return
            end

            alphaPanel = alphaPanel:GetParent()
        end

        -- Use a panel-owned scratch Color so the caller's color is not
        -- modified and no new Color object is allocated on each Paint call.
        local sourceColor = color or color_white
        local drawColor = self._outlinedRoundedRectAlphaColor
        if (not drawColor) then
            drawColor = Color(0, 0, 0, 0)
            self._outlinedRoundedRectAlphaColor = drawColor
        end

        drawColor.r = sourceColor.r
        drawColor.g = sourceColor.g
        drawColor.b = sourceColor.b
        drawColor.a = (sourceColor.a or 255) * panelAlpha / 255

        if (drawColor.a <= 0) then
            return
        end

        local screenX, screenY = self:LocalToScreen(x, y)
        return surface.DrawOutlinedRoundedRect(screenX, screenY, w, h, radius, thickness, drawColor)
    end
end
