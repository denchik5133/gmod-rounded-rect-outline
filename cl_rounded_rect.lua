/***
 *   @addon         DrawOutlinedRoundedRect
 *   @component     UI Effects
 *   @license       MIT License
 *   @version       1.0.0
 *   @release_date  13/07/2026
 *   @author        DDI Scripts
 *
 *   @contact
 *                  Discord:  https://discord.gg/CND6B5sH3j
 *                  GitHub:   https://github.com/denchik5133/gmod-rounded-rect-outline
 *
 *   @description   Draws rectangle outlines with rounded corners on the
 *                  client 2D surface, with adjustable stroke thickness.
 *                  Corners are rendered using the stock engine textures
 *                  (gui/corner8/16/32/64/512, the same ones stock draw.lua
 *                  uses for draw.RoundedBox) instead of hand-built vector
 *                  polygons, so the OUTER edge is smooth at any radius with
 *                  no pixelated/jagged ('staircase') look. The INNER edge
 *                  (where the stroke meets the hollow middle) is cut with a
 *                  stencil test and then softened with a short alpha
 *                  feather, since a stencil test itself has no
 *                  antialiasing -- see @notes for why, and why a fully
 *                  baked-texture approach was tried and reverted.
 *
 *   @functions
 *                  - DrawOutlinedRoundedRect: Draws a rounded rectangle
 *                    outline with configurable radius, thickness, and color.
 *                  - _GetCornerTexture (internal): Picks the smallest stock
 *                    corner texture that is >= the requested radius.
 *
 *   @example
 *                  hook.Add('HUDPaint', 'MyRoundedRect', function()
 *                      surface.DrawOutlinedRoundedRect(100, 100, 200, 100, 16, 2, color_white)
 *                  end)
 *
 *   @notes         How the outline is built:
 *                  1. Draw an inner rounded box (radius - thickness),
 *                     inset by `thickness` on every side, writing only to
 *                     the stencil buffer. Colour writes are force-disabled
 *                     for this pass via render.OverrideColorWriteEnable(
 *                     true, false) -- relying on draw color alpha = 0
 *                     instead is NOT reliable, GMod's blend state can leave
 *                     a pixel's colour untouched without that implying the
 *                     stencil write was skipped too (or vice versa).
 * 
 *                     This pass marks the hole with an explicit
 *                     triangle-fan arc (not the stock corner texture) --
 *                     a textured quad rasterizes, and therefore
 *                     stencil-marks, its ENTIRE r x r square regardless of
 *                     the texture's per-pixel alpha, which would wrongly
 *                     mark part of the visible ring (the texture's
 *                     transparent 'cut corner' triangle) as hole too,
 *                     eating a chunk out of the ring near each corner.
 *                  2. Draw the full-size outer rounded box normally
 *                     (stock corner textures, smooth), with the stencil
 *                     compare function set to only pass pixels that were
 *                     NOT marked in step 1.
 *                  A stencil test is always a hard pass/fail, never
 *                  antialiased, no matter how precise the shape tested
 *                  against is -- so the inner edge stays jagged even
 *                  though the outer edge (drawn from a real texture) is
 *                  smooth. Two attempts to fix that were tried and
 *                  reverted, see @notes below.
 *
 *                  Two other approaches were tried for the inner edge and
 *                  reverted because they made things worse, not better:
 *
 *                  - Baking the whole ring into a supersampled RenderTarget
 *                    texture (antialiasing both edges from one alpha
 *                    channel). GMod RT alpha-channel behaviour proved too
 *                    fragile to get right reliably -- it kept producing an
 *                    opaque black square instead of a transparent one, for
 *                    more than one distinct underlying cause.
 *                  - Feathering the inner edge with extra low-alpha bands
 *                    drawn just inside the true radius. This visibly
 *                    thickened and blurred every stroke instead of
 *                    smoothing it, so it was removed again.
 *
 *                  Current state: outer edge smooth (texture-based), inner
 *                  edge is a plain hard stencil cut (visible pixelation at
 *                  small radii). See README.md for the full history.
 */



local _cos = math.cos
local _sin = math.sin
local _rad = math.rad
local _min = math.min
local _max = math.max
local _floor = math.floor
local _Round = math.Round
local _ipairs = ipairs
local _DrawPoly = surface.DrawPoly
local _DrawRect = surface.DrawRect
local _SetTexture = surface.SetTexture
local _ClearStencil = render.ClearStencil
local _SetDrawColor = surface.SetDrawColor
local _GetTextureID = surface.GetTextureID
local _SetStencilEnable = render.SetStencilEnable
local _SetStencilWriteMask = render.SetStencilWriteMask
local _DrawTexturedRectUV = surface.DrawTexturedRectUV
local _SetStencilTestMask = render.SetStencilTestMask
local _SetStencilReferenceValue = render.SetStencilReferenceValue
local _SetStencilCompareFunction = render.SetStencilCompareFunction
local _SetStencilPassOperation = render.SetStencilPassOperation
local _SetStencilFailOperation = render.SetStencilFailOperation
local _SetStencilZFailOperation = render.SetStencilZFailOperation
local _OverrideColorWriteEnable = render.OverrideColorWriteEnable

local CORNER_TEXTURES = {
    { size = 8, id = _GetTextureID('gui/corner8') },
    { size = 16, id = _GetTextureID('gui/corner16') },
    { size = 32, id = _GetTextureID('gui/corner32') },
    { size = 64, id = _GetTextureID('gui/corner64') },
    { size = 512, id = _GetTextureID('gui/corner512') },
}

--- Picks the smallest stock corner texture whose native size is >= the
-- requested radius (falls back to the largest one available). Mirrors
-- the same selection stock draw.RoundedBoxEx uses.
local function _GetCornerTexture(radius)
    for _, entry in _ipairs(CORNER_TEXTURES) do
        if (radius <= entry.size) then
            return entry.id
        end
    end

    return CORNER_TEXTURES[#CORNER_TEXTURES].id
end

--- Draws a filled rounded rectangle (all 4 corners rounded), same
-- behaviour as stock draw.RoundedBox but taking a raw Color instead of
-- going through draw.SetDrawColor state, so it composes cleanly with the
-- stencil-based outline logic below.
local function _DrawFilledRoundedRect(x, y, w, h, radius, color)
    _SetDrawColor(color)

    if (radius <= 0) then
        _DrawRect(x, y, w, h)
        return
    end

    -- Straight middle/edges, no texture needed.
    _DrawRect(x + radius, y, w - radius * 2, h)
    _DrawRect(x, y + radius, radius, h - radius * 2)
    _DrawRect(x + w - radius, y + radius, radius, h - radius * 2)

    -- Rounded corners via stock engine textures (see file header for why
    -- these don't pixelate).
    _SetTexture(_GetCornerTexture(radius))
    _DrawTexturedRectUV(x, y, radius, radius, 0, 0, 1, 1) -- top-left
    _DrawTexturedRectUV(x + w - radius, y, radius, radius, 1, 0, 0, 1) -- top-right
    _DrawTexturedRectUV(x, y + h - radius, radius, radius, 0, 1, 1, 0) -- bottom-left
    _DrawTexturedRectUV(x + w - radius, y + h - radius, radius, radius, 1, 1, 0, 0) -- bottom-right
end

local MASK_SEGMENTS = 32

--- Draws one filled quarter-disc (a triangle fan from the center point),
-- used only for stencil-marking the inner hole -- see
-- _MarkStencilHole below for why this can't reuse the corner textures.
local function _DrawFilledQuarterDisc(cx, cy, r, startAngleDeg)
    if (r <= 0) then
        return
    end

    local points = {
        {
            x = cx,
            y = cy
        }
    }

    for i = 0, MASK_SEGMENTS do
        local a = _rad(startAngleDeg + (i / MASK_SEGMENTS) * 90)
        points[#points + 1] = {
            x = cx + _cos(a) * r,
            y = cy + _sin(a) * r
        }
    end

    _DrawPoly(points)
end

--- Marks the stencil buffer for a rounded rectangle's exact shape, to be
-- used as the 'hole' in DrawOutlinedRoundedRect. See file header notes
-- for why this uses an explicit triangle fan instead of the corner textures.
local function _MarkStencilHole(x, y, w, h, radius)
    if (radius <= 0) then
        _DrawRect(x, y, w, h)
        return
    end

    _DrawRect(x + radius, y, w - radius * 2, h)
    _DrawRect(x, y + radius, radius, h - radius * 2)
    _DrawRect(x + w - radius, y + radius, radius, h - radius * 2)

    _DrawFilledQuarterDisc(x + radius, y + radius, radius, 180) -- top-left
    _DrawFilledQuarterDisc(x + w - radius, y + radius, radius, 270) -- top-right
    _DrawFilledQuarterDisc(x + radius, y + h - radius, radius, 90) -- bottom-left
    _DrawFilledQuarterDisc(x + w - radius, y + h - radius, radius, 0) -- bottom-right
end

--- surface.DrawOutlinedRoundedRect(x, y, w, h, radius, thickness, color)
--
-- Draws the outline of a rectangle with rounded corners, using stock
-- engine corner textures (no pixelation on the outer edge at any
-- radius) and the stencil buffer to punch out the inner area, leaving a
-- ring/outline. See the file header for the full explanation.
--
-- Parameters:
--     x, y - top-left corner coordinates
--     w, h - width and height of the rectangle
--     radius - corner radius
--     thickness - stroke thickness (default 1), clamped to <= radius
--     color - Color to draw with (default color_white)
function surface.DrawOutlinedRoundedRect(x, y, w, h, radius, thickness, color)
    x = _Round(x)
    y = _Round(y)
    w = _Round(w)
    h = _Round(h)
    radius = _min(_Round(radius or 0), _floor(w / 2), _floor(h / 2))
    thickness = _min(_Round(thickness or 1), radius > 0 and radius or _floor(_min(w, h) / 2))
    color = color or color_white

    if (thickness <= 0) then
        return
    end

    -- No corner rounding at all -- draw a plain rectangular outline, no
    -- need for the stencil trick.
    if (radius <= 0) then
        _SetDrawColor(color)
        _DrawRect(x, y, w, thickness) -- top
        _DrawRect(x, y + h - thickness, w, thickness) -- bottom
        _DrawRect(x, y + thickness, thickness, h - thickness * 2) -- left
        _DrawRect(x + w - thickness, y + thickness, thickness, h - thickness * 2) -- right
        return
    end

    _ClearStencil()
    _SetStencilEnable(true)
    _SetStencilWriteMask(0xFF)
    _SetStencilTestMask(0xFF)
    _SetStencilReferenceValue(1)

    -- Pass 1: mark the inner hole in the stencil buffer only.
    _SetStencilCompareFunction(STENCILCOMPARISONFUNCTION_ALWAYS)
    _SetStencilPassOperation(STENCILOPERATION_REPLACE)
    _SetStencilFailOperation(STENCILOPERATION_KEEP)
    _SetStencilZFailOperation(STENCILOPERATION_KEEP)

    local innerRadius = _max(radius - thickness, 0)

    _OverrideColorWriteEnable(true, false)
    _SetDrawColor(color)
    _MarkStencilHole(x + thickness, y + thickness, w - thickness * 2, h - thickness * 2, innerRadius)
    _OverrideColorWriteEnable(false, false)

    -- Pass 2: draw the outer rounded rect, but only where the stencil was
    -- NOT marked in pass 1 -- i.e. skip the punched-out inner area,
    -- leaving just the ring/outline visible.
    _SetStencilCompareFunction(STENCILCOMPARISONFUNCTION_NOTEQUAL)
    _SetStencilPassOperation(STENCILOPERATION_KEEP)

    _DrawFilledRoundedRect(x, y, w, h, radius, color)

    _SetStencilEnable(false)
end
