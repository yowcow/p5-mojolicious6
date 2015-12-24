.PHONY: test

all: carton-install-deployment

carton-install-deployment:
	carton install --deployment

test:
	carton exec -- prove test.pl
