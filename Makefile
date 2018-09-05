all: memory check_nic mmap uname caml_string

memory:
	jbuilder build test/memory.exe

check_nic:
	jbuilder build test/check_nic.exe

mmap:
	jbuilder build test/mmap.exe

uname:
	jbuilder build test/uname.exe

caml_string:
	jbuilder build test/caml_string.exe

clean:
	jbuilder clean
