# Development Guide for vox.nvim

Guidelines for agentic coding assistants working on this Neovim plugin.

## Project Overview

`vox.nvim` is a Neovim plugin that announces editor state changes (cursor position, mode, diagnostics, etc.) for accessibility. Written in pure Lua with `plenary.nvim` dependency.

## Commands

### Linting

```bash
lua -l lua/vox/init.lua
nvim --headless -c "lua require('vox')" -c "q"
```

### Testing

```bash
nvim --noplugin -u init.lua
```

Commands:
```vim
:lua require('vox').setup()
:VoxSpeak line
:checkhealth vox
```

### Development Reload

```vim
:lua package.loaded['vox'] = nil; require('vox')
```

## Code Style

### General Principles

- Write clear, self-documenting code
- Prefer readability over clever optimizations
- Keep functions focused on a single responsibility
- Use descriptive names

### Formatting

- Use **tabs** for indentation
- No trailing whitespace
- Max line length: 100 characters
- Blank line between function definitions

### Imports

```lua
local uv = vim.loop
local Path = require 'plenary.path'
local backend = require 'vox.voxd_backend'
```

### Naming Conventions

| Type | Convention | Examples |
|------|-----------|----------|
| Module | `local M = {}` | `local M = {}` |
| Functions | `snake_case` | `get_cursor_pos()` |
| Variables | `snake_case` | `cursor_pos`, `bufnr` |
| Constants | `UPPER_SNAKE` | `LINENR`, `DEFAULT_ROUTING` |
| Private | `_private_func()` | `_is_utterance()` |
| Keys | `snake_case` or `strings` | `["'"]`, `mappings` |

### Module Structure

```lua
local M = {}
local state = { opts = {} }
local defaults = {}

function M.setup(opts)
    state.opts = vim.tbl_deep_extend('force', defaults, opts or {})
    return M
end

local function helper_func() end
function M.public_func() end
return M
```

### Error Handling

```lua
function M.func()
    if not condition then return nil end
end

local result = vim.api.nvim_get_var('key')
if result == nil then
end
```

### Tables

```lua
local defaults = {
    mappings = { ["'"] = "single quote", ['"'] = "double quote" },
    modes = { n = 'normal', i = 'insert' },
}

for _, item in ipairs(items) do end
for key, value in pairs(config) do end
```

### String Handling

```lua
local formatted = string.format('%s %d', label, number)
local escaped = (string.gsub(key, '([%(%)%.%%%+%-%*%?%[%]%^%$])', '%%%1'))
```

### Async and Callbacks

```lua
client:connect('127.0.0.1', 1729, function(err)
    if err then return end
    vim.schedule_wrap(function() end)
end)
```

### Vim API Usage

- Use `vim.tbl_*` utilities: `vim.tbl_deep_extend`, `vim.tbl_isempty`
- Use `vim.api.nvim_*` for editor interaction
- Use `vim.treesitter.*` for treesitter queries
- Use `vim.fn.*` for Vimscript functions

### Neovim Integration

- Use `nvim_create_autocmd` (not `nvimcommand`)
- Use `nvim_create_user_command` for commands
- Create augroups with `clear = true`

### Comments

- Avoid comments unless explaining non-obvious logic
- No TODO comments

## File Organization

```
lua/vox/
├── init.lua         # Main entry, setup, and high-level API
├── core.lua         # Core utilities (placeholder)
├── voxd_backend.lua # TCP backend for voxd daemon
└── log_backend.lua  # File logging backend
```

## Configuration Example

```lua
require('vox').setup({
    mappings = { ['"'] = 'double quote', ['('] = 'parenthesis' },
    cursor_moved_debounce = 150,
    backend = require('vox.voxd_backend').setup({
        routing = { linenr = '__default', line = '__default' },
    }),
})
```
