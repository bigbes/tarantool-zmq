# Build
if (APPLE)
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -undefined suppress -flat_namespace")
endif(APPLE)

add_library(zmq_internal SHARED internal_lib.c)
set_target_properties(zmq_internal
        PROPERTIES
            PREFIX ""
            SUFFIX ".so"
            OUTPUT_NAME "internal_lib")

# Install
install(TARGETS zmq_internal LIBRARY DESTINATION ${TARANTOOL_INSTALL_LIBDIR}/zmq)
install(FILES internal.lua           DESTINATION ${TARANTOOL_INSTALL_LUADIR}/zmq)
install(FILES init.lua               DESTINATION ${TARANTOOL_INSTALL_LUADIR}/zmq)
