/***
 *   @addon         DrawOutlinedRoundedRect
 *   @component     UI Effects - Demo
 *   @license       MIT License
 *   @version       1.0.0
 *   @release_date  13/07/2026
 *   @author        DDI Scripts
 *
 *   @contact
 *                  Discord:  https://discord.gg/CND6B5sH3j
 *                  GitHub:   https://github.com/denchik5133/gmod-rounded-rect-outline
 *
 *   @description   Demo showcase for surface.DrawOutlinedRoundedRect (see
 *                  cl_rounded_rect.lua). Draws a grid of example boxes
 *                  covering different radius/thickness combinations, all
 *                  using the stock corner-texture + stencil technique, so
 *                  every corner stays smooth even at large radii.
 *
 *
 *   @notes         Edit the DEMO_BOXES table below to add or change the
 *                  showcased radius/thickness combinations. Always drawn
 *                  via HUDPaint, no toggle command.
 */
 


-- Each entry: { w, h, radius, thickness, label }
local DEMO_BOXES = {
    { w = 180, h = 90, radius = 8, thickness = 1, label = 'radius 8, thickness 1' },
    { w = 180, h = 90, radius = 20, thickness = 2, label = 'radius 20, thickness 2' },
    { w = 180, h = 90, radius = 40, thickness = 3, label = 'radius 40, thickness 3' },
    { w = 180, h = 90, radius = 45, thickness = 15, label = 'radius 45, thickness 15 (thick stroke)' },
    { w = 180, h = 90, radius = 60, thickness = 4, label = 'radius 60, thickness 4 (large radius, still smooth)' },
    { w = 180, h = 90, radius = 90, thickness = 6, label = 'radius 90, thickness 6 (full pill)' },
}

local COLUMNS = 3
local PADDING_X = 40
local PADDING_Y = 70
local START_X = 60
local START_Y = 80

hook.Add('HUDPaint', 'RoundedRectDemo', function()
    draw.SimpleText('surface.DrawOutlinedRoundedRect demo', 'DermaDefaultBold', START_X, START_Y - 40, color_white)

    for i, box in ipairs(DEMO_BOXES) do
        local col = (i - 1) % COLUMNS
        local row = math.floor((i - 1) / COLUMNS)

        local x = START_X + col * (box.w + PADDING_X)
        local y = START_Y + row * (box.h + PADDING_Y)

        surface.DrawOutlinedRoundedRect(x, y, box.w, box.h, box.radius, box.thickness, color_white)
        draw.SimpleText(box.label, 'DermaDefault', x, y + box.h + 6, color_white)
    end
end)
