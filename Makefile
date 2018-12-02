JBUILDER=jbuilder build
JBUILDERFLAGS=-j 4

TEST=check_nic uname pci_config blink parse_pci_addr
APPS=echo fwd pktgen

all: ${TEST} ${APPS}

apps: ${APPS}

test: ${TEST}

${TEST}:
	${JBUILDER} test/$@.exe ${JBUILDERFLAGS}

${APPS}:
	${JBUILDER} app/$@.exe ${JBUILDERFLAGS}

documentation:
	${JBUILDER} @doc

clean:
	jbuilder clean
