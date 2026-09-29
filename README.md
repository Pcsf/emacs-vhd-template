# emacs-vhd-template

VHDL and FPGA file templates for Emacs. It uses only what ships with Emacs
(`auto-insert`, `completing-read`, `vhdl-mode`), with no packages to install.

- Open a new `foo.vhd` and pick a template from a list of 40, the things an
  FPGA engineer keeps re-writing: entity, testbench, FSM, CDC synchronizers
  (including a handshake bus synchronizer and an async FIFO), UART, SPI,
  AXI-Lite, AXI-Stream and Avalon blocks, bus functional models (BFMs) to
  drive and check them, top level, GHDL and Vivado scripts, constraints.
- Insert snippets at point: clocked process, `case`, `generate`, entity
  instance, and more. They are indented to fit the surrounding code.
- New `.xdc` (Vivado) and `.sdc` files are filled with a constraints template.
- Templates are plain `.vhd` files, not Elisp. Edit them with any editor,
  add your own, or override the bundled ones from your own directory.

Tested with Emacs 29 and GHDL 4 (`make check`). It needs Emacs 27.1 or newer.

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

## What is included

All VHDL is VHDL-2008, uses `ieee.numeric_std`, and has synchronous
active-high reset unless noted. Every template is analysed, elaborated and
simulated with GHDL by `make check` (see [Tests](#tests)).

### File templates (`templates/`)

**Design basics**

| Template          | Contents |
|-------------------|----------|
| `entity_arch`     | Entity and RTL architecture: generic width, clocked process, sync reset |
| `two_process_pkg`, `two_process` | Gaisler two-process style: port records and component package, then `comb` and `regs` processes with a `reg_type` record and `REG_RESET` |
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
| `sync_2ff`        | N-flop single-bit synchronizer, `ASYNC_REG` (Xilinx), Quartus attribute as comment |
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
| `axis_skid`       | AXI4-Stream register slice (skid buffer): registered data and ready, full throughput |
| `axi_lite_regs`   | AXI4-Lite slave with a register map (CONTROL, STATUS, SCRATCH, VERSION), byte strobes, SLVERR on read-only writes |
| `avalon_mm_regs`  | Avalon-MM slave with the same register map, byteenable, one wait state per access, `readdatavalid` |

**Bus functional models** (VHDL packages, see [below](#bus-functional-models))

| Template            | Contents |
|---------------------|----------|
| `bfm_util_pkg`      | Log, alert counters, `bfm_check_value`, final report; used by all BFMs |
| `bfm_axis_pkg`      | AXI4-Stream master and slave: packets, `tlast`, source gaps, sink back-pressure |
| `bfm_avalon_st_pkg` | Avalon-ST source and sink: packets, `startofpacket` / `endofpacket`, gaps, back-pressure |
| `bfm_axilite_pkg`   | AXI4-Lite master: write, read, check; byte strobes, response check, delayed `bready` / `rready` |
| `bfm_avalon_mm_pkg` | Avalon-MM master: write, read, check; `waitrequest`, `readdatavalid`, byteenable |
| `bfm_uart_pkg`      | UART transmit, receive, expect: 5-8 data bits, parity, 1-2 stop bits, parity and framing error injection |
| `bfm_spi_pkg`       | SPI master and slave: modes 0-3, MSB or LSB first, 1-32 bits per word |

**Verification and project files**

| Template          | Contents |
|-------------------|----------|
| `testbench`       | Self-checking testbench: clock that stops itself, reset, `check` and `tick` helpers, `TEST PASSED` / `severity failure` |
| `testbench_bfm`   | Testbench built on the BFMs for an AXI-Stream DUT: numbered test cases, source BFM in the sequencer, sink BFM in a checker process, final report |
| `ghdl_makefile`   | Makefile for a `rtl/` + `tb/` project: GHDL resolves the compile order, writes a `.ghw` waveform, `make wave` opens GTKWave |
| `vivado_build`    | Vivado non-project batch script: synth, place, route, reports, stops before the bitstream if setup timing fails |
| `xdc_constraints` | Vivado: clock, pins, false path on reset, CDC and I/O delay examples (Arty A7 pins as example) |
| `sdc_constraints` | SDC (Quartus and others): clock, reset, I/O delays |

`testbench` is written for the `entity_arch` template and `testbench_bfm` for
`axis_skid`. Rendered with default answers, each passes with its design out of
the box. They are starting points, so edit the port map for your own device
under test.

`ghdl_makefile` and `vivado_build` are project files, not VHDL. Use
`C-c t n`, then type the file name (`Makefile`, `build.tcl`).

### Snippets (`snippets/`)

`libs`, `process_clk`, `process_comb`, `case`, `enum_state`, `record`,
`slv_array`, `generate_for`, `generate_if`, `inst_entity`, `function`,
`clog2`, `assert_check`, `attr_debug` (Vivado `mark_debug`), `tristate`.

## Bus functional models

The `bfm_*_pkg` templates are VHDL packages that drive and check a bus from a
testbench, so a test reads as a list of transactions instead of wiggling
signals. They need no UVVM: `bfm_util_pkg` supplies a small log / alert /
`check_value` / final-report layer in the same style (config records, scope
strings), so moving a testbench to UVVM's `bitvis_vip_*` later is mostly a
rename. Use `C-c t n` to create `bfm_util_pkg.vhd` and the BFMs you need, in
your `tb/` directory, and compile `bfm_util_pkg` first.

```vhdl
use work.bfm_util_pkg.all;
use work.bfm_axilite_pkg.all;
...
signal axi_m2s : t_axilite_m2s := C_AXILITE_M2S_INIT;   -- BFM drives
signal axi_s2m : t_axilite_s2m;                         -- DUT drives
...
bfm_log(C_LOG_HDR, "TC-01: CONTROL reads back what was written", C_SCOPE);
axilite_write(x"00000000", x"DEADBEEF", "CONTROL", clk, axi_m2s, axi_s2m);
axilite_check(x"00000000", x"DEADBEEF", "CONTROL", clk, axi_m2s, axi_s2m);
axilite_write(x"00000004", x"00000001", "STATUS is read-only", clk, axi_m2s, axi_s2m,
              exp_resp => C_AXI_RESP_SLVERR);
...
bfm_report_final(C_SCOPE);        -- "TEST PASSED", or a failure that stops GHDL
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
  and the test continues; `bfm_report_final` prints `TEST PASSED` or stops the
  simulation with `severity failure`.
- **What is not modelled:** AXI-Stream `tkeep` / `tstrb` / `tid` / `tdest` /
  `tuser`, Avalon-ST `empty` / `channel` / `error`, pipelined or burst
  Avalon-MM and AXI4-Lite outstanding transactions. Add fields to the records
  and procedures as you need them; the packages are short on purpose. I2C is
  not included.

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
- **Vendor attributes** (`async_reg`, `ram_style`, `mark_debug`,
  `fsm_encoding`) are Xilinx. The Intel equivalents are in comments next to
  them.

### Simulating with GHDL

```sh
mkdir -p work
ghdl -a --std=08 --workdir=work entity_arch.vhd entity_arch_tb.vhd
ghdl -e --std=08 --workdir=work entity_arch_tb
ghdl -r --std=08 --workdir=work entity_arch_tb --wave=tb.ghw   # then: gtkwave tb.ghw
```

For a whole project use the `ghdl_makefile` template: keep the design in
`rtl/` and testbenches in `tb/`, and `make TOP=my_tb` does the rest, in the
right compile order.

The testbench template prints `TEST PASSED`. On a failed check it stops with
`severity failure`, so `ghdl -r` exits non-zero and works in CI.

## Tests

```sh
make test     # Elisp tests (ERT): engine, auto-insert, key bindings, indentation
make sim      # render every template with its defaults, then GHDL
              # analyse, elaborate and simulate them (needs ghdl)
make project  # run the rendered ghdl_makefile on a small rtl/ + tb/ project
make check    # all three
```

`make sim` runs five testbenches:

- `entity_arch_tb`: the rendered `testbench` template against `entity_arch`.
- `axis_skid_tb`: the rendered `testbench_bfm` template against `axis_skid`.
- `test/tb_bfm.vhd`: every BFM against a design or model it did not write.
  AXI-Stream and Avalon-ST through `axis_skid` (gaps, back-pressure,
  single-beat packets), AXI4-Lite against `axi_lite_regs`, Avalon-MM against
  `avalon_mm_regs`, UART against `uart_rx` and `uart_tx` plus BFM to BFM for
  7E1, 8O2, 5N1 and injected parity and framing errors, SPI slave against
  `spi_master`, and the SPI master in all four modes and five word formats
  against a separately written reference slave and against the slave BFM.
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
templates/      whole-file templates
snippets/       fragments
partials/       shared pieces (file headers)
test/           ERT tests, render script, functional testbench
Makefile        make check
```
