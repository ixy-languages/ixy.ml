all: memory check_nic mmap

memory:
	jbuilder build test/memory.exe

check_nic:
	jbuilder build test/check_nic.exe

mmap:
	jbuilder build test/mmap.exe

clean:
	jbuilder clean
