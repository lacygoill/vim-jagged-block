vim9script noclear

if exists('loaded') | finish | endif
var loaded = true

# Config {{{1

const SHOWMODE: string = '-- VISUAL JAGGED BLOCK --'

# Init {{{1

var curbuf: number
var exclusive: bool = true
var expand_backward: bool
var jagged_block: list<dict<number>>
var popup_bufnr: number

# Interface {{{1
def jaggedBlock#mapping() #{{{2
    expand_backward = virtcol('.') < virtcol('v')
    exe "norm! \e"
    jagged_block = []
    # Don't try to use `charcount()`.  It wouldn't work as expected if the lines
    # contain multicells characters (like tabs).
    var vcol1: number = min([virtcol("'<"), virtcol("'>")])
    var vcol2: number = max([virtcol("'<"), virtcol("'>")])
    var start_col: number
    var end_col: number
    for lnum in range(line("'<"), line("'>"))
        var line: string = getline(lnum)
        # We can't simply use `col("'<")` and `col("'>")`.{{{
        #
        # They match  valid columns  on the  first and last  line of  the visual
        # selection, yes.   But they do  not necessarily match valid  columns on
        # the  lines  in-between.  Remember  that  the  selection could  contain
        # multibyte characters in arbitrary locations.
        #}}}
        # Don't include a character after `\%v`.{{{
        #
        #     start_col = matchstr(line, '.*\%' .. vcol1 .. 'v.')->strlen()
        #                                                     ^
        #                                                     ✘
        #
        # It wouldn't work as expected  when the first column contains multibyte
        # characters.
        #}}}
        start_col = matchstr(line, '.*\%' .. vcol1 .. 'v')->strlen()
        end_col = matchstr(line, '.*\%' .. vcol2 .. 'v')->strlen()
        if start_col == 0 || end_col == 0
            # trying to support this special case is too tricky
            Error('the first and last columns must be occupied by single-cell characters only')
            return
        endif
        jagged_block += [{
            lnum: lnum,
            start_col: start_col + 1,
            end_col: end_col + 1,
            }]
    endfor
    curbuf = bufnr('%')
    UpdateHighlighting()
    # necessary to clear a possible old message on the command-line (e.g. after an undo/redo)
    echo ''
    popup_bufnr = PopupGetText()->popup_create({
        line: &lines,
        col: 1,
        highlight: 'ModeMsg',
        mapping: false,
        filter: Filter,
        callback: function(ClearJaggedBlock, [false]),
        })->winbufnr()
enddef
#}}}1
# Core {{{1
def UpdateHighlighting(key = '') #{{{2
    ClearJaggedBlock(true)
    if key != ''
        UpdateCoords(key)
    endif
    for coords in jagged_block
        prop_add(coords.lnum, coords.start_col, {
            type: 'JaggedBlock',
            length: coords.end_col - coords.start_col + 1,
            bufnr: curbuf,
            })
    endfor
enddef

def UpdateCoords(key: string) #{{{2
    var pat: string
    var n: number
    for coords in jagged_block
        pat = PatToUpdateBlock(key, coords)
        if expand_backward
            n = coords.lnum
                    ->getline()
                    ->match(pat)
        else
            n = coords.lnum
                    ->getline()
                    ->matchend(pat)
        endif
        if exclusive
            n += 1
        endif
        if n <= 0
            continue
        elseif expand_backward
            coords.start_col = n
        else
            coords.end_col = n
        endif
    endfor
enddef

def Filter(winid: number, key: string): bool #{{{2
    if key == 'y'
        # Specifying  a small  width  (`1`) prevents  Vim  from adding  trailing
        # spaces when we paste the jagged block inside 2 columns of text.
        GetJaggedBlock()->setreg('"', 'b1')
        popup_close(winid)
        return true
    elseif key == 'd' || key == 'c'
        popup_close(winid)
        # We want to use the native `c` and `d` operators, because emulating them perfectly is tricky.
        # Issue: We can't visually select a jagged block.
        # Solution: Temporarily insert spaces to equalize the block, right before `c`/`d` is pressed.
        EqualizeBlock()
        if expand_backward
            # If we've expanded backward, we've inserted spaces to equalize the block.{{{
            #
            # They need to be removed.
            #}}}
            # Why a nested autocmd?{{{
            #
            # `EqualizeBlock()` has  invoked `setline()`, which for  some reason
            # causes  `TextChanged` to  be  fired, even  though  the autocmd  is
            # installed later:
            #
            #     vim9script
            #     setline(1, '')
            #     au TextChanged * echom 'TextChanged was fired'
            #
            # We need to ignore this `TextChanged` event, and wait for the next
            # one which will be fired when `feedkeys()` will have pressed `c` or `d`.
            #
            # ---
            #
            # Note  that it  doesn't matter  that `setline()`  might be  invoked
            # several times, the event is fired only once:
            #
            #     vim9script
            #     setline(1, '')
            #     setline(1, '')
            #     setline(1, '')
            #     au TextChanged * echom 'TextChanged was fired'
            #
            # ---
            #
            # It's not a Vim9 bug.
            # It's not specific to `setline()` (can also be reproduced with `:norm! ii`).
            # `:noa` does not suppress the event here.
            #}}}
            au TextChanged * ++once au TextChanged * ++once RemoveHeadingSpaces()
        else
            # Similar issue if we've expanded forward.{{{
            #
            # Except  that this  time, the  extra  spaces don't  persist in  the
            # buffer, they end up in the unnamed register.
            #}}}
            au TextChanged * ++once au TextChanged * ++once RemoveTrailingSpaces()
        endif
        feedkeys(key, 'in')
        return true
    # if we press `v`, `V` or `C-v` we should leave the submode, and enter visual mode
    elseif index(['v', 'V', "\<c-v>"], key) >= 0
        popup_close(winid)
    elseif key == "\<c-x>"
        exclusive = !exclusive
        popup_settext(winid, PopupGetText())
    elseif key =~ '^\p$'
        UpdateHighlighting(key)
        return true
    endif
    return popup_filter_menu(winid, key)
enddef

def EqualizeBlock() #{{{2
    var shortest: number = jagged_block
        ->mapnew((_, v: dict<number>): number => LineInBlockLength(v))
        ->min()
    var longest: number = jagged_block
        ->mapnew((_, v: dict<number>): number => LineInBlockLength(v))
        ->max()
    if expand_backward
        var n: number = longest - shortest
        for coords in jagged_block
            var pat: string = '\%' .. coords.start_col .. 'c'
            getline(coords.lnum)
                ->substitute(pat, repeat(' ', n), '')
                ->setline(coords.lnum)
        endfor
        var lnum: number = jagged_block[0]['lnum']
        var col: number = jagged_block[0]['end_col'] + longest - shortest
        cursor(lnum, col)
        exe "norm! \<c-v>"
        lnum = jagged_block[-1]['lnum']
        cursor(lnum, col)
        exe 'norm! ' .. (longest == 1 ? '' : (longest - 1) .. 'h')
    else
        for coords in jagged_block
            var n: number = longest - LineInBlockLength(coords)
            var pat: string = '\%' .. coords.end_col .. 'c.\zs'
            getline(coords.lnum)
                ->substitute(pat, repeat(' ', n), '')
                ->setline(coords.lnum)
        endfor
        var lnum: number = jagged_block[0]['lnum']
        var col: number = jagged_block[0]['start_col']
        cursor(lnum, col)
        exe "norm! \<c-v>"
        lnum = jagged_block[-1]['lnum']
        cursor(lnum, col)
        exe 'norm! ' .. (longest == 1 ? '' : (longest - 1) .. 'l')
    endif
enddef

def RemoveTrailingSpaces() #{{{2
    getreginfo('"')
        ->extend({
            regcontents: getreg('"', true, true)
                       ->map((_, v: string): string => v->trim(' ', 2)),
            regtype: 'b1',
        })->setreg('"')
enddef

def RemoveHeadingSpaces() #{{{2
    for coords in jagged_block
        getline(coords.lnum)
            ->substitute('\%' .. coords.start_col .. 'c\s\+', '', '')
            ->setline(coords.lnum)
    endfor
enddef

def GetJaggedBlock(): list<string> #{{{2
    return jagged_block
        ->mapnew((_, v: dict<number>): string =>
                    v.lnum
                    ->getline()
                    ->strpart(v.start_col - 1, v.end_col - v.start_col + 1))
enddef

def PopupGetText(): string #{{{2
    return SHOWMODE .. (exclusive ? '' : ' (inclusive)')
enddef

def ClearJaggedBlock(reinstall_proptype = false, ...l: any) #{{{2
    var lnum_start: number = jagged_block[0]['lnum']
    var lnum_end: number = jagged_block[-1]['lnum']
    prop_clear(lnum_start, lnum_end, {
        bufnr: curbuf,
        type: 'JaggedBlock',
        })
    prop_type_delete('JaggedBlock', {bufnr: curbuf})
    if reinstall_proptype
        prop_type_add('JaggedBlock', {
            bufnr: curbuf,
            highlight: 'Visual'
            })
    endif
enddef
#}}}1
# Utilities {{{1
def Error(msg: string) #{{{2
    echohl ErrorMsg
    echom msg
    echohl NONE
enddef

def LineInBlockLength(coords: dict<number>): number #{{{2
    return getline(coords.lnum)
        ->strpart(coords.start_col - 1, coords.end_col - coords.start_col + 1)
        ->strcharlen()
enddef

def PatToUpdateBlock(key: string, coords: dict<number>): string #{{{2
    var char: string
    var pat: string

    # pattern to undo latest backward exclusive expansion
    if key == 'u' && expand_backward && exclusive
        char = coords.lnum
            ->getline()
            ->strpart(0, coords.start_col - 1)[-1]
        pat = '\%' .. coords.start_col .. 'c.\{-}' .. char
            .. '\zs.*\%' .. coords.end_col .. 'c'

    # pattern to undo latest backward inclusive expansion
    elseif key == 'u' && expand_backward && !exclusive
        char = coords.lnum
            ->getline()
            ->strpart(coords.start_col - 1)[0]
        pat = '.*\%' .. coords.start_col .. 'c.\{-1,}' .. char
            .. '\zs.*\%' .. coords.end_col .. 'c'

    # pattern to undo latest forward expansion, excluding the pressed character
    elseif key == 'u' && !expand_backward && exclusive
        char = coords.lnum
            ->getline()
            ->strpart(coords.end_col - 1)[1]
        pat = '.*\%' .. coords.start_col .. 'c.*'
            .. '\ze.' .. char
            .. '.\{-1,}\%' .. coords.end_col .. 'c'

    # pattern to undo latest forward expansion, including the pressed character
    elseif key == 'u' && !expand_backward && !exclusive
        char = coords.lnum
            ->getline()
            ->strpart(coords.end_col - 1)[0]
        pat = '.*\%' .. coords.start_col .. 'c.*'
            .. char .. '\ze'
            .. '.\{-1,}\%' .. coords.end_col .. 'c'

    # pattern to expand block back to previous occurrence of pressed character, excluding it
    elseif key != 'u' && expand_backward && exclusive
        pat = '.*' .. key .. '\zs' .. '.\{-1,}\%' .. coords.start_col .. 'c'

    # pattern to expand block back to previous occurrence of pressed character, including it
    elseif key != 'u' && expand_backward && !exclusive
        pat = '.*' .. key .. '\zs' .. '.\{-}\%' .. coords.start_col .. 'c'

    # pattern to expand block up to next occurrence of pressed character, excluding it
    elseif key != 'u' && !expand_backward && exclusive
        pat = '.*\%' .. coords.end_col .. 'c' .. '.\{-1,}\ze.' .. key

    # pattern to expand block up to next occurrence of pressed character, including it
    elseif key != 'u' && !expand_backward && !exclusive
        pat = '.*\%' .. coords.end_col .. 'c' .. '.\{-1,}' .. key
    endif

    return pat
enddef

