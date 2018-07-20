package = 'zmq'
version = 'scm-1'
source  = {
    url    = 'git://github.com/bigbes/zmq.git',
    branch = 'master',
}
description = {
    summary  = "ZeroMQ wrappers for Tarantool",
    homepage = 'https://github.com/bigbes/zmq/',
    license  = 'BSD',
    maintainer = "Eugene Blikh <bigbes@gmail.com>";

}
dependencies = {
    'lua >= 5.1'
}
build = {
    type = 'cmake';
    variables = {
        CMAKE_BUILD_TYPE="RelWithDebInfo";
        TARANTOOL_INSTALL_LIBDIR="$(LIBDIR)";
        TARANTOOL_INSTALL_LUADIR="$(LUADIR)";
    };
}


-- vim: syntax=lua
