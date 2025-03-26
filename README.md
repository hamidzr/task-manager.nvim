# Todo Priority Manager for Neovim

A Neovim plugin that helps manage, prioritize, and categorize to-do items in your Markdown lists.

## TODO
- remove priorities
- tx to also work in visual mode and over many lines
- ts and ta to ignore [x] items. sort at the bottom

## Features

- Interactively assign priority numbers to selected task items
- Move tasks between categories with auto-generated shortcuts
- Option to prioritize only unprioritized items or reprioritize everything
- Sort tasks by priority (stable sort within each category)
- Works with Markdown lists, bullet points, and numbered lists

## Installation

### Using Packer

```lua
use {
  'hamidzr/task-manager.nvim',
  name='task-manager',
  config = function()
    require('task-manager').setup()
  end
}
```

### Using vim-plug

```vim
Plug 'hamidzr/task-manager'
```

Then add to your init.vim or init.lua:

```lua
require('task-manager').setup()
```

Lazy Lua for neovim:

```lua
{
  'hamidzr/task-manager.nvim.nvim',
  name='task-manager',
  config = function()
    require('task-manager').setup({
      -- Optional: customize settings here
      debug = true,  -- Enable debug mode during development
    })
  end
}
```

## Configuration

The plugin works with default settings, but you can customize it:

```lua
require('task-manager').setup({
  -- Format for priority tags: [p1], [p2], etc.
  priority_format = "%s [p%d] %s",

  -- Regular expression to identify already prioritized items
  priority_pattern = "%[p(%d+)%]",

  -- Keybindings (without leader)
  keybindings = {
    prioritize_all = "ta",      -- (t)odo (a)ll prioritize
    prioritize_new = "tn",      -- (t)odo (n)ew prioritize
    sort_by_priority = "ts",    -- (t)odo (s)ort
  },

  -- Category heading pattern (Markdown h2)
  category_pattern = "^%s*##%s+(.+)$",

  -- Debug mode (prints additional information)
  debug = false
})
```

## Usage

### Document Format

The plugin expects your to-do list to be organized with Markdown headings as categories:

```markdown
## Work

- Fix bug in login form
- [p1] Prepare for meeting
- Update documentation

## Personal

- [p3] Buy groceries
- Call dentist
```

### Commands

1. Select the lines containing your tasks in visual mode
2. Use one of the following commands:

- `<leader>ta` - Prioritize all selected items (reprioritize everything)
- `<leader>tn` - Prioritize only new items (skip already prioritized items)
- `<leader>ts` - Sort selected items by priority (stable sort within each category)

### Prioritization Process

When you initiate prioritization:

1. The plugin will display a table of categories and their auto-generated shortcuts
2. For each line, you'll be prompted to:
   - Enter a number (1-9) to set a priority
   - Enter a category shortcut to move the task to another category
   - Press 'q' to quit the process

### Category Shortcuts

The plugin automatically generates single-letter shortcuts for each category, preferring:

1. First letter of each word in the category name
2. Other letters in the category name
3. Any available letter if needed

These shortcuts are displayed when you start the prioritization process.

### Example

Starting with:

```markdown
## Work

- Fix bug in login form
- [p1] Prepare for meeting

## Personal

- Buy groceries
- [p3] Call dentist
```

After prioritization and category changes:

```markdown
## Work

- [p1] Prepare for meeting
- [p2] Fix bug in login form

## Personal

- [p3] Call dentist
- [p4] Buy groceries
```

## File Structure

Place the plugin in your Neovim configuration directory:

```
~/.config/nvim/lua/task-manager.lua
```

Or if you're packaging it as a proper plugin:

```
~/.config/nvim/
└── lua/
    └── task-manager/
        ├── init.lua
        └── README.md
```

## License

MIT
