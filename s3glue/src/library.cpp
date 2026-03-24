#include "internal.h"

#include <chrono>
#include <cstdlib>
#include <fstream>

std::filesystem::path s3g_debug_log_path() {
    if (const char* user_profile = std::getenv("USERPROFILE")) {
        return std::filesystem::path(user_profile) / "Documents" / "Merrow" / "temp" / "s3glue-debug.log";
    }
    return std::filesystem::current_path() / "s3glue-debug.log";
}

void s3g_append_debug(const std::string& message) {
    const auto path = s3g_debug_log_path();
    std::error_code ec;
    std::filesystem::create_directories(path.parent_path(), ec);
    std::ofstream out(path, std::ios::app | std::ios::binary);
    if (!out) return;

    const auto now = std::chrono::system_clock::now().time_since_epoch();
    const auto seconds = std::chrono::duration_cast<std::chrono::seconds>(now).count();
    out << seconds << " | " << message << "\r\n";
}

extern "C" {

uint32_t s3g_get_abi_version(void) {
    return S3G_ABI_VERSION;
}

s3g_status s3g_create_library(const s3g_runtime_options* options,
                              s3g_library* out_library) {
    if (!out_library) return S3G_INVALID_ARGUMENT;
    *out_library = nullptr;

    s3g_append_debug("s3g_create_library begin");

    if (options && options->abi_version != 0 && options->abi_version != S3G_ABI_VERSION) {
        s3g_append_debug("s3g_create_library invalid ABI version");
        return S3G_INVALID_ARGUMENT;
    }

    auto* library = new (std::nothrow) s3g_library_t();
    if (!library) {
        s3g_append_debug("s3g_create_library out of memory allocating library state");
        return S3G_OUT_OF_MEMORY;
    }

    try {
        s3g_append_debug("calling Aws::InitAPI");
        Aws::InitAPI(library->sdk_options);
        library->sdk_initialized = true;
        s3g_append_debug("Aws::InitAPI succeeded");
    } catch (const std::exception& ex) {
        s3g_append_debug(std::string("Aws::InitAPI threw std::exception: ") + ex.what());
        delete library;
        return S3G_SDK_INIT_FAILED;
    } catch (...) {
        s3g_append_debug("Aws::InitAPI threw unknown exception");
        delete library;
        return S3G_SDK_INIT_FAILED;
    }

    *out_library = library;
    s3g_append_debug("s3g_create_library success");
    return S3G_OK;
}

s3g_status s3g_destroy_library(s3g_library library) {
    if (!library) return S3G_INVALID_ARGUMENT;

    if (library->sdk_initialized) {
        s3g_append_debug("calling Aws::ShutdownAPI");
        Aws::ShutdownAPI(library->sdk_options);
        library->sdk_initialized = false;
    }

    delete library;
    s3g_append_debug("s3g_destroy_library success");
    return S3G_OK;
}

s3g_status s3g_get_last_error(s3g_library library,
                              s3g_error_info* out_error) {
    if (!library || !out_error) return S3G_INVALID_ARGUMENT;

    out_error->status = library->last_status;
    out_error->http_status = library->last_http_status;
    out_error->aws_error = library->last_aws_error;
    out_error->utf8_message = library->last_error_message.c_str();
    out_error->utf8_function = library->last_error_function.c_str();
    return S3G_OK;
}

s3g_status s3g_clear_last_error(s3g_library library) {
    if (!library) return S3G_INVALID_ARGUMENT;
    s3g_clear_error(library);
    return S3G_OK;
}

} /* extern "C" */