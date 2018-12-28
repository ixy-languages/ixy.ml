TEST=check_nic uname pci_config blink parse_pci_addr pagesize

all:
	dune build @install

test: ${TEST}

${TEST}:
	dune build test/$@.exe

install: all
	dune install

uninstall: all
	dune uninstall

docs:
	dune build @doc

clean:
	dune clean
