vim9 noclear

# Config {{{1

const SHOWMODE: string = '-- VISUAL JAGGED BLOCK --'

# Init {{{1

var curbuf: number
var exclusive: bool = true
var jagged_block: list<dict<number>>
var expand_backward: bool
var popup_bufnr: number

# Interface {{{1
def jaggedBlock#mapping() #{{{2
    expand_backward = col('.') < col('v')
    exe "norm! \e"
    jagged_block = []
    var col1: number = min([virtcol("'<"), virtcol("'>")])
    var col2: number = max([virtcol("'<"), virtcol("'>")])
    for lnum in range(line("'<"), line("'>"))
        var line: string = getline(lnum)
        jagged_block += [{
            lnum: lnum,
            # We can't simply use `col("'<")` and `col("'>")`.{{{
            #
            # They match valid columns on the  first and last line of the visual
            # selection, yes.  But  they do not necessarily  match valid columns
            # on  the  lines  in-between.   Remember that  the  selection  could
            # contain multibyte characters in arbitrary locations.
            #}}}
            start_col: line->matchstr('.*\%' .. col1 .. 'v')->strlen() + 1,
            end_col: line->matchstr('.*\%' .. col2 .. 'v')->strlen() + 1,
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
        ->mapnew((_, v) => LineInBlockLength(v))
        ->min()
    var longest: number = jagged_block
        ->mapnew((_, v) => LineInBlockLength(v))
        ->max()
    if expand_backward
        var n: number = longest - shortest
        for coords in jagged_block
            var pat: string = '\%' .. coords.start_col .. 'c'
            getline(coords.lnum)
                ->substitute(pat, repeat(' ', n), '')
                ->setline(coords.lnum)
        endfor
        var lnum: number = jagged_block[0].lnum
        var col: number = jagged_block[0].end_col + longest - shortest
        cursor(lnum, col)
        exe "norm! \<c-v>"
        lnum = jagged_block[-1].lnum
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
        var lnum: number = jagged_block[0].lnum
        var col: number = jagged_block[0].start_col
        cursor(lnum, col)
        exe "norm! \<c-v>"
        lnum = jagged_block[-1].lnum
        cursor(lnum, col)
        exe 'norm! ' .. (longest == 1 ? '' : (longest - 1) .. 'l')
    endif
enddef

def RemoveTrailingSpaces() #{{{2
    getreginfo('"')
        ->extend({
            regcontents: getreg('"', true, true)
                            ->map((_, v) => v->trim()),
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
    return jagged_block->mapnew((_, v) =>
        v.lnum
        ->getline()
        ->matchstr('\%' .. v.start_col .. 'c.*\%' .. v.end_col .. 'c.')
        )
enddef

def PopupGetText(): string #{{{2
    return SHOWMODE .. (exclusive ? '' : ' (inclusive)')
enddef

def ClearJaggedBlock(reinstall_proptype = false, ...l: any) #{{{2
    var lnum_start: number = jagged_block[0].lnum
    var lnum_end: number = jagged_block[-1].lnum
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
def LineInBlockLength(coords: dict<number>): number #{{{2
    return getline(coords.lnum)
        ->matchstr('\%' .. coords.start_col .. 'c.*\%' .. coords.end_col .. 'c.')
        ->strchars(true)
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

