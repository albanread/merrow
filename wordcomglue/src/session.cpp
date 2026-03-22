/*
 * session.cpp — Word application session management for wordcomglue.
 */

#include "internal.h"

extern "C" {

wcg_status wcg_start_word(wcg_library library,
                          const wcg_word_options* options,
                          wcg_session* out_session) {
    if (!library || !out_session) return WCG_INVALID_ARGUMENT;
    *out_session = nullptr;

    /* Create Word.Application via COM. */
    CLSID clsid;
    HRESULT hr = CLSIDFromProgID(L"Word.Application", &clsid);
    if (FAILED(hr)) {
        wcg_record_error(library, WCG_WORD_NOT_INSTALLED, hr,
                         "wcg_start_word", "Word.Application ProgID not found");
        return WCG_WORD_NOT_INSTALLED;
    }

    IDispatch* word_app = nullptr;
    hr = CoCreateInstance(clsid, nullptr, CLSCTX_LOCAL_SERVER,
                          IID_IDispatch, reinterpret_cast<void**>(&word_app));
    if (FAILED(hr) || !word_app) {
        wcg_record_error(library, WCG_WORD_START_FAILED, hr,
                         "wcg_start_word", "CoCreateInstance for Word failed");
        return WCG_WORD_START_FAILED;
    }

    /* Set Visible property. */
    bool visible = (!options || options->visibility == WCG_VISIBLE);
    {
        VARIANT v;
        VariantInit(&v);
        v.vt = VT_BOOL;
        v.boolVal = visible ? VARIANT_TRUE : VARIANT_FALSE;
        wcg_put_property(word_app, L"Visible", &v);
    }

    /* Suppress alerts for automation usage. */
    {
        VARIANT v;
        VariantInit(&v);
        v.vt = VT_I4;
        v.lVal = 0; /* wdAlertsNone */
        wcg_put_property(word_app, L"DisplayAlerts", &v);
    }

    auto* session = new (std::nothrow) wcg_session_t();
    if (!session) {
        word_app->Release();
        return WCG_OUT_OF_MEMORY;
    }

    session->library = library;
    session->word_app = word_app;
    session->owns_process = true;

    *out_session = session;
    return WCG_OK;
}

wcg_status wcg_shutdown_word(wcg_session session) {
    if (!session) return WCG_INVALID_ARGUMENT;

    if (session->word_app) {
        if (session->owns_process) {
            /* Call Application.Quit(SaveChanges:=wdDoNotSaveChanges). */
            VARIANT arg;
            VariantInit(&arg);
            arg.vt = VT_I4;
            arg.lVal = 0; /* wdDoNotSaveChanges */
            wcg_call_method1(session->word_app, L"Quit", &arg, nullptr);
        }
        session->word_app->Release();
        session->word_app = nullptr;
    }

    delete session;
    return WCG_OK;
}

} /* extern "C" */
