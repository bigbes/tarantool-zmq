#include <module.h> /* tarantool/module.h */

#include <errno.h>
#include <limits.h>
#include <stdarg.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#include <zmq.h>

uint32_t CTID_VOID_P;

#define ASYNC_URI_MACRO(NAME)									\
												\
static ssize_t											\
async_ ## NAME ## _cb(va_list ap) {								\
	void *socket    = va_arg(ap, void *);							\
	const char *uri = va_arg(ap, const char *);						\
												\
	return zmq_ ## NAME(socket, uri);							\
}												\
												\
static int											\
lzmq_async_ ## NAME(lua_State *L) {								\
												\
	if (lua_gettop(L) > 3)									\
		return luaL_error(L, "usage: zmq.internal.async_" #NAME "(socket, uri)");	\
												\
	uint32_t cdata;										\
	void *socket = *(void **)luaL_checkcdata(L, 1, &cdata);					\
	if (cdata != CTID_VOID_P || socket == NULL)						\
		return luaL_error(L, "usage: zmq.internal.async_" #NAME "(socket, uri)");	\
												\
	const char *uri = lua_tostring(L, 2);							\
												\
	ssize_t rv = coio_call(async_ ## NAME ## _cb, socket, uri);				\
	if (rv == -1) {										\
		lua_pushinteger(L, -1);								\
		lua_pushinteger(L, errno);							\
		return 2;									\
	}											\
	lua_pushinteger(L, 0);									\
	return 1;										\
};

ASYNC_URI_MACRO(connect);
ASYNC_URI_MACRO(disconnect);
ASYNC_URI_MACRO(bind);
ASYNC_URI_MACRO(unbind);

LUA_API int
luaopen_zmq_internal_lib(lua_State *L)
{
	CTID_VOID_P = luaL_ctypeid(L, "void *");
	lua_newtable(L);
	static const struct luaL_Reg funcs[] = {
		{"async_connect",    lzmq_async_connect    },
		{"async_bind",       lzmq_async_bind       },
		{"async_disconnect", lzmq_async_disconnect },
		{"async_unbind",     lzmq_async_unbind     },
		{NULL,               NULL                  }
	};
	luaL_register(L, NULL, funcs);

	return 1;
}
