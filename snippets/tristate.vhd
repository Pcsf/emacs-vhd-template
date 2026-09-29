{{!Tri-state / bidirectional pin (infers IOBUF)}}
{{pin|io_pin}} <= {{out|data_out}} when {{oe|oe}} = '1' else 'Z';
{{in|data_in}} <= {{pin}};
{{_}}
