.PHONY: all spk check icons clean native-runtime native-spk native-check native-armv8-runtime native-armv8-spk

all: spk check

spk:
	./spk/build-spk.sh

check:
	scripts/check-spk.sh

# Native (no Docker) package. Build the runtime once, then the SPK.
native-runtime:
	./scripts/build-native-runtime.sh

native-spk:
	./spk-native/build-spk.sh

native-armv8-runtime:
	TARGET="$(CURDIR)/spk-native/package/runtime-armv8" PLATFORM=linux/arm64 DSHD_IMAGE=dshd-synology:arm64 ./scripts/build-native-runtime.sh

native-armv8-spk:
	ARCH=armv8 RUNTIME_DIR="$(CURDIR)/spk-native/package/runtime-armv8" ./spk-native/build-spk.sh

native-check:
	scripts/check-spk-native.sh

# Regenerate the checked-in package icons (stdlib Python, no Pillow needed).
icons:
	python3 spk/tools/gen-icons.py

clean:
	rm -rf dist/*
