{{!Vivado mark_debug attribute, so the signal survives for the ILA}}
attribute mark_debug : string;
attribute mark_debug of {{sig|sig_name}} : signal is "true";
