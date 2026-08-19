-- This configuration is intended to be copied to a newly provisioned machine
-- before all editor tooling is installed. Core editing must always start;
-- optional integrations should appear as they become available and explain
-- what is missing without failing startup or flooding the screen.

vim.g.mapleader = " "
vim.g.maplocalleader = " "
vim.opt.relativenumber = true
vim.opt.number = true
vim.opt.termguicolors = false
vim.cmd.colorscheme("vim")
vim.opt.list = true
vim.opt.spelllang = "en_gb"
vim.g.have_nerd_font = true
vim.opt.colorcolumn = "80,100"
vim.opt.signcolumn = "yes"
vim.opt.wrap = false

-- Keep ordinary leading and repeated spaces invisible while still showing
-- tabs, trailing spaces, and non-breaking spaces when 'list' is enabled.
local invisible_space = " "
vim.opt.listchars:append({
	tab = "| ",
	multispace = invisible_space,
	lead = invisible_space,
	trail = "·",
	nbsp = "␣",
})

local config_health = require("config_health")

-- Missing optional tooling should reduce functionality, not prevent Neovim
-- from starting. The same inventory powers :ConfigHealth to avoid drift.
if config_health.neovim_supported() then
	for _, server in ipairs(config_health.language_servers) do
		if
			config_health.lsp_config_available(server.name) and config_health.executable_available(server.executable)
		then
			vim.lsp.enable(server.name)
		end
	end
end

-- gitsigns is useful but optional on a newly provisioned machine. pcall keeps
-- startup usable until the pinned plugin submodules have been initialised.
local gitsigns_ok, gitsigns = pcall(require, "gitsigns")
if gitsigns_ok then
	gitsigns.setup()
end

-- Sidekick provides a Neovim-native terminal for the already authenticated
-- Codex CLI. Next Edit Suggestions are deliberately disabled because they
-- require GitHub Copilot, which is not part of this workstation setup. Keep
-- the existing Tab buffer navigation untouched and expose only explicit AI
-- mappings under <leader>a.
local sidekick_ok, sidekick = pcall(require, "sidekick")
if sidekick_ok then
	sidekick.setup({
		nes = { enabled = false },
		cli = {
			win = {
				keys = {
					-- Keep a single Escape available to Codex for cancelling and
					-- dismissing its UI; a deliberate double Escape returns to
					-- Neovim's Normal mode.
					exit_terminal_mode = {
						"<esc><esc>",
						"stopinsert",
						mode = "t",
						desc = "Exit Sidekick terminal mode",
					},
				},
			},
		},
	})

	vim.keymap.set("n", "<leader>aa", function()
		require("sidekick.cli").toggle({ name = "codex", focus = true })
	end, { desc = "Toggle Sidekick Codex" })
	vim.keymap.set("n", "<leader>af", function()
		require("sidekick.cli").send({ msg = "{file}" })
	end, { desc = "Send file to Sidekick" })
	vim.keymap.set("x", "<leader>av", function()
		require("sidekick.cli").send({ msg = "{selection}" })
	end, { desc = "Send selection to Sidekick" })
	vim.keymap.set({ "n", "x" }, "<leader>ap", function()
		require("sidekick.cli").prompt()
	end, { desc = "Select Sidekick prompt" })
end

require("keymaps")
require("autocmds")
config_health.setup()

vim.api.nvim_create_autocmd("ColorScheme", {
	pattern = "*",
	callback = function()
		vim.api.nvim_set_hl(0, "SignColumn", { bg = "NONE", ctermbg = "NONE" })
	end,
})
