.PHONY: release debug

all: release

debug: $(glob src/*.rs)
	cargo build
	cp target/debug/cdenv .

release: $(glob src/*.rs)
	cargo build --release
	cp target/release/cdenv .
	strip cdenv

clean:
	cargo clean
	rm -f cdenv
	rm -f cdenv.shar

check:
	cargo clippy
	shellcheck -e SC1090,SC2155 cdenv.sh

shar: cdenv.shar

cdenv.shar: release
	shar -n "cdenv" -s "lars@gustaebel.de" -z --no-timestamp --no-check-existing cdenv.sh cdenv > cdenv.shar
