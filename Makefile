.PHONY: project build run test release clean

DERIVED := .build/xcode
APP := $(DERIVED)/Build/Products/Release/Shelf.app

project:
	xcodegen generate

build: project
	xcodebuild -project Shelf.xcodeproj -scheme Shelf -configuration Release -derivedDataPath $(DERIVED) build

run: build
	open $(APP)

test:
	cd Packages/ShelfCore && swift test --enable-code-coverage

release: build
	mkdir -p dist
	ditto -c -k --keepParent $(APP) dist/Shelf.zip
	@echo "dist/Shelf.zip"

clean:
	rm -rf .build dist Shelf.xcodeproj
