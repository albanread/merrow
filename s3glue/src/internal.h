/*
 * internal.h — Private C++ header for s3glue implementation.
 */

#ifndef S3G_INTERNAL_H
#define S3G_INTERNAL_H

#include <aws/core/Aws.h>
#include <aws/core/auth/AWSCredentialsProvider.h>
#include <aws/core/client/ClientConfiguration.h>
#include <aws/core/utils/DateTime.h>
#include <aws/core/utils/memory/stl/AWSStreamFwd.h>
#include <aws/s3/S3Client.h>
#include <aws/s3/model/DeleteObjectRequest.h>
#include <aws/s3/model/GetObjectRequest.h>
#include <aws/s3/model/ListObjectsV2Request.h>
#include <aws/s3/model/Object.h>
#include <aws/s3/model/PutObjectRequest.h>

#include <cstdint>
#include <cstring>
#include <filesystem>
#include <memory>
#include <new>
#include <string>
#include <vector>

#include "../s3glue.h"

struct s3g_library_t {
    Aws::SDKOptions sdk_options;
    bool sdk_initialized;
    std::string last_error_message;
    std::string last_error_function;
    s3g_status last_status;
    int32_t last_http_status;
    uint32_t last_aws_error;

    s3g_library_t()
        : sdk_initialized(false)
        , last_status(S3G_OK)
        , last_http_status(0)
        , last_aws_error(0) {}
};

struct s3g_client_t {
    s3g_library_t* library;
    std::unique_ptr<Aws::S3::S3Client> client;
    std::string region;

    s3g_client_t()
        : library(nullptr) {}
};

inline void s3g_record_error(s3g_library_t* lib,
                             s3g_status status,
                             const char* func,
                             const std::string& message,
                             int32_t http_status = 0,
                             uint32_t aws_error = 0) {
    if (!lib) return;
    lib->last_status = status;
    lib->last_error_function = func ? func : "";
    lib->last_error_message = message;
    lib->last_http_status = http_status;
    lib->last_aws_error = aws_error;
}

inline void s3g_clear_error(s3g_library_t* lib) {
    if (!lib) return;
    lib->last_status = S3G_OK;
    lib->last_error_function.clear();
    lib->last_error_message.clear();
    lib->last_http_status = 0;
    lib->last_aws_error = 0;
}

inline s3g_library_t* s3g_lib_from_client(s3g_client_t* client) {
    return client ? client->library : nullptr;
}

inline std::string s3g_to_string(const char* value) {
    return value ? std::string(value) : std::string();
}

inline char* s3g_dup_cstr(const std::string& value) {
    char* copy = new (std::nothrow) char[value.size() + 1];
    if (!copy) return nullptr;
    std::memcpy(copy, value.c_str(), value.size() + 1);
    return copy;
}

inline void s3g_release_list_result(s3g_list_result* result) {
    if (!result) return;
    if (result->objects) {
        for (uint32_t index = 0; index < result->object_count; ++index) {
            delete[] result->objects[index].utf8_key;
            delete[] result->objects[index].utf8_etag;
            result->objects[index].utf8_key = nullptr;
            result->objects[index].utf8_etag = nullptr;
        }
        delete[] result->objects;
        result->objects = nullptr;
    }
    delete[] result->utf8_next_continuation_token;
    result->utf8_next_continuation_token = nullptr;
    result->object_count = 0;
    result->is_truncated = 0;
}

inline s3g_status s3g_map_error_type(const Aws::Client::AWSError<Aws::S3::S3Errors>& error) {
    using Aws::S3::S3Errors;
    switch (error.GetErrorType()) {
        case S3Errors::NO_SUCH_BUCKET:
        case S3Errors::NO_SUCH_KEY:
        case S3Errors::RESOURCE_NOT_FOUND:
            return S3G_NOT_FOUND;
        case S3Errors::INVALID_ACCESS_KEY_ID:
        case S3Errors::SIGNATURE_DOES_NOT_MATCH:
        case S3Errors::ACCESS_DENIED:
        case S3Errors::UNRECOGNIZED_CLIENT:
            return S3G_AUTH_FAILED;
        default:
            return S3G_INTERNAL_ERROR;
    }
}

inline std::string s3g_format_aws_error(const Aws::Client::AWSError<Aws::S3::S3Errors>& error) {
    std::string message = error.GetExceptionName().c_str();
    if (!message.empty()) {
        message += ": ";
    }
    message += error.GetMessage().c_str();
    return message;
}

void s3g_append_debug(const std::string& message);

std::string s3g_resolve_region(const s3g_client_options* options);
s3g_status s3g_build_client(s3g_library_t* library, const s3g_client_options* options, std::unique_ptr<Aws::S3::S3Client>* out_client, std::string* out_region);

#endif /* S3G_INTERNAL_H */