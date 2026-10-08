" ----------------------------------------------------------------------------
" Global mappings
" ----------------------------------------------------------------------------
" Set no highlight until next search

nnoremap <silent> <C-L> :noh<CR>
" ----------------------------------------------------------------------------
" Turn on spell check for the local buffer

nnoremap <F1> :setlocal spell spelllang=en_us<CR>
" ----------------------------------------------------------------------------
" Add Claude Code as co-author

nnoremap \cc :call append(line('.'), ['', 'Co-Authored-By: Claude Code <noreply@anthropic.com>'])<CR>
" ----------------------------------------------------------------------------
" Use NvChad style window navigation

nnoremap <C-h> <C-w><C-h>
nnoremap <C-j> <C-w><C-j>
nnoremap <C-k> <C-w><C-k>
nnoremap <C-l> <C-w><C-l>
" ----------------------------------------------------------------------------
" Use Tab and Shift+Tab to navigate buffers

function! s:IsSourceBuffer(bufnr)
  if !buflisted(a:bufnr)
    return 0
  endif
  if getbufvar(a:bufnr, '&buftype') != ''
    return 0
  endif
  if getbufvar(a:bufnr, '&filetype') ==# 'nerdtree'
    return 0
  endif
  return 1
endfunction

function! s:NavSourceBuffer(dir)
  let l:source_bufs = filter(range(1, bufnr('$')), {_, v -> s:IsSourceBuffer(v)})
  if empty(l:source_bufs)
    return
  endif
  let l:idx = index(l:source_bufs, bufnr('%'))
  let l:n = len(l:source_bufs)
  let l:next = l:source_bufs[(l:idx + a:dir + l:n) % l:n]
  if &buftype !=# ''
    let l:win = s:FindNormalWindow()
    if l:win > 0
      execute l:win . 'wincmd w'
    endif
  endif
  execute 'buffer ' . l:next
endfunction

function! s:FindNormalWindow()
  for l:w in range(1, winnr('$'))
    if getwinvar(l:w, '&buftype') ==# '' && getwinvar(l:w, '&filetype') !=# 'nerdtree'
      return l:w
    endif
  endfor
  return -1
endfunction

nnoremap <silent> <Tab>   :call <SID>NavSourceBuffer(1)<CR>
nnoremap <silent> <S-Tab> :call <SID>NavSourceBuffer(-1)<CR>
" ----------------------------------------------------------------------------
" Echo full file path of the current buffer

nnoremap <silent> \eb :echo expand('%:p')<CR>
" ----------------------------------------------------------------------------
" Wrap words under cursor inside backticks

function! s:WrapInBackticks(boundary_pat) abort
  let l:col = col('.') - 1
  let l:line = getline('.')
  let l:len = len(l:line)

  if l:col >= l:len || l:line[l:col] =~# a:boundary_pat
    return
  endif

  let l:word_start = l:col
  while l:word_start > 0 && l:line[l:word_start - 1] !~# a:boundary_pat
    let l:word_start -= 1
  endwhile

  let l:word_end = l:col
  while l:word_end < l:len - 1 && l:line[l:word_end + 1] !~# a:boundary_pat
    let l:word_end += 1
  endwhile

  let l:new_line = l:line[:l:word_end] . '`' . l:line[l:word_end + 1:]
  let l:new_line = l:word_start > 0
        \ ? l:new_line[:l:word_start - 1] . '`' . l:new_line[l:word_start:]
        \ : '`' . l:new_line
  call setline('.', l:new_line)
endfunction

nnoremap <silent> <leader>wg :call <SID>WrapInBackticks('\s')<CR>
nnoremap <silent> <leader>wl :call <SID>WrapInBackticks('[ \t,.:;]')<CR>
" ----------------------------------------------------------------------------
