/*
 * smoke_test.cpp — Minimal smoke test for s3glue.
 *
 * Required environment variables:
 *   S3GLUE_TEST_BUCKET
 * Optional environment variables:
 *   S3GLUE_TEST_PREFIX
 *   S3GLUE_TEST_REGION
 *   S3GLUE_TEST_ENDPOINT
 *   S3GLUE_TEST_PROFILE
 *
 * Credentials default to the AWS SDK provider chain unless S3GLUE_TEST_PROFILE
 * is set, in which case the named shared credentials profile is used.
 */

#include "../s3glue.h"

#include <cstdio>
#include <ctime>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <string>

static s3g_library g_library = nullptr;

static std::string env_or_empty(const char* name) {
    const char* value = std::getenv(name);
    return value ? std::string(value) : std::string();
}

static bool file_contents_equal(const std::filesystem::path& left,
                                const std::filesystem::path& right) {
    std::ifstream lhs(left, std::ios::binary);
    std::ifstream rhs(right, std::ios::binary);
    std::string lhs_text((std::istreambuf_iterator<char>(lhs)), std::istreambuf_iterator<char>());
    std::string rhs_text((std::istreambuf_iterator<char>(rhs)), std::istreambuf_iterator<char>());
    return lhs_text == rhs_text;
}

#define CHECK(call, msg) do { \
    s3g_status status = (call); \
    if (status != S3G_OK) { \
        std::printf("FAIL: %s (status=%u)\n", (msg), status); \
        if (g_library) { \
            s3g_error_info error = {}; \
            if (s3g_get_last_error(g_library, &error) == S3G_OK && error.utf8_message) { \
                std::printf("  error: %s\n", error.utf8_message); \
                std::printf("  http: %d\n", error.http_status); \
                std::printf("  aws_error: %u\n", error.aws_error); \
                std::printf("  in: %s\n", error.utf8_function ? error.utf8_function : "?"); \
            } \
        } \
        return 1; \
    } \
    std::printf("  ok: %s\n", (msg)); \
} while (0)

int main() {
    const std::string bucket = env_or_empty("S3GLUE_TEST_BUCKET");
    if (bucket.empty()) {
        std::printf("SKIP: S3GLUE_TEST_BUCKET is not set\n");
        return 0;
    }

    const std::string prefix = env_or_empty("S3GLUE_TEST_PREFIX");
    const std::string region = env_or_empty("S3GLUE_TEST_REGION");
    const std::string endpoint = env_or_empty("S3GLUE_TEST_ENDPOINT");
    const std::string profile = env_or_empty("S3GLUE_TEST_PROFILE");
    const long long nonce = static_cast<long long>(std::time(nullptr));
    const std::string key = (prefix.empty() ? std::string("merrow-smoke") : prefix) + "/smoke-" + std::to_string(nonce) + ".txt";

    const std::filesystem::path work_dir = std::filesystem::current_path() / "s3glue" / "build";
    std::filesystem::create_directories(work_dir);
    const std::filesystem::path upload_path = work_dir / "s3g-upload.txt";
    const std::filesystem::path download_path = work_dir / "s3g-download.txt";

    {
        std::ofstream out(upload_path, std::ios::binary | std::ios::trunc);
        out << "merrow s3glue smoke payload\n";
        out << "key=" << key << "\n";
    }

    s3g_runtime_options runtime = {};
    runtime.abi_version = S3G_ABI_VERSION;
    CHECK(s3g_create_library(&runtime, &g_library), "create library");

    s3g_client_options options = {};
    options.credential_mode = profile.empty() ? S3G_CREDENTIALS_DEFAULT : S3G_CREDENTIALS_PROFILE;
    options.utf8_profile_name = profile.empty() ? nullptr : profile.c_str();
    options.utf8_region = region.empty() ? nullptr : region.c_str();
    options.utf8_endpoint_override = endpoint.empty() ? nullptr : endpoint.c_str();
    options.verify_ssl = 1;

    s3g_client client = nullptr;
    CHECK(s3g_create_client(g_library, &options, &client), "create client");

    CHECK(s3g_put_object_file(client, bucket.c_str(), key.c_str(), upload_path.string().c_str(), nullptr), "put object file");

    s3g_list_options list_options = {};
    const std::string list_prefix = key.substr(0, key.find_last_of('/') + 1);
    list_options.utf8_prefix = list_prefix.c_str();

    s3g_list_result list_result = {};
    CHECK(s3g_list_objects(client, bucket.c_str(), &list_options, &list_result), "list objects");

    bool found = false;
    for (uint32_t index = 0; index < list_result.object_count; ++index) {
        if (list_result.objects[index].utf8_key && key == list_result.objects[index].utf8_key) {
            found = true;
            break;
        }
    }
    s3g_free_list_result(&list_result);
    if (!found) {
        std::printf("FAIL: uploaded key was not present in list results\n");
        return 1;
    }
    std::printf("  ok: uploaded key found in list results\n");

    CHECK(s3g_get_object_file(client, bucket.c_str(), key.c_str(), download_path.string().c_str()), "get object file");
    if (!file_contents_equal(upload_path, download_path)) {
        std::printf("FAIL: downloaded file contents differ from uploaded file\n");
        return 1;
    }
    std::printf("  ok: downloaded file matches uploaded file\n");

    CHECK(s3g_delete_object(client, bucket.c_str(), key.c_str()), "delete object");
    CHECK(s3g_destroy_client(client), "destroy client");
    CHECK(s3g_destroy_library(g_library), "destroy library");
    g_library = nullptr;

    std::printf("PASS\n");
    return 0;
}