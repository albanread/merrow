/*
 * s3glue.h — Public C ABI header for AWS S3 operations.
 *
 * The library wraps AWS SDK for C++ S3Client behind a stable C ABI so it can
 * be loaded from Zig or other native clients through a DLL boundary.
 *
 * Strings are UTF-8 and null-terminated. Input strings are caller-owned.
 * Output strings and list result buffers are library-owned and must be released
 * with the corresponding free helpers.
 */

#ifndef S3GLUE_H
#define S3GLUE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define S3G_ABI_VERSION 1

uint32_t s3g_get_abi_version(void);

typedef uint32_t s3g_status;

enum {
    S3G_OK                    = 0,
    S3G_INVALID_ARGUMENT      = 1,
    S3G_OUT_OF_MEMORY         = 2,
    S3G_SDK_INIT_FAILED       = 3,
    S3G_CLIENT_CREATE_FAILED  = 4,
    S3G_LIST_FAILED           = 5,
    S3G_PUT_FAILED            = 6,
    S3G_GET_FAILED            = 7,
    S3G_DELETE_FAILED         = 8,
    S3G_NOT_FOUND             = 9,
    S3G_PATH_NOT_FOUND        = 10,
    S3G_AUTH_FAILED           = 11,
    S3G_INTERNAL_ERROR        = 255
};

typedef struct s3g_library_t* s3g_library;
typedef struct s3g_client_t* s3g_client;

typedef uint32_t s3g_credential_mode;
enum {
    S3G_CREDENTIALS_DEFAULT = 0,
    S3G_CREDENTIALS_STATIC  = 1,
    S3G_CREDENTIALS_PROFILE = 2
};

typedef struct s3g_runtime_options {
    uint32_t abi_version;
    uint32_t flags;
} s3g_runtime_options;

typedef struct s3g_client_options {
    const char* utf8_region;
    const char* utf8_endpoint_override;
    const char* utf8_profile_name;
    const char* utf8_access_key_id;
    const char* utf8_secret_access_key;
    const char* utf8_session_token;
    s3g_credential_mode credential_mode;
    uint32_t verify_ssl;
    uint32_t connect_timeout_ms;
    uint32_t request_timeout_ms;
    uint32_t flags;
} s3g_client_options;

typedef struct s3g_list_options {
    const char* utf8_prefix;
    const char* utf8_delimiter;
    const char* utf8_continuation_token;
    uint32_t max_keys;
    uint32_t flags;
} s3g_list_options;

typedef struct s3g_put_options {
    const char* utf8_content_type;
    const char* utf8_cache_control;
    uint32_t flags;
} s3g_put_options;

typedef struct s3g_list_entry {
    const char* utf8_key;
    const char* utf8_etag;
    uint64_t size_bytes;
    int64_t last_modified_epoch_seconds;
} s3g_list_entry;

typedef struct s3g_list_result {
    uint32_t object_count;
    s3g_list_entry* objects;
    uint32_t is_truncated;
    const char* utf8_next_continuation_token;
} s3g_list_result;

typedef struct s3g_error_info {
    s3g_status status;
    int32_t http_status;
    uint32_t aws_error;
    const char* utf8_message;
    const char* utf8_function;
} s3g_error_info;

s3g_status s3g_create_library(const s3g_runtime_options* options, s3g_library* out_library);
s3g_status s3g_destroy_library(s3g_library library);

s3g_status s3g_create_client(s3g_library library, const s3g_client_options* options, s3g_client* out_client);
s3g_status s3g_destroy_client(s3g_client client);

s3g_status s3g_list_objects(s3g_client client, const char* utf8_bucket, const s3g_list_options* options, s3g_list_result* out_result);
s3g_status s3g_free_list_result(s3g_list_result* result);

s3g_status s3g_put_object_file(s3g_client client, const char* utf8_bucket, const char* utf8_key, const char* utf8_local_path, const s3g_put_options* options);
s3g_status s3g_get_object_file(s3g_client client, const char* utf8_bucket, const char* utf8_key, const char* utf8_local_path);
s3g_status s3g_delete_object(s3g_client client, const char* utf8_bucket, const char* utf8_key);

s3g_status s3g_get_last_error(s3g_library library, s3g_error_info* out_error);
s3g_status s3g_clear_last_error(s3g_library library);

#ifdef __cplusplus
}
#endif

#endif /* S3GLUE_H */