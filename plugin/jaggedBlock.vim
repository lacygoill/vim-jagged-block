vim9script noclear

if exists('loaded') | finish | endif
var loaded = true

xno <c-g><c-g> <cmd>call jaggedBlock#mapping()<cr>

# TODO: Write tests.{{{
#
#     # source this
#     var lines: list<string> =<< trim END
#         the_quick+brown-fox_jumps+over-the_lazy+dog
#         the+quick-brown_fox+jumps-over_the+lazy-dog
#         the-quick_brown+fox-jumps_over+the-lazy_dog
#
#         [ ]
#         [ ]
#         [ ]
#     END
#     setline(1, lines)
#
# Select a  jagged block,  using whatever  character (underscore,  plus, minus),
# then try to paste it inside the square brackets column.
#
# ---
#
# To test multibyte characters:
#
#     var lines: list<string> =<< trim END
#         thé_qùîck+brôwn-fôx_jùmps+ôvér-thé_làzy+dôg
#         thé+qùîck-brôwn_fôx+jùmps-ôvér_thé+làzy-dôg
#         thé-qùîck_brôwn+fôx-jùmps_ôvér+thé-làzy_dôg
#
#         [ ]
#         [ ]
#         [ ]
#     END
#     setline(1, lines)
#}}}
