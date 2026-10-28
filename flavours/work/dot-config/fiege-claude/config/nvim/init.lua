-- init.lua
-- This is the entry point of the configuration.
-- Most of the configuration is done via runtimepath loading of lua files.
--

-- Set leader and localleader
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- expect a nerd font to be installed
vim.g.have_nerd_font = true

-- Disable netrw (using oil.nvim / neo-tree instead)
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- Clipboard over OSC 52: the forwarded $TMUX points at the host tmux socket,
-- which does not exist in the container. Terminals mostly refuse OSC 52 reads,
-- so paste returns the unnamed register; paste from the host with Cmd-V.
local osc52 = require("vim.ui.clipboard.osc52")
local function paste()
	return { vim.fn.split(vim.fn.getreg(""), "\n"), vim.fn.getregtype("") }
end
vim.g.clipboard = {
	name = "OSC 52",
	copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
	paste = { ["+"] = paste, ["*"] = paste },
}
vim.opt.clipboard = "unnamedplus"

-- Install `lazy.nvim` plugin manager
-- See `:help lazy.nvim.txt` or https://github.com/folke/lazy.nvim for more info
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
	local lazyrepo = "https://github.com/folke/lazy.nvim.git"
	-- clocker forwards git into the workspace container when the cwd is under
	-- /workspace; a cwd outside it keeps the clone in this container.
	vim.fn.mkdir(vim.fn.stdpath("data"), "p")
	local out = vim.system(
		{ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath },
		{ cwd = vim.fn.stdpath("data"), text = true }
	):wait()

	if out.code ~= 0 then
		error("Error cloning lazy.nvim:\n" .. (out.stderr or ""))
		return
	end
end

-- Add the plugin to the runtimepath
---@diagnostic disable-next-line: undefined-field
vim.opt.rtp:prepend(lazypath)

-- Set up lazy and load the plugins from ./lua/plugins/...
-- Config for plugins might live in ./lua/rv/config/...
-- for easy reloading of the configuration (source %)
require("lazy").setup({ import = "rv.plugins" }, {
	change_detection = { notify = true },
	lockfile = vim.fn.stdpath("data") .. "/lazy-lock.json",
	-- lazy clones plugins from the nvim cwd; under /workspace that clone is
	-- forwarded to the workspace container, so missing plugins install only
	-- when nvim starts outside it:
	--   cd ~ && nvim --headless "+Lazy! install" +qa
	install = { missing = not vim.startswith(vim.uv.cwd() .. "/", "/workspace/") },
})
