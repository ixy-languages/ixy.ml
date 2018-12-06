TEST=check_nic uname pci_config blink parse_pci_addr
APPS=echo fwd pktgen

all: ${TEST} ${APPS}

apps: ${APPS}

test: ${TEST}

${TEST}:
	dune build test/$@.exe

${APPS}:
	dune build app/$@.exe

install:
	dune install

uninstall:
	dune uninstall

documentation:
	dune build @doc

clean:
	dune clean
