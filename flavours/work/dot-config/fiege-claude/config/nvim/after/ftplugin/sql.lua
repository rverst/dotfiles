-- PostgreSQL / sqlc: 2-space indent, standard SQL line comments
vim.opt_local.tabstop = 2
vim.opt_local.shiftwidth = 2
vim.opt_local.expandtab = true
vim.opt_local.commentstring = '-- %s'
-- Disable extending comment leader on 'o'/'O' in normal mode
vim.opt_local.formatoptions:remove({ 'o' })
