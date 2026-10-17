SHELL := /bin/bash
TEST_SCRIPTS := $(wildcard */tests/test_stackscript.sh)
TEST_IDS := $(patsubst %/tests/test_stackscript.sh,test-%,$(TEST_SCRIPTS))

.PHONY: test update summary $(TEST_SCRIPTS) $(TEST_IDS)

test: $(TEST_SCRIPTS)

$(TEST_SCRIPTS):
	@echo "==> Running $@"
	./$@

$(TEST_IDS): test-%: %/tests/test_stackscript.sh
	@echo "==> Running $<"
	./$<

summary:
	./update-stackscripts summary

update:
	./update-stackscripts update
