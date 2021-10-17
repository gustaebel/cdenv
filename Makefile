.PHONY: cdenv

all: cdenv

clean:
	rm -f cdenv
	rm -rf target

cdenv:
	cargo build --release
	cp target/release/cdenv .

check:
	shellcheck -e SC1090,SC2155 cdenv.sh

install: cdenv
	mkdir -p $(DESTDIR)/usr/lib/cdenv
	install -m755 cdenv $(DESTDIR)/usr/lib/cdenv
	install cdenv.sh $(DESTDIR)/usr/lib/cdenv
