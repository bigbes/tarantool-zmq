local ffi    = require('ffi')
local log    = require('log')
local errno  = require('errno')
local fiber  = require('fiber')
local socket = require('socket')

local internal = require('zmq.internal')
local _, internal_lib = pcall(require, 'zmq.internal_lib')
if type(internal_lib) == 'string' then
    log.error(internal_lib)
    log.error('async (dis)connect/(un)bind are diasbled')
    internal_lib = false
end

if not internal_lib then -- async is disabled
    internal_lib = {
        async_connect    = function(socket, uri, timeout) return zmq.zmq_connect(socket, uri)    end,
        async_disconnect = function(socket, uri, timeout) return zmq.zmq_disconnect(socket, uri) end,
        async_bind       = function(socket, uri, timeout) return zmq.zmq_bind(socket, uri)       end,
        async_unbind     = function(socket, uri, timeout) return zmq.zmq_unbind(socket, uri)     end,
    }
end

local function zmq_strerror(_errno)
    return internal.zmq_strerror(_errno or errno())
end

-- [[=====================================================================]] --

local function zmq_msg_check(obj, method, args)
    if not getmetatable(obj) or getmetatable(obj).__type ~= 'zmq.message' then
        error('Usage: msg:' .. method .. '(' .. args .. ')', 3)
    elseif obj.msg == nil then
        error('Message is closed', 3)
    end
    return true
end

local zmq_msg_new

local function zmq_msg_copy(self)
    zmq_msg_check(self, 'copy', '')
    local dst = assert(zmq_msg_new(), 'Failed to allocate memory for message')
    local rv = internal.zmq_msg_copy(dst, self.msg)
    if rv == -1 then
        dst:close()
        assert(false)
    end
    return dst
end

local function zmq_msg_size(self)
    zmq_msg_check(self, 'size', '')
    return internal.zmq_msg_size(self.msg)
end

local function zmq_msg_data(self, offset, limit)
    zmq_msg_check(self, 'data', 'offset, limit')
    return internal.zmq_msg_data_str(self.msg, offset, limit)
end

local function zmq_msg_close(self)
    zmq_msg_check(self, 'close', '')
    local msg = ffi.gc(self.msg, nil)
    self.msg = nil
    return internal.zmq_msg_close(msg) == 0
end

local function zmq_msg_more(self)
    zmq_msg_check(self, 'more', '')
    return internal.zmq_msg_more(self.msg) == 1
end

local zmq_msg_methods = {
    data  = zmq_msg_data,
    more  = zmq_msg_more,
    size  = zmq_msg_size,
    close = zmq_msg_close,
}

zmq_msg_new = function(value, opts)
    opts = opts or {}
    local msg = nil
    if opts.size or value then
        msg = internal.zmq_msg_init_size(nil, opts.size or #value)
    else
        msg = internal.zmq_msg_init(nil)
    end
    ffi.gc(msg, internal.zmq_msg_close)
    local self = setmetatable({
        msg = msg,
        closed = false
    }, { __index = zmq_msg_methods, __type = 'zmq.message' })
    if value then
        internal.zmq_msg_set_data(self.msg, value)
    end
    return self
end

-- [[=====================================================================]] --

local function zmq_sopts_index(self, name)
    local func = internal.SOCKET_OPTIONS['ZMQ_' .. name:upper()]
    if func == nil then
        error(('Failed zmq_getsockopt[%s]: unknown option'):format(name), 2)
    elseif not func[2]:find('R') then
        error(('Failed zmq_getsockopt[%s]: write-only option'):format(name), 2)
    end
    local socket = getmetatable(self).__socket
    local rv = internal['zmq_skt_getopt_' .. func[3]](socket, func[1])
    if rv == -1 then
        error(('Failed zmq_getsockopt[%s]: %s'):format(name, zmq_strerror()), 2)
    end
    return rv
end

local function zmq_sopts_newindex(self, name, value)
    local func = internal.SOCKET_OPTIONS['ZMQ_' .. name:upper()]
    if func == nil then
        error(('Failed zmq_setsockopt[%s]: unknown option'):format(name), 2)
    elseif not func[2]:find('W') then
        error(('Failed zmq_setsockopt[%s]: read-only option'):format(name), 2)
    end
    local socket = getmetatable(self).__socket
    local rv = internal['zmq_skt_setopt_' .. func[3]](socket, func[1], value)
    if rv == nil then
        error(('Failed zmq_setsockopt[%s]: %s'):format(name, zmq_strerror()), 2)
    end
    return true
end

local function zmq_sopts_new(socket)
    return setmetatable({}, {
        __socket   = socket,
        __index    = zmq_sopts_index,
        __newindex = zmq_sopts_newindex,
    })
end

-- [[=====================================================================]] --

local function zmq_copts_index(self, name)
    local func = internal.CONTEXT_OPTIONS['ZMQ_' .. name:upper()]
    if func == nil then
        error(('Failed zmq_ctx_get[%s]: unknown option'):format(name), 2)
    end
    local rv = internal.zmq_ctx_get(getmetatable(self).__ctx, func)
    if rv == -1 then
        error(('Failed zmq_ctx_get[%s]: %s'):format(name, zmq_strerror()), 2)
    end
    return rv
end

local function zmq_copts_newindex(self, name, value)
    local func = internal.CONTEXT_OPTIONS['ZMQ_' .. name:upper()]
    if func == nil then
        error(('Failed zmq_ctx_set[%s]: unknown option'):format(name), 2)
    end
    local rv = internal.zmq_ctx_set(getmetatable(self).__ctx, func, value)
    if rv == nil then
        error(('Failed zmq_ctx_set[%s]: %s'):format(name, zmq_strerror()), 2)
    end
    return true
end

local function zmq_copts_new(ctx)
    return setmetatable({}, {
        __ctx      = ctx,
        __index    = zmq_copts_index,
        __newindex = zmq_copts_newindex,
    })
end

-- [[=====================================================================]] --

local TIMEOUT_MAX = 4294967296

local function zmq_socket_recv(self, len, timeout)
    timeout = timeout or TIMEOUT_MAX
    local fd, err = self.opts.fd; if not fd then error(err) end;

    while true do
        local cur_time = fiber.time()
        local rv = internal.zmq_recv(self.socket, len, internal.FLAGS.ZMQ_DONTWAIT)
        if rv == nil then
            local _errno = errno()
            repeat
               if _errno == errno.EAGAIN or _errno == errno.EWOULDBLOCK then
                    local rv = socket.iowait(fd, "R", timeout)
                    timeout = timeout - (fiber.time() - cur_time)
                    if rv ~= "R" and timeout <= 0.001 then
                        _errno = errno.ETIMEDOUT
                    else
                        break
                    end
                end
                return nil, 'Failed to zmq_recv: ' .. zmq_strerror(_errno)
            until (false)
        else
            return rv
        end
    end
end

local function zmq_socket_send(self, data, timeout)
    timeout = timeout or TIMEOUT_MAX
    local fd, err = self.opts.fd; if not fd then error(err) end;

    while true do
        local cur_time = fiber.time()
        local rv = internal.zmq_send(self.socket, data, internal.FLAGS.ZMQ_NOBLOCK)
        if rv == -1 then
            local _errno = errno()
            repeat
               if _errno == errno.EAGAIN or _errno == errno.EWOULDBLOCK then
                    local rv = socket.iowait(fd, "W", timeout)
                    timeout = timeout - (fiber.time() - cur_time)
                    if rv ~= "W" and timeout <= 0.001 then
                        _errno = errno.ETIMEDOUT
                    else
                        break
                    end
                end
                return nil, 'Failed to zmq_send: ' .. zmq_strerror(_errno)
            until (false)
        else
            return true
        end
    end
end

local function zmq_socket_msg_recv(self, timeout)
    timeout = timeout or TIMEOUT_MAX
    local fd, err = self.opts.fd; if not fd then error(err) end;
    local msg = assert(zmq_msg_new(), 'Failed to allocate memory for message')

    while true do
        local cur_time = fiber.time()
        local rv = internal.zmq_msg_recv(msg.msg, self.socket, internal.FLAGS.ZMQ_DONTWAIT)
        if rv == -1 then
            local _errno = errno()
            repeat
               if _errno == errno.EAGAIN or _errno == errno.EWOULDBLOCK then
                    local rv = socket.iowait(fd, "R", timeout)
                    timeout = timeout - (fiber.time() - cur_time)
                    if rv ~= "R" and timeout <= 0.001 then
                        _errno = errno.ETIMEDOUT
                    else
                        break
                    end
                end
                msg:close()
                return nil, 'Failed to zmq_msg_recv: ' .. zmq_strerror(_errno)
            until (false)
        else
            return msg
        end
    end
end

local function zmq_socket_msg_send(self, msg, timeout)
    timeout = timeout or TIMEOUT_MAX
    local fd, err = self.opts.fd; if not fd then error(err) end;

    while true do
        local cur_time = fiber.time()
        local rv = internal.zmq_msg_send(msg.msg, self.socket, internal.FLAGS.ZMQ_NOBLOCK)
        if rv == -1 then
            local _errno = errno()
            repeat
               if _errno == errno.EAGAIN or _errno == errno.EWOULDBLOCK then
                    local rv = socket.iowait(fd, "W", timeout)
                    timeout = timeout - (fiber.time() - cur_time)
                    if rv ~= "W" and timeout <= 0.001 then
                        _errno = errno.ETIMEDOUT
                    else
                        break
                    end
                end
                return nil, 'Failed to zmq_msg_send: ' .. zmq_strerror(_errno)
            until (false)
        end
        return true
    end
end

-- timeout is ignored, for now
-- TODO: store all connects/binds for multiple disconnects/unbinds
local function zmq_socket_establish(name)
    return function(self, uri, timeout)
        local rv = internal_lib['async_' .. name](self.socket, uri, timeout)
        if rv == -1 then
            return nil, ('Failed to zmq_%s: %s'):format(name, zmq_strerror()), errno()
        end
        return true
    end
end

local function zmq_socket_close(self)
    local rv = internal.zmq_close(self.socket)
    self.socket = nil
    return rv == 0
end

local zmq_socket_methods = {
    connect    = zmq_socket_establish('connect'),
    disconnect = zmq_socket_establish('disconnect'),
    bind       = zmq_socket_establish('bind'),
    unbind     = zmq_socket_establish('unbind'),
    recv       = zmq_socket_recv,
    send       = zmq_socket_send,
    msg_recv   = zmq_socket_msg_recv,
    msg_send   = zmq_socket_msg_send,
    close      = zmq_socket_close,
}

local function zmq_socket_new(ctx, socket)
    return setmetatable({
        ctx    = ctx,
        socket = socket,
        opts   = zmq_sopts_new(socket)
    }, { __index = zmq_socket_methods, __type = 'zmq.socket' })
end

-- TODO: close all sockets in case of shutdown
local function zmq_ctx_shutdown(self)
    if self.closed then
        errno(errno.EFAULT)
        return nil
    end

    self.closed = true
    return internal.zmq_ctx_shutdown(ffi.gc(self.ctx, nil)) == 0
end

-- TODO: save all opened sockets into table
local function zmq_ctx_socket(self, socket_type)
    if self.closed then
        errno(errno.EFAULT)
        return nil
    end

    local socket_typeno = internal.SOCKET_TYPES['ZMQ_' .. socket_type:upper()]
    if socket_typeno == nil then
        error(('Failed zmq_socket[%s]: unknown socket type'):format(socket_type), 2)
    end
    local socket = internal.zmq_socket(self.ctx, socket_typeno)
    if socket == nil then
        return nil, 'Failed zmq_socket: ' .. zmq_strerror()
    end
    return zmq_socket_new(self.ctx, socket)
end

local zmq_ctx_methods = {
    socket   = zmq_ctx_socket,
    shutdown = zmq_ctx_shutdown,
}

local function zmq_ctx_new()
    local ctx = internal.zmq_ctx_new()
    if ctx == nil then
        error('Failed zmq_ctx_new: ' .. zmq_strerror())
    end
    return setmetatable({
        ctx    = ctx,
        closed = false,
        opts   = zmq_copts_new(ctx)
    }, { __index = zmq_ctx_methods, __type = 'zmq.context' })
end

return {
    context  = zmq_ctx_new,
    msg_new  = zmq_msg_new,
    strerror = zmq_strerror,
}
