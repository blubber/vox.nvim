local config = require("vox.config")
local utils = require("vox.utils")

local function assert_tables_equal(a, b)
	assert(type(a) == "table" and type(b) == "table", "Can only compare tables")
	assert(#a == #b, string.format("#a (%d) ~= #b (%d)", #a, #b))

	local keys = {}
	for k, _ in pairs(a) do
		keys[k] = true
	end
	for k, _ in pairs(b) do
		keys[k] = true
	end

	for k, _ in pairs(keys) do
		local av = a[k]
		local bv = b[k]

		assert.equal(type(av), type(bv))

		if type(av) == "table" then
			assert_tables_equal(av, bv)
		else
			assert.equal(av, bv)
		end
	end
end

describe("expand_special_chars", function()
	config.setup({
		char_map = {
			["("] = "left paren",
			[")"] = "right paren",
		},
	})

	it("should expand special characters", function()
		local utterances = { { text = "def foo(bar):", source = "line" } }
		local expected = {
			{ text = "def foo", source = "line" },
			{ text = "left paren", source = "line", special = true },
			{ text = "bar", source = "line" },
			{ text = "right paren", source = "line", special = true },
			{ text = ":", source = "line" },
		}

		local result = utils.expand_special_chars(utterances)

		assert_tables_equal(expected, result)
	end)

	it("leaves line without special chars unchanged", function()
		local utterances = { { text = "line without special chars", source = "line" } }
		local result = utils.expand_special_chars(utterances)
		assert_tables_equal(utterances, result)
	end)
end)
