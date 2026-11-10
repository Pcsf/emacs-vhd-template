# Firmware systems engineering: background

A short introduction for someone who writes FPGA logic that software talks
to, and who has not worked with interface contracts before. It explains the
ideas behind the `doc_*` templates and the vocabulary they use.

## The problem it solves

A block can pass every test of its own and still fail in the system,
because the failure sits on the boundary: software wrote a register at a
moment the hardware did not expect, read a flag that had a side effect, or
restarted while the hardware carried on. Nobody's code is wrong on its own.
The agreement between the two sides was never written down, so each side
assumed its own version.

Firmware systems engineering is the habit of writing that agreement down
and making it checkable. It is defensive work: with the boundary fixed, the
logic inside can be designed and changed in peace.

Two questions run through all of it:

- Verification: did we build the block right? Testbenches, timing, CDC.
- Validation: did we build the right block? Does the system do what the
  application needs?

A block can be fully verified and still fail validation. Keep the system
requirement in view while doing verification work.

## The method in five steps

1. **Ask whether the application needs it.** Before a request becomes a
   design, hold it against the system requirement: which budget (loop
   time, throughput, latency) does it serve, and by how much? If the
   present design already meets the requirement, the answer is no, and the
   requirement is the reason. This is the rationale line of every
   requirement and the "do nothing" option of every decision record.
2. **Write the contract (the ICD).** The interface control document says
   what can be observed and relied on at the boundary: ports, clocks and
   resets, the register map, timing, errors and recovery. It lives in the
   repository next to the VHDL and is reviewed with it.
3. **Make the contract executable (tripwire monitors).** For each clause
   of the ICD, the testbench gets an independent process that only watches
   the interface. It drives nothing and stops the simulation when the
   clause is broken. A run that ends silently means the contract held.
4. **Test in bad weather.** Good-weather tests show the block works when
   software behaves. Bad-weather tests drive it like software that ignores
   the ICD: a command sent twice, a write during an operation, a processor
   reset in the middle of a transaction, an enable before the clock is
   stable. The block must stay safe, keep the bus free, and need no
   correct software in order to be safe.
5. **Settle disputes with the contract.** When integration finds a bug,
   name the clause that was broken and show the monitor output. That turns
   "your side is wrong" into "this clause, this assertion".

## Vocabulary

| Term | Meaning |
|------|---------|
| ICD | Interface control document: the contract at the boundary of a block |
| Clause | One statement of the ICD that can be checked: a latency, an ordering rule, the answer to an illegal access |
| Side effect | What touching a register does beyond storing or returning a value: clears a flag, starts an operation, takes effect later |
| Tripwire monitor | Testbench process that watches one clause and fails the run when it is broken. The templates name these `p_tw_<clause>`: `p_` for process, `tw` for tripwire |
| Good weather / bad weather | Stimulus that follows the ICD / stimulus that breaks it on purpose |
| Mutation check | Breaking the design on purpose to see the test that should catch it fail |
| Traceability | The chain requirement -> design element -> ICD clause -> test -> result, with no empty link |
| W1C | Write-1-to-clear: a status bit that software clears by writing 1 to it |

## How the documents fit together

| Question | Document | Template |
|----------|----------|----------|
| What must the block do, and why? | Requirements | `doc_srs` |
| What can the other side rely on? | ICD | `doc_icd` |
| How is it built? | Design description | `doc_hdd` |
| How is it shown to work? | Verification plan | `doc_vplan` |
| Is every requirement built and tested? | Traceability matrix | `doc_rtm` |
| Why this way and not another? | Decision record | `doc_adr` |
| What was checked, what was shipped? | Review, test report, release note | `doc_review`, `doc_test_report`, `doc_release` |

## Tips for applying it

- **Start with the ICD, and start small.** For a first block, the register
  map with its side effects and the recovery sequence are worth more than
  the other eight documents together. Add the rest when a question comes
  up that they answer.
- **Write the side effect of every register, "none" included.** A missing
  entry reads as "none" to software and as "not thought about" to you.
  Describe the physical consequence and the reason, not the register name
  again: "takes effect at the next period boundary, to avoid a glitch on
  the output" is what saves a debug session later.
- **Write the recovery sequence early.** A processor restart usually does
  not reset the fabric. Decide what software must do before first use, and
  what happens when it does not.
- **One monitor per clause, named after it.** Small monitors are easy to
  trust. Change the monitor in the same commit as the clause, before the
  VHDL.
- **Prove that each monitor can fire.** A monitor that never fired in a
  bad-weather test may be dead. The same holds for a test that never
  failed: break the design once on purpose and watch it fail.
- **One "shall" per requirement, and a rationale.** A requirement without
  a reason cannot be defended later and cannot be dropped safely either.
- **Put the numbers where they are derived.** A latency limit with its
  calculation next to it survives the next "make it faster" request.
- **Change the contract on purpose.** A changed clause moves the version,
  and the software side hears about it before the bitstream arrives.
- **Keep it short enough to stay true.** A document nobody updates is
  wrong within a week. Generate what can be generated (port table,
  matrix) and delete sections that do not apply.

The [`examples/`](../examples/) show all of this three times: for an
imaginary block with registers, for a small real block (`debounce`) and for
a protocol block (`i2c_master`). The two real ones run: their testbenches
carry the monitors, and each monitor is shown to fire.
