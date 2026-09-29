{{!clog2 function: bits needed to address N items}}
function clog2 (n : positive) return natural is
  variable bits  : natural  := 0;
  variable value : positive := 1;
begin
  while value < n loop
    value := value * 2;
    bits  := bits + 1;
  end loop;
  return bits;
end function clog2;
