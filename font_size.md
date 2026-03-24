# Font Sizing in the Canvas Renderer

## Units at a Glance

| Unit | Definition | Used in |
|---|---|---|
| **Point (pt)** | 1/72 inch | `ProjectFontSettings` (user-facing UI) |
| **DIP** | 1/96 inch (device-independent pixel at 96 DPI) | D2D/DirectWrite, canvas coordinates |
| **cm** | centimetre | Canvas physical size (`canvas_width_cm`, `canvas_height_cm`) |

The canvas coordinate system is built on **96-DPI DIPs**:

```
preview_pixels_per_cm = 96.0 / 2.54   ← project_settings.zig
```

So 1 cm = 37.8 DIPs, and all node/edge positions and sizes are stored and drawn in DIPs.

---

## The pt → DIP Conversion

`ProjectFontSettings` stores font sizes in **typographic points** because that is the unit users understand ("14pt body text").  DirectWrite's `CreateTextFormat` however expects its `fontSize` argument in **DIPs**, not points.

$$\text{font\_size\_dip} = \text{font\_size\_pt} \times \frac{96}{72} \approx 1.\overline{3} \times \text{font\_size\_pt}$$

This conversion is applied in `draw.zig` inside both `drawLabel` and `drawLabelAligned` before every `CreateTextFormat` call:

```zig
// draw.zig  (app/platform/windows/canvas/draw.zig)
const font_size_dip: f32 = font_size_pt * (96.0 / 72.0);
const hr = dwrite_factory.CreateTextFormat(
    fontFamilyNameW(font_family),
    null, …,
    font_size_dip,   // ← DIPs, not points
    …,
);
const half_h: f32 = font_size_dip * 1.4;   // bounding box in canvas DIPs
```

Without the conversion, a 14 pt font would be rendered as if it were 14 DIPs (~10.5 pt), making text look noticeably too small for the stated canvas size.

---

## Data Flow

```
User picks 14 pt in the Font Settings dialog
  │
  ▼
ProjectFontSettings.node_label_size = 14.0    (project_settings.zig)
  │  saved/loaded as JSON sidecar
  ▼
project_font_settings (windows_main.zig:318)
  │  written into every node on graph load / settings change
  ▼
StudioEditableNode.label_font_size = 14.0     (state.zig, extern struct field)
  │  read at draw time
  ▼
draw.zig:  font_size_n = clamp(node.label_font_size, 6, 48)
  │
  ▼
drawLabel(…, font_size_pt = font_size_n)
  │
  ├─ font_size_dip = font_size_pt × 96/72  → 18.67 DIP
  └─ CreateTextFormat(…, font_size_dip)
```

The same chain applies to:
- **Subgraph titles** – `ProjectFontSettings.group_title_size` → `StudioEditableSubgraph` → `draw.zig`
- **Edge labels** – `ProjectFontSettings.edge_label_size` → `StudioEditableEdge` → `draw.zig`

---

## Canvas Physical Scale

At 96 DPI, 1 DIP = 1/96 inch = 0.0265 cm.  A default 15 cm canvas is:

$$15 \times \frac{96}{2.54} \approx 566 \text{ DIPs wide}$$

A 14 pt node label occupies:

$$14 \times \frac{96}{72} \approx 18.7 \text{ DIPs tall (cap height region)}$$

which is roughly $18.7 / 37.8 \approx 0.50$ cm on the canvas — matching what a 14 pt label looks like when the document is printed or exported at the configured physical size.

---

## Export

The high-resolution PNG export path (`renderGraphToD2DPng`) creates an off-screen render target also at **96 DPI** and uses the same viewport zoom to map canvas DIPs to output pixels, so exported text renders at exactly the same physical size as the on-screen preview.

```
export DPI = 96                                (windows_main.zig:3320)
export zoom = output_pixel_width / graph_width_in_DIPs
```

The 600 DPI `exportDimensionsFromCentimeters` value is only used for the
software-rasterised Mermaid PNG path (`app/preview.zig`), which has its own
`font_size = 16.0` constant and does **not** read `ProjectFontSettings`.
