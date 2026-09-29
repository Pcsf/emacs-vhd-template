# Checks for the templates: Elisp unit tests, render every template with its
# defaults, then analyse/elaborate/simulate the result with GHDL.
#
#   make check     everything
#   make test      Elisp tests only
#   make sim       render + GHDL only

EMACS ?= emacs
GHDL  ?= ghdl

BUILD    := build
RENDERED := $(BUILD)/rendered
WORK     := $(BUILD)/work
GHDLFLAGS := --std=08 --workdir=$(WORK)

# Analysis order: packages and leaf entities first.
UNITS := my_pkg two_process_pkg two_process entity_arch fsm counter sync_2ff \
         reset_sync fifo_sync ram_sdp edge_detect top_level entity_arch_tb
# Entities to elaborate on their own (the testbenches are run below).
ENTITIES := two_process entity_arch fsm counter sync_2ff reset_sync fifo_sync \
            ram_sdp edge_detect top_level

.PHONY: check test render sim clean

check: test sim

test:
	$(EMACS) -Q --batch -L . -l test/vhdl-tpl-test.el \
	  -f ert-run-tests-batch-and-exit

render:
	rm -rf $(RENDERED)
	$(EMACS) -Q --batch -L . -l test/render-all.el

sim: render
	rm -rf $(WORK)
	mkdir -p $(WORK)
	set -e; for u in $(UNITS); do \
	  $(GHDL) -a $(GHDLFLAGS) $(RENDERED)/$$u.vhd; \
	done
	$(GHDL) -a $(GHDLFLAGS) test/tb_functional.vhd
	set -e; for e in $(ENTITIES); do \
	  $(GHDL) -e $(GHDLFLAGS) $$e; \
	done
	@for tb in entity_arch_tb tb_functional; do \
	  echo "== $$tb"; \
	  $(GHDL) -e $(GHDLFLAGS) $$tb && \
	  $(GHDL) -r $(GHDLFLAGS) $$tb 2>&1 | tee $(BUILD)/$$tb.log; \
	  grep -q "TEST PASSED" $(BUILD)/$$tb.log || { echo "$$tb FAILED"; exit 1; }; \
	done

clean:
	rm -rf $(BUILD)
