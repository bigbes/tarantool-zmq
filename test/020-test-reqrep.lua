local zmq   = require('zmq')
local errno = require('errno')

local tap  = require('tap')
local test = tap.test(); test:plan(2);

local ctx = zmq.context()

local function socket_in(test, socket)  end
local function socket_out(test, socket) end

test:test("req-rep", function(test) end)
test:test("pub-sub", function(test) end)

return test:check()
