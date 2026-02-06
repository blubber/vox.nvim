local M = {}

local state = {
	enabled = true,
    o = false,
	last_display = nil,
	augroup = nil,
}

function M.setup(vox)
	local ok, _ = pcall(require, "telescope")
	if not ok then
		return M
	end

	state.augroup = vim.api.nvim_create_augroup("VoxTelescopeAugroup", { clear = true })

	vim.api.nvim_create_autocmd("User", {
		group = state.augroup,
		pattern = "TelescopeFindPre",
		callback = function()
			state.last_display = nil
			vim.schedule(function()
				M._attach_to_picker(vox)
			end)
		end,
	})

	return M
end

function M._attach_to_picker(vox)
	local action_state = require("telescope.actions.state")
	local actions = require("telescope.actions")
    local action_set = require("telescope.actions.set")

	local function speak_selection()
		if not state.enabled then
			return
		end

		local entry = action_state.get_selected_entry()
		if not entry then
			return
		end

		local display = entry.display
		if type(display) == "function" then
			display = display(entry)
		end

		if display and display ~= state.last_display then
			state.last_display = display
			vox.speak({ { source = "line", content = display } })
		end
	end

	actions.move_selection_next:replace( function(prompt_bufnr)
        action_set.shift_selection(prompt_bufnr, 1)
		vim.schedule(speak_selection)
	end)

	actions.move_selection_previous:replace(function(prompt_bufnr)
        action_set.shift_selection(prompt_bufnr, -1)
		vim.schedule(speak_selection)
	end)

	vim.defer_fn(function()
    speak_selection()
end, 50)
end

function M.enable()
	state.enabled = true
end

function M.disable()
	state.enabled = false
end

return M
