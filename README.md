## Purpose

This plugin lets you select a block of lines with different lengths, then yank/delete/cut it.

## Installation

Using vim-plug:

    Plug 'lacygoill/vim-jagged-block'

## Requirements

Vim 8.2.2324 or higher.

## Usage

Enter visual block mode, select the first column of the block, then press `CTRL-J` to enter the "VISUAL JAGGED BLOCK" mode.  In this mode, press the key matching the character up to which you want the block to be expanded on each line.  You can repeat the expansion by pressing on the same key several times consecutively.  If you press it one too many times, press `u` to undo the latest expansion.  Once your block matches what you want, press `y`, `d` or `c` to resp. yank/delete/cut it.

By default, the expansion ends right before the character you've pressed.  If instead, you want the expansion to include it, press `CTRL-X` while in the "VISUAL JAGGED BLOCK" mode.  This command toggles an inclusive flag on and off.

You can also expand backward.  Before entering the "VISUAL JAGGED BLOCK" mode, make sure your cursor controls the bottom-left or top-left corner of the visual block.

![gif](https://user-images.githubusercontent.com/8505073/106329837-6f72d800-6282-11eb-82ef-4d0144180eaa.gif)

## Customization

You can change the key to enter the "VISUAL JAGGED BLOCK" mode like this:

    xmap <key> <plug>(jagged-block)

