.PHONY: spec.zip

# Claude chat/Cowork only take uploads: Customize > Skills on claude.ai.
spec.zip:
	rm -f $@
	cd skills && zip -qr ../$@ spec -x '*/__pycache__/*' '*.test.sh' '*/.DS_Store'
