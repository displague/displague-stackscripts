SHELL := /bin/bash
TEST_DIRS := $(wildcard */tests)

.PHONY: test update summary $(TEST_DIRS)

test: $(TEST_DIRS)

$(TEST_DIRS):
	@echo "==> Running tests in $@"
	@for t in $@/test*.sh; do \
		if [ -x "$$t" ]; then \
			"$$t"; \
		else \
			bash "$$t"; \
		fi; \
	done

summary:
	./update-stackscripts summary

update:
	./update-stackscripts update
