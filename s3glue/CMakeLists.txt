cmake_minimum_required(VERSION 3.20)
project(s3glue LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(AWSSDK REQUIRED COMPONENTS s3)

add_library(s3glue SHARED
    s3glue.def
    src/library.cpp
    src/client.cpp
)

target_include_directories(s3glue PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${AWSSDK_INCLUDE_DIRS}
)

target_link_libraries(s3glue PRIVATE
    ${AWSSDK_LINK_LIBRARIES}
)

target_compile_definitions(s3glue PRIVATE
    WIN32_LEAN_AND_MEAN
)

set_target_properties(s3glue PROPERTIES
    OUTPUT_NAME s3glue
)

option(S3G_BUILD_TESTS "Build the s3glue smoke test" ON)

if(S3G_BUILD_TESTS)
    add_executable(s3g_smoke_test tests/smoke_test.cpp)
    target_include_directories(s3g_smoke_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
    target_link_libraries(s3g_smoke_test PRIVATE s3glue)
endif()