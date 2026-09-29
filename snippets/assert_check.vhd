{{!assert with report and severity}}
assert {{cond|dout = expected}}
  report "{{msg|check failed}}"
  severity {{sev|error}};
