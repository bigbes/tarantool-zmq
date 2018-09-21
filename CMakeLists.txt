cmake_minimum_required(VERSION 2.8 FATAL_ERROR)

project(zmq C)
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Debug)
endif()
set(CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake" ${CMAKE_MODULE_PATH})

# Find Tarantool, Lua dependecies and ZeroMQ
find_package(Tarantool REQUIRED)
find_package(ZeroMQ REQUIRED)
message(STATUS "ZeroMQ libraries ${ZeroMQ_LIBRARY}")

include_directories(${TARANTOOL_INCLUDE_DIRS})

# Set CFLAGS
set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} -Wall -Wextra")

add_subdirectory(zmq)

enable_testing()

set (LUA_PATH "LUA_PATH=${PROJECT_SOURCE_DIR}/?.lua\\;${PROJECT_SOURCE_DIR}/?/init.lua\\;\\;")
set (LUA_SOURCE_DIR "LUA_SOURCE_DIR=${PROJECT_SOURCE_DIR}")

add_test(test-basic  ${CMAKE_SOURCE_DIR}/test/010-test-basic.lua)
add_test(test-reqrep ${CMAKE_SOURCE_DIR}/test/020-test-reqrep.lua)

set_tests_properties(test-basic  PROPERTIES ENVIRONMENT "${LUA_PATH};${LUA_SOURCE_DIR}")
set_tests_properties(test-reqrep PROPERTIES ENVIRONMENT "${LUA_PATH};${LUA_SOURCE_DIR}")

# Add `make check`
add_custom_target(check
    WORKING_DIRECTORY ${PROJECT_BUILD_DIR}
    COMMAND ctest -V)
