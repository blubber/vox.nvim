local log = require("vox2.dev").log
local config = require("vox2.config")

local M = {}

local cursor_pos = { 1, 0 }
local mode = "n"
local scheduled_utterances = {}
local mode_names = {
	n = "Normal",
	v = "Visual",
	V = "Line visual",
	c = "Command",
}

local function dispatch_utterances()
	for _, u in ipairs(scheduled_utterances) do
		log.trace("Dispatching utterance:", u)
	end

	scheduled_utterances = {}
end

local function handle_event(event)
	log.debug("Handling event", event)

	if event.type == "ModeChanged" then
		return { { text = mode_names[event.new_mode], source = "text" } }
	end

	return {}
end

local function dispatch_event(event)
	local handler = config.get("event_handler")

	if handler ~= nil then
		return handler(event, handle_event)
	else
		return handle_event(event)
	end
end

local function setup_autocmds()
	local group = vim.api.nvim_create_augroup("vox", { clear = true })

	local cursor_moved_counter = 0
	vim.api.nvim_create_autocmd("CursorMoved", {
		group = group,
		callback = function()
			cursor_moved_counter = cursor_moved_counter + 1

			vim.schedule(function()
				cursor_moved_counter = cursor_moved_counter - 1

				local new_cursor_pos = vim.api.nvim_win_get_cursor(0)
				if
					cursor_moved_counter == 0
					and (new_cursor_pos[1] ~= cursor_pos[1] or new_cursor_pos[2] ~= cursor_pos[2])
				then
					local old_cursor_pos = cursor_pos
					cursor_pos = new_cursor_pos

					log.trace("Cursor moved to", cursor_pos)

					local utterances = dispatch_event({
						type = "CursorMoved",
						old_cursor_pos = old_cursor_pos,
						new_cursor_pos = new_cursor_pos,
					})
					M.schedule_utterances(utterances)
				end
			end)
		end,
	})

	local mode_changed_counter = 0

	vim.api.nvim_create_autocmd("ModeChanged", {
		group = group,
		callback = function()
			mode_changed_counter = mode_changed_counter + 1
			local new_mode = vim.v.event.new_mode

			vim.schedule(function()
				mode_changed_counter = mode_changed_counter - 1

				if mode_changed_counter == 0 and new_mode ~= mode then
					local old_mode = mode
					mode = new_mode

					log.trace("Switch mode to", mode)

					local utterances = handle_event({
						type = "ModeChanged",
						old_mode = old_mode,
						new_mode = mode,
					})
					M.schedule_utterances(utterances)
				end
			end)
		end,
	})
end

M.setup = function(user_config)
	log.trace("setup")

	config.setup(user_config)

	setup_autocmds()

	vim.api.nvim_create_user_command("Vox2", function()
		log.debug("COMMAND")
	end, { range = true })

	log.debug("Vox setup done")
end

M.schedule_utterances = function(utterances)
	log.debug("Potentially scheduling", #utterances, "utterances")
	local postprocess = config.get("postprocess")

	for _, u in ipairs(utterances) do
		if u.text == nil then
			goto continue
		end

		u = vim.tbl_extend("force", {
			rate = 1.0,
			pitch = 1.0,
			volume = 1.0,
			channel = 0,
			text = "",
		}, u)

		u.text = string.gsub(u.text or "", "^%s*(.-)%s*$", "%1")
		if u.text == "" then
			goto continue
		end

		if postprocess then
			u = postprocess(u)
		end

		table.insert(scheduled_utterances, u)
		if #scheduled_utterances == 1 then
			vim.schedule(function()
				dispatch_utterances()
			end)
		end

		::continue::
	end
end

return M
