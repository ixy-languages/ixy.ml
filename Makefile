all: memory check_nic mmap uname

memory:
	jbuilder build test/memory.exe -j 4

check_nic:
	jbuilder build test/check_nic.exe -j 4

mmap:
	jbuilder build test/mmap.exe -j 4

uname:
	jbuilder build test/uname.exe -j 4

clean:
	jbuilder clean
