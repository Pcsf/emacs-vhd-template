{{!case statement with a when others branch}}
case {{expr|state}} is
  when {{choice|S_IDLE}} =>
    {{_}}
  when others =>
    null;
end case;
