all: cdenv

cdenv: src/main.rs
	cargo build --release
	cp target/release/cdenv .

check:
	shellcheck cdenv.sh

install: cdenv
	mkdir -p $(DESTDIR)/usr/lib/cdenv
	install -m755 cdenv $(DESTDIR)/usr/lib/cdenv
	install cdenv.sh $(DESTDIR)/usr/lib/cdenv

