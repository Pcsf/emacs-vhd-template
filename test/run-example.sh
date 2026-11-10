#!/bin/sh
# Run one example: its testbench must pass, and every mutant of its design
# listed in tb/mutants.txt must make the same testbench fail with the text
# the list names.  Usage: test/run-example.sh BLOCK   (from the repository root)
set -eu
block=$1
ghdl=${GHDL:-ghdl}
dir=examples/$block
out=build/examples/$block
src=$dir/src/$block.vhd
rm -rf "$out"
mkdir -p "$out/work"

analyse() {    # analyse WORKDIR DESIGN-FILE
  grep -v '^#' "$dir/tb/sources.txt" | while read -r f; do
    [ -n "$f" ] || continue
    [ "$f" = "$src" ] && f=$2
    "$ghdl" -a --std=08 --workdir="$1" "$f"
  done
  "$ghdl" -e --std=08 --workdir="$1" "tb_$block"
}

analyse "$out/work" "$src"
if ! "$ghdl" -r --std=08 --workdir="$out/work" "tb_$block" --stop-time=1sec > "$out/run.log" 2>&1 \
   || ! grep -q "TEST PASSED" "$out/run.log"; then
  cat "$out/run.log"
  echo "example $block: FAILED"
  exit 1
fi
echo "example $block: $(grep -c 'TC-[0-9]' "$out/run.log") log lines with a test case, TEST PASSED"

[ -f "$dir/tb/mutants.txt" ] || exit 0
grep -v '^#' "$dir/tb/mutants.txt" | while IFS='|' read -r name expr expect; do
  [ -n "$name" ] || continue
  m=$out/mutant_$name
  mkdir -p "$m/work"
  sed "$expr" "$src" > "$m/$block.vhd"
  if cmp -s "$src" "$m/$block.vhd"; then
    echo "mutant $name: the sed expression changes nothing"
    exit 1
  fi
  analyse "$m/work" "$m/$block.vhd"
  if "$ghdl" -r --std=08 --workdir="$m/work" "tb_$block" --stop-time=1sec > "$m/run.log" 2>&1 \
     && grep -q "TEST PASSED" "$m/run.log"; then
    echo "mutant $name: survived, the testbench still passes"
    exit 1
  fi
  if ! grep -qF -- "$expect" "$m/run.log"; then
    echo "mutant $name: failed, but without $expect in the log"
    exit 1
  fi
  echo "mutant $name: killed, $expect reported"
done
