JBUILDER=jbuilder build
JBUILDERFLAGS=-j 4

TEST=memory check_nic uname pci_config
APPS=echo fwd pktgen

all: ${TEST} ${APPS}

apps: ${APPS}

test: ${TEST}

${TEST}:
	${JBUILDER} test/$@.exe ${JBUILDERFLAGS}

${APPS}:
	${JBUILDER} app/$@.exe ${JBUILDERFLAGS}

clean:
	jbuilder clean
