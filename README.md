# merrow

A fast, self-contained Mermaid diagram renderer written in Zig.

Merrow parses Mermaid diagram syntax and renders to **PNG** (raster via a built-in canvas) and **SVG** (vector). No browser, no JavaScript runtime, no external dependencies beyond a font file.

## Supported Diagram Types

| Diagram | Parse | SVG | PNG |
|---------|-------|-----|-----|
| Flowchart | ✅ | ✅ | ✅ |
| Sequence | ✅ | ✅ | ✅ |
| Class | ✅ | ✅ | ✅ |
| State | ✅ | ✅ | ✅ |
| Entity-Relationship | ✅ | ✅ | ✅ |
| Gantt | ✅ | ✅ | ✅ |
| Pie | ✅ | ✅ | ✅ |
| Journey | ✅ | ✅ | ✅ |

## Building

Requires **Zig 0.15.2** or later.

```sh
zig build
```

The binary is placed at `zig-out/bin/merrow`.

## Usage

```sh
# Render to PNG (default)
./zig-out/bin/merrow input.mmd output.png

# Render to SVG
./zig-out/bin/merrow input.mmd output.svg
```

The output format is determined by the file extension (`.png` or `.svg`).

### Example

Given `diagram.mmd`:

```text
stateDiagram-v2
    [*] --> Idle
    Idle --> Processing : Start
    Processing --> Done : Complete
    Processing --> Error : Fail
    Error --> Idle : Reset
    Done --> [*]
```

```sh
./zig-out/bin/merrow diagram.mmd diagram.png
```

## Fonts

Merrow looks for TrueType fonts in the following locations (in order):

1. A `fonts/` directory next to the executable
2. A `fonts/` directory relative to the current working directory

Place a `.ttf` file (e.g. DejaVu Sans) in one of those locations for text rendering in PNG output. SVG output specifies font families in the markup and doesn't require a local font file.

## Layout Engine

Merrow includes a full **Dagre**-style layout engine (ported from Rust/JS reference implementations):

- **Network simplex** rank assignment
- **Barycenter** crossing minimisation (Barth et al. accumulator-tree cross counting)
- **Brandes–Köpf** coordinate assignment
- **Acyclic** transformation with edge reversal
- **Edge normalisation** with dummy nodes for long-span edges
- **Compound graph** support (subgraphs)

This is used by the flowchart, class, and state diagram renderers.

## Running Tests

```sh
zig build test
```

## Project Structure

```
src/
├── main.zig              # CLI entry point
├── model.zig             # Shared Dagre graph data types
├── graph/                # Directed graph data structure
├── layout/               # Dagre layout engine
│   └── dagre/            # Ranking, ordering, positioning
├── parser/               # Flowchart parser & lexer
├── render/               # Canvas (PNG) and SVG writer
├── class/                # Class diagram parser & renderers
├── er/                   # ER diagram parser & renderers
├── gantt/                # Gantt chart parser & renderers
├── journey/              # Journey map parser & renderers
├── pie/                  # Pie chart parser & renderers
├── sequence/             # Sequence diagram parser & renderers
└── state/                # State diagram parser & renderers
test-diagrams/            # Sample .mmd files and rendered outputs
fonts/                    # TrueType fonts for rasterisation
```

## Acknowledgements

Merrow is a Zig port inspired by [**Selkie**](https://github.com/btucker/selkie), a fast, native Mermaid diagram renderer written in Rust. Selkie's architecture, layout engine, and rendering approach served as the primary reference for this project. Huge thanks to the Selkie team for their excellent work.

Both projects stand on the shoulders of these foundational efforts:

- **[Mermaid](https://github.com/mermaid-js/mermaid)** — The original JavaScript diagramming library that defines the syntax and rendering we aim to match
- **[Dagre](https://github.com/dagrejs/dagre)** — Graph layout algorithms that inspire our layout engine
- **[ELK](https://github.com/kieler/elkjs)** — Eclipse Layout Kernel, providing additional layout strategies

## License

MIT