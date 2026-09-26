.PHONY: test lint

test:
	nvim --clean --headless -l tests/run.lua

lint:
	stylua --check .
