JBUILDER=jbuilder build
JBUILDERFLAGS=-j 4

TEST=memory check_nic mmap uname pci_config
APPS=echo fwd

all: ${TEST} ${APPS}

apps: ${APPS}

test: ${TEST}

${TEST}:
	${JBUILDER} test/$@.exe ${JBUILDERFLAGS}

${APPS}:
	${JBUILDER} app/$@.exe ${JBUILDERFLAGS}

clean:
	jbuilder clean
