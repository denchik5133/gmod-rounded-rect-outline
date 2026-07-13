# Rounded Rect Outline for Garry's Mod

![Demo showcase of rounded rectangle outlines with various radius and thickness combinations](DrawOutlinedRoundedRect.jpg)

A drop-in `surface.DrawOutlinedRoundedRect` function for drawing rectangle
outlines with rounded corners on the client's 2D HUD/VGUI surface, at
adjustable stroke thickness. The outer edge is smooth at any radius (built
from GMod's own stock corner textures); the inner edge is cut with a
stencil test and then softened with a short alpha feather so it doesn't
look like a hard staircase.

## Installation

Copy the `autorun/client` folder into your addon so the paths become:

```
lua/autorun/client/cl_rounded_rect.lua
lua/autorun/client/cl_rounded_rect_demo.lua -- optional, demo only
```

Both files are client-only (`cl_` prefix, loaded from `autorun/client`) and
have no dependencies beyond stock GMod libraries.

## API

```lua
surface.DrawOutlinedRoundedRect(x, y, w, h, radius, thickness, color)
```

| Parameter   | Type   | Default        | Description                                                      |
|-------------|--------|-----------------|--------------------------------------------------------------------|
| `x, y`      | number | -               | Top-left corner position                                            |
| `w, h`      | number | -               | Rectangle width and height                                          |
| `radius`    | number | -               | Corner radius, automatically clamped to `min(radius, w/2, h/2)`     |
| `thickness` | number | `1`             | Stroke thickness in pixels, clamped to `<= radius`                  |
| `color`     | Color  | `color_white`   | Draw color                                                           |

Must be called from a paint-capable hook such as `HUDPaint`, `PostDrawHUD`,
or a `DPanel`'s `Paint`.

```lua
hook.Add('HUDPaint', 'MyRoundedRect', function()
    surface.DrawOutlinedRoundedRect(100, 100, 200, 100, 16, 2, color_white)
end)
```

## How it works (and how it got here)

Several approaches were tried, in order:

**1. Raw vector polygons every frame.** Pixelated at any decent radius --
GMod's 2D surface has no MSAA, so a curved edge built from hand-placed
polygon segments always rasterizes with a hard, aliased staircase, worse
the larger the radius.

**2. Stock `gui/cornerN` corner textures (the same ones `draw.RoundedBox`
uses) for the outer edge, with the inner edge cut using a stencil test.**
The outer edge came out smooth for free, since `gui/cornerN` is a
pre-antialiased texture and GMod downsamples it with normal bilinear
filtering. The inner "hole" is marked in the stencil buffer using an
explicit triangle-fan arc (not a textured quad -- see the code comments
for why a textured quad over-marks the stencil and eats a chunk out of the
ring near each corner).

**3. Bake the exact ring shape into a RenderTarget-backed texture, to get
antialiasing on both edges from one texture's alpha channel.** This was
tried and reverted. In principle it's the "right" fix (both edges would be
antialiased from a single downsampled bake, no stencil hard-edge at all),
but GMod's render-target alpha-channel behaviour proved too fragile to get
right reliably in practice -- multiple different, non-obvious causes
(missing `OverrideAlphaWriteEnable`, override-before-`cam.Start2D` being
silently discarded, missing `TEXTUREFLAGS_EIGHTBITALPHA`) each produced
the same "opaque black square instead of transparent" symptom, and fixing
one didn't guarantee the others were also right. Since the RT approach
could regress the outer edge too (as it did), it was reverted in favor of
a lower-risk option.

**4. Tried: feathering the inner edge with a few thin, low-alpha bands
drawn just inside the true inner radius.** Also reverted -- rather than
softening the staircase, it visibly thickened and blurred every stroke
(most noticeably at small radius/thickness values), making the result
look worse, not better.

**Current state: approach 2, unchanged.** Outer edge smooth (stock
texture), inner edge is a plain hard stencil cut with visible pixelation
at small radii. No further attempt is in progress -- both alternatives
tried so far (RT bake, alpha feather) made things worse rather than
better, so the simplest working version is kept until a genuinely
different technique is worth trying.

### Gotchas found along the way (kept for reference)

- **A textured quad marks its entire bounding square in the stencil
  buffer, not just the texture's visibly opaque pixels.** Stencil writes
  happen for every rasterized fragment of a quad regardless of that
  fragment's texture alpha. If you ever need a stencil mask to match an
  arbitrary alpha shape exactly, build it from real geometry (e.g. a
  triangle fan), not a textured quad.
- **`render.OverrideColorWriteEnable(true, false)` is the reliable way to
  make a draw invisible while still writing to the stencil/depth buffer**
  -- relying on draw color alpha `0` instead is not reliable, since GMod's
  blend state can leave a pixel's colour untouched without that implying
  the rasterizer skipped it for stencil purposes too.
- **Never fan a ring sector (area between two arcs) from a single center
  point** -- it's not convex once the angular span is wide relative to the
  radius, so a single `surface.DrawPoly` fan self-intersects (a "bowtie").
  Build it from many small quads instead, one per arc segment.
- **GMod render targets need `render.OverrideAlphaWriteEnable(true, true)`
  after `cam.Start2D()`, plus `TEXTUREFLAGS_EIGHTBITALPHA` (8192) on
  `GetRenderTargetEx`**, or "empty" areas render as opaque black instead
  of transparent. Even with both of those, this project still saw a black
  square in testing, which is why the RT approach was dropped rather than
  pursued further -- flagging here in case a future attempt hits the same
  wall.

## Performance

- Runtime cost per rectangle: 2 filled rounded boxes (via `surface.DrawRect`
  + textured corners + a 32-segment triangle-fan arc per corner) for the
  stencil-mark pass and the visible ring. No render targets or materials
  are created.
- Radii beyond 512px fall back to stretching `gui/corner512` larger than
  its native resolution, which can look slightly soft at very large radii.

## Demo

`cl_rounded_rect_demo.lua` draws a grid of example boxes covering
different radius/thickness combinations, including a large radius (90) to
show the outer edge stays smooth. It is always drawn via `HUDPaint` --
there is no toggle command, so simply removing the file (or its
`hook.Add` call) disables it.

Edit the `DEMO_BOXES` table in that file to add or change examples.
