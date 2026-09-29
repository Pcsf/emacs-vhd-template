{{!if ... generate, switched by a generic}}
gen_{{label|opt}} : if {{cond|G_ENABLE}} generate
  {{_}}
end generate gen_{{label}};
