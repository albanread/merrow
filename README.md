# merrow

A fast, self-contained Mermaid diagram renderer.

Merrow parses Mermaid diagram syntax and renders to **PNG** (raster via a built-in canvas) and **SVG** (vector). 

The main use case for merrow is the generation of Flowchart and Sequence diagrams for document - hence the focus on PNG rendering.

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

Merrow includes a full **Dagre**-style layout engine.

- **Network simplex** rank assignment
- **Barycenter** crossing minimisation (Barth et al. accumulator-tree cross counting)
- **Brandes–Köpf** coordinate assignment
- **Acyclic** transformation with edge reversal
- **Edge normalisation** with dummy nodes for long-span edges
- **Compound graph** support (subgraphs)

This is used by the flowchart, class, and state diagram renderers.

### The Origins of Dagre

**Dagre** is a JavaScript library designed to lay out directed graphs on the client side. It is the layout engine that powers **Mermaid.js** flowcharts — when you write `graph TD` in Mermaid, Dagre is the algorithm calculating where the boxes and arrows go.

To understand Dagre, you must look at **[Graphviz](https://graphviz.org/)** (Graph Visualization Software), started at AT&T Labs Research in the late 1980s. Graphviz established the standard for automated graph layout, particularly with its `dot` tool, which uses a **layered approach** to hierarchical graph drawing. It was so effective that it became the benchmark for how directed graphs should look.

As web applications grew more complex in the early 2010s, there was a need to render these graphs directly in the browser without server-side tools. **Chris Pettitt** created `dagre` (and its renderer `dagre-d3`) as a way to bring strict, Graphviz-style layout algorithms to JavaScript — essentially a port of the techniques described in the same academic papers that powered Graphviz, adapted for a JS environment.

**[Selkie](https://github.com/btucker/selkie)** contains an extremely thorough Rust port of Dagre.

**Merrow** (this project) ports the same algorithms to Zig, aiming for high performance and embedded use cases.

Dagre is not just code — it is an implementation of specific academic research. The two pillars of its logic are:

- **Rank Assignment** — *Gansner, E. R., Koutsofios, E., North, S. C., & Vo, K. P. (1993). "A Technique for Drawing Directed Graphs."* This paper describes the **Network Simplex** algorithm used to assign layers (ranks) to nodes while minimizing the total length of edges.
- **Coordinate Assignment** — *Brandes, U., & Köpf, B. (2001). "Fast and Simple Horizontal Coordinate Assignment."* Once nodes are in layers, this algorithm determines their horizontal position, producing symmetric, balanced layouts that avoid the "spaghetti" look.

In summary: **Dagre is the bridge that brought 1990s academic graph theory from C++ (Graphviz) to the Web (JavaScript)

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

Merrow is a Zig port inspired by [**Selkie**](https://github.com/btucker/selkie), a fast, native Mermaid diagram renderer written in Rust. 

Selkie's architecture, layout engine, and rendering approach served as the primary reference for this project. 

Huge thanks to the Selkie team for sharing their excellent work.

Selkie has a wider and more comprehensive scope than merrow, Merrow is mainly interested in creating small diagrams for documents.

Both projects stand on the shoulders of these foundational efforts:

- **[Mermaid](https://github.com/mermaid-js/mermaid)** — The original JavaScript diagramming library that defines the syntax and rendering.
- **[Dagre](https://github.com/dagrejs/dagre)** — Graph layout algorithms.
- **[ELK](https://github.com/kieler/elkjs)** — Eclipse Layout Kernel, providing additional layout strategies

## License

MIT
