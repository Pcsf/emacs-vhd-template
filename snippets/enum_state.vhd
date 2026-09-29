{{!Enumeration type for a state machine plus state and next_state signals}}
type {{type|state_t}} is ({{items|S_IDLE, S_RUN, S_DONE}});
signal {{sig|state}}, next_{{sig}} : {{type}};
{{_}}
