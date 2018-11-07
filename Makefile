JBUILDER=jbuilder build
JBUILDERFLAGS=-j 4

TEST=check_nic uname pci_config
APPS=echo fwd pktgen

all: ${TEST} ${APPS} documentation

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
