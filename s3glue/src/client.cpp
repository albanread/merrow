#include "internal.h"

#include <aws/core/auth/AWSCredentials.h>
#include <aws/core/auth/AWSCredentialsProvider.h>
#include <aws/core/auth/ProfileCredentialsProvider.h>
#include <aws/core/utils/memory/stl/AWSStreamFwd.h>

#include <cstdlib>
#include <fstream>

namespace {

std::string get_env_string(const char* name) {
    const char* value = std::getenv(name);
    return value ? std::string(value) : std::string();
}

bool is_empty(const char* value) {
    return !value || value[0] == '\0';
}

s3g_status map_request_failure(const Aws::Client::AWSError<Aws::S3::S3Errors>& error,
                               s3g_status fallback) {
    const s3g_status mapped = s3g_map_error_type(error);
    if (mapped == S3G_INTERNAL_ERROR) return fallback;
    return mapped;
}

} // namespace

std::string s3g_resolve_region(const s3g_client_options* options) {
    if (options && !is_empty(options->utf8_region)) return options->utf8_region;

    std::string region = get_env_string("AWS_REGION");
    if (!region.empty()) return region;

    region = get_env_string("AWS_DEFAULT_REGION");
    if (!region.empty()) return region;

    return "us-east-1";
}

s3g_status s3g_build_client(s3g_library_t* library,
                            const s3g_client_options* options,
                            std::unique_ptr<Aws::S3::S3Client>* out_client,
                            std::string* out_region) {
    if (!library || !out_client || !out_region) return S3G_INVALID_ARGUMENT;

    s3g_append_debug("s3g_build_client begin");

    Aws::S3::S3ClientConfiguration config;
    config.region = s3g_resolve_region(options).c_str();
    if (options && !is_empty(options->utf8_endpoint_override)) {
        config.endpointOverride = options->utf8_endpoint_override;
    }
    config.verifySSL = !options || options->verify_ssl != 0;
    if (options && options->connect_timeout_ms > 0) {
        config.connectTimeoutMs = static_cast<long>(options->connect_timeout_ms);
    }
    if (options && options->request_timeout_ms > 0) {
        config.requestTimeoutMs = static_cast<long>(options->request_timeout_ms);
    }

    *out_region = config.region.c_str();
    s3g_append_debug(std::string("resolved region=") + *out_region);

    try {
        const s3g_credential_mode credential_mode = options ? options->credential_mode : S3G_CREDENTIALS_DEFAULT;
        switch (credential_mode) {
            case S3G_CREDENTIALS_STATIC: {
                s3g_append_debug("creating client with static credentials");
                if (!options || is_empty(options->utf8_access_key_id) || is_empty(options->utf8_secret_access_key)) {
                    s3g_record_error(library, S3G_INVALID_ARGUMENT, "s3g_create_client", "Static credentials require access key id and secret access key");
                    return S3G_INVALID_ARGUMENT;
                }
                Aws::Auth::AWSCredentials credentials(
                    options->utf8_access_key_id,
                    options->utf8_secret_access_key,
                    is_empty(options->utf8_session_token) ? "" : options->utf8_session_token);
                auto provider = Aws::MakeShared<Aws::Auth::SimpleAWSCredentialsProvider>("s3glue", credentials);
                out_client->reset(new (std::nothrow) Aws::S3::S3Client(provider, nullptr, config));
                break;
            }
            case S3G_CREDENTIALS_PROFILE: {
                s3g_append_debug("creating client with profile credentials");
                if (!options || is_empty(options->utf8_profile_name)) {
                    s3g_record_error(library, S3G_INVALID_ARGUMENT, "s3g_create_client", "Profile credentials require a profile name");
                    return S3G_INVALID_ARGUMENT;
                }
                auto provider = Aws::MakeShared<Aws::Auth::ProfileConfigFileAWSCredentialsProvider>("s3glue", options->utf8_profile_name);
                out_client->reset(new (std::nothrow) Aws::S3::S3Client(provider, nullptr, config));
                break;
            }
            case S3G_CREDENTIALS_DEFAULT:
            default:
                s3g_append_debug("creating client with default credentials");
                out_client->reset(new (std::nothrow) Aws::S3::S3Client(config));
                break;
        }
    } catch (const std::exception& ex) {
        s3g_append_debug(std::string("s3g_build_client std::exception: ") + ex.what());
        s3g_record_error(library, S3G_CLIENT_CREATE_FAILED, "s3g_create_client", ex.what());
        return S3G_CLIENT_CREATE_FAILED;
    } catch (...) {
        s3g_append_debug("s3g_build_client unknown exception");
        s3g_record_error(library, S3G_CLIENT_CREATE_FAILED, "s3g_create_client", "Unknown error creating S3 client");
        return S3G_CLIENT_CREATE_FAILED;
    }

    if (!out_client->get()) {
        s3g_append_debug("s3g_build_client allocation returned null");
        s3g_record_error(library, S3G_OUT_OF_MEMORY, "s3g_create_client", "Failed to allocate S3 client");
        return S3G_OUT_OF_MEMORY;
    }

    s3g_append_debug("s3g_build_client success");

    return S3G_OK;
}

extern "C" {

s3g_status s3g_create_client(s3g_library library,
                             const s3g_client_options* options,
                             s3g_client* out_client) {
    if (!library || !out_client) return S3G_INVALID_ARGUMENT;
    *out_client = nullptr;
    s3g_clear_error(library);
    s3g_append_debug("s3g_create_client begin");

    auto* client = new (std::nothrow) s3g_client_t();
    if (!client) return S3G_OUT_OF_MEMORY;

    client->library = library;
    const s3g_status status = s3g_build_client(library, options, &client->client, &client->region);
    if (status != S3G_OK) {
        s3g_append_debug(std::string("s3g_create_client failed status=") + std::to_string(status));
        delete client;
        return status;
    }

    *out_client = client;
    s3g_append_debug("s3g_create_client success");
    return S3G_OK;
}

s3g_status s3g_destroy_client(s3g_client client) {
    if (!client) return S3G_INVALID_ARGUMENT;
    delete client;
    return S3G_OK;
}

s3g_status s3g_list_objects(s3g_client client,
                            const char* utf8_bucket,
                            const s3g_list_options* options,
                            s3g_list_result* out_result) {
    if (!client || is_empty(utf8_bucket) || !out_result) return S3G_INVALID_ARGUMENT;
    s3g_library_t* library = s3g_lib_from_client(client);
    s3g_clear_error(library);
    std::memset(out_result, 0, sizeof(*out_result));
    s3g_append_debug(std::string("s3g_list_objects bucket=") + utf8_bucket + " prefix=" + (options && options->utf8_prefix ? options->utf8_prefix : ""));

    Aws::S3::Model::ListObjectsV2Request request;
    request.SetBucket(utf8_bucket);
    if (options) {
        if (!is_empty(options->utf8_prefix)) request.SetPrefix(options->utf8_prefix);
        if (!is_empty(options->utf8_delimiter)) request.SetDelimiter(options->utf8_delimiter);
        if (!is_empty(options->utf8_continuation_token)) request.SetContinuationToken(options->utf8_continuation_token);
        if (options->max_keys > 0) request.SetMaxKeys(static_cast<int>(options->max_keys));
    }

    const auto outcome = client->client->ListObjectsV2(request);
    if (!outcome.IsSuccess()) {
        const auto& error = outcome.GetError();
        const s3g_status status = map_request_failure(error, S3G_LIST_FAILED);
        s3g_append_debug(std::string("s3g_list_objects failed: ") + s3g_format_aws_error(error));
        s3g_record_error(library,
                         status,
                         "s3g_list_objects",
                         s3g_format_aws_error(error),
                         static_cast<int32_t>(error.GetResponseCode()),
                         static_cast<uint32_t>(error.GetErrorType()));
        return status;
    }

    s3g_append_debug(std::string("s3g_list_objects success count=") + std::to_string(outcome.GetResult().GetContents().size()));

    const auto& objects = outcome.GetResult().GetContents();
    if (!objects.empty()) {
        out_result->objects = new (std::nothrow) s3g_list_entry[objects.size()];
        if (!out_result->objects) {
            s3g_record_error(library, S3G_OUT_OF_MEMORY, "s3g_list_objects", "Failed to allocate list entries");
            return S3G_OUT_OF_MEMORY;
        }
        std::memset(out_result->objects, 0, sizeof(s3g_list_entry) * objects.size());

        for (size_t index = 0; index < objects.size(); ++index) {
            const auto& object = objects[index];
            out_result->objects[index].utf8_key = s3g_dup_cstr(object.GetKey().c_str());
            out_result->objects[index].utf8_etag = s3g_dup_cstr(object.GetETag().c_str());
            out_result->objects[index].size_bytes = static_cast<uint64_t>(object.GetSize());
            out_result->objects[index].last_modified_epoch_seconds = static_cast<int64_t>(object.GetLastModified().Millis() / 1000);
            if (!out_result->objects[index].utf8_key || !out_result->objects[index].utf8_etag) {
                s3g_release_list_result(out_result);
                s3g_record_error(library, S3G_OUT_OF_MEMORY, "s3g_list_objects", "Failed to allocate object metadata strings");
                return S3G_OUT_OF_MEMORY;
            }
        }

        out_result->object_count = static_cast<uint32_t>(objects.size());
    }

    out_result->is_truncated = outcome.GetResult().GetIsTruncated() ? 1u : 0u;
    if (out_result->is_truncated) {
        out_result->utf8_next_continuation_token = s3g_dup_cstr(outcome.GetResult().GetNextContinuationToken().c_str());
        if (!out_result->utf8_next_continuation_token) {
            s3g_release_list_result(out_result);
            s3g_record_error(library, S3G_OUT_OF_MEMORY, "s3g_list_objects", "Failed to allocate continuation token");
            return S3G_OUT_OF_MEMORY;
        }
    }

    return S3G_OK;
}

s3g_status s3g_free_list_result(s3g_list_result* result) {
    if (!result) return S3G_INVALID_ARGUMENT;
    s3g_release_list_result(result);
    return S3G_OK;
}

s3g_status s3g_put_object_file(s3g_client client,
                               const char* utf8_bucket,
                               const char* utf8_key,
                               const char* utf8_local_path,
                               const s3g_put_options* options) {
    if (!client || is_empty(utf8_bucket) || is_empty(utf8_key) || is_empty(utf8_local_path)) {
        return S3G_INVALID_ARGUMENT;
    }

    s3g_library_t* library = s3g_lib_from_client(client);
    s3g_clear_error(library);

    const std::filesystem::path local_path(utf8_local_path);
    if (!std::filesystem::exists(local_path)) {
        s3g_record_error(library, S3G_PATH_NOT_FOUND, "s3g_put_object_file", "Local file path does not exist");
        return S3G_PATH_NOT_FOUND;
    }

    std::shared_ptr<Aws::IOStream> input_stream = Aws::MakeShared<Aws::FStream>("s3glue", utf8_local_path, std::ios_base::in | std::ios_base::binary);
    if (!input_stream || !(*input_stream)) {
        s3g_record_error(library, S3G_PATH_NOT_FOUND, "s3g_put_object_file", "Failed to open local file for upload");
        return S3G_PATH_NOT_FOUND;
    }

    Aws::S3::Model::PutObjectRequest request;
    request.SetBucket(utf8_bucket);
    request.SetKey(utf8_key);
    request.SetBody(input_stream);
    if (options) {
        if (!is_empty(options->utf8_content_type)) request.SetContentType(options->utf8_content_type);
        if (!is_empty(options->utf8_cache_control)) request.SetCacheControl(options->utf8_cache_control);
    }

    const auto outcome = client->client->PutObject(request);
    if (!outcome.IsSuccess()) {
        const auto& error = outcome.GetError();
        const s3g_status status = map_request_failure(error, S3G_PUT_FAILED);
        s3g_record_error(library,
                         status,
                         "s3g_put_object_file",
                         s3g_format_aws_error(error),
                         static_cast<int32_t>(error.GetResponseCode()),
                         static_cast<uint32_t>(error.GetErrorType()));
        return status;
    }

    return S3G_OK;
}

s3g_status s3g_get_object_file(s3g_client client,
                               const char* utf8_bucket,
                               const char* utf8_key,
                               const char* utf8_local_path) {
    if (!client || is_empty(utf8_bucket) || is_empty(utf8_key) || is_empty(utf8_local_path)) {
        return S3G_INVALID_ARGUMENT;
    }

    s3g_library_t* library = s3g_lib_from_client(client);
    s3g_clear_error(library);

    const std::filesystem::path local_path(utf8_local_path);
    if (!local_path.parent_path().empty()) {
        std::error_code ec;
        std::filesystem::create_directories(local_path.parent_path(), ec);
        if (ec) {
            s3g_record_error(library, S3G_PATH_NOT_FOUND, "s3g_get_object_file", "Failed to create output directory");
            return S3G_PATH_NOT_FOUND;
        }
    }

    Aws::S3::Model::GetObjectRequest request;
    request.SetBucket(utf8_bucket);
    request.SetKey(utf8_key);
    const std::string output_path = utf8_local_path;
    request.SetResponseStreamFactory([output_path]() -> Aws::IOStream* {
        return Aws::New<Aws::FStream>("s3glue", output_path.c_str(), std::ios_base::out | std::ios_base::binary | std::ios_base::trunc);
    });

    const auto outcome = client->client->GetObject(request);
    if (!outcome.IsSuccess()) {
        const auto& error = outcome.GetError();
        const s3g_status status = map_request_failure(error, S3G_GET_FAILED);
        s3g_record_error(library,
                         status,
                         "s3g_get_object_file",
                         s3g_format_aws_error(error),
                         static_cast<int32_t>(error.GetResponseCode()),
                         static_cast<uint32_t>(error.GetErrorType()));
        return status;
    }

    return S3G_OK;
}

s3g_status s3g_delete_object(s3g_client client,
                             const char* utf8_bucket,
                             const char* utf8_key) {
    if (!client || is_empty(utf8_bucket) || is_empty(utf8_key)) return S3G_INVALID_ARGUMENT;

    s3g_library_t* library = s3g_lib_from_client(client);
    s3g_clear_error(library);

    Aws::S3::Model::DeleteObjectRequest request;
    request.SetBucket(utf8_bucket);
    request.SetKey(utf8_key);

    const auto outcome = client->client->DeleteObject(request);
    if (!outcome.IsSuccess()) {
        const auto& error = outcome.GetError();
        const s3g_status status = map_request_failure(error, S3G_DELETE_FAILED);
        s3g_record_error(library,
                         status,
                         "s3g_delete_object",
                         s3g_format_aws_error(error),
                         static_cast<int32_t>(error.GetResponseCode()),
                         static_cast<uint32_t>(error.GetErrorType()));
        return status;
    }

    return S3G_OK;
}

} /* extern "C" */