.PHONY: test test-ai app icons

test:
	swift test

test-ai:
	@scripts/test-ai.sh

app:
	scripts/build-app.sh

icons:
	uv run --no-project --with pillow python scripts/build-icons.py
