# wordcomglue Specification

This document defines the library component tentatively named `wordcomglue`.

`wordcomglue` is a Microsoft Word automation library for Windows. Its job is to open or create Word documents, place branded assets and text into those documents, and save the result in a predictable way.

The library must expose a plain C ABI so it can be called from:

- C
- C++
- Zig
- Rust
- other languages that can bind to a stable C interface

## Purpose

`wordcomglue` exists to solve one narrow problem well:

- manage Word through COM automation
- assemble branded documents from already-prepared text and PNG assets
- hide Word COM complexity behind a stable library boundary

It is a document assembly component, not a document authoring system.

## Scope

The first version of `wordcomglue` must support:

- starting or attaching to Microsoft Word
- creating a new document
- opening an existing document
- saving a document
- saving a document under a new path
- closing a document
- shutting down Word when owned by the library
- setting a default document font to Lato
- adding headings
- adding paragraphs
- adding plain text runs
- placing a full-width document banner from a PNG on disk at the top of the document body
- placing a trailer PNG at the bottom of the final page of the document
- inserting PNG graphics into the document body
- placing graphics above text
- placing graphics below text
- placing graphics to the left or right of text
- adding captions
- basic page and section breaks

## Non-Goals

`wordcomglue` must not be responsible for:

- Markdown parsing
- Mermaid parsing
- diagram rendering
- natural-language generation
- white-paper composition strategy
- document outline generation
- template design authoring

Those tasks belong to higher layers.

`wordcomglue` should receive already-decided content and layout intent, then apply that intent to a Word document.

## Primary Use Cases

The component is intended for workflows such as:

1. Create a new architecture white paper from generated headings, paragraphs, and PNG diagrams.
2. Open an existing `.docx` template and populate it with branded report content.
3. Add a full-width branded banner to the top of the document body.
4. Add a trailer image at the bottom of the final page only.
5. Insert diagrams with predictable spacing, captions, and alignment.
6. Place text beside smaller diagrams or callout graphics.
7. Save the result as a `.docx` and later support PDF export.

## Architectural Overview

The component should have three layers.

### 1. Word COM Adapter

This layer owns direct interaction with Word COM objects such as:

- `Application`
- `Documents`
- `Document`
- `Range`
- `Selection`
- `Paragraph`
- `InlineShape`
- `Shape`
- `Sections`
- `HeadersFooters`

This layer should be private to the library.

### 2. Internal Document Model For Operations

This layer should translate higher-level commands into stable Word actions.

Examples:

- "insert heading level 2"
- "insert a full-width header banner in section 1"
- "insert a right-aligned image with caption"
- "apply Lato as base document font"

This layer should normalize Word behavior and avoid leaking Word-specific constants to callers.

### 3. Public Plain ABI Layer

This layer is the only layer visible to external callers.

It must:

- expose a C ABI
- use opaque handles rather than language-specific objects
- use explicit structs for options
- use stable integer enums and flags
- avoid exceptions or C++ types in the API
- return structured error codes

## ABI Requirements

The public ABI must be plain C ABI.

### Calling Convention

The library should export functions using a standard C-compatible calling convention.

Examples by language intent:

- C and C++: `extern "C"`
- Zig: `callconv(.C)`
- Rust: `extern "C"`

The ABI must avoid:

- C++ classes
- templates in the public boundary
- STL types in parameters or return values
- exceptions crossing the boundary
- COM interfaces directly crossing the boundary

### Handle Model

The public API should use opaque handles.

Suggested opaque types:

- `wcg_library_handle`
- `wcg_session_handle`
- `wcg_document_handle`

The caller must not know the struct internals.

Example model:

```c
typedef struct wcg_library_handle_t* wcg_library_handle;
typedef struct wcg_session_handle_t* wcg_session_handle;
typedef struct wcg_document_handle_t* wcg_document_handle;
```

### String Encoding

The ABI should use UTF-8 for all incoming and outgoing text.

Reasons:

- Zig and Rust work cleanly with UTF-8
- C callers can still pass byte strings
- conversion to Windows UTF-16 can happen inside the library

All path parameters should be UTF-8 paths.

### Memory Ownership

The ABI must define ownership rules precisely.

Preferred rules:

- caller-owned input strings
- library-owned handles
- library-owned error message buffers when requested
- explicit free function for any heap memory returned by the library

Do not return memory that the caller cannot free deterministically.

### Threading Model

The spec should assume a single-thread-affine Word automation session.

Requirements:

- a session must be created and used on one thread
- the library must initialize COM correctly for that thread
- the library must document that handles are not thread-safe unless explicitly stated
- callers must not use the same session or document handle concurrently from multiple threads

This matters because Word COM automation is not a general free-threaded API.

## Public API Surface

The initial public API should be intentionally small.

### Lifecycle

```c
typedef uint32_t wcg_status;

typedef struct wcg_runtime_options {
    uint32_t abi_version;
    uint32_t flags;
} wcg_runtime_options;

wcg_status wcg_create_library(
    const wcg_runtime_options* options,
    wcg_library_handle* out_library);

wcg_status wcg_destroy_library(
    wcg_library_handle library);

wcg_status wcg_start_word(
    wcg_library_handle library,
    const struct wcg_word_options* options,
    wcg_session_handle* out_session);

wcg_status wcg_shutdown_word(
    wcg_session_handle session);
```

### Document Operations

```c
wcg_status wcg_create_document(
    wcg_session_handle session,
    const struct wcg_document_create_options* options,
    wcg_document_handle* out_document);

wcg_status wcg_open_document(
    wcg_session_handle session,
    const char* utf8_path,
    const struct wcg_document_open_options* options,
    wcg_document_handle* out_document);

wcg_status wcg_save_document(
    wcg_document_handle document);

wcg_status wcg_save_document_as(
    wcg_document_handle document,
    const char* utf8_path,
    const struct wcg_save_options* options);

wcg_status wcg_close_document(
    wcg_document_handle document,
    const struct wcg_close_options* options);
```

### Text And Style Operations

```c
wcg_status wcg_set_document_font(
    wcg_document_handle document,
    const struct wcg_font_spec* font);

wcg_status wcg_insert_heading(
    wcg_document_handle document,
    const char* utf8_text,
    const struct wcg_heading_options* options);

wcg_status wcg_insert_paragraph(
    wcg_document_handle document,
    const char* utf8_text,
    const struct wcg_paragraph_options* options);

wcg_status wcg_insert_text_run(
    wcg_document_handle document,
    const char* utf8_text,
    const struct wcg_text_run_options* options);
```

### Image And Layout Operations

```c
wcg_status wcg_insert_header_banner(
    wcg_document_handle document,
    const char* utf8_png_path,
    const struct wcg_banner_options* options);

wcg_status wcg_insert_footer_trailer(
    wcg_document_handle document,
    const char* utf8_png_path,
    const struct wcg_trailer_options* options);

wcg_status wcg_insert_image(
    wcg_document_handle document,
    const char* utf8_png_path,
    const struct wcg_image_options* options);

wcg_status wcg_insert_caption(
    wcg_document_handle document,
    const char* utf8_text,
    const struct wcg_caption_options* options);

wcg_status wcg_insert_page_break(
    wcg_document_handle document);

wcg_status wcg_insert_section_break(
    wcg_document_handle document,
    const struct wcg_section_break_options* options);
```

### Diagnostics And Errors

```c
wcg_status wcg_get_last_error(
    wcg_library_handle library,
    struct wcg_error_info* out_error);

wcg_status wcg_clear_last_error(
    wcg_library_handle library);

wcg_status wcg_free_string(
    wcg_library_handle library,
    char* utf8_string);
```

## Core Data Types

The API should use stable POD-style structs only.

### Status Codes

The ABI should define numeric status codes.

Suggested initial values:

```c
enum {
    WCG_STATUS_OK = 0,
    WCG_STATUS_INVALID_ARGUMENT = 1,
    WCG_STATUS_OUT_OF_MEMORY = 2,
    WCG_STATUS_COM_INIT_FAILED = 3,
    WCG_STATUS_WORD_NOT_INSTALLED = 4,
    WCG_STATUS_WORD_START_FAILED = 5,
    WCG_STATUS_DOCUMENT_OPEN_FAILED = 6,
    WCG_STATUS_DOCUMENT_SAVE_FAILED = 7,
    WCG_STATUS_DOCUMENT_CLOSE_FAILED = 8,
    WCG_STATUS_PATH_NOT_FOUND = 9,
    WCG_STATUS_PNG_NOT_FOUND = 10,
    WCG_STATUS_PNG_INSERT_FAILED = 11,
    WCG_STATUS_FONT_NOT_AVAILABLE = 12,
    WCG_STATUS_LAYOUT_UNSUPPORTED = 13,
    WCG_STATUS_INTERNAL_ERROR = 255
};
```

### Flags And Enums

Enums should use explicit integer storage in the C header.

Suggested enums:

- `wcg_visibility_mode`
- `wcg_alignment`
- `wcg_image_placement`
- `wcg_wrap_mode`
- `wcg_section_scope`
- `wcg_break_kind`
- `wcg_unit_kind`

### Units

The API should use explicit measurement units.

Suggested unit struct:

```c
typedef struct wcg_measurement {
    uint32_t unit_kind;
    double value;
} wcg_measurement;
```

Supported unit kinds should include:

- points
- inches
- millimeters
- percent_of_page_width
- percent_of_content_width

### Font Spec

```c
typedef struct wcg_font_spec {
    const char* utf8_family;
    double size_points;
    uint32_t flags;
} wcg_font_spec;
```

Font flags may include:

- bold
- italic
- underline

### Heading Options

```c
typedef struct wcg_heading_options {
    uint32_t level;
    uint32_t alignment;
    wcg_measurement spacing_before;
    wcg_measurement spacing_after;
    uint32_t page_break_before;
    const char* utf8_style_name;
} wcg_heading_options;
```

### Paragraph Options

```c
typedef struct wcg_paragraph_options {
    uint32_t alignment;
    wcg_measurement spacing_before;
    wcg_measurement spacing_after;
    double line_spacing;
    const char* utf8_style_name;
} wcg_paragraph_options;
```

### Image Options

```c
typedef struct wcg_image_options {
    uint32_t placement;
    uint32_t alignment;
    uint32_t wrap_mode;
    wcg_measurement width;
    wcg_measurement height;
    wcg_measurement max_width;
    wcg_measurement max_height;
    wcg_measurement spacing_before;
    wcg_measurement spacing_after;
    uint32_t preserve_aspect_ratio;
    uint32_t add_caption;
    const char* utf8_caption;
    const char* utf8_alt_text;
} wcg_image_options;
```

### Banner And Trailer Options

These should include:

- section scope
- first-page-only flag
- repeat-on-each-page flag where relevant
- preserve aspect ratio
- target width mode
- top or bottom spacing

## Behavioral Requirements

### Document Lifecycle

The library must support:

- creating a new blank document
- opening an existing `.docx`
- opening a template-backed document later if needed
- saving the current document
- saving to a new output path
- closing without leaving orphaned Word processes

If the library launches Word itself, it owns shutdown behavior.

If the library attaches to an existing Word instance, it must not shut down that external instance unless explicitly configured.

### Font Behavior

The library must support setting the document base font to Lato.

This must include:

- applying the base font to normal body text
- applying the font to headings unless overridden
- applying font settings to newly inserted text ranges when needed

The library should detect whether Lato is installed. If not, it should either:

- return `WCG_STATUS_FONT_NOT_AVAILABLE`, or
- apply a configured fallback and report the fallback through diagnostics

### Header Banner Behavior

The library must support a full-width banner image at the top of the page.

Preferred implementation:

- use the header area rather than fake body placement
- scale to writable content width
- preserve aspect ratio by default
- support first-page-only and all-pages modes

### Footer Trailer Behavior

The library must support two distinct trailer modes:

- footer-anchored trailer
- final-content trailer at the end of the document body

These are not the same and the API should preserve that distinction.

### Body Image Behavior

The library must support:

- full-width block images
- centered images
- left image with text beside it
- right image with text beside it
- captioned figures

The library should prioritize stable output over visually clever placement.

For side-by-side content, the preferred first implementation is a borderless two-column table because it is typically more stable in generated Word documents than free-floating wrapped shapes.

### Text Behavior

The library must support:

- heading 1 through heading 3 at minimum
- normal paragraphs
- plain text runs
- spacing control
- alignment control

The library should prefer Word styles over direct formatting wherever practical.

## Suggested Internal Strategy

The internal implementation should prefer:

- range-based editing over selection-based editing
- explicit style application over inherited interactive state
- deterministic placement rules
- explicit cleanup of COM references
- explicit conversion from UTF-8 to UTF-16 inside the library

The library should avoid relying on the current cursor position in Word unless the operation is explicitly defined in those terms.

## Error Model

The library must have a clear error model.

Each failing API call should return a non-zero `wcg_status`.

The library should also maintain per-library or per-session structured error information containing:

- status code
- human-readable UTF-8 message
- optional source function name
- optional underlying HRESULT
- optional underlying system error code

Suggested error struct:

```c
typedef struct wcg_error_info {
    uint32_t status;
    int32_t hresult;
    uint32_t system_error;
    char* utf8_message;
    char* utf8_function;
} wcg_error_info;
```

## ABI Versioning

The ABI must be versioned from day one.

Requirements:

- expose a compile-time ABI version constant in the public header
- include `abi_version` in top-level runtime options
- reject incompatible callers cleanly
- preserve binary compatibility across patch releases where possible

Suggested exported function:

```c
uint32_t wcg_get_abi_version(void);
```

## Platform Requirements

The first version targets:

- Windows only
- Microsoft Word desktop installed locally
- local COM automation only

The library should assume:

- Word typelibs are available on the machine
- the Windows SDK and COM libraries are installed for build time
- the caller is running in a desktop session where Word automation is supported

## Things The Higher Layer Will Probably Want Soon

If the end goal is architecture reports and white papers, the higher layer will likely need these capabilities shortly after the first release:

- cover page generation
- page numbers
- table of contents
- lists
- figure numbering
- cross-references
- section orientation changes for wide diagrams
- metadata such as title and author
- PDF export
- document template support
- repeatable caption styles
- keep-with-next for headings

These do not all need to be in version 1, but the ABI design should leave room for them.

## Recommended V1 Feature Set

Version 1 should implement only the stable core.

### Required In V1

- create library
- start Word
- create document
- open document
- save document
- save document as
- close document
- shutdown Word
- set base font to Lato
- insert heading
- insert paragraph
- insert text run
- insert header banner from PNG
- insert footer or end-of-document trailer from PNG
- insert body PNG image
- insert caption
- insert page break
- get structured last error

### Defer If Necessary

- advanced floating-shape positioning
- cross-references
- automatic figure numbering
- PDF export
- template introspection
- tables of contents
- section-specific advanced formatting rules

## Header Design Recommendation

The library should ship with a single C header, tentatively:

- `wordcomglue.h`

That header should contain:

- ABI version constant
- opaque handle typedefs
- status codes
- enums and flags
- POD option structs
- exported function declarations
- memory management rules
- a short usage example

## Example Usage Shape

This is not final code, but it shows the intended boundary.

```c
wcg_library_handle library = NULL;
wcg_session_handle session = NULL;
wcg_document_handle document = NULL;

wcg_runtime_options runtime = {0};
runtime.abi_version = WCG_ABI_VERSION_1;

wcg_word_options word = {0};
word.visibility_mode = WCG_VISIBILITY_HIDDEN;
word.flags = WCG_WORD_OWN_PROCESS;

wcg_font_spec lato = {0};
lato.utf8_family = "Lato";
lato.size_points = 11.0;

wcg_create_library(&runtime, &library);
wcg_start_word(library, &word, &session);
wcg_create_document(session, NULL, &document);
wcg_set_document_font(document, &lato);
wcg_insert_header_banner(document, "header.png", NULL);
wcg_insert_heading(document, "Architecture Overview", NULL);
wcg_insert_paragraph(document, "This document describes the target system.", NULL);
wcg_insert_image(document, "diagram.png", NULL);
wcg_save_document_as(document, "report.docx", NULL);
wcg_close_document(document, NULL);
wcg_shutdown_word(session);
wcg_destroy_library(library);
```

## Summary

`wordcomglue` should be a narrow Windows Word automation library with a stable plain C ABI.

Its job is to:

- manage Word sessions and documents
- apply a predictable branded document style
- place headings, paragraphs, and images reliably
- support architecture diagrams and white-paper layouts
- remain callable from C, C++, Zig, Rust, and similar languages

The first implementation should be intentionally boring: stable handles, UTF-8 strings, explicit option structs, deterministic layout behavior, and no COM details escaping the library boundary.
