# Worked examples

Three blocks with their firmware systems engineering documents filled in.
Read [../doc/firmware-systems-engineering.md](../doc/firmware-systems-engineering.md)
first if the vocabulary is new.

| Example | Block | What it shows |
|---------|-------|---------------|
| `demo_*.org` | An imaginary block with a start/busy/done interface and four registers | All nine documents, with a register map, its side effects and the recovery sequence after a software restart. Nothing here can be run. |
| [`debounce/`](debounce/) | The `debounce` template | How little is enough for a small block: a pin-level contract of four clauses, each with a tripwire monitor, ten test cases and six mutants. |
| [`i2c_master/`](i2c_master/) | The `i2c_master` template | A protocol contract: command and response interface, bus timing derived from the generics, clock stretching, and what happens after a reset in the middle of a transfer. |

The two real examples are projects in the layout the package creates:

```
<block>/src/    the template as rendered (a test keeps it identical)
<block>/tb/     tb_<block>.vhd with test cases and p_tw_* monitors,
                sources.txt (analysis order), mutants.txt
<block>/doc/    ICD, requirements, design description, verification plan,
                traceability matrix, test report
```

Run them from the repository root:

```sh
make examples                     # both
test/run-example.sh debounce      # one (after `make render`)
```

A run passes when the testbench prints `TEST PASSED` and every line of
`tb/mutants.txt` is killed: the design is changed with the `sed` expression
of that line, the same testbench must then fail, and its log must name the
monitor or test case the line expects. A mutant that changes nothing, or
that the testbench does not notice, fails the run. This is the mutation
table of the verification plan, executed.

Where a document says "not run" or a result is OPEN, that check (CDC
report, timing, hardware) was not done for the example. The documents say
so instead of leaving the cell empty.
