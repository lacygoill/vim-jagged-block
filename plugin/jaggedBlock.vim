vim9 noclear

# Need Vim 8.2.2257 and higher
if v:version < 802 || !has('patch-8.2.2257')
    finish
endif

if mapcheck('<c-j>', 'x')->empty() && !hasmapto('<plug>(jagged-block)', 'x')
    xmap <unique> <c-j> <plug>(jagged-block)
endif
xno <plug>(jagged-block) <cmd>call jaggedBlock#mapping()<cr>
