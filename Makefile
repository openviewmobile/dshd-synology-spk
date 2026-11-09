.PHONY: all spk docker-spk check clean

all: spk docker-spk check

spk:
	./spk/build-spk.sh

docker-spk:
	./spk-docker-project/build-spk.sh

check:
	scripts/check-spk.sh

clean:
	rm -rf dist/*
