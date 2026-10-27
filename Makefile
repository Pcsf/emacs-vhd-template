# Checks for the templates: Elisp unit tests, render every template with its
# defaults, then analyse/elaborate/simulate the result with GHDL.
#
#   make check     everything
#   make test      Elisp tests only
#   make sim       render + GHDL only
#   make tdd       new-block bundle on mk/: RED on the skeleton, then GREEN

EMACS ?= emacs
GHDL  ?= ghdl

BUILD    := build
RENDERED := $(BUILD)/rendered
WORK     := $(BUILD)/work
GHDLFLAGS := --std=08 --workdir=$(WORK)

# Analysis order: packages and leaf entities first.
UNITS := my_pkg tb_util_pkg sb_pkg two_process_pkg two_process entity_arch fsm \
         counter sync_2ff reset_sync fifo_sync ram_sdp edge_detect top_level \
         debounce pulse_sync fifo_async pwm lfsr shift_reg rom_lut mac_dsp \
         uart_tx uart_rx spi_master spi_slave axis_skid axi_lite_regs \
         avalon_mm_regs bus_sync_handshake i2c_master i2c_slave bfm_axis_pkg \
         bfm_avalon_st_pkg bfm_axilite_pkg bfm_avalon_mm_pkg bfm_uart_pkg \
         bfm_spi_pkg bfm_i2c_pkg entity_arch_tb two_process_tb axis_skid_tb
# Entities to elaborate on their own (the testbenches are run below).
ENTITIES := two_process entity_arch fsm counter sync_2ff reset_sync fifo_sync \
            ram_sdp edge_detect top_level debounce pulse_sync fifo_async pwm \
            lfsr shift_reg rom_lut mac_dsp uart_tx uart_rx spi_master spi_slave \
            axis_skid axi_lite_regs avalon_mm_regs bus_sync_handshake \
            i2c_master i2c_slave
TESTBENCHES := entity_arch_tb two_process_tb axis_skid_tb tb_functional \
               tb_functional_ip tb_bfm tb_i2c tb_util
# tb_util_fail with each of these must exit non-zero and print TEST FAILED.
FAIL_MODES := mismatch limit failure warning

.PHONY: check test render sim tdd clean

check: test sim tdd

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
	$(GHDL) -a $(GHDLFLAGS) test/tb_functional.vhd test/tb_functional_ip.vhd \
	  test/tb_bfm.vhd test/tb_i2c.vhd test/tb_util.vhd test/tb_util_fail.vhd
	set -e; for e in $(ENTITIES); do \
	  $(GHDL) -e $(GHDLFLAGS) $$e; \
	done
	@for tb in $(TESTBENCHES); do \
	  echo "== $$tb"; \
	  $(GHDL) -e $(GHDLFLAGS) $$tb && \
	  $(GHDL) -r $(GHDLFLAGS) $$tb 2>&1 | tee $(BUILD)/$$tb.log; \
	  grep -q "TEST PASSED" $(BUILD)/$$tb.log || { echo "$$tb FAILED"; exit 1; }; \
	done
	@$(GHDL) -e $(GHDLFLAGS) tb_util_fail
	@for m in $(FAIL_MODES); do \
	  echo "== tb_util_fail $$m (must fail)"; \
	  if $(GHDL) -r $(GHDLFLAGS) tb_util_fail -gG_MODE=$$m > $(BUILD)/tb_util_fail_$$m.log 2>&1; then \
	    echo "tb_util_fail $$m exited 0"; exit 1; fi; \
	  grep -q "TEST FAILED" $(BUILD)/tb_util_fail_$$m.log || { echo "$$m: no TEST FAILED"; exit 1; }; \
	  grep -q "TEST PASSED\|NOT REACHED" $(BUILD)/tb_util_fail_$$m.log && { echo "$$m: ran past the failure"; exit 1; }; \
	  tail -1 $(BUILD)/tb_util_fail_$$m.log; \
	done

# The test-first bundle (vhdl-tpl-new-block) on the mk/ framework: the fresh
# skeleton must fail TC-02 (RED), and one line of comb must make it pass.
MK_REPO ?= https://github.com/Pcsf/makefile_project_template.git
TDD     := $(BUILD)/tdd
TDD_LINE := \    if blki.start = '1' then v.busy := '1'; end if;

tdd:
	rm -rf $(TDD)
	$(EMACS) -Q --batch -L . -l test/new-block.el $(TDD) blk
	git clone -q --depth 1 $(MK_REPO) $(TDD)/mk
	-$(MAKE) -C $(TDD) test TEST_CHECK=0 \
	  > $(BUILD)/tdd_red.log 2>&1
	grep -a -q "error: \[TC-02\] CHECK FAILED: busy, expected 1 got 0" $(BUILD)/tdd_red.log
	! grep -a -q "TEST PASSED" $(BUILD)/tdd_red.log
	sed -i "/-- Default every helper variable here./a $(TDD_LINE)" $(TDD)/src/blk.vhd
	$(MAKE) -C $(TDD) test > $(BUILD)/tdd_green.log 2>&1 \
	  || { cat $(BUILD)/tdd_green.log; echo "tdd FAILED"; exit 1; }
	grep -a -q "TEST PASSED" $(BUILD)/tdd_green.log
	@echo "tdd: RED on the skeleton, GREEN after one line of comb"

clean:
	rm -rf $(BUILD)
