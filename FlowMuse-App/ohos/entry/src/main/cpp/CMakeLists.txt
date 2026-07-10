cmake_minimum_required(VERSION 3.16)
project(harmony_sqlite)

add_library(harmony_sqlite SHARED
    harmony_sqlite_loader.c
    third_party/sqlite/sqlite3.c
)

target_compile_definitions(harmony_sqlite PRIVATE
    SQLITE_ENABLE_COLUMN_METADATA
    SQLITE_ENABLE_PREUPDATE_HOOK
    SQLITE_ENABLE_SESSION
    SQLITE_TEMP_STORE=2
    SQLITE_THREADSAFE=1
)

# SQLite uses dlopen only for its optional extension-loading API.
target_link_libraries(harmony_sqlite PRIVATE dl)
target_link_options(harmony_sqlite PRIVATE "-Wl,-z,global")

# Expose the SQLite API to the sqlite3 Dart FFI fallback lookup.
set_target_properties(harmony_sqlite PROPERTIES
    OUTPUT_NAME "harmony_sqlite.z"
    PREFIX "lib"
    SUFFIX ".so"
    C_VISIBILITY_PRESET default
    CXX_VISIBILITY_PRESET default
)
