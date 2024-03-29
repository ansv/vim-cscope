" vim-cscope - cscope helper for vim
"
" Copyright (C) 2019 Andrey Shvetsov
"
" SPDX-License-Identifier: MIT
"
" Install:
"
" If you use junegunn/vim-plug:
" Add to your .vimrc
" Plug 'ansv/vim-cscope'
"
" Take a look at the plugin https://github.com/ansv/vim-supernext
" This helps to walk between quickfix entries.
"
" Hint:
"
" Since this script uses the key mapping <C-g> that must print current
" file name, you may remap <C-l> in your .vimrc to have lost functionality as
" following:
"
" nnoremap <silent> <C-l> <C-l><C-g>

if !has("cscope")
    echo expand('<sfile>:p') . " cannot start:"
    echo "vim is compiled without option '--enable-cscope'"
    finish
endif

if !executable('cscope')
    echo expand('<sfile>:p') . " cannot start:"
    echo "cscope is not installed"
    finish
endif

" use both cscope and ctag for 'ctrl-]', ':ta', and 'vim -t'
set cscopetag

" check cscope for definition of a symbol before checking ctags: set to 1
" if you want the reverse search order.
set csto=0

set cscopequickfix=s-,g-,d-,c-,t-,e-,f-,i-

let s:script = expand('<sfile>:p:r') . '.sh'
let s:dirty = 1
let s:pp = system(s:script . " cs_init")
let s:id = "0"
let s:sid_prev = ""
let s:sid = ""
let s:qf_prev = ""
let s:qf = ""
let s:is_qf_dirty = 0

function! s:scall(cmd, param)
    call system(s:script . ' ' . a:cmd . ' "' . s:pp . '" "' . a:param . '"')
    return !v:shell_error
endfunction

function! s:try_to_reload()
    if !s:scall("cs_is_file_ready", "")
        return
    endif

    let s:dirty = 0
    silent cscope kill -1
    let file = system(s:script . ' cs_get_xref_file "' . s:pp . '/' . s:id . '"')
    let s:id = s:id =~ "0" ? "1" : "0"

    " add dynamic cscope database
    if filereadable(file)
        silent execute "cscope add " . file
    endif

    " add default (static) cscope database
    if filereadable(s:pp . "/cscope.out")
        silent execute "cscope add " . s:pp . "/cscope.out"
    endif
endfunction

function! s:proper_rebuild()
    call s:scall("cs_reset", "")
    call s:rebuild()
endfunction

function! s:rebuild()
    call s:try_to_reload() " get latest good before rebuild
    call s:scall("cs_rebuild", s:id)
    let s:dirty = 1
endfunction

function! s:is_qf_open()
    return filter(getwininfo(), 'v:val.quickfix && !v:val.loclist') != []
endfunction

" close and clear quickfix
function! s:hide_quickfix()
    execute "cclose"
    call setqflist([])
endfunction

nnoremap <silent> <C-g><C-h> :call <SID>hide_quickfix()<CR>
nnoremap <silent> <C-g>h     :call <SID>hide_quickfix()<CR>

function! s:track_project()
    if s:scall("cs_track_project", "")
        call s:rebuild()
    endif
endfunction

function! s:track_file(name)
    let name = a:name
    if empty(name)
        let name = expand("%")
    endif
    if s:scall("cs_track_file", name)
        call s:rebuild()
    endif
endfunction

function! s:cscope_find(cmd)
    if s:dirty == 1
        call s:try_to_reload()
        if s:dirty == 1
            echo "cscope: updating database, results may be incomplete"
        else
            echo
        endif
    endif
    try
        silent execute "cscope find " . a:cmd
        return 1
    catch /^Vim\%((\a\+)\)\=:E259:/
    catch /^Vim\%((\a\+)\)\=:E567:/
    endtry
    call s:hide_quickfix()
    return 0
endfunction

function! s:push_qf(qf, sid)
    let s:qf_prev = s:qf
    let s:sid_prev = s:sid
    let s:qf = a:qf
    let s:sid = a:sid
endfunction

function! s:show_qf(qf, sid, wnr, temp_qf_entry)
    call setqflist(a:qf, 'r')
    let len = len(a:qf)
    if len > 33
        "execute "cclose \| vertical botright copen \| vertical resize 100"
        execute "copen \| wincmd L"
    else
        execute "copen \| wincmd J \| resize " . (len + 1)
    endif
    call clearmatches()
    call matchadd("cscope_finding", a:sid)
    execute a:wnr . "wincmd w"
    let s:is_qf_dirty = a:temp_qf_entry
endfunction

function! s:quickfix_list(cmd, id, sid)
    let wnr = winnr()
    let fname = bufname(bufnr())
    let lnum = line(".")
    let home_row = fname . ":" . lnum  . ":" . col(".")

    if !s:cscope_find(a:cmd . " " . a:id)
        return
    endif

    " list of current source lines; may be empty
    let fqf = filter(getqflist(), {idx, val -> bufname(val.bufnr) == fname && val.lnum == lnum})

    " add home row to the quickfix
    :caddexpr home_row . ":" . (len(fqf) == 1 ? fqf[0].text : "<<source line>>")

    " create quickfix item
    let qf = getqflist()
    let item = remove(qf, -1)

    if len(fqf) == 1
        " an item with the same content will be inserted to the home row;
        " remove an equivalent from the original place
        let qf = filter(qf, {idx, val -> bufname(val.bufnr) != fname || val.lnum != lnum})
    endif

    " insert item with the home row
    call insert(qf, item, 0)

    call s:push_qf(qf, a:sid)
    call s:show_qf(qf, a:sid, wnr, 0)
    execute "cfirst"
endfunction

function! s:goto_def()
    let wnr = winnr()
    let id = expand("<cword>")

    if !s:cscope_find("g " . id)
        return
    endif

    let sid = '\<' . id . '\>'
    call s:show_qf(getqflist(), sid, wnr, 1)
    if len(getqflist()) == 1
        call setqflist([])
        execute "cclose"
    endif
endfunction

" goto global [D]efinition
nnoremap <silent> <C-g><C-d> :call <SID>goto_def()<CR>
nnoremap <silent> <C-g>d     :call <SID>goto_def()<CR>
nnoremap <silent> g<C-d>     :call <SID>goto_def()<CR>

function! s:find_token_refs()
    let id = expand("<cword>")
    call s:quickfix_list("s", id, '\<' . id . '\>')
endfunction

" find all refs to the token (Definition + Usages)
nnoremap <silent> <C-g><C-g> :call <SID>find_token_refs()<CR>
nnoremap <silent> <C-g>g     :call <SID>find_token_refs()<CR>

function! s:switch_qf()
    let wnr = winnr()
    if !s:is_qf_dirty && s:is_qf_open() && !empty(s:sid_prev)
        call s:push_qf(s:qf_prev, s:sid_prev)
    endif
    if !empty(s:sid)
        call s:show_qf(s:qf, s:sid, wnr, 0)
    endif
endfunction

nnoremap <silent> <C-g><C-z> :call <SID>switch_qf()<CR>
nnoremap <silent> <C-g>z :call <SID>switch_qf()<CR>

function! s:find_text()
    let str = input("find text: ")
    if str != ''
        call s:quickfix_list("t", str, str)
    endif
endfunction

" find all instances of the [T]ext
nnoremap <silent> <C-g><C-t> :call <SID>find_text()<CR>
nnoremap <silent> <C-g>t     :call <SID>find_text()<CR>

function! s:find_files()
    let str = input("find files with the name part: ")
    if str != ''
        call s:quickfix_list("f", str, str)
    else
        call s:quickfix_list("f", "/", "")
    endif
endfunction

" find [F]iles
nnoremap <silent> <C-g><C-f> :call <SID>find_files()<CR>
nnoremap <silent> <C-g>f     :call <SID>find_files()<CR>

function! s:on_write()
    if s:scall("cs_is_file_tracked", expand("%:p"))
        call s:rebuild()
    endif
endfunction

au BufWritePost * call <SID>on_write()

command! CScopeRebuild
    \ call s:proper_rebuild()
command! CScopeTrackProject
    \ call s:track_project()
command! -nargs=? -complete=file CScopeTrackFile
    \ call s:track_file(<q-args>)

call s:rebuild()
highlight cscope_finding ctermfg=yellow guifg=yellow
