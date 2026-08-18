-- Centralise the assumptions this configuration makes about its environment.
-- The goal is for the same config to work during and after provisioning: core
-- editing remains available, optional features activate only when ready, and
-- one quiet warning points to a complete, actionable health report.

local M = {}

-- Keep server names and their required commands together. init.lua consumes
-- this same table, so enabling a server and checking it cannot diverge.
M.language_servers = {
	{ name = "gopls", executable = "gopls" },
	{ name = "ruff", executable = "ruff" },
	{ name = "pyright", executable = "pyright-langserver" },
	{ name = "terraformls", executable = "terraform-ls" },
	{ name = "golangci_lint_ls", executable = "golangci-lint-langserver" },
	{ name = "marksman", executable = "marksman" },
	{ name = "ts_ls", executable = "typescript-language-server" },
	{ name = "eslint", executable = "vscode-eslint-language-server" },
}

local dependencies = {
	plugins = {
		{
			name = "nvim-lspconfig",
			available = function()
				return #vim.api.nvim_get_runtime_file("lsp/gopls.lua", false) > 0
			end,
		},
		{ name = "gitsigns.nvim", module = "gitsigns" },
	},
	executables = {
		-- Include both direct tools and secondary commands used behind an LSP.
		-- An LSP executable can exist while its underlying runtime is absent.
		{ name = "stylua", feature = "Lua formatting" },
		{ name = "gofmt", feature = "Go formatting" },
		{ name = "shfmt", feature = "shell formatting" },
		{ name = "prettier", feature = "Markdown formatting" },
		{ name = "git", feature = "Git integration" },
		{ name = "node", feature = "TypeScript and ESLint language servers" },
		{ name = "tsc", feature = "TypeScript language server" },
		{ name = "eslint", feature = "ESLint language server" },
		{ name = "terraform", feature = "Terraform language server" },
		{ name = "golangci-lint", feature = "golangci-lint language server" },
	},
}

local warned = {}

local function plugin_available(plugin)
	if plugin.available then
		return plugin.available()
	end

	return pcall(require, plugin.module)
end

function M.executable_available(name)
	return vim.fn.executable(name) == 1
end

function M.neovim_supported()
	local version = vim.version()
	return version.major > 0 or version.minor >= 11
end

-- Neovim cannot determine which font the terminal selected, but confirming
-- that a Nerd Font is installed catches the common fresh-machine failure.
local function nerd_font_available()
	local font_directories = vim.fn.has("mac") == 1 and { "~/Library/Fonts", "/Library/Fonts", "/System/Library/Fonts" }
		or { "~/.local/share/fonts", "~/.fonts", "/usr/local/share/fonts", "/usr/share/fonts" }

	for _, directory in ipairs(font_directories) do
		local expanded_directory = vim.fn.expand(directory)
		if vim.fn.isdirectory(expanded_directory) == 1 then
			local matches = vim.fn.globpath(expanded_directory, "**/*NerdFont*", false, true)
			if #matches > 0 then
				return true
			end
		end
	end

	return false
end

local function clipboard_available()
	-- pbcopy is built into macOS. Retain viable providers for the portable Linux
	-- subset of these dotfiles rather than reporting a macOS-only requirement.
	if vim.fn.has("mac") == 1 then
		return M.executable_available("pbcopy")
	end

	return vim.fn.has("clipboard") == 1
		or M.executable_available("wl-copy")
		or M.executable_available("xclip")
		or M.executable_available("xsel")
end

function M.lsp_config_available(name)
	return #vim.api.nvim_get_runtime_file("lsp/" .. name .. ".lua", false) > 0
end

function M.warn_once(key, message)
	-- Missing tools and failed formatters may be encountered repeatedly. One
	-- warning per session is actionable without turning every save into noise.
	if warned[key] then
		return
	end

	warned[key] = true
	vim.notify(message, vim.log.levels.WARN)
end

function M.warn_missing_once(name, feature)
	M.warn_once("missing:" .. name, ("Neovim config: skipped %s; %q is not on PATH"):format(feature, name))
end

function M.missing()
	-- Return data rather than displaying it here so startup and :ConfigHealth
	-- present the same result in different levels of detail.
	local missing = {}

	if not M.neovim_supported() then
		local version = vim.version()
		table.insert(
			missing,
			("Neovim 0.11 or newer (found %d.%d.%d)"):format(version.major, version.minor, version.patch)
		)
	end

	if vim.g.have_nerd_font and not nerd_font_available() then
		table.insert(missing, "Nerd Font installation")
	end

	if not clipboard_available() then
		table.insert(missing, vim.fn.has("mac") == 1 and "clipboard provider: pbcopy" or "clipboard provider")
	end

	for _, server in ipairs(M.language_servers) do
		if not M.lsp_config_available(server.name) then
			table.insert(missing, ("LSP config: %s"):format(server.name))
		end
		if not M.executable_available(server.executable) then
			table.insert(missing, ("LSP executable: %s (%s)"):format(server.executable, server.name))
		end
	end

	for _, plugin in ipairs(dependencies.plugins) do
		if not plugin_available(plugin) then
			table.insert(missing, ("plugin: %s"):format(plugin.name))
		end
	end

	for _, executable in ipairs(dependencies.executables) do
		if not M.executable_available(executable.name) then
			table.insert(missing, ("executable: %s (%s)"):format(executable.name, executable.feature))
		end
	end

	return missing
end

function M.report()
	local missing = M.missing()
	local lines = { "Neovim configuration health" }

	if #missing == 0 then
		table.insert(lines, "All automatically checked assumptions are satisfied.")
	else
		table.insert(lines, ("Unsatisfied assumptions (%d):"):format(#missing))
		for _, dependency in ipairs(missing) do
			table.insert(lines, "  - " .. dependency)
		end
	end

	table.insert(lines, "Manual check: terminal sends Option as Meta for Alt-key mappings.")
	-- Terminal key translation cannot be observed until the user presses a key,
	-- so keep this informational and never fail an otherwise healthy report.

	vim.notify(table.concat(lines, "\n"), #missing == 0 and vim.log.levels.INFO or vim.log.levels.WARN)
end

function M.setup()
	vim.api.nvim_create_user_command("ConfigHealth", M.report, {
		desc = "Check optional Neovim configuration dependencies",
	})

	local missing = M.missing()
	if #missing == 0 then
		return
	end

	-- Retain the complete diagnosis in :messages, but show only one short
	-- notification after startup rather than one warning per missing tool.
	local history_lines = { "Neovim config has unsatisfied assumptions:" }
	for _, dependency in ipairs(missing) do
		table.insert(history_lines, "  - " .. dependency)
	end
	vim.api.nvim_echo({ { table.concat(history_lines, "\n"), "WarningMsg" } }, true, {})

	vim.schedule(function()
		vim.notify(
			("Neovim config: %d assumptions unsatisfied; run :ConfigHealth"):format(#missing),
			vim.log.levels.WARN
		)
	end)
end

return M
