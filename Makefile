SERVER_DIR ?= ../voltane
DEST ?= platform=iOS Simulator,name=iPhone 17
DERIVED = build/DerivedData

.PHONY: bootstrap generate fixtures test build ipa clean

bootstrap:
	brew list xcodegen >/dev/null 2>&1 || brew install xcodegen

generate:
	xcodegen generate

# 同步服务端导出的接口样例到核心库测试目录
fixtures:
	$(SERVER_DIR)/.venv/bin/python $(SERVER_DIR)/scripts/dump_fixtures.py --out VoltaneKit/Tests/VoltaneKitTests/Fixtures

test:
	cd VoltaneKit && swift test

build: generate
	xcodebuild -project Voltane.xcodeproj -scheme Voltane -destination '$(DEST)' -derivedDataPath $(DERIVED) build -quiet

ipa: generate
	scripts/build-ipa.sh

clean:
	rm -rf build Voltane.xcodeproj VoltaneKit/.build
