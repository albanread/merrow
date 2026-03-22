/*
 * smoke_test.cpp — Minimal smoke test for wordcomglue C ABI.
 *
 * This test verifies that the library can be created and destroyed,
 * Word can be started and shut down, and a document can be created,
 * populated with basic content, and saved.
 *
 * Usage:  wcg_smoke_test [output.docx]
 *
 * If no output path is given, the document is created but not saved.
 */

#include "../wordcomglue.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

static wcg_library g_lib = nullptr;

static const char* kHeaderPng = "C:\\projects\\zig\\merrow\\app\\assets\\devtest\\fake_header.png";
static const char* kDiagramPng = "C:\\projects\\zig\\merrow\\app\\assets\\devtest\\fake_diagram.png";
static const char* kTrailerPng = "C:\\projects\\zig\\merrow\\app\\assets\\devtest\\fake_trailer.png";
static const char* kDefaultOutput = "C:\\projects\\zig\\merrow\\visual-checks\\wordcomglue-devtest-smoke.docx";

static std::string derive_pdf_path(const char* output_path) {
    std::string pdf_path = output_path ? output_path : kDefaultOutput;
    std::size_t last_dot = pdf_path.find_last_of('.');
    std::size_t last_sep = pdf_path.find_last_of("\\/");
    if (last_dot != std::string::npos &&
        (last_sep == std::string::npos || last_dot > last_sep)) {
        pdf_path.replace(last_dot, std::string::npos, ".pdf");
    } else {
        pdf_path += ".pdf";
    }
    return pdf_path;
}

#define CHECK(call, msg) do { \
    wcg_status s = (call); \
    if (s != WCG_OK) { \
        std::printf("FAIL: %s (status=%u)\n", (msg), s); \
        if (g_lib) { \
            wcg_error_info ei = {}; \
            if (wcg_get_last_error(g_lib, &ei) == WCG_OK && ei.utf8_message) { \
                std::printf("  error: %s\n", ei.utf8_message); \
                std::printf("  hresult: 0x%08X\n", (unsigned)ei.hresult); \
                std::printf("  in: %s\n", ei.utf8_function ? ei.utf8_function : "?"); \
            } \
        } \
        return 1; \
    } \
    std::printf("  ok: %s\n", (msg)); \
} while (0)

int main(int argc, char* argv[]) {
    const char* output_path = (argc > 1) ? argv[1] : kDefaultOutput;
    const std::string pdf_path = derive_pdf_path(output_path);

    std::printf("wordcomglue smoke test (ABI version %u)\n",
                wcg_get_abi_version());

    wcg_library library = nullptr;
    wcg_session session = nullptr;
    wcg_document document = nullptr;

    wcg_runtime_options rt = {};
    rt.abi_version = WCG_ABI_VERSION;

    CHECK(wcg_create_library(&rt, &library), "create library");
    g_lib = library;

    wcg_word_options wo = {};
    wo.visibility = WCG_HIDDEN;

    CHECK(wcg_start_word(library, &wo, &session), "start Word (hidden)");
    CHECK(wcg_create_document(session, &document), "create document");

    wcg_font_spec lato = {};
    lato.utf8_family = "Lato";
    lato.size_points = 11.0;
    CHECK(wcg_set_document_font(document, &lato), "set font to Lato 11pt");

        wcg_banner_options banner = {};
        banner.scope = WCG_BANNER_ALL_PAGES;
        banner.preserve_aspect_ratio = 1;
        CHECK(wcg_insert_header_banner(document, kHeaderPng, &banner),
            "insert full-width fake header");

        wcg_heading_options title = {};
        title.level = 1;
        CHECK(wcg_insert_heading(document, "Project Mercury Pretend Integration Report", &title),
            "insert title");

        wcg_paragraph_options subtitle = {};
        CHECK(wcg_insert_paragraph(document,
            "Subtitle: Fabricated findings for a fake COM automation smoke document.",
            &subtitle),
            "insert subtitle");

        CHECK(wcg_insert_paragraph(document,
            "Nonsense summary: flanged zebras negotiated a middleware treaty while the cache politely leaked confidence into the corridor.",
            nullptr),
            "insert nonsense summary");
        CHECK(wcg_insert_paragraph(document,
            "- Bullet alpha: seven cardboard metrics escaped the baseline and requested a ceremonial rollback.",
            nullptr),
            "insert fake bullet 1");
        CHECK(wcg_insert_paragraph(document,
            "- Bullet beta: the ceramic load balancer whispered false comfort to a queue of imaginary penguins.",
            nullptr),
            "insert fake bullet 2");
        CHECK(wcg_insert_paragraph(document,
            "- Bullet gamma: all downstream marshmallows now comply with the provisional telemetry accordion.",
            nullptr),
            "insert fake bullet 3");

        wcg_image_options diagram = {};
        diagram.width.unit = WCG_UNIT_PCT_CONTENT;
        diagram.width.value = 100.0;
        diagram.preserve_aspect_ratio = 1;
        CHECK(wcg_insert_image(document, kDiagramPng, &diagram),
            "insert fake diagram");

        CHECK(wcg_insert_caption(document,
            "Figure 1. Fake system diagram for deliberate nonsense validation.", nullptr),
            "insert fake diagram caption");

        wcg_heading_options section = {};
        section.level = 2;
        CHECK(wcg_insert_heading(document, "Synthetic Findings", &section),
            "insert findings heading");

        CHECK(wcg_insert_paragraph(document,
            "The left-handed scheduler promoted twelve decorative sockets to advisory status and then misplaced the memo behind a fictional radiator.",
            nullptr),
            "insert nonsense paragraph 1");
        CHECK(wcg_insert_paragraph(document,
            "Additional fake observations include a reversible backlog, an overeducated toaster service, and two ceremonial APIs that return only shrugging noises.",
            nullptr),
            "insert nonsense paragraph 2");
        CHECK(wcg_insert_paragraph(document,
            "- Follow-up bullet: validate the invisible turnip bus before shipping the ornamental compliance envelope.",
            nullptr),
            "insert fake bullet 4");
        CHECK(wcg_insert_paragraph(document,
            "- Follow-up bullet: keep the nonsense index below boiling and above interpretive dance thresholds.",
            nullptr),
            "insert fake bullet 5");

        wcg_trailer_options trailer = {};
            trailer.mode = WCG_TRAILER_FOOTER;
        trailer.preserve_aspect_ratio = 1;
        CHECK(wcg_insert_footer_trailer(document, kTrailerPng, &trailer),
                "insert last-page fake trailer");

        CHECK(wcg_save_document_as(document, output_path, nullptr),
            "save document as");
        std::printf("  saved to: %s\n", output_path);

        wcg_pdf_options pdf = {};
        pdf.optimize_for = WCG_PDF_OPTIMIZE_ON_SCREEN;
        pdf.item = WCG_PDF_ITEM_DOCUMENT_CONTENT;
        pdf.create_bookmarks = WCG_PDF_BOOKMARKS_HEADINGS;
        pdf.doc_structure_tags = 1;
        pdf.bitmap_missing_fonts = 1;
        CHECK(wcg_export_pdf(document, pdf_path.c_str(), &pdf),
            "export pdf for viewing");
        std::printf("  saved pdf to: %s\n", pdf_path.c_str());

    wcg_close_options co = {};
    co.save_before_close = 0;
    CHECK(wcg_close_document(document, &co), "close document");

    CHECK(wcg_shutdown_word(session), "shutdown Word");
    CHECK(wcg_destroy_library(library), "destroy library");

    std::printf("PASS\n");
    return 0;
}
