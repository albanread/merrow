/*
 * wordcomglue.h — Public C ABI header for Word COM automation.
 *
 * This header defines the complete public interface for wordcomglue.
 * All functions use the C calling convention and can be called from
 * C, C++, Zig, Rust, or any language that supports a plain C FFI.
 *
 * String encoding: all strings are UTF-8 null-terminated.
 * Memory ownership: input strings are caller-owned; handles and error
 * message buffers are library-owned and freed through explicit calls.
 * Threading: a session and its documents must be used from a single thread.
 */

#ifndef WORDCOMGLUE_H
#define WORDCOMGLUE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ---------- ABI version ---------- */

#define WCG_ABI_VERSION 1

uint32_t wcg_get_abi_version(void);

/* ---------- Status codes ---------- */

typedef uint32_t wcg_status;

enum {
    WCG_OK                      = 0,
    WCG_INVALID_ARGUMENT        = 1,
    WCG_OUT_OF_MEMORY           = 2,
    WCG_COM_INIT_FAILED         = 3,
    WCG_WORD_NOT_INSTALLED      = 4,
    WCG_WORD_START_FAILED       = 5,
    WCG_DOCUMENT_OPEN_FAILED    = 6,
    WCG_DOCUMENT_SAVE_FAILED    = 7,
    WCG_DOCUMENT_CLOSE_FAILED   = 8,
    WCG_PATH_NOT_FOUND          = 9,
    WCG_PNG_NOT_FOUND           = 10,
    WCG_PNG_INSERT_FAILED       = 11,
    WCG_FONT_NOT_AVAILABLE      = 12,
    WCG_LAYOUT_UNSUPPORTED      = 13,
    WCG_NOT_INITIALIZED         = 14,
    WCG_INTERNAL_ERROR          = 255
};

/* ---------- Opaque handles ---------- */

typedef struct wcg_library_t*  wcg_library;
typedef struct wcg_session_t*  wcg_session;
typedef struct wcg_document_t* wcg_document;

/* ---------- Enums ---------- */

typedef uint32_t wcg_visibility;
enum {
    WCG_VISIBLE = 0,
    WCG_HIDDEN  = 1
};

typedef uint32_t wcg_alignment;
enum {
    WCG_ALIGN_LEFT   = 0,
    WCG_ALIGN_CENTER = 1,
    WCG_ALIGN_RIGHT  = 2
};

typedef uint32_t wcg_image_placement;
enum {
    WCG_PLACE_INLINE = 0,
    WCG_PLACE_BLOCK  = 1,
    WCG_PLACE_LEFT   = 2,
    WCG_PLACE_RIGHT  = 3
};

typedef uint32_t wcg_wrap_mode;
enum {
    WCG_WRAP_NONE           = 0,
    WCG_WRAP_SQUARE         = 1,
    WCG_WRAP_TOP_AND_BOTTOM = 2,
    WCG_WRAP_TIGHT          = 3
};

typedef uint32_t wcg_unit;
enum {
    WCG_UNIT_POINTS  = 0,
    WCG_UNIT_INCHES  = 1,
    WCG_UNIT_MM      = 2,
    WCG_UNIT_PCT_PAGE    = 3,
    WCG_UNIT_PCT_CONTENT = 4
};

typedef uint32_t wcg_banner_scope;
enum {
    WCG_BANNER_ALL_PAGES   = 0,
    WCG_BANNER_FIRST_ONLY  = 1
};

typedef uint32_t wcg_trailer_mode;
enum {
    WCG_TRAILER_FOOTER       = 0,
    WCG_TRAILER_END_OF_BODY  = 1
};

typedef uint32_t wcg_break_kind;
enum {
    WCG_BREAK_PAGE    = 0,
    WCG_BREAK_SECTION = 1
};

/* ---------- Measurement ---------- */

typedef struct wcg_measurement {
    wcg_unit unit;
    double   value;
} wcg_measurement;

/* ---------- Option structs ---------- */

typedef struct wcg_runtime_options {
    uint32_t abi_version;
    uint32_t flags;
} wcg_runtime_options;

typedef struct wcg_word_options {
    wcg_visibility visibility;
    uint32_t       flags;
} wcg_word_options;

typedef struct wcg_font_spec {
    const char* utf8_family;
    double      size_points;
    uint32_t    flags;          /* bit 0 = bold, bit 1 = italic */
} wcg_font_spec;

typedef struct wcg_heading_options {
    uint32_t        level;      /* 1, 2, 3, ... */
    wcg_alignment   alignment;
    wcg_measurement spacing_before;
    wcg_measurement spacing_after;
    uint32_t        page_break_before;
    const char*     utf8_style_override;
} wcg_heading_options;

typedef struct wcg_paragraph_options {
    wcg_alignment   alignment;
    wcg_measurement spacing_before;
    wcg_measurement spacing_after;
    double          line_spacing;
    const char*     utf8_style_override;
} wcg_paragraph_options;

typedef struct wcg_text_run_options {
    const wcg_font_spec* font;
    uint32_t             color_rgb;
    uint32_t             flags;     /* reserved */
} wcg_text_run_options;

typedef struct wcg_banner_options {
    wcg_banner_scope scope;
    uint32_t         preserve_aspect_ratio;
    wcg_measurement  spacing_after;
} wcg_banner_options;

typedef struct wcg_trailer_options {
    wcg_trailer_mode mode;
    uint32_t         preserve_aspect_ratio;
    uint32_t         repeat_every_page;
    wcg_measurement  spacing_before;
} wcg_trailer_options;

typedef struct wcg_image_options {
    wcg_image_placement placement;
    wcg_alignment       alignment;
    wcg_wrap_mode       wrap;
    wcg_measurement     width;
    wcg_measurement     height;
    wcg_measurement     max_width;
    wcg_measurement     max_height;
    wcg_measurement     spacing_before;
    wcg_measurement     spacing_after;
    uint32_t            preserve_aspect_ratio;
    const char*         utf8_caption;
    const char*         utf8_alt_text;
} wcg_image_options;

typedef struct wcg_caption_options {
    wcg_alignment   alignment;
    wcg_measurement spacing_before;
    wcg_measurement spacing_after;
    const char*     utf8_style_override;
} wcg_caption_options;

typedef struct wcg_section_break_options {
    uint32_t flags;  /* reserved for landscape, column config, etc. */
} wcg_section_break_options;

typedef struct wcg_save_options {
    uint32_t flags;  /* reserved */
} wcg_save_options;

typedef uint32_t wcg_pdf_optimize_for;
enum {
    WCG_PDF_OPTIMIZE_PRINT    = 0,
    WCG_PDF_OPTIMIZE_ON_SCREEN = 1
};

typedef uint32_t wcg_pdf_range;
enum {
    WCG_PDF_RANGE_ALL          = 0,
    WCG_PDF_RANGE_SELECTION    = 1,
    WCG_PDF_RANGE_CURRENT_PAGE = 2,
    WCG_PDF_RANGE_FROM_TO      = 3
};

typedef uint32_t wcg_pdf_item;
enum {
    WCG_PDF_ITEM_DOCUMENT_CONTENT     = 0,
    WCG_PDF_ITEM_DOCUMENT_WITH_MARKUP = 1
};

typedef uint32_t wcg_pdf_bookmarks;
enum {
    WCG_PDF_BOOKMARKS_NONE     = 0,
    WCG_PDF_BOOKMARKS_HEADINGS = 1,
    WCG_PDF_BOOKMARKS_WORD     = 2
};

typedef struct wcg_pdf_options {
    uint32_t              open_after_export;
    wcg_pdf_optimize_for  optimize_for;
    wcg_pdf_range         range;
    uint32_t              from_page;
    uint32_t              to_page;
    wcg_pdf_item          item;
    uint32_t              include_doc_props;
    uint32_t              keep_irm;
    wcg_pdf_bookmarks     create_bookmarks;
    uint32_t              doc_structure_tags;
    uint32_t              bitmap_missing_fonts;
    uint32_t              use_pdfa;
} wcg_pdf_options;

typedef struct wcg_close_options {
    uint32_t save_before_close;  /* 0 = no, 1 = yes */
} wcg_close_options;

/* ---------- Error info ---------- */

typedef struct wcg_error_info {
    wcg_status  status;
    int32_t     hresult;
    uint32_t    system_error;
    const char* utf8_message;
    const char* utf8_function;
} wcg_error_info;

/* ---------- Library lifecycle ---------- */

wcg_status wcg_create_library(
    const wcg_runtime_options* options,
    wcg_library*               out_library);

wcg_status wcg_destroy_library(
    wcg_library library);

/* ---------- Word session ---------- */

wcg_status wcg_start_word(
    wcg_library             library,
    const wcg_word_options* options,
    wcg_session*            out_session);

wcg_status wcg_shutdown_word(
    wcg_session session);

/* ---------- Document lifecycle ---------- */

wcg_status wcg_create_document(
    wcg_session   session,
    wcg_document* out_document);

wcg_status wcg_open_document(
    wcg_session   session,
    const char*   utf8_path,
    wcg_document* out_document);

wcg_status wcg_save_document(
    wcg_document document);

wcg_status wcg_save_document_as(
    wcg_document            document,
    const char*             utf8_path,
    const wcg_save_options* options);

wcg_status wcg_export_pdf(
    wcg_document                 document,
    const char*                  utf8_path,
    const wcg_pdf_options*       options);

wcg_status wcg_close_document(
    wcg_document             document,
    const wcg_close_options* options);

/* ---------- Font / style ---------- */

wcg_status wcg_set_document_font(
    wcg_document         document,
    const wcg_font_spec* font);

/* ---------- Text insertion ---------- */

wcg_status wcg_insert_heading(
    wcg_document               document,
    const char*                utf8_text,
    const wcg_heading_options* options);

wcg_status wcg_insert_paragraph(
    wcg_document                 document,
    const char*                  utf8_text,
    const wcg_paragraph_options* options);

wcg_status wcg_insert_text_run(
    wcg_document                document,
    const char*                 utf8_text,
    const wcg_text_run_options* options);

/* ---------- Image / layout ---------- */

wcg_status wcg_insert_header_banner(
    wcg_document              document,
    const char*               utf8_png_path,
    const wcg_banner_options* options);

wcg_status wcg_insert_footer_trailer(
    wcg_document               document,
    const char*                utf8_png_path,
    const wcg_trailer_options* options);

wcg_status wcg_insert_image(
    wcg_document             document,
    const char*              utf8_png_path,
    const wcg_image_options* options);

wcg_status wcg_insert_caption(
    wcg_document               document,
    const char*                utf8_text,
    const wcg_caption_options* options);

/* ---------- Breaks ---------- */

wcg_status wcg_insert_page_break(
    wcg_document document);

wcg_status wcg_insert_section_break(
    wcg_document                      document,
    const wcg_section_break_options*  options);

/* ---------- Diagnostics ---------- */

wcg_status wcg_get_last_error(
    wcg_library     library,
    wcg_error_info* out_error);

wcg_status wcg_clear_last_error(
    wcg_library library);

#ifdef __cplusplus
}
#endif

#endif /* WORDCOMGLUE_H */
