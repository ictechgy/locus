SWIFT = swift
BINARY = .build/release/locus

.PHONY: build test release demo clean

build:
	$(SWIFT) build

test:
	$(SWIFT) test

release:
	$(SWIFT) build -c release

# End-to-end demo: crawl the bundled DemoApp (its own git repo with a dirty
# change) and run the full query surface.
demo: release
	cd Examples/DemoApp && ../../$(BINARY) crawl . --out .locus
	cd Examples/DemoApp && ../../$(BINARY) where-is profile.save --out .locus
	cd Examples/DemoApp && ../../$(BINARY) what-renders ProfileView --out .locus
	cd Examples/DemoApp && ../../$(BINARY) affected-tests --out .locus
	cd Examples/DemoApp && ../../$(BINARY) missing-identifiers --out .locus

clean:
	$(SWIFT) package clean
