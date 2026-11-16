cmake_minimum_required(VERSION 3.16)
project(CompilerForNASMCpp LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(FLEX REQUIRED)

# macOS ships Bison 2.3; prefer Homebrew's Bison 3 when it is installed.
if(APPLE AND NOT BISON_EXECUTABLE)
    find_program(BISON_EXECUTABLE bison
        PATHS /opt/homebrew/opt/bison/bin /usr/local/opt/bison/bin
        NO_DEFAULT_PATH)
endif()
find_package(BISON 3.6)

set(SRC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/src)
set(INC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/include)

file(GLOB_RECURSE SOURCES ${SRC_DIR}/*.cpp)

flex_target(scanner ${SRC_DIR}/scanner.l ${CMAKE_CURRENT_BINARY_DIR}/scanner.cpp)

add_executable(compiler ${SOURCES} ${FLEX_scanner_OUTPUTS})

target_include_directories(compiler PRIVATE ${INC_DIR} ${CMAKE_CURRENT_BINARY_DIR})

# Optional Bison parser (src/parser.yy), selected at run time with --bison.
if(BISON_FOUND)
    bison_target(bison_parser ${SRC_DIR}/parser.yy ${CMAKE_CURRENT_BINARY_DIR}/parser_bison.cpp
        COMPILE_FLAGS -Wall)
    target_sources(compiler PRIVATE ${BISON_bison_parser_OUTPUTS})
    target_compile_definitions(compiler PRIVATE HAVE_BISON_PARSER)
else()
    message(STATUS "Bison >= 3.6 not found: building without the --bison parser")
endif()
