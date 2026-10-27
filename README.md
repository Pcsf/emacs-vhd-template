# emacs-vhd-template

VHDL and FPGA file templates for Emacs. It uses only what ships with Emacs
(`auto-insert`, `completing-read`, `vhdl-mode`), with no packages to install.

- Open a new `foo.vhd` and pick a template from a list of 56, the things an
  FPGA engineer keeps re-writing: entity, testbench, FSM, CDC synchronizers
  (including a handshake bus synchronizer and an async FIFO), UART, SPI,
  AXI-Lite, AXI-Stream and Avalon blocks, a UVVM-style testbench package
  (clock generator, pulses, `check_value`, `await_value`, alert counting,
  scoreboard) and bus functional models (BFMs) on top of it, top level,
  GHDL and Vivado scripts, constraints.
- Write the documents around a block as Org files from the same chooser:
  interface control document (ICD) with register side effects, requirements,
  design description, verification plan, test report, traceability matrix,
  decision record, design review, release note.
- Insert snippets at point: clocked process, `case`, `generate`, entity
  instance, and more. They are indented to fit the surrounding code.
- New `.xdc` (Vivado) and `.sdc` files are filled with a constraints template.
- Templates are plain `.vhd` files, not Elisp. Edit them with any editor,
  add your own, or override the bundled ones from your own directory.

Tested with Emacs 29 and 31, GHDL 4 and 6 (`make check`). It needs Emacs 27.1 or newer.

## Install

```sh
git clone https://github.com/pcsf/emacs-vhd-template ~/src/emacs-vhd-template
```

Add this to `~/.emacs.d/init.el`:

```elisp
(add-to-list 'load-path "~/src/emacs-vhd-template")
(require 'vhdl-tpl)

(setq auto-insert-query nil)              ; don't ask "Perform vhdl-tpl-auto-insert?"
(setq vhdl-tpl-author "Your Name")        ; default: user-full-name
;; (setq vhdl-tpl-user-directory "~/.emacs.d/vhdl-tpl/")   ; your own templates

(vhdl-tpl-setup)
```

`vhdl-tpl-setup` does three things:

1. Registers the template chooser in `auto-insert-alist` for `*.vhd` and
   `*.vhdl`, and templates for `*.xdc` and `*.sdc`. Turn the constraint
   templates off with `(setq vhdl-tpl-constraint-templates nil)` before the
   call.
2. Turns on `auto-insert-mode`. It only acts on **new, empty** files.
3. Enables `vhdl-tpl-mode` (the key bindings below) in `vhdl-mode` and
   `vhdl-ts-mode` buffers.

## Everyday use

| You do                          | What happens                                             |
|---------------------------------|----------------------------------------------------------|
| `C-x C-f src/uart_tx.vhd`       | Asks for a template, then for its variables              |
| `C-x C-f src/uart_tx_tb.vhd`    | Same, and proposes `testbench` (from the `_tb` suffix)   |
| `C-c t n`                       | New file: pick template, then file name                  |
| `C-c t b`                       | New two-process block, test first: package, skeleton, testbench, `project.mk` |
| `C-c t t`                       | Insert a whole-file template at point                    |
| `C-c t s`                       | Insert a snippet at point, indented for the context      |
| `M-x auto-insert`               | Insert a template into the current empty buffer          |

The template list shows a one-line description next to each name.
`vhdl-mode` already owns `C-c C-t` for its own templates, so this package uses
`C-c t`. Change it with `(setq vhdl-tpl-key-prefix "C-c v")`, or `nil` for no
binding.

The variable prompts use the file name for their defaults. For
`src/uart_tx.vhd`, the entity is named `uart_tx`, so `RET` accepts it. For
`uart_tx_tb.vhd`, the testbench is `uart_tx_tb` and the device under test
defaults to `uart_tx`. After insertion, point is left where you would start
typing.

Suggested file names:

| Suffix / prefix     | Proposed template |
|---------------------|-------------------|
| `_tb`, `tb_`        | `testbench`       |
| `_pkg`              | `package`         |
| `_top`              | `top_level`       |
| anything else       | `entity_arch` (`vhdl-tpl-default-template`) |

## Two-process blocks, test first

`C-c t b` (`M-x vhdl-tpl-new-block`) asks for the project root and a block
name, then writes everything a new block needs:

```
project.mk            mk build framework settings (only if there is none)
Makefile              include mk/Makefile (only if there is none)
src/<name>_pkg.vhd    port records, one in and one out
src/<name>.vhd        two-process skeleton with an empty comb process
tb/tb_util_pkg.vhd    the testbench package (only if there is none)
tb/tb_<name>.vhd      testbench with TC-01 and TC-02, ends with TEST PASSED
src/.compile_order    the package before the block (new lines only)
tb/.compile_order     tb_util_pkg first, the testbench last
```

An existing `project.mk` gets `TESTS += tb_<name>` instead. Nothing is ever
overwritten. The build runs on the
[mk framework](https://github.com/Pcsf/makefile_project_template) (commit
`f87eeee` or later), added once per project:

```sh
git submodule add https://github.com/Pcsf/makefile_project_template.git mk
```

Then the loop:

| Step     | Do                                                     | Expect |
|----------|--------------------------------------------------------|--------|
| RED      | `make test TEST_CHECK=0`                               | `error: [TC-02] CHECK FAILED: busy` in `build/test/tb_<name>.log`; the summary says SKIPPED |
| GREEN    | add the `comb` lines one test case needs, `make test`  | `[TEST] PASSED` |
| Next     | `C-c t s tc` in the testbench                          | a new numbered test case that fails until you write its check |
| Refactor | change `comb` and `reg_type`, testbench untouched, `make test` | still `[TEST] PASSED` |

As written, the skeleton fails TC-02 ("start raises busy on the next clock").
One line in `comb` makes it pass, with the default interface name (the block
name, so the ports are `<name>i` and `<name>o`):

```vhdl
if <name>i.start = '1' then v.busy := '1'; end if;
```

What saves time later:

- **TC-01 passes on the empty skeleton,** because the reset values already
  satisfy it. Any test that passes before its logic exists has not shown it
  can fail. Break the design on purpose once (a wrong `REG_RESET` value, a
  dropped condition), watch exactly that test fail, then undo it.
- **Look at waveforms in GHW.** `make simulate` writes
  `build/<project>.ghw`. GHDL leaves record signals out of a VCD, so a
  two-process design looks empty there.
- **The skeleton says where each signal goes:** a memory -> its own RAM
  entity (`ram_sdp`), another clock -> a synchronizer first (`sync_2ff`),
  needed after the next edge or an output -> a `reg_type` field, anything else
  -> a variable in `comb`, with a default.
- **The testbench stops itself** with `std.env.stop`, so `make simulate`
  ends on its own; `make test` also has the `TEST_TIME` limit.

## What is included

All VHDL is VHDL-2008, uses `ieee.numeric_std`, and has synchronous
active-high reset unless noted. Every template is analysed, elaborated and
simulated with GHDL by `make check` (see [Tests](#tests)).

### File templates (`templates/`)

**Design basics**

| Template          | Contents |
|-------------------|----------|
| `entity_arch`     | Entity and RTL architecture: generic width, clocked process, sync reset |
| `two_process_pkg`, `two_process` | Gaisler two-process style: port records and component package, then `comb` and `regs` processes with a `reg_type` record, `REG_RESET` as reset and initial value, outputs driven from register fields |
| `two_process_skeleton` | The same structure with an empty `comb` process: the RED stub for test-first design (used by `C-c t b`) |
| `two_process_tb` | Test-first testbench for a two-process block on `tb_util_pkg`: port records, `tc_start` per test case, inputs driven after the rising edge and outputs checked on the falling edge, `TEST PASSED` for `make test` |
| `package`         | Package and body: constants, types, `clog2` |
| `fsm`             | State register, next-state process, Moore outputs, recovery from illegal states |
| `counter`         | Modulo-N counter with enable and wrap strobe |
| `edge_detect`     | Rising, falling or any-edge pulse, chosen by a generic |
| `debounce`        | Button debouncer: input synchronizer plus stability counter, time set in ms |
| `pwm`             | PWM generator |
| `lfsr`            | LFSR / PRBS generator, maximal length |
| `top_level`       | FPGA top: board clock and reset button, `reset_sync`, blinking LED (needs `reset_sync` and `counter`) |

**Clock domain crossing**

| Template          | Contents |
|-------------------|----------|
| `sync_2ff`        | N-flop single-bit synchronizer, `ASYNC_REG` (Xilinx) and `SYNCHRONIZER_IDENTIFICATION` (Intel) |
| `reset_sync`      | Reset that asserts asynchronously and releases synchronously |
| `pulse_sync`      | Single-pulse transfer between two clocks (toggle method) |
| `bus_sync_handshake` | Multi-bit word between two clocks: 2-phase req/ack handshake, the word is frozen until the acknowledge is seen; for configuration words and commands. The constraints it needs are in its header and in `xdc_constraints` |
| `fifo_async`      | Asynchronous FIFO: Gray-coded pointers, registered full/empty, two clocks and resets |

**Memory and datapath**

| Template          | Contents |
|-------------------|----------|
| `fifo_sync`       | Single-clock FIFO with full/empty flags and block RAM inference |
| `ram_sdp`         | Simple dual-port RAM, `ram_style` attribute |
| `rom_lut`         | ROM / lookup table filled by a function (sine table), block RAM inference |
| `shift_reg`       | Delay line without reset, maps to SRL / shift-register RAM |
| `mac_dsp`         | Multiply-accumulate with input, multiplier and accumulator registers, DSP block inference |

**Interfaces and protocols**

| Template          | Contents |
|-------------------|----------|
| `uart_tx`, `uart_rx` | UART 8N1, baud rate from `G_CLK_HZ` / `G_BAUD`; TX has valid/ready, RX samples mid-bit and flags framing errors |
| `spi_master`      | SPI master, mode 0, 8 bits MSB first, start/busy/done |
| `spi_slave`       | SPI slave: any mode, MSB or LSB first, any word width, optional tri-state MISO. Runs on the system clock (no SCLK-clocked logic, so no extra clock domain); needs `clk` at least 8 times SCLK |
| `i2c_master`      | I2C master: one command per byte (optional START, write or read a byte, optional STOP), so any transaction incl. repeated START; clock stretching; open-drain pins as `*_i` / `*_oe`. Single master, 7-bit addresses |
| `i2c_slave`       | I2C slave: 7-bit address, `addr_match` / `rx_data` / `tx_req` / `start_evt` / `stop_evt` byte interface, runs on the system clock (needs `clk` at least 8 times SCL), does not stretch |
| `axis_skid`       | AXI4-Stream register slice (skid buffer): registered data and ready, full throughput |
| `axi_lite_regs`   | AXI4-Lite slave with a register map (CONTROL, STATUS, SCRATCH, VERSION), byte strobes, SLVERR on read-only writes |
| `avalon_mm_regs`  | Avalon-MM slave with the same register map, byteenable, one wait state per access, `readdatavalid` |

**Testbench packages** (see [below](#testbench-utilities))

| Template            | Contents |
|---------------------|----------|
| `tb_util_pkg`       | UVVM-style utilities: `clock_generator` with duty cycle and enable, `gen_pulse`, `check_value` on every common type, `check_stable`, `await_value` / `await_change` / `await_stable` with timeouts, `tc_start`, `log` with verbosity, counted alerts with expected counts and stop limits, `random`, `report_final`; used by all BFMs |
| `sb_pkg`            | Generic scoreboard (VHDL-2008 generic package): queue of expected values per instance, `check_received` against the oldest, `check_empty` |

**Bus functional models** (VHDL packages, see [below](#bus-functional-models))

| Template            | Contents |
|---------------------|----------|
| `bfm_axis_pkg`      | AXI4-Stream master and slave: packets, `tlast`, source gaps, sink back-pressure |
| `bfm_avalon_st_pkg` | Avalon-ST source and sink: packets, `startofpacket` / `endofpacket`, gaps, back-pressure |
| `bfm_axilite_pkg`   | AXI4-Lite master: write, read, check; byte strobes, response check, delayed `bready` / `rready` |
| `bfm_avalon_mm_pkg` | Avalon-MM master: write, read, check; `waitrequest`, `readdatavalid`, byteenable |
| `bfm_uart_pkg`      | UART transmit, receive, expect: 5-8 data bits, parity, 1-2 stop bits, parity and framing error injection |
| `bfm_spi_pkg`       | SPI master and slave: modes 0-3, MSB or LSB first, 1-32 bits per word |
| `bfm_i2c_pkg`       | I2C master and slave: transmit, receive, check; repeated START, address NACK, slave clock stretching |

**Verification and project files**

| Template          | Contents |
|-------------------|----------|
| `testbench`       | Self-checking testbench on `tb_util_pkg`: `clock_generator`, reset by `gen_pulse`, numbered test cases, watchdog, `report_final` |
| `testbench_bfm`   | Testbench built on the BFMs for an AXI-Stream DUT: numbered test cases, source BFM in the sequencer, sink BFM in a checker process, final report |
| `project_mk`      | `project.mk` for the [mk build framework](https://github.com/Pcsf/makefile_project_template): `src/` + `tb/`, `make test` verdict on `TEST PASSED`, time limit, GHW waveforms |
| `vivado_build`    | Vivado non-project batch script: synth, place, route, reports, stops before the bitstream if setup timing fails |
| `xdc_constraints` | Vivado: clock, pins, false path on reset, CDC and I/O delay examples (Arty A7 pins as example) |
| `sdc_constraints` | SDC (Quartus and others): clock, reset, I/O delays |

`testbench` is written for the `entity_arch` template and `testbench_bfm` for
`axis_skid`. Rendered with default answers, each passes with its design out of
the box. They are starting points, so edit the port map for your own device
under test.

`project_mk` and `vivado_build` are project files, not VHDL. Use
`C-c t n`, then type the file name (`project.mk`, `build.tcl`).

**Documents** (Org mode, see [below](#system-engineering-documents))

| Template          | Contents |
|-------------------|----------|
| `doc_icd`         | Interface control document: ports, clocks and resets, CDC list, register map with a side-effect entry per register and bit, bus timing, normal and illegal sequences, error causes, recovery after a software reboot, change control |
| `doc_srs`         | Requirements: numbered shall-statements with rationale, verification method (T/A/I/D) and test case, grouped functional, interface, performance, resources, reset, constraints |
| `doc_hdd`         | Design description: block diagram, file list, clocks and resets, CDC table, `reg_type` fields, FSM table, datapath, register interface, decisions, resource budget, requirements satisfied |
| `doc_vplan`       | Verification plan: unit / integration / static / hardware levels, environment, test case table traced to requirements, bad-weather tests, contract monitors, mutation checks, coverage, exit criteria |
| `doc_test_report` | Test report: verdict, configuration under test (commit, tools), results per test case, static results (timing, CDC, utilisation), hardware test, anomalies, deviations, sign-off |
| `doc_rtm`         | Traceability matrix: requirement to design element, ICD clause, test case, monitor and result; reverse trace of things without a requirement; counts |
| `doc_adr`         | Architecture decision record: requirement at stake, options with "do nothing" first, decision, consequences for ICD, design and tests |
| `doc_review`      | Design review record: checklist for requirements and ICD, reset and clocks, CDC, code, verification, implementation; findings with owner; verdict |
| `doc_release`     | Release note: version and `VERSION` register value, commit, tool, changes, ICD changes and whether they break software, verification status, known issues, upgrade steps |

### Snippets (`snippets/`)

`libs`, `process_clk`, `process_comb`, `case`, `enum_state`, `record`,
`slv_array`, `generate_for`, `generate_if`, `inst_entity`, `function`,
`clog2`, `assert_check`, `attr_debug` (Vivado `mark_debug`), `tristate`,
`check_value` and `tc` (a numbered test case on `tb_util_pkg` that fails
until you write its check).

## System engineering documents

The `doc_*` templates are Org files for the paperwork that keeps a block
honest: the contract with the software team, the requirements it is tested
against, and the records that show it was. They live in the repository next
to the VHDL, so they are diffed, reviewed and versioned with it. Create one
with `C-c t n` from a VHDL buffer, or `M-x vhdl-tpl-new-file` anywhere, and
type the file name (`uart_icd.org`); the file name proposes the module name.
New `.org` files are not filled by `auto-insert`, since not every Org file is
an FPGA document.

The documents are written for the blocks in this repository and refer to
each other by section number:

- `doc_icd` documents the register map of `axi_lite_regs` (CONTROL, STATUS,
  SCRATCH, VERSION) around the `start` / `busy` / `done` interface of the
  two-process skeleton. Every register and bit has a side-effect entry, "none"
  included, because the side effect is what breaks software six months later.
  Each timing clause names the testbench monitor (`p_tw_*`: an independent
  process that drives nothing and stops the simulation on a violation) that
  enforces it.
- `doc_srs` numbers requirements `REQ-NNN` and points each at a test case
  `TC-NN`, the numbering the `tc` snippet and `two_process_tb` use.
- `doc_vplan` lists the test cases, the bad-weather tests (software that
  ignores the ICD: double start, write while busy, reboot mid-transaction),
  the monitors and the mutation checks; `doc_test_report` reports them, and
  `doc_rtm` ties requirement, design section, ICD clause, test and result
  together in one table.
- `doc_hdd`, `doc_adr`, `doc_review` and `doc_release` cover the design, its
  decisions, its review and what was shipped.

The Org header (`#+AUTHOR`, `#+DATE`, `#+OPTIONS` with `^:nil` so that
`uart_tx` is not a subscript) is `partials/header.org`; override it from
your own directory to add a company or classification line.

## Testbench utilities

`tb_util_pkg` is one VHDL-2008 file that gives a testbench what UVVM's
`uvvm_util` gives it, without a library to build: create it once per project
with `C-c t n` (`C-c t b` does it for you), analyse it first, and every
testbench and BFM uses it. The names are UVVM's, so moving to UVVM later is
mostly a matter of `use` clauses; the one difference is that UVVM's
`check_value` takes the alert level before the message.

```vhdl
use work.tb_util_pkg.all;
...
constant C_SCOPE : string := "uart_tx_tb";
signal clk : std_logic := '0';
signal rst : std_logic := '0';
...
p_clk : process begin clock_generator(clk, 10 ns, 50); end process;

p_main : process
begin
  gen_pulse(rst, '1', clk, 4, "reset", C_SCOPE);        -- high for 4 clocks
  tc_start("TC-01", "a byte goes out LSB first", C_SCOPE);
  ...
  check_value(txd, '0', "start bit", C_SCOPE);
  await_value(busy, '0', 80 us, 100 us, "frame done", C_SCOPE);
  check_stable(txd, 8 us, "stop bit", C_SCOPE);

  tc_start("TC-02", "a write while busy is refused", C_SCOPE);
  increment_expected_alerts(ERROR, 1);                   -- the BFM will report one
  ...
  report_final(C_SCOPE);                                 -- TEST PASSED, or a failure
  std.env.stop;
end process;
```

What it does:

- **Clocks and pulses.** `clock_generator(clk, period, duty_cycle_pct)` runs
  forever in a process of its own; a second form takes an `ena` signal that
  stops the clock low. `gen_pulse` drives a `std_logic` or a vector for a
  time or a number of rising edges and restores the previous value.
  `wait_num_rising_edges`, `wait_num_falling_edges`.
- **Checks.** `check_value(actual, expected, msg)` for `std_logic`,
  `std_logic_vector`, `unsigned`, `signed`, `integer`, `boolean`, `time`
  and `string`, plus `check_value(condition, msg)`; `check_value_in_range`;
  `check_stable(signal, time, msg)`.
- **Waiting with a verdict.** `await_value(signal, expected, min, max, msg)`,
  `await_change`, `await_stable(signal, stable_for, timeout, msg)`: each
  waits, then reports a timeout, a too-early arrival, or a log line.
- **Alerts are counted, not fatal.** A failed check prints an `error:` line
  and the run goes on, so one run shows every failure. `report_final` prints
  the totals per level and `TEST PASSED` when each level has exactly the
  number of alerts announced with `increment_expected_alerts`; otherwise it
  prints `TEST FAILED` and stops with `severity failure`, so `ghdl -r` exits
  non-zero. `set_alert_stop_limit(ERROR, 1)` stops at the first error
  instead. A `FAILURE` alert always stops.
- **Test cases.** `tc_start("TC-03", "what it checks")` prints a header and
  tags every alert with `[TC-03]`; the final report lists the test cases
  that raised one.
- **Output.** Every line is `<time> <scope>: <message>` on the simulator's
  output, with no file and line noise. `set_log_verbosity(C_LOG_BFM)` also
  prints every passing check and BFM transaction; `log(C_LOG_HDR, ...)`
  for your own lines.
- **Random.** `set_random_seed`, `random(min, max)`, `random(length)`.

`sb_pkg` is a generic scoreboard for when the checker is not the process
that knows the expected values: one instance per stream, `add_expected` in
the sequencer, `check_received` where the data comes out, `check_empty`
before the final report. It is a VHDL-2008 generic package, which GHDL and
Questa take; it is a separate file so a simulator without that support
can leave it out.

```vhdl
package sb_byte_pkg is new work.sb_pkg
  generic map (t_element => std_logic_vector(7 downto 0));
use sb_byte_pkg.all;
...
shared variable sb : t_scoreboard;
```

With the mk build framework nothing else is needed: the package is a file in
`tb/`, listed first in `tb/.compile_order`, and `make test` reads `TEST PASSED`
from the transcript. There is no compile script and no library name.

## Bus functional models

The `bfm_*_pkg` templates are VHDL packages that drive and check a bus from a
testbench, so a test reads as a list of transactions instead of wiggling
signals. They need no UVVM: they log, check and count through `tb_util_pkg`
in the same style (config records, scope strings), so moving a testbench to
UVVM's `bitvis_vip_*` later is mostly a rename. Use `C-c t n` to create
`tb_util_pkg.vhd` and the BFMs you need, in your `tb/` directory, and
compile `tb_util_pkg` first.

```vhdl
use work.tb_util_pkg.all;
use work.bfm_axilite_pkg.all;
...
signal axi_m2s : t_axilite_m2s := C_AXILITE_M2S_INIT;   -- BFM drives
signal axi_s2m : t_axilite_s2m;                         -- DUT drives
...
tc_start("TC-01", "CONTROL reads back what was written", C_SCOPE);
axilite_write(x"00000000", x"DEADBEEF", "CONTROL", clk, axi_m2s, axi_s2m);
axilite_check(x"00000000", x"DEADBEEF", "CONTROL", clk, axi_m2s, axi_s2m);
axilite_write(x"00000004", x"00000001", "STATUS is read-only", clk, axi_m2s, axi_s2m,
              exp_resp => C_AXI_RESP_SLVERR);
...
report_final(C_SCOPE);            -- "TEST PASSED", or a failure that stops GHDL
```

How they work, common to all of them:

- **Two records per interface**, `t_xxx_m2s` (driven by the master or source)
  and `t_xxx_s2m` (driven by the slave or sink), so a BFM never drives a
  signal the DUT drives. Connect DUT ports to the record fields in the port
  map. Widths are constants at the top of each package: change them there.
- **Procedures take the clock as a signal**, drive right after a rising edge
  and sample at the rising edge, and block until the transaction is done. A
  DUT between a source and a sink needs them in two processes (see
  `testbench_bfm`).
- **A config record per BFM** holds the knobs: timeouts, source gaps, sink
  back-pressure, delayed `bready` / `rready`, UART frame format, SPI mode.
- **Errors are counted, not fatal.** A timeout or mismatch raises an alert
  and the test continues; `report_final` prints `TEST PASSED` or stops the
  simulation with `severity failure`.
- **What is not modelled:** AXI-Stream `tkeep` / `tstrb` / `tid` / `tdest` /
  `tuser`, Avalon-ST `empty` / `channel` / `error`, pipelined or burst
  Avalon-MM and AXI4-Lite outstanding transactions. Add fields to the records
  and procedures as you need them; the packages are short on purpose. The I2C
  BFM has no 10-bit addressing and no arbitration.

## Customising

| Variable                       | Default      | Meaning |
|--------------------------------|--------------|---------|
| `vhdl-tpl-author`              | `user-full-name` | Value of `{{author}}` in file headers |
| `vhdl-tpl-date-format`         | `"%Y-%m-%d"` | Format of `{{date}}` |
| `vhdl-tpl-default-template`    | `"entity_arch"` | Proposed for a plain `.vhd` file |
| `vhdl-tpl-user-directory`      | `nil`        | Your own templates, see below |
| `vhdl-tpl-constraint-templates`| `t`          | Fill new `.xdc` and `.sdc` files |
| `vhdl-tpl-key-prefix`          | `"C-c t"`    | Key prefix of `vhdl-tpl-mode` |

### Your own templates

Point `vhdl-tpl-user-directory` at a directory with the same layout as this
repository (`templates/`, `snippets/`, `partials/`, all optional):

```
~/.emacs.d/vhdl-tpl/
├── partials/header.vhd      # replaces the bundled file header (licence, company, ...)
├── partials/header.org      # same for the Org keywords of the document templates
├── templates/entity_arch.vhd    # overrides the bundled template of that name
└── templates/axi_lite_slave.vhd # a new template, shows up in the list
```

A template is the file you want, with a few markers:

| Marker              | Meaning |
|---------------------|---------|
| `{{name}}`          | Ask for `name` once and reuse it everywhere |
| `{{name\|default}}` | Same with a default. The default may use `$file`, `$stem`, `$author`, ... and earlier answers such as `$entity` |
| `{{_}}`             | Where point ends up |
| `{{>header.vhd}}`   | Include `partials/header.vhd` |
| `{{!text}}`         | A whole line that is a description for the chooser; it is not inserted |

Built-in variables (never asked): `filename` (`foo_tb.vhd`), `file`
(`foo_tb`), `stem` (`foo`, without `_tb`, `_pkg`, `_top` or a `tb_` prefix),
`date`, `year`, `author`, `email`.

Answers are inserted as typed and are never expanded a second time.
Single braces such as `{ PACKAGE_PIN ... }` in XDC files are literal.

## FPGA notes

- **VHDL-2008.** The templates use `process (all)` and conditional signal
  assignments. In Vivado, set the file type of the sources to *VHDL 2008*. In Quartus, use `set_global_assignment -name VHDL_INPUT_VERSION
  VHDL_2008`. For a VHDL-93 tool, list the sensitivity lists by hand.
- **Reset.** The templates use a synchronous, active-high `rst`. It maps well
  to FPGA fabric and keeps RAMs inferable. Bring an external asynchronous
  button in through `reset_sync`, as `top_level` does. For asynchronous reset
  in the two-process style, move the reset to the `regs` process.
- **Clock domain crossings.** Use `sync_2ff` for single-bit levels only. For
  buses use a Gray-coded async FIFO or a handshake. Constrain the crossing in
  the XDC/SDC file (`set_false_path`, `set_max_delay -datapath_only`, or
  `set_clock_groups -asynchronous`).
- **Vendor attributes.** Every synchronizer chain carries both `async_reg`
  (Xilinx) and `SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS` (Intel).
  `ram_style`, `mark_debug` and `fsm_encoding` are Xilinx; their Intel
  equivalents are in comments next to them.

### Simulating with GHDL

```sh
mkdir -p work
ghdl -a --std=08 --workdir=work tb_util_pkg.vhd entity_arch.vhd entity_arch_tb.vhd
ghdl -e --std=08 --workdir=work entity_arch_tb
ghdl -r --std=08 --workdir=work entity_arch_tb --wave=tb.ghw   # then: gtkwave tb.ghw
```

For a whole project use the mk build framework: `C-c t b` writes its
`project.mk`, or start one from the `project_mk` template. See
[Two-process blocks, test first](#two-process-blocks-test-first).

The testbenches print `TEST PASSED`. After a failed check they go on, and
`report_final` stops with `severity failure`, so `ghdl -r` exits non-zero
and works in CI.

## Tests

```sh
make test     # Elisp tests (ERT): engine, auto-insert, key bindings, indentation, Org documents
make sim      # render every template with its defaults, then GHDL
              # analyse, elaborate and simulate them (needs ghdl)
make tdd      # C-c t b bundle on the mk framework: RED on the skeleton,
              # GREEN after one line of comb (clones mk, needs git)
make check    # all three
```

`make sim` runs nine testbenches, plus four runs that must fail:

- `entity_arch_tb`: the rendered `testbench` template against `entity_arch`.
- `two_process_tb`: the rendered `two_process_tb` template against `two_process`.
- `axis_skid_tb`: the rendered `testbench_bfm` template against `axis_skid`.
- `test/tb_util.vhd`: `tb_util_pkg` and `sb_pkg` themselves: a 25 % clock
  and a clock with enable, `gen_pulse` timing, every `await_*` against a
  side process with known edge times, `check_stable`, planted errors and
  warnings announced with `increment_expected_alerts`, `random`, and the
  scoreboard with a planted mismatch and an unexpected value.
- `test/tb_util_fail.vhd`, four times: an unexpected error, the alert stop
  limit, a `FAILURE` alert, an unexpected warning. Each must exit non-zero,
  print `TEST FAILED` and never reach the line after the stop.
- `test/tb_bfm.vhd`: every BFM against a design or model it did not write.
  AXI-Stream and Avalon-ST through `axis_skid` (gaps, back-pressure,
  single-beat packets), AXI4-Lite against `axi_lite_regs`, Avalon-MM against
  `avalon_mm_regs`, UART against `uart_rx` and `uart_tx` plus BFM to BFM for
  7E1, 8O2, 5N1 and injected parity and framing errors, SPI slave against
  `spi_master`, and the SPI master in all four modes and five word formats
  against a separately written reference slave and against the slave BFM.
  The `spi_slave` template runs against the master BFM in the same 20
  mode / word format combinations: two normal frames, a frame one clock short
  (no `rx_valid`), a frame one clock long (first bits delivered once), and a
  normal frame again.
- `test/tb_i2c.vhd`: four bus pairings. `i2c_master` against the slave BFM
  (write, read, write then read with a repeated START, address NACK, a slave
  that stretches SCL), the master BFM against `i2c_slave` on a register file
  (pointer byte, write, read back, wrong address, START and STOP counts),
  `i2c_master` against `i2c_slave`, and master BFM against slave BFM. The bus
  is modelled open-drain with a weak pull-up, and a monitor proves that the
  stretching slave really held SCL low.
- `test/tb_functional.vhd`: counter, sync FIFO (including a write to a full
  and a read from an empty FIFO), two-process module, edge detector, both
  synchronizers.
- `test/tb_functional_ip.vhd`: debounce (glitches at several phases),
  pulse_sync, fifo_async (two unrelated clocks, 40 words through a 4-deep
  FIFO), PWM, LFSR period, shift register, ROM, MAC, UART loopback, UART
  receiver against +-3 % baud rate error, SPI loopback, AXI-Stream under
  back-pressure, AXI-Lite (byte strobes, held read data, SLVERR), and
  bus_sync_handshake in both directions between unrelated clocks (30 words
  each, the source changes its data while a transfer is in flight).

The checks were validated by breaking the templates on purpose (wrong bit
order, off-by-one counters, dropped skid register, ...) and confirming that
the testbenches fail.

What simulation cannot show: metastability behaviour, timing, and how a
vendor tool maps the code. The CDC templates are functionally verified, but
you still need the constraints and a CDC report (`report_cdc` in Vivado).
`vivado_build` was syntax-checked but not run in Vivado.

### CI

To run the same checks on GitHub, save this as `.github/workflows/ci.yml`:

```yaml
name: CI
on: [push, pull_request]
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: sudo apt-get update && sudo apt-get install -y --no-install-recommends emacs-nox ghdl
      - run: make check
```

## Layout

```
vhdl-tpl.el     the whole engine (one file)
templates/      whole-file templates (VHDL, constraints, scripts, Org documents)
snippets/       fragments
partials/       shared pieces (file headers, Org keywords)
test/           ERT tests, render script, functional testbenches
Makefile        make check
```
