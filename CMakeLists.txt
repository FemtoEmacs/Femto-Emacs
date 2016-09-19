if ("${CMAKE_CURRENT_BINARY_DIR}" STREQUAL
    "${CMAKE_CURRENT_SOURCE_DIR}")
  message (FATAL_ERROR [[In source builds are not allowed.
Try running `cmake' . -B<build-dir>]])
endif ()

cmake_minimum_required (VERSION 3.0)
cmake_policy (SET CMP0054 NEW)

project (femtoemacs LANGUAGES C)

set (CMAKE_INCLUDE_CURRENT_DIR ON)
list (APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake")
include (Utils)

add_custom_target (femtolisp ALL
                   COMMAND make
		   WORKING_DIRECTORY
		     "${PROJECT_SOURCE_DIR}/femtolisp")

add_custom_target (llt ALL
                   COMMAND make
		   WORKING_DIRECTORY
		     "${PROJECT_SOURCE_DIR}/femtolisp/llt")

add_custom_target (femtolisp-clean
                   COMMAND make clean
		   WORKING_DIRECTORY
		     "${PROJECT_SOURCE_DIR}/femtolisp")

add_custom_target (llt-clean
                   COMMAND make clean
		   WORKING_DIRECTORY
		     "${PROJECT_SOURCE_DIR}/femtolisp/llt")

add_dependencies (femtolisp llt)

include_directories (femtolisp femtolisp/llt)

find_package (Curses 6.0 REQUIRED)


include_directories (${CURSES_INCLUDE_DIRS})

link_libraries (
${PROJECT_SOURCE_DIR}/femtolisp/libflisp.a
${PROJECT_SOURCE_DIR}/femtolisp/llt/libllt.a
${CURSES_LIBRARIES}
m
)

include (CMakePrintHelpers)
cmake_print_variables (CURSES_INCLUDE_DIRS)

add_executable (femto
"${PROJECT_SOURCE_DIR}/complete.c"
"${PROJECT_SOURCE_DIR}/command.c"
"${PROJECT_SOURCE_DIR}/data.c"
"${PROJECT_SOURCE_DIR}/display.c"
"${PROJECT_SOURCE_DIR}/gap.c"
"${PROJECT_SOURCE_DIR}/key.c"
"${PROJECT_SOURCE_DIR}/search.c"
"${PROJECT_SOURCE_DIR}/buffer.c"
"${PROJECT_SOURCE_DIR}/replace.c"
"${PROJECT_SOURCE_DIR}/utils.c"
"${PROJECT_SOURCE_DIR}/window.c"
"${PROJECT_SOURCE_DIR}/main.c"
"${PROJECT_SOURCE_DIR}/femtolisp/interface2editor.c"
"${PROJECT_SOURCE_DIR}/femtolisp/flcall.c")
