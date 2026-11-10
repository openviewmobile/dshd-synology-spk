.PHONY: all spk docker-spk check icons clean

# Build both variants into dist/, then validate fresh builds in a temp dir.
all: spk docker-spk check

spk:
	./spk/build-spk.sh

docker-spk:
	./spk-docker-project/build-spk.sh

check:
	scripts/check-spk.sh

# Regenerate the checked-in package icons (stdlib Python, no Pillow needed).
icons:
	python3 spk/tools/gen-icons.py
	cp spk/PACKAGE_ICON.PNG spk/PACKAGE_ICON_256.PNG spk-docker-project/

clean:
	rm -rf dist/*
