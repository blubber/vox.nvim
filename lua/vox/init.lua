local ts_utils = require("nvim-treesitter.ts_utils")

local M = {}

local uv = vim.loop

local state = {
	opts = {},
	cursor_pos = {},
	augroup = nil,
	cursor_moved_timer = uv.new_timer(),
	suspend = false,
	enabled = true,
}

local function defaults()
	return {
		mappings = {
			["'"] = " single quote",
			['"'] = "double quote",
			["["] = "bracker",
			["]"] = "bracker",
			["("] = "parenthesis",
			[")"] = "parenthesis",
			["<"] = "angle",
			[">"] = "angle",
			["{"] = "brace",
			["}"] = "brace",
			["="] = "equals",
			["."] = "dot",
		},
		whitespace = {
			[" "] = "space",
			["\n"] = "newline",
			["\t"] = "tab",
		},
		modes = {
			["R"] = "replace",
			["S"] = "select line",
			["V"] = "visual line",
			["\19"] = "select block",
			["\22"] = "visual block",
			["c"] = "command",
			["i"] = "insert",
			["n"] = "normal",
			["s"] = "select",
			["t"] = "terminal",
			["v"] = "visual",
		},

		cursor_moved_debounce = 150,
		on_row_changed = { "row", "line", "diagnostics" },
		on_col_changed = { "character" },
		on_mode_changed = { "mode" },
		on_buf_read = { M.say("Open"), "filename" },
		on_buf_delete = { M.say("Close"), "filename" },
		on_buf_write = { M.say("Save"), "filename" },
		on_buf_enter = { M.filename },
		backend = nil,
	}
end

local function get_cursor_pos()
	local row, col = unpack(vim.api.nvim_win_get_cursor(0))
	return { row = row, col = col }
end

local function get_ts_node_text_under_cursor()
	local node = ts_utils.get_node_at_cursor()
	if not node then
		return nil
	end

	local bufnr = vim.api.nvim_get_current_buf()
	local text = vim.treesitter.get_node_text(node, bufnr)

	return text
end

local function split_by_delimiters(line)
	local result = {}
	local pos = 1
	local current_type = nil
	local buf = ""

	local open = "({[<"
	local close = ")]}>"

	while pos <= #line do
		local char = line:sub(pos, pos)
		local char_type = "text"

		if string.find(open, char, 1, true) ~= nil then
			char_type = "open"
		elseif string.find(close, char, 1, true) ~= nil then
			char_type = "close"
		end

		if char_type ~= current_type and #buf > 0 then
			table.insert(result, { type = current_type, content = buf })
			buf = ""
		end

		current_type = char_type
		buf = buf .. char

		pos = pos + 1
	end

	if #buf > 0 then
		table.insert(result, { type = current_type, content = buf })
	end

	return result
end

local function expand(line)
	local s = line
	for _, pair in ipairs(state.mappings) do
		local key, value = unpack(pair)
		s = string.gsub(s, key, value)
	end

	return s
end

local function list_line_diagnostics()
	local bufnr = vim.api.nvim_get_current_buf()
	local row = vim.api.nvim_win_get_cursor(0)[1] - 1

	local diags = vim.diagnostic.get(bufnr, { lnum = row })

	return diags
end

function M.setup(opts)
	state.opts = vim.tbl_deep_extend("force", defaults(), opts or {})

	state.cursor_pos = get_cursor_pos()
	state.augroup = vim.api.nvim_create_augroup("VoxAugroup", { clear = true })

	-- Prepare mappings for expand()
	local keys = {}
	for k in pairs(state.opts.mappings) do
		table.insert(keys, k)
	end

	table.sort(keys, function(a, b)
		return #a > #b
	end)

	state.mappings = {}
	for _, k in ipairs(keys) do
		local escaped_key = (string.gsub(k, "([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"))
		local value = string.format(" %s ", state.opts.mappings[k])
		table.insert(state.mappings, { escaped_key, value })
	end

	vim.api.nvim_create_autocmd("CursorMoved", {
		group = state.augroup,
		pattern = "*", -- apply to all buffers
		callback = function()
			local cursor_pos = get_cursor_pos()
			local delta = {
				row = cursor_pos.row - state.cursor_pos.row,
				col = cursor_pos.col - state.cursor_pos.col,
			}

			if delta.row ~= 0 or delta.col ~= 0 then
				state.cursor_pos = cursor_pos

				state.cursor_moved_timer:stop()
				state.cursor_moved_timer:start(
					state.opts.cursor_moved_debounce,
					0,
					vim.schedule_wrap(function()
						if state.suspend then
							state.suspend = false
							return
						end

						if delta.row ~= 0 then
							M.speak(state.opts.on_row_changed)
						elseif delta.col ~= 0 then
							M.speak(state.opts.on_col_changed)
						end
					end)
				)
			end
		end,
	})

	vim.api.nvim_create_autocmd("ModeChanged", {
		group = state.augroup,
		pattern = "*",
		callback = function(ev)
			if state.suspend then
				state.suspend = false
				return
			end

			local old_mode, new_mode = ev.match:match("([^:]+):([^:]+)")
			if old_mode ~= new_mode then
				M.speak(state.opts.on_mode_changed)
			end
		end,
	})

	local commands = {
		["BufReadPost"] = "on_buf_red",
		["BufWritePost"] = "on_buf_write",
		["BufDelete"] = "on_buf_delete",
		["BufEnter"] = "on_buf_enter",
	}

	for event, name in pairs(commands) do
		vim.api.nvim_create_autocmd(event, {
			group = state.augroup,
			pattern = "*",
			callback = function()
				if state.suspend then
					state.suspend = false
					return
				end

				local utterances = state.opts[name]
				M.speak(utterances)
			end,
		})
	end

	vim.api.nvim_create_user_command("Vox", function(cmdopts)
		local arg = cmdopts.args ~= "" and cmdopts.args or "toggle"

		if arg == "toggle" then
			state.enabled = not state.enabled
		elseif arg == "enable" then
			state.enabled = true
		elseif arg == "disable" then
			state.enabled = false
		elseif arg == "stop" then
			M.stop()
		end
	end, {
		nargs = "?",
		complete = function(_, _, _)
			return { "stop", "enable", "disable", "toggle" }
		end,
	})

	vim.api.nvim_create_user_command("VoxSpeak", function(cmdopts)
		local arg = cmdopts.args ~= "" and cmdopts.args or "line"

		if arg == "line" then
			M.speak(M.line())
		elseif arg == "row" then
			M.speak(M.row())
		elseif arg == "col" then
			M.speak(M.col())
		elseif arg == "word" then
			M.speak(M.word())
		elseif arg == "node" then
			M.speak(M.node())
		elseif arg == "diag" then
			M.speak(M.diagnostics())
		elseif arg == "mode" then
			M.speak(M.mode())
		elseif arg == "filename" or arg == "file" then
			M.speak(M.filename())
		end
	end, {
		nargs = "?", -- optional single argument
		range = true,
		complete = function(_, _, _)
			return { "line", "row", "col", "word", "token", "diag", "mode", "filename", "file" }
		end,
	})
end

function M.suspend()
	state.suspend = true
end

function M.stop()
	M.speak({ source = "line", content = "" })
end

local function is_utterance(value)
	if type(value) == "table" then
		return value.source ~= nil and value.content ~= nil
	end

	return false
end

local function flatten(list)
	if is_utterance(list) then
		return { list }
	end

	local result = {}

	for _, value in ipairs(list) do
		if type(value) == "function" then
			value = value()
		elseif type(value) == "string" then
			local func = M[value]
			value = func()
		end

		if is_utterance(value) then
			result[#result + 1] = value
		elseif type(value) == "table" then
			for _, nested_value in ipairs(flatten(value)) do
				result[#result + 1] = nested_value
			end
		end
	end

	return result
end

function M.speak(utterances)
	if utterances == nil or vim.tbl_isempty(utterances) or not state.enabled then
		return
	end

	utterances = flatten(utterances)

	state.opts.backend.speak(utterances)
end

function M.row()
	return { source = "linenr", content = string.format("%d", state.cursor_pos.row) }
end

function M.col()
	return { source = "linenr", content = string.format("%d", state.cursor_pos.col + 1) }
end

function M.line()
	local line = vim.api.nvim_get_current_line()
	local parts = split_by_delimiters(line)

	local utterances = {}
	for _, part in ipairs(parts) do
		local source = "line"

		if part.type == "open" then
			source = "special.open"
		elseif part.type == "close" then
			source = "special.close"
		end

		table.insert(utterances, { source = source, content = expand(part.content) })
	end

	return utterances
end

function M.word()
	local word = vim.fn.expand("<cword>")
	return { source = "line", content = word }
end

function M.node()
	local node = get_ts_node_text_under_cursor()
	return { source = "line", content = node }
end

function M.character()
	local col = state.cursor_pos.col + 1
	local line = vim.api.nvim_get_current_line()
	local char = line:sub(col, col)

	char = state.opts.whitespace[char] or char

	return { source = "line", content = char }
end

function M.diagnostics()
	local utterances = {}
	local diagnostics = list_line_diagnostics()

	for _, d in ipairs(diagnostics) do
		local severity = d.severity and vim.diagnostic.severity[d.severity] or ""
		utterances[#utterances + 1] = { source = "diagnostic", content = string.format("%s %s", severity, d.message) }
	end

	return utterances
end

function M.mode()
	local mode = vim.fn.mode()
	local mode_name = state.opts.modes[mode]

	if mode_name then
		return { source = "line", content = mode_name }
	else
		return { source = "line", content = string.format("Mode %s", mode) }
	end
end

function M.filename()
	local filepath = vim.api.nvim_buf_get_name(0)

	if filepath == "" then
		return { source = "line", content = "Unknown file" }
	end

	local cwd = vim.fn.getcwd()

	if string.sub(filepath, 1, #cwd) == cwd then
		local relative_path = string.sub(filepath, #cwd + 2)
		return { source = "line", content = expand(relative_path) }
	else
		return { source = "line", content = expand(filepath) }
	end
end

function M.say(content)
	return function()
		return { source = "line", content = content }
	end
end

return M
