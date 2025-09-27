# Todo Priority Manager for Neovim

A Neovim plugin that helps manage, prioritize, and categorize to-do items in your Markdown lists.

## Features

- Interactively assign priority numbers to selected task items
- Move tasks between categories with auto-generated shortcuts
- Option to prioritize only unprioritized items or reprioritize everything
- Sort tasks by priority (stable sort within each category)
- Toggle task checkboxes in normal and visual mode
- Checking a task automatically moves it to the bottom of its section
- Works with Markdown lists, bullet points, and numbered lists
- Preserves task hierarchy and sub-items when moving between categories

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

### Using Lazy.nvim

```lua
{
  'hamidzr/task-manager.nvim',
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
    toggle_checkbox = "tx",     -- (t)odo (x) checkbox toggle
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
- `<leader>ts` - Sort selected items by priority (stable sort within each category, checked items at bottom)
- `<leader>tx` - Toggle checkbox state (works in both normal and visual mode)

### Prioritization Process

When you initiate prioritization:

1. The plugin will display a table of categories and their auto-generated shortcuts
2. For each line, you'll be prompted to:
   - Enter a number (1-9) to set a priority
   - Enter a category shortcut to move the task to another category
   - Press 's' to skip the current item
   - Press 'q' to quit the process
3. If you quit with pending changes:
   - You'll be prompted to apply or discard the changes
   - Changes include both priority updates and category moves
   - All changes are applied atomically (all or nothing)

### Sorting Behavior

The sort command (`ts`) organizes tasks with the following rules:

1. Tasks are sorted within their respective categories
2. Checked items (`[x]`) are moved to the bottom of their category
3. Unchecked items are sorted by priority (1-9)
4. Items without priorities maintain their relative order
5. Sub-items (indented tasks) stay with their parent items
6. Category headings remain at the top of their sections

### Example

Starting with:

```markdown
## Work

- [x] Fix bug in login form
- [p1] Prepare for meeting
  - [x] Review agenda
  - [p2] Prepare slides

## Personal

- Buy groceries
- [p3] Call dentist
```

After sorting (`ts`):

```markdown
## Work

- [p1] Prepare for meeting
  - [p2] Prepare slides
  - [x] Review agenda
- [x] Fix bug in login form

## Personal

- [p3] Call dentist
- Buy groceries
```

Note: When sorting tasks by priority (`ts`), checked items (`[x]`) are automatically moved to the bottom of their respective categories, regardless of their priority.

### Checkbox Toggling

The plugin provides a convenient way to toggle task checkboxes:

- In normal mode: Place your cursor on a task line and press `<leader>tx` to toggle its checkbox state
- In visual mode: Select multiple task lines and press `<leader>tx` to toggle all selected checkboxes

If a line doesn't have a checkbox, pressing `<leader>tx` will add one in the checked state (`[x]`).

When you toggle a checkbox from unchecked (`[ ]`) to checked (`[x]`), the task is automatically moved to the bottom of its current section (between the heading it belongs to and the next heading), keeping completed items out of the way while preserving any sub-items.

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

## TODO
- remove priorities
- [x] tx to also work in visual mode and over many lines
- [x] ts and ta to ignore [x] items. sort at the bottom
- [ ] highlight the same lines (or reduced set because of the moves) after changes
- [ ] should work on a list that's nested if only l1 lists are selected only operate on thoese. neesd more thinking
