/*
 * library.cpp — Library lifecycle and diagnostics for wordcomglue.
 */

#include "internal.h"

extern "C" {

uint32_t wcg_get_abi_version(void) {
    return WCG_ABI_VERSION;
}

wcg_status wcg_create_library(const wcg_runtime_options* options,
                              wcg_library* out_library) {
    if (!out_library) return WCG_INVALID_ARGUMENT;
    *out_library = nullptr;

    if (options && options->abi_version != 0 &&
        options->abi_version != WCG_ABI_VERSION) {
        return WCG_INVALID_ARGUMENT;
    }

    auto* lib = new (std::nothrow) wcg_library_t();
    if (!lib) return WCG_OUT_OF_MEMORY;

    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (SUCCEEDED(hr) || hr == S_FALSE) {
        lib->com_initialized = true;
    } else {
        /* RPC_E_CHANGED_MODE means COM is already initialized with a
           different threading model. That is usually fine for our purposes
           as long as Word can be created on this thread. */
        if (hr == RPC_E_CHANGED_MODE) {
            lib->com_initialized = false; /* we did not initialize it */
        } else {
            delete lib;
            return WCG_COM_INIT_FAILED;
        }
    }

    *out_library = lib;
    return WCG_OK;
}

wcg_status wcg_destroy_library(wcg_library library) {
    if (!library) return WCG_INVALID_ARGUMENT;

    if (library->com_initialized) {
        CoUninitialize();
        library->com_initialized = false;
    }

    delete library;
    return WCG_OK;
}

wcg_status wcg_get_last_error(wcg_library library,
                              wcg_error_info* out_error) {
    if (!library || !out_error) return WCG_INVALID_ARGUMENT;

    out_error->status       = library->last_status;
    out_error->hresult      = static_cast<int32_t>(library->last_hresult);
    out_error->system_error = 0;
    out_error->utf8_message  = library->last_error_message.c_str();
    out_error->utf8_function = library->last_error_function.c_str();
    return WCG_OK;
}

wcg_status wcg_clear_last_error(wcg_library library) {
    if (!library) return WCG_INVALID_ARGUMENT;
    wcg_clear_error(library);
    return WCG_OK;
}

} /* extern "C" */
