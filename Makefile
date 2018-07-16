all:
	gcc zmq/internal_lib.c -fPIC -Wall -o zmq/internal_lib.o -I/usr/local/include/tarantool/ -c -g3 -ggdb3
	gcc -shared -o zmq/internal_lib.dylib -fPIC \
		-Wl,"-undefined,suppress" -Wl,-flat_namespace \
		/usr/local/opt/zeromq/lib/libzmq.a \
		zmq/internal_lib.o
