all: memory check_nic mmap uname

memory:
	jbuilder build test/memory.exe

check_nic:
	jbuilder build test/check_nic.exe

mmap:
	jbuilder build test/mmap.exe

uname:
	jbuilder build test/uname.exe

clean:
	jbuilder clean
