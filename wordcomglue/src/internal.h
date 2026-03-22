/*
 * internal.h — Private C++ header for wordcomglue implementation.
 * Not part of the public API. Do not include from external code.
 */

#ifndef WCG_INTERNAL_H
#define WCG_INTERNAL_H

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#include <windows.h>
#include <objbase.h>
#include <oleauto.h>

#include <cstdint>
#include <cstring>
#include <string>

#include "../wordcomglue.h"

/* ---------- UTF-8 / UTF-16 helpers ---------- */

/* Convert a UTF-8 string to a Windows wide string. */
inline std::wstring wcg_utf8_to_wide(const char* utf8) {
    if (!utf8 || !utf8[0]) return {};
    int len = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, nullptr, 0);
    if (len <= 0) return {};
    std::wstring out(static_cast<size_t>(len), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, utf8, -1, &out[0], len);
    /* Remove trailing null that WideCharToMultiByte includes in the count. */
    if (!out.empty() && out.back() == L'\0') out.pop_back();
    return out;
}

/* Convert a wide string to UTF-8. */
inline std::string wcg_wide_to_utf8(const wchar_t* wide) {
    if (!wide || !wide[0]) return {};
    int len = WideCharToMultiByte(CP_UTF8, 0, wide, -1, nullptr, 0, nullptr, nullptr);
    if (len <= 0) return {};
    std::string out(static_cast<size_t>(len), '\0');
    WideCharToMultiByte(CP_UTF8, 0, wide, -1, &out[0], len, nullptr, nullptr);
    if (!out.empty() && out.back() == '\0') out.pop_back();
    return out;
}

/* ---------- BSTR helper ---------- */

struct BstrGuard {
    BSTR bstr;
    explicit BstrGuard(const wchar_t* s) : bstr(SysAllocString(s)) {}
    explicit BstrGuard(const std::wstring& s) : bstr(SysAllocString(s.c_str())) {}
    ~BstrGuard() { if (bstr) SysFreeString(bstr); }
    BstrGuard(const BstrGuard&) = delete;
    BstrGuard& operator=(const BstrGuard&) = delete;
};

/* ---------- IDispatch helpers ---------- */

/*
 * Get the DISPID for a named member on an IDispatch interface.
 * Returns S_OK on success.
 */
inline HRESULT wcg_get_dispid(IDispatch* disp, const wchar_t* name, DISPID* out) {
    LPOLESTR names[] = { const_cast<LPOLESTR>(name) };
    return disp->GetIDsOfNames(IID_NULL, names, 1, LOCALE_USER_DEFAULT, out);
}

/*
 * Invoke a method or property on an IDispatch interface.
 * Caller must configure the DISPPARAMS before calling.
 */
inline HRESULT wcg_invoke(IDispatch* disp, DISPID id, WORD flags,
                          DISPPARAMS* params, VARIANT* result) {
    EXCEPINFO excep = {};
    UINT arg_err = 0;
    return disp->Invoke(id, IID_NULL, LOCALE_USER_DEFAULT, flags,
                        params, result, &excep, &arg_err);
}

/* Helper: invoke a property-get with no arguments. */
inline HRESULT wcg_get_property(IDispatch* disp, const wchar_t* name, VARIANT* result) {
    DISPID id;
    HRESULT hr = wcg_get_dispid(disp, name, &id);
    if (FAILED(hr)) return hr;
    DISPPARAMS params = {};
    return wcg_invoke(disp, id, DISPATCH_PROPERTYGET, &params, result);
}

/* Helper: invoke a property-put with one VARIANT argument. */
inline HRESULT wcg_put_property(IDispatch* disp, const wchar_t* name, VARIANT* arg) {
    DISPID id;
    HRESULT hr = wcg_get_dispid(disp, name, &id);
    if (FAILED(hr)) return hr;
    DISPID put_id = DISPID_PROPERTYPUT;
    DISPPARAMS params = {};
    params.rgvarg = arg;
    params.cArgs = 1;
    params.rgdispidNamedArgs = &put_id;
    params.cNamedArgs = 1;
    return wcg_invoke(disp, id, DISPATCH_PROPERTYPUT, &params, nullptr);
}

/* Helper: invoke a method with 0 arguments, returning a VARIANT. */
inline HRESULT wcg_call_method0(IDispatch* disp, const wchar_t* name, VARIANT* result) {
    DISPID id;
    HRESULT hr = wcg_get_dispid(disp, name, &id);
    if (FAILED(hr)) return hr;
    DISPPARAMS params = {};
    return wcg_invoke(disp, id, DISPATCH_METHOD, &params, result);
}

/* Helper: invoke a method with 1 argument. */
inline HRESULT wcg_call_method1(IDispatch* disp, const wchar_t* name,
                                VARIANT* arg, VARIANT* result) {
    DISPID id;
    HRESULT hr = wcg_get_dispid(disp, name, &id);
    if (FAILED(hr)) return hr;
    DISPPARAMS params = {};
    params.rgvarg = arg;
    params.cArgs = 1;
    return wcg_invoke(disp, id, DISPATCH_METHOD, &params, result);
}

/* ---------- Opaque handle structs ---------- */

struct wcg_library_t {
    bool        com_initialized;
    std::string last_error_message;
    std::string last_error_function;
    wcg_status  last_status;
    HRESULT     last_hresult;

    wcg_library_t()
        : com_initialized(false)
        , last_status(WCG_OK)
        , last_hresult(S_OK) {}
};

struct wcg_session_t {
    wcg_library_t* library;
    IDispatch*     word_app;
    bool           owns_process;

    wcg_session_t()
        : library(nullptr)
        , word_app(nullptr)
        , owns_process(false) {}
};

struct wcg_document_t {
    wcg_session_t* session;
    IDispatch*     doc_dispatch;

    wcg_document_t()
        : session(nullptr)
        , doc_dispatch(nullptr) {}
};

/* ---------- Internal error recording ---------- */

inline void wcg_record_error(wcg_library_t* lib, wcg_status status,
                             HRESULT hr, const char* func, const char* msg) {
    if (!lib) return;
    lib->last_status = status;
    lib->last_hresult = hr;
    lib->last_error_function = func ? func : "";
    lib->last_error_message = msg ? msg : "";
}

inline void wcg_clear_error(wcg_library_t* lib) {
    if (!lib) return;
    lib->last_status = WCG_OK;
    lib->last_hresult = S_OK;
    lib->last_error_function.clear();
    lib->last_error_message.clear();
}

/* Get the library pointer from a session or document handle. */
inline wcg_library_t* wcg_lib_from_session(wcg_session_t* s) {
    return s ? s->library : nullptr;
}
inline wcg_library_t* wcg_lib_from_document(wcg_document_t* d) {
    return (d && d->session) ? d->session->library : nullptr;
}

#endif /* WCG_INTERNAL_H */
