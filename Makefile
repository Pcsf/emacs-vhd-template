# Checks for the templates: Elisp unit tests, render every template with its
# defaults, then analyse/elaborate/simulate the result with GHDL.
#
#   make check     everything
#   make test      Elisp tests only
#   make sim       render + GHDL only
#   make project   run the rendered GHDL Makefile on a small project

EMACS ?= emacs
GHDL  ?= ghdl

BUILD    := build
RENDERED := $(BUILD)/rendered
WORK     := $(BUILD)/work
GHDLFLAGS := --std=08 --workdir=$(WORK)

# Analysis order: packages and leaf entities first.
UNITS := my_pkg two_process_pkg two_process entity_arch fsm counter sync_2ff \
         reset_sync fifo_sync ram_sdp edge_detect top_level debounce \
         pulse_sync fifo_async pwm lfsr shift_reg rom_lut mac_dsp uart_tx \
         uart_rx spi_master axis_skid axi_lite_regs entity_arch_tb
# Entities to elaborate on their own (the testbenches are run below).
ENTITIES := two_process entity_arch fsm counter sync_2ff reset_sync fifo_sync \
            ram_sdp edge_detect top_level debounce pulse_sync fifo_async pwm \
            lfsr shift_reg rom_lut mac_dsp uart_tx uart_rx spi_master \
            axis_skid axi_lite_regs
TESTBENCHES := entity_arch_tb tb_functional tb_functional_ip

.PHONY: check test render sim project clean

check: test sim project

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
	$(GHDL) -a $(GHDLFLAGS) test/tb_functional.vhd test/tb_functional_ip.vhd
	set -e; for e in $(ENTITIES); do \
	  $(GHDL) -e $(GHDLFLAGS) $$e; \
	done
	@for tb in $(TESTBENCHES); do \
	  echo "== $$tb"; \
	  $(GHDL) -e $(GHDLFLAGS) $$tb && \
	  $(GHDL) -r $(GHDLFLAGS) $$tb 2>&1 | tee $(BUILD)/$$tb.log; \
	  grep -q "TEST PASSED" $(BUILD)/$$tb.log || { echo "$$tb FAILED"; exit 1; }; \
	done

# The rendered GHDL Makefile template must work on a rtl/ + tb/ project.
project: render
	rm -rf $(BUILD)/proj
	mkdir -p $(BUILD)/proj/rtl $(BUILD)/proj/tb
	cp $(RENDERED)/entity_arch.vhd $(BUILD)/proj/rtl/
	cp $(RENDERED)/entity_arch_tb.vhd $(BUILD)/proj/tb/
	cp $(RENDERED)/Makefile $(BUILD)/proj/Makefile
	$(MAKE) -C $(BUILD)/proj TOP=entity_arch_tb 2>&1 | tee $(BUILD)/proj.log
	@grep -q "TEST PASSED" $(BUILD)/proj.log || { echo "project FAILED"; exit 1; }

clean:
	rm -rf $(BUILD)
