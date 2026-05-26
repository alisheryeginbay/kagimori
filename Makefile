.PHONY: help dev prod both devices setup

help:
	@echo "Kagimori device install:"
	@echo "  make dev      Build Debug   and install com.kagimori.app.debug"
	@echo "  make prod     Build Release and install com.kagimori.app"
	@echo "  make both     Install dev then prod (side-by-side)"
	@echo "  make devices  List paired devices and their UDIDs"
	@echo "  make setup    Save your iPhone UDID to .install.env"

dev:
	./Scripts/install.sh Debug

prod:
	./Scripts/install.sh Release

both: dev prod

devices:
	./Scripts/install.sh devices

setup:
	./Scripts/install.sh setup
