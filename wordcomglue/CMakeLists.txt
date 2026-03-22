cmake_minimum_required(VERSION 3.20)
project(wordcomglue LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ---------- Library ----------

add_library(wordcomglue STATIC
    src/library.cpp
    src/session.cpp
    src/document.cpp
)

target_include_directories(wordcomglue PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
)

target_link_libraries(wordcomglue PRIVATE
    ole32
    oleaut32
    uuid
)

# ---------- Optional test program ----------

option(WCG_BUILD_TESTS "Build the wordcomglue smoke test" ON)

if(WCG_BUILD_TESTS)
    add_executable(wcg_smoke_test tests/smoke_test.cpp)
    target_link_libraries(wcg_smoke_test PRIVATE wordcomglue)
endif()
