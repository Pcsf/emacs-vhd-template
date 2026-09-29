# emacs-vhd-template

VHDL and FPGA file templates for Emacs. It uses only what ships with Emacs
(`auto-insert`, `completing-read`, `vhdl-mode`), with no packages to install.

- Open a new `foo.vhd` and pick a template from a list: entity, testbench,
  FSM, FIFO, CDC synchronizer, FPGA top level, and more.
- Insert snippets at point: clocked process, `case`, `generate`, entity
  instance, and more. They are indented to fit the surrounding code.
- Constraint templates fill new `.xdc` (Vivado) and `.sdc` files.
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
active-high reset unless noted.

### File templates (`templates/`)

| Template                          | Contents |
|-----------------------------------|----------|
| `entity_arch`                     | Entity and RTL architecture: generic width, clocked process, sync reset |
| `two_process_pkg`, `two_process`  | Gaisler two-process style: port records and component package, then `comb` and `regs` processes with a `reg_type` record and `REG_RESET` |
| `package`                         | Package and body: constants, types, `clog2` |
| `testbench`                       | Self-checking testbench: clock that stops itself, reset, `check` and `tick` helpers, `TEST PASSED` / `severity failure` |
| `fsm`                             | State register, next-state process, Moore outputs, recovery from illegal states |
| `counter`                         | Modulo-N counter with enable and wrap strobe |
| `edge_detect`                     | Rising, falling or any-edge pulse, chosen by a generic |
| `sync_2ff`                        | CDC: N-flop single-bit synchronizer, `ASYNC_REG` (Xilinx), Quartus attribute as comment |
| `reset_sync`                      | CDC: reset that asserts asynchronously and releases synchronously |
| `fifo_sync`                       | Single-clock FIFO with full/empty flags and block RAM inference |
| `ram_sdp`                         | Simple dual-port RAM, `ram_style` attribute |
| `top_level`                       | FPGA top: board clock and reset button, `reset_sync`, blinking LED (needs `reset_sync` and `counter`) |
| `xdc_constraints`                 | Vivado: clock, pins, false path on reset, CDC and I/O delay examples (Arty A7 pins as example) |
| `sdc_constraints`                 | SDC (Quartus and others): clock, reset, I/O delays |

`testbench` is written for the `entity_arch` template. Rendered with default
answers, the two pass together out of the box. It is a starting point, so
edit the port map for your own device under test.

### Snippets (`snippets/`)

`libs`, `process_clk`, `process_comb`, `case`, `enum_state`, `record`,
`generate_for`, `generate_if`, `inst_entity`, `function`, `clog2`,
`assert_check`, `attr_debug` (Vivado `mark_debug`).

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
ghdl -a --std=08 --workdir=work entity_arch.vhd entity_arch_tb.vhd
ghdl -e --std=08 --workdir=work entity_arch_tb
ghdl -r --std=08 --workdir=work entity_arch_tb --wave=tb.ghw   # then: gtkwave tb.ghw
```

The testbench template prints `TEST PASSED`. On a failed check it stops with
`severity failure`, so `ghdl -r` exits non-zero and works in CI.

## Tests

```sh
make test     # Elisp tests (ERT): engine, auto-insert, key bindings, indentation
make sim      # render every template with its defaults, then GHDL
              # analyse, elaborate and simulate them (needs ghdl)
make check    # both
```

`make sim` also runs `test/tb_functional.vhd`. It checks the counter, FIFO
(including a write to a full FIFO), two-process module, edge detector and both
synchronizers, so the templates are verified in simulation, not just compiled.

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
