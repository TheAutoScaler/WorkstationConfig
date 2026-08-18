-- Make accidental trailing whitespace obvious when reviewing text, but keep
-- the marker unobtrusive while actively typing. Apply the policy consistently
-- to every split rather than only the window that existed during startup.

local config_health = require("config_health")

vim.api.nvim_set_hl(0, "TrailingWhitespace", { link = "Error" })

-- :match state belongs to a window, so each split needs its own match ID.
-- Saving the ID in vim.w also prevents duplicate matches on repeated entry.
local function add_trailing_whitespace_match()
	if vim.w.trailing_whitespace_match then
		pcall(vim.fn.matchdelete, vim.w.trailing_whitespace_match)
	end

	vim.w.trailing_whitespace_match = vim.fn.matchadd("TrailingWhitespace", [[\s\+$]])
end

add_trailing_whitespace_match()

vim.api.nvim_create_autocmd("WinEnter", {
	callback = add_trailing_whitespace_match,
})

-- Hide the trailing-space glyph while typing so it does not distract at the
-- cursor, then restore the visible error marker on leaving insert mode.
vim.api.nvim_create_autocmd("InsertEnter", {
	callback = function()
		vim.opt.listchars:append({ trail = " " })
		vim.api.nvim_set_hl(0, "TrailingWhitespace", { link = "Whitespace" })
	end,
})

vim.api.nvim_create_autocmd("InsertLeave", {
	callback = function()
		vim.opt.listchars:append({ trail = "·" })
		vim.api.nvim_set_hl(0, "TrailingWhitespace", { link = "Error" })
	end,
})

-- Carry personal spelling additions between machines as readable, reviewable
-- source without committing generated binary state. A fresh clone should gain
-- the same dictionary automatically.

vim.api.nvim_create_autocmd("VimEnter", {
	once = true,
	callback = function()
		local spell_source = vim.fn.stdpath("config") .. "/spell/en.utf-8.add"
		local spell_binary = spell_source .. ".spl"
		local source_modified = vim.fn.getftime(spell_source)

		if source_modified < 0 or vim.fn.getftime(spell_binary) >= source_modified then
			return
		end

		local ok, error_message = pcall(vim.cmd, "silent mkspell! " .. vim.fn.fnameescape(spell_source))
		if not ok then
			config_health.warn_once(
				"spellfile",
				"Neovim config: failed to rebuild the spelling dictionary: " .. tostring(error_message)
			)
		end
	end,
})

-- Keep saved source consistently formatted without risking the user's work.
-- A missing or broken formatter should leave the buffer intact and editing
-- should continue normally on a partially provisioned machine.

local formatters = {
	lua = {
		executable = "stylua",
		command = function(path)
			return { "stylua", "--stdin-filepath", path, "-" }
		end,
	},
	go = {
		executable = "gofmt",
		command = function()
			return { "gofmt" }
		end,
	},
	sh = {
		executable = "shfmt",
		command = function(path)
			return { "shfmt", "--filename", path }
		end,
	},
	markdown = {
		executable = "prettier",
		command = function(path)
			return { "prettier", "--stdin-filepath", path }
		end,
	},
}

local function buffer_text(buffer)
	local text = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
	if vim.bo[buffer].endofline then
		text = text .. "\n"
	end
	return text
end

local function output_lines(output)
	local lines = vim.split(output, "\n", { plain = true })
	if lines[#lines] == "" then
		table.remove(lines)
	end
	return lines
end

vim.api.nvim_create_autocmd("BufWritePre", {
	callback = function()
		local buffer = vim.api.nvim_get_current_buf()
		local formatter = formatters[vim.bo[buffer].filetype]
		if formatter == nil then
			return
		end

		if not config_health.executable_available(formatter.executable) then
			config_health.warn_missing_once(formatter.executable, vim.bo[buffer].filetype .. " formatting")
			return
		end

		local path = vim.api.nvim_buf_get_name(buffer)
		local input = buffer_text(buffer)
		-- Argument arrays avoid invoking a shell with an untrusted filename. stdin
		-- lets the formatter see unsaved buffer contents rather than the old file.
		local result = vim.system(formatter.command(path), { stdin = input, text = true }):wait(10000)

		-- A failed formatter must never destroy or partially replace the buffer.
		-- Warn once per session so repeated saves do not become noisy.
		if result.code ~= 0 then
			local reason = vim.trim(result.stderr or "")
			if reason == "" then
				reason = result.code == 124 and "formatter timed out" or "formatter exited with code " .. result.code
			end
			config_health.warn_once(
				"formatter:" .. formatter.executable,
				("Neovim config: %s failed; buffer was not changed: %s"):format(formatter.executable, reason)
			)
			return
		end

		if result.stdout ~= input then
			-- Preserve the cursor and viewport when replacing formatted contents.
			local view = vim.fn.winsaveview()
			vim.api.nvim_buf_set_lines(buffer, 0, -1, false, output_lines(result.stdout))
			vim.fn.winrestview(view)
		end
	end,
})
