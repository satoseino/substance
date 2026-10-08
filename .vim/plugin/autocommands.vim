" ----------------------------------------------------------------------------
" Autocommands
" ----------------------------------------------------------------------------
" Set extension name for Bash scripts

augroup ShellScriptFileType
  autocmd!
  autocmd BufRead,BufNewFile *.sh,*.bashrc let b:is_bash = 1 | set filetype=bash
augroup END
" ----------------------------------------------------------------------------
" For Markdown files, show rendered HTML in browser

function! s:SetupMarkdownMappings()
  nnoremap <buffer> <silent> \ll :call <SID>RenderMarkdownFile()<CR>
endfunction

function! s:RenderMarkdownFile()
  let l:curr_file = expand('%:p')

  call system('toolkit-show-md ' . shellescape(l:curr_file) . ' >/dev/null 2>&1')
endfunction

augroup MarkdownShowFile
  autocmd!
  autocmd FileType markdown call s:SetupMarkdownMappings()
augroup END
" ----------------------------------------------------------------------------
