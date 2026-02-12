# merrow

> ⚠️ **DO NOT USE (YET)**

Under development: A fast, self-contained Mermaid diagram renderer.

Merrow parses Mermaid diagram syntax and renders to **PNG** (raster via a built-in canvas) and **SVG** (vector). 

The main use case for merrow is the generation of Flowchart and Sequence diagrams for documents - hence the focus on PNG rendering.

## Supported Diagram Types

| Diagram | Parse | SVG | PNG |
|---------|-------|-----|-----|
| Flowchart | ✅ | ✅ | ✅ |
| Sequence | ✅ | ✅ | ✅ |
| Class | ✅ | ✅ | ✅ |
| Entity-Relationship | ✅ | ✅ | ✅ |
| Gantt | ✅ | ✅ | ✅ |
| Pie | ✅ | ✅ | ✅ |
| Journey | ✅ | ✅ | ✅ |

## Install

### From GitHub Releases

Download the latest release for your platform from the [Releases](https://github.com/albanread/merrow/releases) page.

```sh
# Example: macOS Apple Silicon
tar xzf merrow-v0.1.0-macos-aarch64.tar.gz
cd merrow-v0.1.0-macos-aarch64
./merrow diagram.mmd diagram.png
```

Each release archive includes the `merrow` binary and the bundled `fonts/` directory.
Verify your download against the `checksums-sha256.txt` file included in every release.

### From Source

Requires **Zig 0.15.2** or later.

```sh
zig build
```

The binary is placed at `zig-out/bin/merrow`.

For an optimised build:

```sh
zig build -Doptimize=ReleaseSafe
```

## Usage

### Single File

```sh
# Render to PNG (default)
merrow input.mmd output.png

# Render to SVG
merrow input.mmd output.svg

# Auto-detect output name from input (diagram.mmd → diagram.png)
merrow diagram.mmd

# Force SVG output without specifying a filename
merrow diagram.mmd --svg
```

The output format is determined by the file extension (`.png` or `.svg`).
Flags like `--svg` can appear in any position.

### Bulk Mode

Render all `.mmd` files in a directory at once:

```sh
merrow --bulk <infolder> <outfolder> [--force] [--svg]
```

Options:

| Flag | Description |
|------|-------------|
| `--force` | Re-render all files regardless of timestamps |
| `--svg` | Output SVG instead of PNG |

By default, bulk mode only renders files whose `.mmd` source is newer than the existing output — making it fast for incremental workflows.

**Examples:**

```sh
# Render all diagrams to PNG (only changed files)
merrow --bulk docs/diagrams out/images

# Force re-render everything as SVG
merrow --bulk docs/diagrams out/images --svg --force

# Flags can appear in any order
merrow --svg --bulk src/diagrams build/images --force
```

**Sample output:**

```
=== Merrow Bulk Render ===

  Input folder:  docs/diagrams
  Output folder: out/images
  Format:        PNG
  Mode:          update

  Found 12 .mmd file(s)

  ok    flowchart.mmd -> flowchart.png  (14ms)
  ok    sequence.mmd -> sequence.png  (3ms)
  skip  pie.mmd  (up to date)
  ok    state.mmd -> state.png  (11ms)

--- Summary ---
  Rendered: 3 file(s)
  Skipped:  1 file(s)  (up to date)
  Render time:  28ms
  Total time:   31ms
```

### Example

Given `diagram.mmd`:

```text
graph TD
    A[Start] --> B{Decision}
    B -->|Yes| C[Process]
    B -->|No| D[Skip]
    C --> E[Done]
    D --> E
```

```sh
merrow diagram.mmd diagram.png
```

## Fonts

Merrow looks for TrueType fonts in the following locations (in order):

1. A `fonts/` directory next to the executable
2. A `fonts/` directory relative to the current working directory

Place a `.ttf` file (e.g. DejaVu Sans) in one of those locations for text rendering in PNG output. SVG output specifies font families in the markup and doesn't require a local font file.

Release archives include the Lato font family ready to use.

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

In summary: **Dagre is the bridge that brought 1990s academic graph theory from C++ (Graphviz) to the Web (JavaScript)**

## Running Tests

```sh
zig build test
```

## Releasing

Releases are automated via GitHub Actions. The workflow tests, cross-compiles for four platforms, and publishes a GitHub Release with checksums.

**To create a release:**

```sh
git tag v0.1.0
git push origin v0.1.0
```

The workflow builds these targets:

| Platform | Architecture | Archive |
|----------|-------------|---------|
| Linux | x86_64 | `.tar.gz` |
| Linux | aarch64 | `.tar.gz` |
| macOS | x86_64 | `.tar.gz` |
| macOS | aarch64 | `.tar.gz` |

You can also trigger a release manually from the Actions tab with a custom tag.

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
.github/workflows/        # CI/CD release workflow
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