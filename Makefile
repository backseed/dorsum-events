all: dorsum-events

lib:
	shards

spec: lib main.cr
	crystal spec

dorsum-events: lib main.cr
	crystal build --error-trace -o dorsum-events main.cr
	@strip dorsum-events
	@du -sh dorsum-events

release: lib main.cr
	crystal build --release -o dorsum-events main.cr
	@strip dorsum-events
	@du -sh dorsum-events

clean:
	rm -rf dorsum-events *.dwarf

realclean:
	rm -rf .crystal dorsum-events .deps .shards libs lib *.dwarf build

PREFIX ?= /usr/local

install: release
	install -d $(PREFIX)/bin
	install dorsum-events $(PREFIX)/bin
