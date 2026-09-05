SWIFT = swift
BINARY = .build/release/breadcrumb

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
	cd Examples/DemoApp && ../../$(BINARY) crawl . --out .breadcrumb
	cd Examples/DemoApp && ../../$(BINARY) where-is profile.save --out .breadcrumb
	cd Examples/DemoApp && ../../$(BINARY) what-renders ProfileView --out .breadcrumb
	cd Examples/DemoApp && ../../$(BINARY) affected-tests --out .breadcrumb
	cd Examples/DemoApp && ../../$(BINARY) missing-identifiers --out .breadcrumb

clean:
	$(SWIFT) package clean
