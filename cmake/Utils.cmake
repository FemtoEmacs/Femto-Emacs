set (CMAKE_POSITION_INDEPENDENT_CODE ON)
set (CMAKE_INCLUDE_CURRENT_DIR_IN_INTERFACE ON)
set (CMAKE_INCLUDE_CURRENT_DIR ON)
set (CMAKE_C_STANDARD 99)

set (CMAKE_RUNTIME_OUTPUT_DIRECTORY "${PROJECT_BINARY_DIR}/bin")
set (CMAKE_LIBRARY_OUTPUT_DIRECTORY "${PROJECT_BINARY_DIR}/lib")
set (CMAKE_ARCHIVE_OUTPUT_DIRECTORY "${PROJECT_BINARY_DIR}/lib")
set (CMAKE_DEBUG_POSTFIX d)

if (NOT CMAKE_BUILD_TYPE)
  set (CMAKE_BUILD_TYPE "Release")
endif ()

if (NOT DEFINED BUILD_SHARED_LIBS)
  set (BUILD_SHARED_LIBS ON)
endif ()

macro (list_to_string VARNAME)
  list (REMOVE_DUPLICATES ${VARNAME})
  string (REPLACE ";" " " ${VARNAME} "${${VARNAME}}")
endmacro ()

if (CMAKE_C_COMPILER_ID STREQUAL "Clang")
  set (CLANG ON)
  if (CMAKE_C_COMPILER_VERSION VERSION_GREATER "3.3.0")
    set (COMPILER_SUPPORTS_SAN ON)
  endif ()
elseif (CMAKE_C_COMPILER_ID STREQUAL "GNU")
  set (GNU ON)
  if (CMAKE_C_COMPILER_VERSION VERSION_GREATER "4.8.0")
    set (COMPILER_SUPPORTS_SAN ON)
  endif ()
endif ()

if (CMAKE_BUILD_TYPE STREQUAL "Debug")
  set (CMAKE_WARN_DEPRECATED ON)
  set (CMAKE_ERROR_DEPRECATED ON)
  set (CMAKE_EXPORT_COMPILE_COMMANDS ON)
  set (DEBUG 1)
  unset (NDEBUG)

  option (ENABLE_SAN "Enable sanatizers." ON)
  list (APPEND CMAKE_C_FLAGS_DEBUG -Wall
				   -Wextra
				   -Werror
				   -std=c99
                                   -pedantic
				   # -Wwrite-strings
				   )
  if (COMPILER_SUPPORTS_SAN)
    set (SAN_BLACKLIST_FILE "${CMAKE_SOURCE_DIR}/res/blacklists.txt")
    list (APPEND CMAKE_C_FLAGS_DEBUG -fPIE )
    list (APPEND CMAKE_EXE_LINKER_FLAGS_DEBUG -fno-omit-frame-pointer
                                              -pie)
    if (ENABLE_SAN)
      string (TOLOWER ${ENABLE_SAN} ENABLE_SAN)
      list (APPEND CMAKE_EXE_LINKER_FLAGS_DEBUG -pie)
    endif ()

    if (CLANG)
      list (APPEND CMAKE_C_FLAGS_DEBUG
	           -fsanitize-blacklist="${SAN_BLACKLIST_FILE}")
    endif ()

    if (${ENABLE_SAN} STREQUAL "asan" OR ${ENABLE_SAN} STREQUAL "on")
      list (APPEND CMAKE_EXE_LINKER_FLAGS_DEBUG -fsanitize=address
	                                        -fsanitize=undefined)
    elseif (${ENABLE_SAN} STREQUAL "msan")
      list (APPEND CMAKE_EXE_LINKER_FLAGS_DEBUG -fsanitize=memory)
    elseif (${ENABLE_SAN} STREQUAL "tsan")
      list (APPEND CMAKE_EXE_LINKER_FLAGS_DEBUG -fsanitize=thread)
    endif ()
  endif ()

  list_to_string (CMAKE_C_FLAGS_DEBUG)
  list_to_string (CMAKE_EXE_LINKER_FLAGS_DEBUG)
endif ()

mark_as_advanced (COMILER_SUPPORTS_SAN
                  CLANG
		  GNU
		  DEBUG)
