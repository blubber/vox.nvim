local log = require("vox.dev").log
local config = require("vox.config")
local utils = require("vox.utils")

local M = {}

local mode = "n"
local cursor_pos = { 1, 0 }
local scheduled_utterances = {}
local scheduled_utterances_timer = nil

local function dispatch_utterances()
	config.get("backend"):speak(scheduled_utterances)
	scheduled_utterances = {}
end

local function schedule_utterances(utterances)
	if #utterances == 0 then
		return
	end

	for _, u in ipairs(utterances) do
		table.insert(scheduled_utterances, u)
	end

	if scheduled_utterances_timer ~= nil then
		vim.fn.timer_stop(scheduled_utterances_timer)
	end

	scheduled_utterances_timer = vim.fn.timer_start(config.get("wait_time"), function()
		scheduled_utterances_timer = nil
		dispatch_utterances()
	end)
end

local function flatten(t)
	if type(t) ~= "table" then
		return t
	end

	local result = {}
	for _, v in ipairs(t) do
		if type(v) == "table" then
			local tt = flatten(v)
			for _, e in ipairs(tt) do
				table.insert(result, e)
			end
		else
			table.insert(result, v)
		end
	end

	return result
end

local function get_virt_texts(start, last)
	local extmarks = vim.api.nvim_buf_get_extmarks(
		0,
		-1,
		{ start, 0 },
		{ last, 1000 },
		{ type = "virt_text", details = true }
	)

	local virt_texts = {}
	for _, vt in ipairs(extmarks) do
		table.insert(virt_texts, vt[4]["virt_text"])
	end

	return flatten(virt_texts)
end

local function handle_event(event)
	if event.type == "ModeChanged" then
		local modes = config.get("modes") or {}
		return { { text = modes[event.new_mode], source = "meta", event = event } }
	else
		if event.type == "CursorMoved" then
			local new_cursor_pos = event.new_cursor_pos

			if new_cursor_pos[1] ~= event.old_cursor_pos[1] then
				local lines = vim.api.nvim_buf_get_lines(0, new_cursor_pos[1] - 1, new_cursor_pos[1], false)
				local virt_texts = get_virt_texts(new_cursor_pos[1] - 1, new_cursor_pos[1] - 1)

				local utterances = {
					{ text = string.format("%d", event.new_cursor_pos[1]), source = "lnum", event = event },
					{ text = lines[1], source = "line", event = event },
				}

				for _, vt in ipairs(virt_texts) do
					if string.match(vt, "^%s*@") == nil then -- Don't speak indent guides
						table.insert(utterances, { text = vt, source = "virt_text", event = event })
					end
				end

				return utterances
			end
		end
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

	local cursor_moved_timer = nil
	vim.api.nvim_create_autocmd("CursorMoved", {
		group = group,
		callback = function()
			if cursor_moved_timer ~= nil then
				cursor_moved_timer = vim.fn.timer_stop(cursor_moved_timer)
			end

			cursor_moved_timer = vim.fn.timer_start(config.get("wait_time"), function()
				local new_cursor_pos = vim.api.nvim_win_get_cursor(0)
				if new_cursor_pos[1] ~= cursor_pos[1] or new_cursor_pos[2] ~= cursor_pos[2] then
					local old_cursor_pos = cursor_pos
					cursor_pos = new_cursor_pos

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

	vim.api.nvim_create_user_command("Vox", function()
		M.schedule_utterances({ { text = "Test command", source = "line" } })
	end, { range = true })

	log.debug("Vox setup done")
end

M.schedule_utterances = function(utterances)
	if utterances == nil or #utterances == 0 then
		return
	end

	local final_utterances = {}
	for _, utterance in ipairs(utterances) do
		utterance.text = string.gsub(utterance.text or "", "^%s*(.-)%s*$", "%1")
		if utterance.text ~= "" then
			table.insert(final_utterances, utterance)
		end
	end

	local postprocess = config.get("postprocess")
	if postprocess ~= nil then
		final_utterances = postprocess(final_utterances)
	end

	schedule_utterances(utils.expand_special_chars(final_utterances))
end

return M
