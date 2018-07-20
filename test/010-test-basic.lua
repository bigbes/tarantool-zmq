local zmq    = require('zmq')
local errno  = require('errno')
local fiber  = require('fiber')
local socket = require('socket')

local tap  = require('tap')
local test = tap.test(); test:plan(5);

test:test("zmq.strerror test", function(test)
    test:plan(2)

    errno(errno.EINVAL)
    local base_err = errno.strerror()
    test:is(zmq.strerror(), base_err, 'error messages in zmq/errno modules are similar')
    errno(errno.ETIMEDOUT)
    test:is(zmq.strerror(errno.EINVAL), base_err, 'API for getting message from errno')
end)

-- TODO: rich API for messages
-- TODO: API for creating message from buffer class
-- TODO: storing messages globally (in weak key-value pair)
test:test("message creation", function(test)
    test:plan(17)

    local msg1 = zmq.msg_new()
    local msg2 = zmq.msg_new(nil, { size = 255 })
    local msg3 = zmq.msg_new("Hello world!")
    local msg4 = zmq.msg_new("Hello world!", { size = 50 })
    local msg5 = zmq.msg_new("Hello world!", { size = 5 })

    local a = setmetatable({ msg1, msg2, msg3, msg4, msg5 }, { __mode = 'v' })

    test:is(msg1.msg and
            msg2.msg and
            msg3.msg and
            msg4.msg and
            msg5.msg and
            true or false, true, 'Messages are not "closed"')

    test:is(msg1:size(), 0,   'empty message')
    test:is(msg2:size(), 255, 'empty message with fixed size')
    test:is(msg3:size(), 12,  'message with value')
    test:is(msg4:size(), 50,  'message with length more than value length')
    test:is(msg5:size(), 5,   'cutted message value')

    test:is(msg1:data(),   '',               'empty message')
    test:is(#msg2:data(),  255,              'zero-filled message with len 255')
    test:is(msg3:data(),   'Hello world!',   'content compare')
    test:like(msg4:data(), 'Hello world!.*', 'content with zero-filled end')
    test:like(msg5:data(), 'Hello',          'cutted message')

    test:is(pcall(msg1.close), false,  'error is thrown')
    test:is(msg1:close(), true,  'close msg1')
    test:is(msg1.msg,     nil,   'check that msg1 closed')
    test:is(pcall(msg1.close, msg1), false,   'close message 1 again, error is thrown')

    test:is(pcall(msg1.size, msg1), false, 'closed message size if fals')

    msg1, msg2, msg3, msg4, msg5 = nil, nil, nil, nil, nil
    collectgarbage('collect'); collectgarbage('collect')
    test:is(a[1] or a[2] or a[3] or a[4] or a[5], nil, 'Everything is gc-ed')
end)

test:test("context checks", function(test)
    test:plan(11)
    local ctx = zmq.context()

    test:isnt(ctx, nil, 'successfull creation of ZMQ context')
    test:isnt(ctx.opts.io_threads, 2, 'default io threads count')
    ctx.opts.io_threads = 2
    test:is(ctx.opts.io_threads, 2, 'set/get IO thread count')
    ctx.opts.IO_Threads = 3
    test:is(ctx.opts.io_threads, 3, 'case-insensetive option setting')

    -- get option error
    local ok = pcall(function() return ctx.opts.bad_option end)
    test:is(ok, false, 'bad error name thrown in case of get')
    -- set option error
    local ok = pcall(function() ctx.opts.bad_option = 1 end)
    test:is(ok, false, 'bad error name thrown in case of set')
    -- set type option error
    local ok = pcall(function() ctx.opts.io_threads = 'babab' end)
    test:is(ok, false, 'bad error type thrown in case of set')

    test:is(ctx:shutdown(), true,         'context is successfully closed')
    test:is(ctx.closed,     true,         'context is closed flag')
    test:is(ctx:shutdown(), nil,          'retry context shutdown')
    test:is(errno(),        errno.EFAULT, 'EFAULT is set')
end)

local ECHO_ADDR_1 = 'inproc://echo'
local ECHO_ADDR_2 = 'tcp://127.0.0.1:5555'

test:test("set socket for options", function(test)
    test:plan(0)
end)

test:test("bind", function(test)
    test:plan(21)

    local ctx = zmq.context()
    local pub = ctx:socket('pub')
    for _, address in ipairs({
        ECHO_ADDR_1, ECHO_ADDR_2,
        'inproc://pub.test.1', 'inproc://pub.test.2', 'inproc://pub.test.3',
    }) do
        test:is(pub:bind(address), true, 'Successfully bind on "' .. address .. '"')
    end
    test:is(pub:bind('bad address'), nil, 'bad address is supplied')
    test:is(errno(), errno.EFAULT, 'errno is EFAULT')

    local sub1, sub2, sub3 = ctx:socket('SUB'), ctx:socket('SUB'), ctx:socket('SUB')
    sub1.opts.subscribe, sub2.opts.subscribe, sub3.opts.subscribe = "", "", ""

    test:is(sub1:connect("inproc://pub.test.1"), true, 'connect 1 success')
    test:is(sub2:connect("inproc://pub.test.2"), true, 'connect 2 success')
    test:is(sub3:connect("inproc://pub.test.3"), true, 'connect 3 success')

    fiber.sleep(0.1)

    pub:send("hello")

    test:is(sub1:recv(6), "hello", "everything is rcvd")
    test:is(sub2:recv(6), "hello", "everything is rcvd")
    test:is(sub3:recv(6), "hello", "everything is rcvd")

    test:ok(sub2:close(), 'close is ok for 2rd subscriber')
    test:ok(sub3:close(), 'close is ok for 3rd subscriber')

    test:ok(sub1:connect(ECHO_ADDR_1), 'connection success')

    test:is(sub1:disconnect(ECHO_ADDR_1), true, 'Successfully disconnected')
    test:is(sub1:disconnect('inproc://pub.test.3'), nil, 'Failed to disconnect from inproc://pub.test.3')
    test:is(errno(), errno.EAGAIN, 'errno is EAGAIN: WHY ?!?!?!')

    pub:send("hello")
    test:is(sub1:recv(6), "hello", "everything is rcvd")
    test:is(sub1:recv(6, 0.1), nil, "nothing is rcvd")

    sub1:close()
end)

return test:check()
