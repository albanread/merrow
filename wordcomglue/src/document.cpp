/*
 * document.cpp — Document lifecycle and content operations for wordcomglue.
 */

#include "internal.h"
#include <cstdio>
#include <cwctype>

/* ---------- Local helpers ---------- */

/*
 * Get the Documents collection from the Word application.
 * Caller must Release the returned IDispatch.
 */
static HRESULT get_documents(IDispatch* word_app, IDispatch** out) {
    VARIANT result;
    VariantInit(&result);
    HRESULT hr = wcg_get_property(word_app, L"Documents", &result);
    if (FAILED(hr)) return hr;
    if (result.vt != VT_DISPATCH || !result.pdispVal) {
        VariantClear(&result);
        return E_FAIL;
    }
    *out = result.pdispVal;
    /* Do not VariantClear — caller owns the dispatch pointer. */
    return S_OK;
}

/*
 * Get the active document's Content range.
 * Caller must Release the returned IDispatch.
 */
static HRESULT get_content_range(IDispatch* doc, IDispatch** out) {
    VARIANT result;
    VariantInit(&result);
    HRESULT hr = wcg_get_property(doc, L"Content", &result);
    if (FAILED(hr)) return hr;
    if (result.vt != VT_DISPATCH || !result.pdispVal) {
        VariantClear(&result);
        return E_FAIL;
    }
    *out = result.pdispVal;
    return S_OK;
}

/*
 * Move a Range to the end of the document content by collapsing
 * the Content range to its end point.
 * Returns an IDispatch* that the caller must Release.
 */
static HRESULT get_end_range(IDispatch* doc, IDispatch** out) {
    /* Get Content range. */
    IDispatch* content = nullptr;
    HRESULT hr = get_content_range(doc, &content);
    if (FAILED(hr)) return hr;

    /* Collapse to end: wdCollapseEnd = 0. */
    VARIANT dir;
    VariantInit(&dir);
    dir.vt = VT_I4;
    dir.lVal = 0; /* wdCollapseEnd */
    hr = wcg_call_method1(content, L"Collapse", &dir, nullptr);
    if (FAILED(hr)) {
        content->Release();
        return hr;
    }

    *out = content;
    return S_OK;
}

static HRESULT get_start_range(IDispatch* doc, IDispatch** out) {
    DISPID id;
    HRESULT hr = wcg_get_dispid(doc, L"Range", &id);
    if (FAILED(hr)) return hr;

    VARIANT args[2];
    VariantInit(&args[0]);
    VariantInit(&args[1]);
    args[1].vt = VT_I4;
    args[1].lVal = 0;
    args[0].vt = VT_I4;
    args[0].lVal = 0;

    DISPPARAMS params = {};
    params.rgvarg = args;
    params.cArgs = 2;

    VARIANT result;
    VariantInit(&result);
    hr = wcg_invoke(doc, id, DISPATCH_METHOD | DISPATCH_PROPERTYGET, &params, &result);
    if (FAILED(hr)) return hr;
    if (result.vt != VT_DISPATCH || !result.pdispVal) {
        VariantClear(&result);
        return E_FAIL;
    }

    *out = result.pdispVal;
    return S_OK;
}

/*
 * Insert text at the end of the document by getting an end-of-document
 * range and calling InsertAfter.  Returns the range covering the inserted
 * text (caller must Release).
 */
static HRESULT insert_text_at_end(IDispatch* doc, const wchar_t* text,
                                  IDispatch** out_range) {
    /* Get the Content.End position before insert so we can locate the new text. */
    VARIANT content_v;
    VariantInit(&content_v);
    HRESULT hr = wcg_get_property(doc, L"Content", &content_v);
    if (FAILED(hr)) return hr;
    if (content_v.vt != VT_DISPATCH || !content_v.pdispVal) {
        VariantClear(&content_v);
        return E_FAIL;
    }
    IDispatch* content = content_v.pdispVal;

    /* Record the End position before the insert. */
    VARIANT end_before;
    VariantInit(&end_before);
    hr = wcg_get_property(content, L"End", &end_before);
    long start_pos = (SUCCEEDED(hr) && end_before.vt == VT_I4) ? end_before.lVal : 0;
    /* For an empty doc, Content.End is 1, but we want to insert at the end. */
    if (start_pos > 0) start_pos -= 1; /* InsertAfter appends after range end */

    /* Call Content.InsertAfter(text) — appends text at the end of content. */
    BstrGuard bstr(text);
    VARIANT arg;
    VariantInit(&arg);
    arg.vt = VT_BSTR;
    arg.bstrVal = bstr.bstr;
    hr = wcg_call_method1(content, L"InsertAfter", &arg, nullptr);
    content->Release();
    if (FAILED(hr)) return hr;

    if (out_range) {
        /* Get the updated Content range — it now includes the inserted text.
           We need a range covering only the new text for styling. */
        VARIANT new_content_v;
        VariantInit(&new_content_v);
        hr = wcg_get_property(doc, L"Content", &new_content_v);
        if (FAILED(hr)) return hr;
        if (new_content_v.vt != VT_DISPATCH || !new_content_v.pdispVal) {
            VariantClear(&new_content_v);
            return E_FAIL;
        }
        IDispatch* new_content = new_content_v.pdispVal;

        VARIANT new_end;
        VariantInit(&new_end);
        hr = wcg_get_property(new_content, L"End", &new_end);
        long end_pos = (SUCCEEDED(hr) && new_end.vt == VT_I4) ? new_end.lVal : 0;
        new_content->Release();

        /* Create a Range(start_pos, end_pos) covering just the new text. */
        DISPID range_id;
        hr = wcg_get_dispid(doc, L"Range", &range_id);
        if (FAILED(hr)) return hr;

        VARIANT rargs[2];
        VariantInit(&rargs[0]);
        VariantInit(&rargs[1]);
        rargs[1].vt = VT_I4;
        rargs[1].lVal = start_pos;
        rargs[0].vt = VT_I4;
        rargs[0].lVal = end_pos;

        DISPPARAMS rparams = {};
        rparams.rgvarg = rargs;
        rparams.cArgs = 2;

        VARIANT range_result;
        VariantInit(&range_result);
        hr = wcg_invoke(doc, range_id, DISPATCH_METHOD | DISPATCH_PROPERTYGET,
                        &rparams, &range_result);
        if (FAILED(hr)) return hr;
        if (range_result.vt != VT_DISPATCH || !range_result.pdispVal) {
            VariantClear(&range_result);
            return E_FAIL;
        }
        *out_range = range_result.pdispVal;
    }

    return S_OK;
}

/*
 * Apply a Word built-in style to a Range.
 * style_id: a wdBuiltinStyle integer constant.
 */
static HRESULT apply_style(IDispatch* range, int style_id) {
    VARIANT v;
    VariantInit(&v);
    v.vt = VT_I4;
    v.lVal = style_id;
    return wcg_put_property(range, L"Style", &v);
}

/*
 * Apply a named style to a Range.
 */
static HRESULT apply_named_style(IDispatch* range, const wchar_t* name) {
    BstrGuard bstr(name);
    VARIANT v;
    VariantInit(&v);
    v.vt = VT_BSTR;
    v.bstrVal = bstr.bstr;
    return wcg_put_property(range, L"Style", &v);
}

static bool path_has_pdf_extension(const std::wstring& path) {
    std::size_t last_dot = path.find_last_of(L'.');
    if (last_dot == std::wstring::npos) return false;

    std::wstring ext = path.substr(last_dot);
    for (wchar_t& ch : ext) {
        ch = static_cast<wchar_t>(std::towlower(ch));
    }
    return ext == L".pdf";
}

static HRESULT invoke_method2(IDispatch* disp, const wchar_t* name,
                              VARIANT* arg1, VARIANT* arg2, VARIANT* result) {
    DISPID id;
    HRESULT hr = wcg_get_dispid(disp, name, &id);
    if (FAILED(hr)) return hr;

    VARIANT args[2];
    args[0] = *arg2;
    args[1] = *arg1;

    DISPPARAMS params = {};
    params.rgvarg = args;
    params.cArgs = 2;
    return wcg_invoke(disp, id, DISPATCH_METHOD, &params, result);
}

static HRESULT invoke_method_args(IDispatch* disp, const wchar_t* name,
                                  VARIANT* args, unsigned int arg_count,
                                  VARIANT* result) {
    DISPID id;
    HRESULT hr = wcg_get_dispid(disp, name, &id);
    if (FAILED(hr)) return hr;

    DISPPARAMS params = {};
    params.rgvarg = args;
    params.cArgs = arg_count;
    return wcg_invoke(disp, id, DISPATCH_METHOD, &params, result);
}

static VARIANT make_bool_variant(bool value) {
    VARIANT v;
    VariantInit(&v);
    v.vt = VT_BOOL;
    v.boolVal = value ? VARIANT_TRUE : VARIANT_FALSE;
    return v;
}

static VARIANT make_i4_variant(long value) {
    VARIANT v;
    VariantInit(&v);
    v.vt = VT_I4;
    v.lVal = value;
    return v;
}

static wcg_pdf_options default_pdf_options() {
    wcg_pdf_options options = {};
    options.open_after_export = 0;
    options.optimize_for = WCG_PDF_OPTIMIZE_ON_SCREEN;
    options.range = WCG_PDF_RANGE_ALL;
    options.item = WCG_PDF_ITEM_DOCUMENT_CONTENT;
    options.include_doc_props = 0;
    options.keep_irm = 0;
    options.create_bookmarks = WCG_PDF_BOOKMARKS_HEADINGS;
    options.doc_structure_tags = 1;
    options.bitmap_missing_fonts = 1;
    options.use_pdfa = 0;
    return options;
}

static long map_pdf_optimize_for(wcg_pdf_optimize_for value) {
    return (value == WCG_PDF_OPTIMIZE_PRINT) ? 0L : 1L;
}

static long map_pdf_range(wcg_pdf_range value) {
    switch (value) {
    case WCG_PDF_RANGE_SELECTION:
        return 1L;
    case WCG_PDF_RANGE_CURRENT_PAGE:
        return 2L;
    case WCG_PDF_RANGE_FROM_TO:
        return 3L;
    case WCG_PDF_RANGE_ALL:
    default:
        return 0L;
    }
}

static long map_pdf_item(wcg_pdf_item value) {
    return (value == WCG_PDF_ITEM_DOCUMENT_WITH_MARKUP) ? 7L : 0L;
}

static long map_pdf_bookmarks(wcg_pdf_bookmarks value) {
    switch (value) {
    case WCG_PDF_BOOKMARKS_NONE:
        return 0L;
    case WCG_PDF_BOOKMARKS_WORD:
        return 2L;
    case WCG_PDF_BOOKMARKS_HEADINGS:
    default:
        return 1L;
    }
}

static HRESULT export_document_as_pdf(IDispatch* doc, const std::wstring& wide_path,
                                      const wcg_pdf_options* maybe_options) {
    constexpr long kWdExportFormatPdf = 17;
    const wcg_pdf_options options = maybe_options ? *maybe_options : default_pdf_options();

    BstrGuard bstr(wide_path);
    VARIANT args[14];
    args[13].vt = VT_BSTR;
    args[13].bstrVal = bstr.bstr;
    args[12] = make_i4_variant(kWdExportFormatPdf);
    args[11] = make_bool_variant(options.open_after_export != 0);
    args[10] = make_i4_variant(map_pdf_optimize_for(options.optimize_for));
    args[9] = make_i4_variant(map_pdf_range(options.range));
    args[8] = make_i4_variant(static_cast<long>(options.from_page));
    args[7] = make_i4_variant(static_cast<long>(options.to_page));
    args[6] = make_i4_variant(map_pdf_item(options.item));
    args[5] = make_bool_variant(options.include_doc_props != 0);
    args[4] = make_bool_variant(options.keep_irm != 0);
    args[3] = make_i4_variant(map_pdf_bookmarks(options.create_bookmarks));
    args[2] = make_bool_variant(options.doc_structure_tags != 0);
    args[1] = make_bool_variant(options.bitmap_missing_fonts != 0);
    args[0] = make_bool_variant(options.use_pdfa != 0);

    HRESULT hr = invoke_method_args(doc, L"ExportAsFixedFormat", args, 14, nullptr);
    if (SUCCEEDED(hr)) return hr;

    VARIANT file_name;
    VariantInit(&file_name);
    file_name.vt = VT_BSTR;
    file_name.bstrVal = bstr.bstr;

    VARIANT export_format;
    VariantInit(&export_format);
    export_format.vt = VT_I4;
    export_format.lVal = kWdExportFormatPdf;

    hr = invoke_method2(doc, L"SaveAs2", &file_name, &export_format, nullptr);
    if (SUCCEEDED(hr)) return hr;

    return invoke_method2(doc, L"SaveAs", &file_name, &export_format, nullptr);
}

static double variant_to_double(const VARIANT& value) {
    switch (value.vt) {
    case VT_R4:
        return static_cast<double>(value.fltVal);
    case VT_R8:
        return value.dblVal;
    case VT_I2:
        return static_cast<double>(value.iVal);
    case VT_I4:
        return static_cast<double>(value.lVal);
    case VT_UI2:
        return static_cast<double>(value.uiVal);
    case VT_UI4:
        return static_cast<double>(value.ulVal);
    default:
        return 0.0;
    }
}

static HRESULT get_section_at(IDispatch* doc, long index, IDispatch** out_section);

static HRESULT get_first_section(IDispatch* doc, IDispatch** out_section) {
    return get_section_at(doc, 1, out_section);
}

static HRESULT get_section_at(IDispatch* doc, long index, IDispatch** out_section) {
    VARIANT sections_v;
    VariantInit(&sections_v);
    HRESULT hr = wcg_get_property(doc, L"Sections", &sections_v);
    if (FAILED(hr)) return hr;
    if (sections_v.vt != VT_DISPATCH || !sections_v.pdispVal) {
        VariantClear(&sections_v);
        return E_FAIL;
    }

    IDispatch* sections = sections_v.pdispVal;
    VARIANT idx;
    VariantInit(&idx);
    idx.vt = VT_I4;
    idx.lVal = index;

    VARIANT section_v;
    VariantInit(&section_v);
    hr = wcg_call_method1(sections, L"Item", &idx, &section_v);
    sections->Release();
    if (FAILED(hr)) return hr;
    if (section_v.vt != VT_DISPATCH || !section_v.pdispVal) {
        VariantClear(&section_v);
        return E_FAIL;
    }

    *out_section = section_v.pdispVal;
    return S_OK;
}

static HRESULT get_last_section(IDispatch* doc, IDispatch** out_section) {
    VARIANT sections_v;
    VariantInit(&sections_v);
    HRESULT hr = wcg_get_property(doc, L"Sections", &sections_v);
    if (FAILED(hr)) return hr;
    if (sections_v.vt != VT_DISPATCH || !sections_v.pdispVal) {
        VariantClear(&sections_v);
        return E_FAIL;
    }

    IDispatch* sections = sections_v.pdispVal;
    VARIANT count_v;
    VariantInit(&count_v);
    hr = wcg_get_property(sections, L"Count", &count_v);
    sections->Release();
    if (FAILED(hr)) return hr;

    long count = (count_v.vt == VT_I4) ? count_v.lVal : 0;
    if (count <= 0) return E_FAIL;
    return get_section_at(doc, count, out_section);
}

static HRESULT get_document_width_points(IDispatch* doc, bool content_width,
                                         double* out_width) {
    if (!doc || !out_width) return E_INVALIDARG;

    IDispatch* section = nullptr;
    HRESULT hr = get_first_section(doc, &section);
    if (FAILED(hr)) return hr;

    VARIANT setup_v;
    VariantInit(&setup_v);
    hr = wcg_get_property(section, L"PageSetup", &setup_v);
    section->Release();
    if (FAILED(hr)) return hr;
    if (setup_v.vt != VT_DISPATCH || !setup_v.pdispVal) {
        VariantClear(&setup_v);
        return E_FAIL;
    }

    IDispatch* setup = setup_v.pdispVal;

    VARIANT page_width_v;
    VariantInit(&page_width_v);
    hr = wcg_get_property(setup, L"PageWidth", &page_width_v);
    if (FAILED(hr)) {
        setup->Release();
        return hr;
    }
    double width = variant_to_double(page_width_v);

    if (content_width) {
        VARIANT left_margin_v;
        VARIANT right_margin_v;
        VariantInit(&left_margin_v);
        VariantInit(&right_margin_v);
        hr = wcg_get_property(setup, L"LeftMargin", &left_margin_v);
        if (SUCCEEDED(hr)) {
            hr = wcg_get_property(setup, L"RightMargin", &right_margin_v);
        }
        if (SUCCEEDED(hr)) {
            width -= variant_to_double(left_margin_v);
            width -= variant_to_double(right_margin_v);
        }
    }

    setup->Release();
    *out_width = (width > 0.0) ? width : 0.0;
    return S_OK;
}

static HRESULT get_document_page_height_points(IDispatch* doc, double* out_height) {
    if (!doc || !out_height) return E_INVALIDARG;

    IDispatch* section = nullptr;
    HRESULT hr = get_first_section(doc, &section);
    if (FAILED(hr)) return hr;

    VARIANT setup_v;
    VariantInit(&setup_v);
    hr = wcg_get_property(section, L"PageSetup", &setup_v);
    section->Release();
    if (FAILED(hr)) return hr;
    if (setup_v.vt != VT_DISPATCH || !setup_v.pdispVal) {
        VariantClear(&setup_v);
        return E_FAIL;
    }

    IDispatch* setup = setup_v.pdispVal;
    VARIANT page_height_v;
    VariantInit(&page_height_v);
    hr = wcg_get_property(setup, L"PageHeight", &page_height_v);
    setup->Release();
    if (FAILED(hr)) return hr;

    *out_height = variant_to_double(page_height_v);
    return S_OK;
}

static HRESULT get_document_bottom_margin_points(IDispatch* doc, double* out_margin) {
    if (!doc || !out_margin) return E_INVALIDARG;

    IDispatch* section = nullptr;
    HRESULT hr = get_first_section(doc, &section);
    if (FAILED(hr)) return hr;

    VARIANT setup_v;
    VariantInit(&setup_v);
    hr = wcg_get_property(section, L"PageSetup", &setup_v);
    section->Release();
    if (FAILED(hr)) return hr;
    if (setup_v.vt != VT_DISPATCH || !setup_v.pdispVal) {
        VariantClear(&setup_v);
        return E_FAIL;
    }

    IDispatch* setup = setup_v.pdispVal;
    VARIANT margin_v;
    VariantInit(&margin_v);
    hr = wcg_get_property(setup, L"BottomMargin", &margin_v);
    setup->Release();
    if (FAILED(hr)) return hr;

    *out_margin = variant_to_double(margin_v);
    return S_OK;
}

static HRESULT get_inline_shape_width_points(IDispatch* shape, double* out_width) {
    if (!shape || !out_width) return E_INVALIDARG;

    VARIANT width_v;
    VariantInit(&width_v);
    HRESULT hr = wcg_get_property(shape, L"Width", &width_v);
    if (FAILED(hr)) return hr;

    *out_width = variant_to_double(width_v);
    return S_OK;
}

static HRESULT set_inline_shape_width_points(IDispatch* shape, double width_points,
                                             bool preserve_aspect_ratio) {
    if (!shape || width_points <= 0.0) return E_INVALIDARG;

    VARIANT lock_v;
    VariantInit(&lock_v);
    lock_v.vt = VT_I4;
    lock_v.lVal = preserve_aspect_ratio ? -1 : 0;
    wcg_put_property(shape, L"LockAspectRatio", &lock_v);

    VARIANT width_v;
    VariantInit(&width_v);
    width_v.vt = VT_R4;
    width_v.fltVal = static_cast<float>(width_points);
    return wcg_put_property(shape, L"Width", &width_v);
}

static HRESULT set_inline_shape_height_points(IDispatch* shape, double height_points,
                                              bool preserve_aspect_ratio) {
    if (!shape || height_points <= 0.0) return E_INVALIDARG;

    VARIANT lock_v;
    VariantInit(&lock_v);
    lock_v.vt = VT_I4;
    lock_v.lVal = preserve_aspect_ratio ? -1 : 0;
    wcg_put_property(shape, L"LockAspectRatio", &lock_v);

    VARIANT height_v;
    VariantInit(&height_v);
    height_v.vt = VT_R4;
    height_v.fltVal = static_cast<float>(height_points);
    return wcg_put_property(shape, L"Height", &height_v);
}

static HRESULT get_inline_shape_height_points(IDispatch* shape, double* out_height) {
    if (!shape || !out_height) return E_INVALIDARG;

    VARIANT height_v;
    VariantInit(&height_v);
    HRESULT hr = wcg_get_property(shape, L"Height", &height_v);
    if (FAILED(hr)) return hr;

    *out_height = variant_to_double(height_v);
    return S_OK;
}

static HRESULT get_range_information_points(IDispatch* range, long info_id,
                                           double* out_value) {
    if (!range || !out_value) return E_INVALIDARG;

    VARIANT arg;
    VariantInit(&arg);
    arg.vt = VT_I4;
    arg.lVal = info_id;

    VARIANT result;
    VariantInit(&result);
    HRESULT hr = wcg_call_method1(range, L"Information", &arg, &result);
    if (FAILED(hr)) return hr;

    *out_value = variant_to_double(result);
    return S_OK;
}

static HRESULT get_inline_shape_range(IDispatch* shape, IDispatch** out_range) {
    if (!shape || !out_range) return E_INVALIDARG;

    VARIANT range_v;
    VariantInit(&range_v);
    HRESULT hr = wcg_get_property(shape, L"Range", &range_v);
    if (FAILED(hr)) return hr;
    if (range_v.vt != VT_DISPATCH || !range_v.pdispVal) {
        VariantClear(&range_v);
        return E_FAIL;
    }

    *out_range = range_v.pdispVal;
    return S_OK;
}

static HRESULT set_range_space_before_points(IDispatch* range, double space_before_points) {
    if (!range) return E_INVALIDARG;

    VARIANT paragraphs_v;
    VariantInit(&paragraphs_v);
    HRESULT hr = wcg_get_property(range, L"ParagraphFormat", &paragraphs_v);
    if (FAILED(hr)) return hr;
    if (paragraphs_v.vt != VT_DISPATCH || !paragraphs_v.pdispVal) {
        VariantClear(&paragraphs_v);
        return E_FAIL;
    }

    IDispatch* paragraph_format = paragraphs_v.pdispVal;
    VARIANT space_v;
    VariantInit(&space_v);
    space_v.vt = VT_R4;
    space_v.fltVal = static_cast<float>(space_before_points > 0.0 ? space_before_points : 0.0);
    hr = wcg_put_property(paragraph_format, L"SpaceBefore", &space_v);
    paragraph_format->Release();
    return hr;
}

static void position_trailer_inline_shape(IDispatch* doc, IDispatch* shape) {
    if (!doc || !shape) return;

    IDispatch* range = nullptr;
    if (FAILED(get_inline_shape_range(shape, &range))) return;

    constexpr long kWdVerticalPositionRelativeToPage = 6;

    double current_top = 0.0;
    double page_height = 0.0;
    double bottom_margin = 0.0;
    double shape_height = 0.0;

    bool have_position = SUCCEEDED(get_range_information_points(
        range, kWdVerticalPositionRelativeToPage, &current_top));
    bool have_page_height = SUCCEEDED(get_document_page_height_points(doc, &page_height));
    bool have_bottom_margin = SUCCEEDED(get_document_bottom_margin_points(doc, &bottom_margin));
    bool have_shape_height = SUCCEEDED(get_inline_shape_height_points(shape, &shape_height));

    if (have_position && have_page_height && have_bottom_margin && have_shape_height) {
        double target_top = page_height - bottom_margin - shape_height;
        if (target_top > 0.0) {
            if (current_top > target_top + 1.0) {
                VARIANT break_arg;
                VariantInit(&break_arg);
                break_arg.vt = VT_I4;
                break_arg.lVal = 7; /* wdPageBreak */
                wcg_call_method1(range, L"InsertBreak", &break_arg, nullptr);

                double updated_top = 0.0;
                if (SUCCEEDED(get_range_information_points(range,
                    kWdVerticalPositionRelativeToPage, &updated_top))) {
                    current_top = updated_top;
                }
            }

            double space_before = target_top - current_top;
            if (space_before > 1.0) {
                set_range_space_before_points(range, space_before);
            }
        }
    }

    range->Release();
}

static double measurement_to_points(IDispatch* doc, const wcg_measurement* value,
                                    bool* out_is_specified) {
    if (out_is_specified) *out_is_specified = false;
    if (!doc || !value || value->value <= 0.0) return 0.0;

    double basis = 0.0;
    switch (value->unit) {
    case WCG_UNIT_POINTS:
        if (out_is_specified) *out_is_specified = true;
        return value->value;
    case WCG_UNIT_INCHES:
        if (out_is_specified) *out_is_specified = true;
        return value->value * 72.0;
    case WCG_UNIT_MM:
        if (out_is_specified) *out_is_specified = true;
        return value->value * 72.0 / 25.4;
    case WCG_UNIT_PCT_PAGE:
        if (SUCCEEDED(get_document_width_points(doc, false, &basis))) {
            if (out_is_specified) *out_is_specified = true;
            return basis * (value->value / 100.0);
        }
        return 0.0;
    case WCG_UNIT_PCT_CONTENT:
        if (SUCCEEDED(get_document_width_points(doc, true, &basis))) {
            if (out_is_specified) *out_is_specified = true;
            return basis * (value->value / 100.0);
        }
        return 0.0;
    default:
        return 0.0;
    }
}

static void fit_inline_shape_to_width(IDispatch* doc, IDispatch* shape,
                                      double target_width_points,
                                      bool preserve_aspect_ratio) {
    if (!doc || !shape || target_width_points <= 0.0) return;
    set_inline_shape_width_points(shape, target_width_points, preserve_aspect_ratio);
}

static void apply_inline_image_options(IDispatch* doc, IDispatch* shape,
                                       const wcg_image_options* options) {
    if (!doc || !shape || !options) return;

    bool width_specified = false;
    bool height_specified = false;
    double target_width = measurement_to_points(doc, &options->width, &width_specified);
    double target_height = measurement_to_points(doc, &options->height, &height_specified);

    if (width_specified && target_width > 0.0 && height_specified && target_height > 0.0) {
        const bool preserve_aspect_ratio = options->preserve_aspect_ratio != 0;
        if (preserve_aspect_ratio) {
            fit_inline_shape_to_width(doc, shape, target_width, true);
        } else {
            set_inline_shape_width_points(shape, target_width, false);
            set_inline_shape_height_points(shape, target_height, false);
        }
        return;
    }

    if (width_specified && target_width > 0.0) {
        fit_inline_shape_to_width(doc, shape, target_width,
                                  options->preserve_aspect_ratio != 0);
        return;
    }

    if (height_specified && target_height > 0.0) {
        set_inline_shape_height_points(shape, target_height,
                                       options->preserve_aspect_ratio != 0);
        return;
    }

    bool max_width_specified = false;
    bool max_height_specified = false;
    double max_width = measurement_to_points(doc, &options->max_width, &max_width_specified);
    double max_height = measurement_to_points(doc, &options->max_height, &max_height_specified);
    if (max_width_specified && max_width > 0.0) {
        double current_width = 0.0;
        if (SUCCEEDED(get_inline_shape_width_points(shape, &current_width)) &&
            current_width > max_width) {
            fit_inline_shape_to_width(doc, shape, max_width,
                                      options->preserve_aspect_ratio != 0);
        }
    }

    if (max_height_specified && max_height > 0.0) {
        double current_height = 0.0;
        if (SUCCEEDED(get_inline_shape_height_points(shape, &current_height)) &&
            current_height > max_height) {
            set_inline_shape_height_points(shape, max_height,
                                           options->preserve_aspect_ratio != 0);
        }
    }
}

/*
 * Set the font name on a Range.
 */
static HRESULT set_range_font_name(IDispatch* range, const wchar_t* family) {
    VARIANT font_v;
    VariantInit(&font_v);
    HRESULT hr = wcg_get_property(range, L"Font", &font_v);
    if (FAILED(hr)) return hr;
    if (font_v.vt != VT_DISPATCH || !font_v.pdispVal) {
        VariantClear(&font_v);
        return E_FAIL;
    }

    IDispatch* font = font_v.pdispVal;
    BstrGuard bstr(family);
    VARIANT v;
    VariantInit(&v);
    v.vt = VT_BSTR;
    v.bstrVal = bstr.bstr;
    hr = wcg_put_property(font, L"Name", &v);
    font->Release();
    return hr;
}

/*
 * Set the font size on a Range.
 */
static HRESULT set_range_font_size(IDispatch* range, double size_points) {
    VARIANT font_v;
    VariantInit(&font_v);
    HRESULT hr = wcg_get_property(range, L"Font", &font_v);
    if (FAILED(hr)) return hr;
    if (font_v.vt != VT_DISPATCH || !font_v.pdispVal) {
        VariantClear(&font_v);
        return E_FAIL;
    }

    IDispatch* font = font_v.pdispVal;
    VARIANT v;
    VariantInit(&v);
    v.vt = VT_R4;
    v.fltVal = static_cast<float>(size_points);
    hr = wcg_put_property(font, L"Size", &v);
    font->Release();
    return hr;
}

/* ---------- Document lifecycle ---------- */

extern "C" {

wcg_status wcg_create_document(wcg_session session,
                               wcg_document* out_document) {
    if (!session || !out_document) return WCG_INVALID_ARGUMENT;
    *out_document = nullptr;

    if (!session->word_app) {
        wcg_record_error(session->library, WCG_NOT_INITIALIZED, 0,
                         "wcg_create_document", "Word session not started");
        return WCG_NOT_INITIALIZED;
    }

    IDispatch* docs = nullptr;
    HRESULT hr = get_documents(session->word_app, &docs);
    if (FAILED(hr)) {
        wcg_record_error(session->library, WCG_INTERNAL_ERROR, hr,
                         "wcg_create_document", "Failed to get Documents collection");
        return WCG_INTERNAL_ERROR;
    }

    VARIANT result;
    VariantInit(&result);
    hr = wcg_call_method0(docs, L"Add", &result);
    docs->Release();
    if (FAILED(hr) || result.vt != VT_DISPATCH || !result.pdispVal) {
        VariantClear(&result);
        wcg_record_error(session->library, WCG_INTERNAL_ERROR, hr,
                         "wcg_create_document", "Documents.Add failed");
        return WCG_INTERNAL_ERROR;
    }

    auto* doc = new (std::nothrow) wcg_document_t();
    if (!doc) {
        result.pdispVal->Release();
        return WCG_OUT_OF_MEMORY;
    }
    doc->session = session;
    doc->doc_dispatch = result.pdispVal;
    *out_document = doc;
    return WCG_OK;
}

wcg_status wcg_open_document(wcg_session session,
                             const char* utf8_path,
                             wcg_document* out_document) {
    if (!session || !utf8_path || !out_document) return WCG_INVALID_ARGUMENT;
    *out_document = nullptr;

    if (!session->word_app) {
        wcg_record_error(session->library, WCG_NOT_INITIALIZED, 0,
                         "wcg_open_document", "Word session not started");
        return WCG_NOT_INITIALIZED;
    }

    /* Check file exists. */
    std::wstring wide_path = wcg_utf8_to_wide(utf8_path);
    DWORD attrs = GetFileAttributesW(wide_path.c_str());
    if (attrs == INVALID_FILE_ATTRIBUTES) {
        wcg_record_error(session->library, WCG_PATH_NOT_FOUND, 0,
                         "wcg_open_document", "File not found");
        return WCG_PATH_NOT_FOUND;
    }

    IDispatch* docs = nullptr;
    HRESULT hr = get_documents(session->word_app, &docs);
    if (FAILED(hr)) {
        wcg_record_error(session->library, WCG_INTERNAL_ERROR, hr,
                         "wcg_open_document", "Failed to get Documents collection");
        return WCG_INTERNAL_ERROR;
    }

    BstrGuard bstr(wide_path);
    VARIANT arg;
    VariantInit(&arg);
    arg.vt = VT_BSTR;
    arg.bstrVal = bstr.bstr;

    VARIANT result;
    VariantInit(&result);
    hr = wcg_call_method1(docs, L"Open", &arg, &result);
    docs->Release();
    if (FAILED(hr) || result.vt != VT_DISPATCH || !result.pdispVal) {
        VariantClear(&result);
        wcg_record_error(session->library, WCG_DOCUMENT_OPEN_FAILED, hr,
                         "wcg_open_document", "Documents.Open failed");
        return WCG_DOCUMENT_OPEN_FAILED;
    }

    auto* doc = new (std::nothrow) wcg_document_t();
    if (!doc) {
        result.pdispVal->Release();
        return WCG_OUT_OF_MEMORY;
    }
    doc->session = session;
    doc->doc_dispatch = result.pdispVal;
    *out_document = doc;
    return WCG_OK;
}

wcg_status wcg_save_document(wcg_document document) {
    if (!document || !document->doc_dispatch) return WCG_INVALID_ARGUMENT;

    HRESULT hr = wcg_call_method0(document->doc_dispatch, L"Save", nullptr);
    if (FAILED(hr)) {
        wcg_record_error(wcg_lib_from_document(document),
                         WCG_DOCUMENT_SAVE_FAILED, hr,
                         "wcg_save_document", "Document.Save failed");
        return WCG_DOCUMENT_SAVE_FAILED;
    }
    return WCG_OK;
}

wcg_status wcg_save_document_as(wcg_document document,
                                const char* utf8_path,
                                const wcg_save_options* /*options*/) {
    if (!document || !document->doc_dispatch || !utf8_path)
        return WCG_INVALID_ARGUMENT;

    std::wstring wide_path = wcg_utf8_to_wide(utf8_path);
    HRESULT hr;
    if (path_has_pdf_extension(wide_path)) {
        hr = export_document_as_pdf(document->doc_dispatch, wide_path, nullptr);
    } else {
        BstrGuard bstr(wide_path);

        VARIANT arg;
        VariantInit(&arg);
        arg.vt = VT_BSTR;
        arg.bstrVal = bstr.bstr;

        hr = wcg_call_method1(document->doc_dispatch, L"SaveAs2", &arg, nullptr);
        if (FAILED(hr)) {
            /* Fall back to SaveAs if SaveAs2 is not available. */
            hr = wcg_call_method1(document->doc_dispatch, L"SaveAs", &arg, nullptr);
        }
    }
    if (FAILED(hr)) {
        wcg_record_error(wcg_lib_from_document(document),
                         WCG_DOCUMENT_SAVE_FAILED, hr,
                         "wcg_save_document_as", "Document.SaveAs failed");
        return WCG_DOCUMENT_SAVE_FAILED;
    }
    return WCG_OK;
}

wcg_status wcg_export_pdf(wcg_document document,
                          const char* utf8_path,
                          const wcg_pdf_options* options) {
    if (!document || !document->doc_dispatch || !utf8_path) {
        return WCG_INVALID_ARGUMENT;
    }

    std::wstring wide_path = wcg_utf8_to_wide(utf8_path);
    HRESULT hr = export_document_as_pdf(document->doc_dispatch, wide_path, options);
    if (FAILED(hr)) {
        wcg_record_error(wcg_lib_from_document(document),
                         WCG_DOCUMENT_SAVE_FAILED, hr,
                         "wcg_export_pdf", "Document.ExportAsFixedFormat failed");
        return WCG_DOCUMENT_SAVE_FAILED;
    }
    return WCG_OK;
}

wcg_status wcg_close_document(wcg_document document,
                              const wcg_close_options* options) {
    if (!document) return WCG_INVALID_ARGUMENT;

    if (document->doc_dispatch) {
        /* Close(SaveChanges) — 0 = wdDoNotSaveChanges, -1 = wdSaveChanges. */
        VARIANT arg;
        VariantInit(&arg);
        arg.vt = VT_I4;
        arg.lVal = (options && options->save_before_close) ? -1 : 0;
        HRESULT hr = wcg_call_method1(document->doc_dispatch, L"Close", &arg, nullptr);
        document->doc_dispatch->Release();
        document->doc_dispatch = nullptr;

        if (FAILED(hr)) {
            wcg_record_error(wcg_lib_from_document(document),
                             WCG_DOCUMENT_CLOSE_FAILED, hr,
                             "wcg_close_document", "Document.Close failed");
            delete document;
            return WCG_DOCUMENT_CLOSE_FAILED;
        }
    }

    delete document;
    return WCG_OK;
}

/* ---------- Font / style ---------- */

wcg_status wcg_set_document_font(wcg_document document,
                                 const wcg_font_spec* font) {
    if (!document || !document->doc_dispatch || !font || !font->utf8_family)
        return WCG_INVALID_ARGUMENT;

    IDispatch* content = nullptr;
    HRESULT hr = get_content_range(document->doc_dispatch, &content);
    if (FAILED(hr)) {
        wcg_record_error(wcg_lib_from_document(document),
                         WCG_INTERNAL_ERROR, hr,
                         "wcg_set_document_font", "Failed to get Content range");
        return WCG_INTERNAL_ERROR;
    }

    std::wstring family = wcg_utf8_to_wide(font->utf8_family);
    set_range_font_name(content, family.c_str());
    if (font->size_points > 0.0) {
        set_range_font_size(content, font->size_points);
    }
    content->Release();

    /* Also update the Normal style so new text inherits the font. */
    VARIANT styles_v;
    VariantInit(&styles_v);
    hr = wcg_get_property(document->doc_dispatch, L"Styles", &styles_v);
    if (SUCCEEDED(hr) && styles_v.vt == VT_DISPATCH && styles_v.pdispVal) {
        IDispatch* styles = styles_v.pdispVal;

        /* Styles(-1) = wdStyleNormal. */
        VARIANT idx;
        VariantInit(&idx);
        idx.vt = VT_I4;
        idx.lVal = -1;

        DISPID item_id;
        hr = wcg_get_dispid(styles, L"Item", &item_id);
        if (SUCCEEDED(hr)) {
            DISPPARAMS params = {};
            params.rgvarg = &idx;
            params.cArgs = 1;
            VARIANT style_v;
            VariantInit(&style_v);
            hr = wcg_invoke(styles, item_id, DISPATCH_METHOD, &params, &style_v);
            if (SUCCEEDED(hr) && style_v.vt == VT_DISPATCH && style_v.pdispVal) {
                IDispatch* normal_style = style_v.pdispVal;
                VARIANT font_obj;
                VariantInit(&font_obj);
                hr = wcg_get_property(normal_style, L"Font", &font_obj);
                if (SUCCEEDED(hr) && font_obj.vt == VT_DISPATCH && font_obj.pdispVal) {
                    BstrGuard fb(family);
                    VARIANT name_v;
                    VariantInit(&name_v);
                    name_v.vt = VT_BSTR;
                    name_v.bstrVal = fb.bstr;
                    wcg_put_property(font_obj.pdispVal, L"Name", &name_v);

                    if (font->size_points > 0.0) {
                        VARIANT sz;
                        VariantInit(&sz);
                        sz.vt = VT_R4;
                        sz.fltVal = static_cast<float>(font->size_points);
                        wcg_put_property(font_obj.pdispVal, L"Size", &sz);
                    }
                    font_obj.pdispVal->Release();
                }
                normal_style->Release();
            }
        }
        styles->Release();
    }

    return WCG_OK;
}

/* ---------- Text insertion ---------- */

wcg_status wcg_insert_heading(wcg_document document,
                              const char* utf8_text,
                              const wcg_heading_options* options) {
    if (!document || !document->doc_dispatch || !utf8_text)
        return WCG_INVALID_ARGUMENT;

    /* Build the text with a trailing newline so it becomes its own paragraph. */
    std::wstring text = wcg_utf8_to_wide(utf8_text);
    text += L"\r";

    IDispatch* range = nullptr;
    HRESULT hr = insert_text_at_end(document->doc_dispatch, text.c_str(), &range);
    if (FAILED(hr)) {
        wcg_record_error(wcg_lib_from_document(document),
                         WCG_INTERNAL_ERROR, hr,
                         "wcg_insert_heading", "InsertAfter failed");
        return WCG_INTERNAL_ERROR;
    }

    /* Map heading level to wdBuiltinStyle constants.
       wdStyleHeading1 = -2, wdStyleHeading2 = -3, etc. */
    uint32_t level = (options && options->level > 0) ? options->level : 1;
    if (level > 9) level = 9;

    if (options && options->utf8_style_override) {
        std::wstring style_name = wcg_utf8_to_wide(options->utf8_style_override);
        apply_named_style(range, style_name.c_str());
    } else {
        int style_id = -1 - static_cast<int>(level); /* -2 for H1, -3 for H2 ... */
        apply_style(range, style_id);
    }

    range->Release();
    return WCG_OK;
}

wcg_status wcg_insert_paragraph(wcg_document document,
                                const char* utf8_text,
                                const wcg_paragraph_options* options) {
    if (!document || !document->doc_dispatch || !utf8_text)
        return WCG_INVALID_ARGUMENT;

    std::wstring text = wcg_utf8_to_wide(utf8_text);
    text += L"\r";

    IDispatch* range = nullptr;
    HRESULT hr = insert_text_at_end(document->doc_dispatch, text.c_str(), &range);
    if (FAILED(hr)) {
        wcg_record_error(wcg_lib_from_document(document),
                         WCG_INTERNAL_ERROR, hr,
                         "wcg_insert_paragraph", "InsertAfter failed");
        return WCG_INTERNAL_ERROR;
    }

    if (options && options->utf8_style_override) {
        std::wstring style_name = wcg_utf8_to_wide(options->utf8_style_override);
        apply_named_style(range, style_name.c_str());
    } else {
        apply_style(range, -1); /* wdStyleNormal */
    }

    range->Release();
    return WCG_OK;
}

wcg_status wcg_insert_text_run(wcg_document document,
                               const char* utf8_text,
                               const wcg_text_run_options* options) {
    if (!document || !document->doc_dispatch || !utf8_text)
        return WCG_INVALID_ARGUMENT;

    std::wstring text = wcg_utf8_to_wide(utf8_text);

    IDispatch* range = nullptr;
    HRESULT hr = insert_text_at_end(document->doc_dispatch, text.c_str(), &range);
    if (FAILED(hr)) {
        wcg_record_error(wcg_lib_from_document(document),
                         WCG_INTERNAL_ERROR, hr,
                         "wcg_insert_text_run", "InsertAfter failed");
        return WCG_INTERNAL_ERROR;
    }

    if (options && options->font && options->font->utf8_family) {
        std::wstring family = wcg_utf8_to_wide(options->font->utf8_family);
        set_range_font_name(range, family.c_str());
        if (options->font->size_points > 0.0)
            set_range_font_size(range, options->font->size_points);
    }

    apply_style(range, -1); /* wdStyleNormal */

    range->Release();
    return WCG_OK;
}

/* ---------- Image / layout ---------- */

/*
 * Common helper: insert an inline picture at a specific range.
 * Returns the InlineShape IDispatch (caller must Release) or nullptr.
 */
static HRESULT insert_inline_picture_at_range(IDispatch* doc, IDispatch* range,
                                              const wchar_t* png_path,
                                              IDispatch** out_shape) {
    /* Get InlineShapes collection. */
    VARIANT shapes_v;
    VariantInit(&shapes_v);
    HRESULT hr = wcg_get_property(doc, L"InlineShapes", &shapes_v);
    if (FAILED(hr) || shapes_v.vt != VT_DISPATCH || !shapes_v.pdispVal) {
        VariantClear(&shapes_v);
        return FAILED(hr) ? hr : E_FAIL;
    }

    IDispatch* shapes = shapes_v.pdispVal;

    /* InlineShapes.AddPicture(FileName, LinkToFile, SaveWithDocument, Range).
       Args are passed in reverse order. */
    BstrGuard bstr(png_path);

    VARIANT args[4];
    VariantInit(&args[0]);
    VariantInit(&args[1]);
    VariantInit(&args[2]);
    VariantInit(&args[3]);

    args[3].vt = VT_BSTR;
    args[3].bstrVal = bstr.bstr;
    args[2].vt = VT_BOOL;
    args[2].boolVal = VARIANT_FALSE;
    args[1].vt = VT_BOOL;
    args[1].boolVal = VARIANT_TRUE;
    args[0].vt = VT_DISPATCH;
    args[0].pdispVal = range;

    DISPID add_id;
    hr = wcg_get_dispid(shapes, L"AddPicture", &add_id);
    if (FAILED(hr)) {
        shapes->Release();
        return hr;
    }

    DISPPARAMS params = {};
    params.rgvarg = args;
    params.cArgs = 4;

    VARIANT result;
    VariantInit(&result);
    hr = wcg_invoke(shapes, add_id, DISPATCH_METHOD, &params, &result);
    shapes->Release();

    if (FAILED(hr)) return hr;
    if (result.vt == VT_DISPATCH && result.pdispVal) {
        if (out_shape) *out_shape = result.pdispVal;
        else result.pdispVal->Release();
    } else {
        VariantClear(&result);
    }
    return S_OK;
}

static HRESULT insert_inline_picture(IDispatch* doc, const wchar_t* png_path,
                                     IDispatch** out_shape) {
    IDispatch* range = nullptr;
    HRESULT hr = get_end_range(doc, &range);
    if (FAILED(hr)) return hr;

    hr = insert_inline_picture_at_range(doc, range, png_path, out_shape);
    range->Release();
    return hr;
}

wcg_status wcg_insert_header_banner(wcg_document document,
                                    const char* utf8_png_path,
                                    const wcg_banner_options* options) {
    if (!document || !document->doc_dispatch || !utf8_png_path)
        return WCG_INVALID_ARGUMENT;

    std::wstring wide_path = wcg_utf8_to_wide(utf8_png_path);
    DWORD attrs = GetFileAttributesW(wide_path.c_str());
    if (attrs == INVALID_FILE_ATTRIBUTES) {
        wcg_record_error(wcg_lib_from_document(document),
                         WCG_PNG_NOT_FOUND, 0,
                         "wcg_insert_header_banner", "PNG file not found");
        return WCG_PNG_NOT_FOUND;
    }

    IDispatch* range = nullptr;
    HRESULT hr = get_start_range(document->doc_dispatch, &range);
    if (FAILED(hr)) {
        wcg_record_error(wcg_lib_from_document(document),
                         WCG_INTERNAL_ERROR, hr,
                         "wcg_insert_header_banner", "Failed to get start range");
        return WCG_INTERNAL_ERROR;
    }

    IDispatch* shape = nullptr;
    hr = insert_inline_picture_at_range(document->doc_dispatch, range,
                                        wide_path.c_str(), &shape);
    if (FAILED(hr)) {
        range->Release();
        wcg_record_error(wcg_lib_from_document(document),
                         WCG_PNG_INSERT_FAILED, hr,
                         "wcg_insert_header_banner", "Banner insert failed");
        return WCG_PNG_INSERT_FAILED;
    }

    double content_width = 0.0;
    if (shape && SUCCEEDED(get_document_width_points(document->doc_dispatch, true, &content_width))) {
        fit_inline_shape_to_width(document->doc_dispatch, shape, content_width,
                                  !options || options->preserve_aspect_ratio != 0);
    }

    if (shape) {
        IDispatch* shape_range = nullptr;
        if (SUCCEEDED(get_inline_shape_range(shape, &shape_range))) {
            wcg_call_method0(shape_range, L"InsertParagraphAfter", nullptr);
            shape_range->Release();
        }
    }

    if (shape) shape->Release();
    range->Release();
    return WCG_OK;
}

wcg_status wcg_insert_footer_trailer(wcg_document document,
                                     const char* utf8_png_path,
                                     const wcg_trailer_options* options) {
    if (!document || !document->doc_dispatch || !utf8_png_path)
        return WCG_INVALID_ARGUMENT;

    std::wstring wide_path = wcg_utf8_to_wide(utf8_png_path);
    DWORD attrs = GetFileAttributesW(wide_path.c_str());
    if (attrs == INVALID_FILE_ATTRIBUTES) {
        wcg_record_error(wcg_lib_from_document(document),
                         WCG_PNG_NOT_FOUND, 0,
                         "wcg_insert_footer_trailer", "PNG file not found");
        return WCG_PNG_NOT_FOUND;
    }

    bool footer_mode = (!options || options->mode == WCG_TRAILER_FOOTER);

    if (footer_mode) {
        insert_text_at_end(document->doc_dispatch, L"\r", nullptr);

        IDispatch* shape = nullptr;
        HRESULT hr = insert_inline_picture(document->doc_dispatch,
                                           wide_path.c_str(), &shape);
        if (FAILED(hr)) {
            wcg_record_error(wcg_lib_from_document(document), WCG_PNG_INSERT_FAILED, hr,
                             "wcg_insert_footer_trailer", "Last-page trailer insert failed");
            return WCG_PNG_INSERT_FAILED;
        }

        if (shape) {
            double content_width = 0.0;
            if (SUCCEEDED(get_document_width_points(document->doc_dispatch, true, &content_width))) {
                fit_inline_shape_to_width(document->doc_dispatch, shape, content_width,
                                          !options || options->preserve_aspect_ratio != 0);
            }
            position_trailer_inline_shape(document->doc_dispatch, shape);
            shape->Release();
        }
    } else {
        /* End-of-body mode: just insert as inline picture at site end. */
        /* Add a paragraph break first so the trailer stands alone. */
        insert_text_at_end(document->doc_dispatch, L"\r", nullptr);

        IDispatch* shape = nullptr;
        HRESULT hr = insert_inline_picture(document->doc_dispatch,
                                           wide_path.c_str(), &shape);
        if (FAILED(hr)) {
            wcg_record_error(wcg_lib_from_document(document), WCG_PNG_INSERT_FAILED, hr,
                             "wcg_insert_footer_trailer", "Inline picture insert failed");
            return WCG_PNG_INSERT_FAILED;
        }
        if (shape) {
            double content_width = 0.0;
            if (SUCCEEDED(get_document_width_points(document->doc_dispatch, true, &content_width))) {
                fit_inline_shape_to_width(document->doc_dispatch, shape, content_width, true);
            }
            shape->Release();
        }
    }

    return WCG_OK;
}

wcg_status wcg_insert_image(wcg_document document,
                            const char* utf8_png_path,
                            const wcg_image_options* options) {
    if (!document || !document->doc_dispatch || !utf8_png_path)
        return WCG_INVALID_ARGUMENT;

    std::wstring wide_path = wcg_utf8_to_wide(utf8_png_path);
    DWORD attrs = GetFileAttributesW(wide_path.c_str());
    if (attrs == INVALID_FILE_ATTRIBUTES) {
        wcg_record_error(wcg_lib_from_document(document), WCG_PNG_NOT_FOUND, 0,
                         "wcg_insert_image", "PNG file not found");
        return WCG_PNG_NOT_FOUND;
    }

    /* Add a paragraph break so the image has its own line. */
    insert_text_at_end(document->doc_dispatch, L"\r", nullptr);

    IDispatch* shape = nullptr;
    HRESULT hr = insert_inline_picture(document->doc_dispatch,
                                       wide_path.c_str(), &shape);
    if (FAILED(hr)) {
        wcg_record_error(wcg_lib_from_document(document), WCG_PNG_INSERT_FAILED, hr,
                         "wcg_insert_image", "Inline picture insert failed");
        return WCG_PNG_INSERT_FAILED;
    }

    if (shape) {
        apply_inline_image_options(document->doc_dispatch, shape, options);
        shape->Release();
    }
    return WCG_OK;
}

wcg_status wcg_insert_caption(wcg_document document,
                              const char* utf8_text,
                              const wcg_caption_options* /*options*/) {
    if (!document || !document->doc_dispatch || !utf8_text)
        return WCG_INVALID_ARGUMENT;

    std::wstring text = wcg_utf8_to_wide(utf8_text);
    text += L"\r";

    IDispatch* range = nullptr;
    HRESULT hr = insert_text_at_end(document->doc_dispatch, text.c_str(), &range);
    if (FAILED(hr)) {
        wcg_record_error(wcg_lib_from_document(document), WCG_INTERNAL_ERROR, hr,
                         "wcg_insert_caption", "InsertAfter failed");
        return WCG_INTERNAL_ERROR;
    }

    /* Apply Caption style (-35 = wdStyleCaption). */
    apply_style(range, -35);
    range->Release();
    return WCG_OK;
}

/* ---------- Breaks ---------- */

wcg_status wcg_insert_page_break(wcg_document document) {
    if (!document || !document->doc_dispatch) return WCG_INVALID_ARGUMENT;

    /* Insert a paragraph then set the paragraph format to page-break-before. */
    IDispatch* range = nullptr;
    HRESULT hr = insert_text_at_end(document->doc_dispatch, L"\r", &range);
    if (FAILED(hr)) {
        wcg_record_error(wcg_lib_from_document(document), WCG_INTERNAL_ERROR, hr,
                         "wcg_insert_page_break", "InsertAfter failed");
        return WCG_INTERNAL_ERROR;
    }

    /* Range.InsertBreak(wdPageBreak=7). */
    VARIANT arg;
    VariantInit(&arg);
    arg.vt = VT_I4;
    arg.lVal = 7;
    wcg_call_method1(range, L"InsertBreak", &arg, nullptr);

    range->Release();
    return WCG_OK;
}

wcg_status wcg_insert_section_break(wcg_document document,
                                    const wcg_section_break_options* /*options*/) {
    if (!document || !document->doc_dispatch) return WCG_INVALID_ARGUMENT;

    IDispatch* range = nullptr;
    HRESULT hr = insert_text_at_end(document->doc_dispatch, L"\r", &range);
    if (FAILED(hr)) {
        wcg_record_error(wcg_lib_from_document(document), WCG_INTERNAL_ERROR, hr,
                         "wcg_insert_section_break", "InsertAfter failed");
        return WCG_INTERNAL_ERROR;
    }

    /* InsertBreak(wdSectionBreakNextPage=2). */
    VARIANT arg;
    VariantInit(&arg);
    arg.vt = VT_I4;
    arg.lVal = 2;
    wcg_call_method1(range, L"InsertBreak", &arg, nullptr);

    range->Release();
    return WCG_OK;
}

} /* extern "C" */
