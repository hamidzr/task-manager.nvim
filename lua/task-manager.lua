-- task-manager.nvim: A Neovim plugin for managing todo priorities and categories
-- Author: AHZ
-- Description: Allows interactive prioritization of todo items and reassignment between categories

local M = {}

-- Configuration with defaults
M.config = {
  -- Format for priority tags: [p1], [p2], etc.
  priority_format = "%s [p%d] %s",
  -- Regular expression to identify already prioritized items
  priority_pattern = "%[p(%d+)%]",
  -- Keybindings (without leader, which is added by setup)
  keybindings = {
    prioritize_all = "ta",   -- (t)odo (a)ll prioritize
    prioritize_new = "tn",   -- (t)odo (n)ew prioritize
    sort_by_priority = "ts", -- (t)odo (s)ort
    toggle_checkbox = "tx",  -- (t)odo (x) checkbox toggle
  },
  -- Category heading pattern (Markdown h2)
  category_pattern = "^%s*##%s+(.+)$",
  -- Sort selection automatically after triage changes are applied
  auto_sort = true,
  -- Debug mode (prints additional information)
  debug = false
}

-- Debug print function
function M.debug_print(...)
  if M.config.debug then
    print(...)
  end
end

function M.get_indent_level(line)
  if not line then
    return 0 -- Return 0 for nil lines to avoid errors
  end

  local indent = line:match("^(%s*)")
  return indent and #indent or 0
end

-- ATX markdown heading level (1 = #, 6 = ######); nil if not a heading
function M.get_markdown_heading_level(line)
  if not line then
    return nil
  end

  local hashes = line:match("^%s*(#+)%s+%S")
  return hashes and #hashes or nil
end

function M.is_markdown_heading(line)
  return M.get_markdown_heading_level(line) ~= nil
end

-- Nearest heading above line_num (used for checkbox move boundaries)
function M.find_enclosing_section_heading(line_num)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

  for i = line_num, 1, -1 do
    local level = M.get_markdown_heading_level(lines[i])
    if level then
      return i, level
    end
  end

  return nil, nil
end

-- Line index of the next same-or-higher-level heading after from_line
function M.find_section_boundary(buffer_lines, from_line, section_level)
  local buffer_len = #buffer_lines

  for i = from_line, buffer_len do
    local level = M.get_markdown_heading_level(buffer_lines[i])
    if level and level <= section_level then
      return i
    end
  end

  return buffer_len + 1
end

-- Set up the plugin with user config
function M.setup(user_config)
  if user_config then
    M.config = vim.tbl_deep_extend("force", M.config, user_config)
  end

  -- Set up keybindings
  local leader = vim.g.mapleader or "\\"

  -- Prioritize all selected lines (regardless of existing priority)
  vim.api.nvim_set_keymap(
    'v',
    leader .. M.config.keybindings.prioritize_all,
    ':<C-u>lua require("task-manager").prioritize_selected(false)<CR>',
    { noremap = true, silent = true, desc = "Prioritize all selected todo items" }
  )

  -- Prioritize only new (unprioritized) selected lines
  vim.api.nvim_set_keymap(
    'v',
    leader .. M.config.keybindings.prioritize_new,
    ':<C-u>lua require("task-manager").prioritize_selected(true)<CR>',
    { noremap = true, silent = true, desc = "Prioritize only new todo items" }
  )

  -- Sort selected lines by priority
  vim.api.nvim_set_keymap(
    'v',
    leader .. M.config.keybindings.sort_by_priority,
    ':<C-u>lua require("task-manager").sort_by_priority()<CR>',
    { noremap = true, silent = true, desc = "Sort todo items by priority" }
  )

  -- Toggle checkbox in normal mode
  vim.api.nvim_set_keymap(
    'n',
    leader .. M.config.keybindings.toggle_checkbox,
    ':lua require("task-manager").toggle_checkbox()<CR>',
    { noremap = true, silent = true, desc = "Toggle checkbox state" }
  )

  -- Toggle checkbox in visual mode
  vim.api.nvim_set_keymap(
    'v',
    leader .. M.config.keybindings.toggle_checkbox,
    ':<C-u>lua require("task-manager").toggle_checkbox_visual()<CR>',
    { noremap = true, silent = true, desc = "Toggle checkbox state for selected lines" }
  )
end

-- Extract existing priority from a line, if any
function M.get_priority(line)
  if not line then
    return nil
  end

  local priority = line:match(M.config.priority_pattern)
  return priority and tonumber(priority) or nil
end

function M.strip_task_priority(line)
  if not line then
    return ""
  end

  local start_idx, end_idx = line:find(M.config.priority_pattern)
  if not start_idx then
    return line
  end

  local before = line:sub(1, start_idx - 1):gsub("%s+$", "")
  local after = line:sub(end_idx + 1):gsub("^%s+", "")

  if before ~= "" and after ~= "" then
    return before .. " " .. after
  end

  return before .. after
end

-- Extract the list marker from the beginning of a line (if any)
function M.get_list_marker(line)
  -- Match common list markers like "- ", "* ", "1. ", etc.
  local indent = line:match("^(%s*)")

  -- Match bullet list markers
  local marker = line:match("^%s*([%-%*%+]%s+)")
  if marker then
    return indent, marker
  end

  -- Match numbered lists
  local num_marker = line:match("^%s*(%d+%.%s+)")
  if num_marker then
    return indent, num_marker
  end

  -- Return just the indentation if no marker found
  return indent, ""
end

-- Check if a line is indented (potential sub-item)
function M.is_sub_item(line, base_indent)
  local indent = line:match("^(%s+)")
  local indent_level = indent and #indent or 0

  if base_indent ~= nil then
    return indent_level > base_indent
  end

  return indent_level >= 2
end

-- Extract the content of a line without list marker and priority
function M.get_content(line)
  if not line then
    return ""
  end

  local content = line

  -- Remove leading indentation and list markers
  content = content:gsub("^%s*[%-%*%+]%s*", "", 1)
  content = content:gsub("^%s*%d+%.%s*", "", 1)

  content = M.strip_task_priority(content)

  -- Trim surrounding whitespace
  content = content:gsub("^%s+", "")
  content = content:gsub("%s+$", "")

  return content
end

-- Format a line with the given priority
function M.format_with_priority(line, priority, base_indent)
  -- Only add priority to non-sub-items
  if not M.is_sub_item(line, base_indent) then
    local indent, marker = M.get_list_marker(line)
    local content = M.get_content(line)
    -- Strip trailing spaces from the marker to avoid duplicated spaces in the final format
    marker = marker:gsub("%s+$", "")

    if marker ~= "" then
      -- Format with priority and preserve exact formatting
      local formatted = string.format(M.config.priority_format, indent .. marker, priority, content)
      return formatted
    end
  end

  -- For sub-items or non-list items, just return the original line
  return line
end

-- Determine if a line is empty or whitespace-only
function M.is_blank_line(line)
  return line:match("^%s*$") ~= nil
end

-- Find a task block with descendants from a parent line
function M.get_task_block_lines(lines, start_line)
  local parent_line = lines[start_line]
  if not parent_line or not M.is_list_item(parent_line) then
    return nil
  end

  local parent_indent = M.get_indent_level(parent_line)
  local end_line = start_line

  while end_line < #lines do
    local next_line = lines[end_line + 1]

    if M.is_blank_line(next_line) then
      local probe_line = end_line + 2
      while probe_line <= #lines and M.is_blank_line(lines[probe_line]) do
        probe_line = probe_line + 1
      end

      if probe_line <= #lines and M.get_indent_level(lines[probe_line]) > parent_indent then
        end_line = end_line + 1
      else
        break
      end
    elseif M.get_indent_level(next_line) > parent_indent then
      end_line = end_line + 1
    else
      break
    end
  end

  local block_lines = {}
  for i = start_line, end_line do
    table.insert(block_lines, lines[i])
  end

  return {
    start_line = start_line,
    end_line = end_line,
    lines = block_lines,
  }
end

function M.get_task_block_from_buffer(line_num)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  return M.get_task_block_lines(lines, line_num)
end

-- Find the end of a category section
function M.find_category_end(lines, category_line)
  for i = category_line + 1, #lines do
    if lines[i]:match(M.config.category_pattern) then
      return i
    end
  end

  return #lines + 1
end

function M.get_all_categories_from_lines(lines)
  local categories = {}
  local shortcuts = {}

  for i, line in ipairs(lines) do
    if M.is_category_heading(line) then
      local category_name = M.get_category_name(line)
      local shortcut = M.generate_category_shortcut(category_name, shortcuts)
      shortcuts[shortcut] = true

      table.insert(categories, {
        name = category_name,
        shortcut = shortcut,
        line_num = i,
        end_line = M.find_category_end(lines, i),
      })
    end
  end

  return categories
end

-- Check if a line is a category heading
function M.is_category_heading(line)
  return line:match(M.config.category_pattern) ~= nil
end

-- Extract category name from heading
function M.get_category_name(heading)
  return heading:match(M.config.category_pattern)
end

-- Check if a line represents a list item (bullet or numbered)
function M.is_list_item(line)
  if not line or line:match("^%s*$") then
    return false
  end

  if M.is_category_heading(line) then
    return false
  end

  return line:match("^%s*[%-%*%+]%s+") ~= nil or line:match("^%s*%d+%.%s+") ~= nil
end

-- Determine the minimum indentation level among list items in a set of lines
function M.get_base_indent(lines)
  if not lines then
    return 0
  end

  local min_indent = nil
  for _, line in ipairs(lines) do
    if M.is_list_item(line) then
      local indent_level = M.get_indent_level(line)
      if not min_indent or indent_level < min_indent then
        min_indent = indent_level
      end
    end
  end

  return min_indent or 0
end

-- Generate a single-letter shortcut for a category name
function M.generate_category_shortcut(category_name, used_shortcuts)
  -- Define reserved shortcuts that should not be used for categories
  local reserved_shortcuts = {
    s = true, -- Skip
    q = true, -- Quit
    ["1"] = true,
    ["2"] = true,
    ["3"] = true,
    ["4"] = true,
    ["5"] = true,
    ["6"] = true,
    ["7"] = true,
    ["8"] = true,
    ["9"] = true -- Priorities
  }

  -- Add reserved shortcuts to used_shortcuts
  for key in pairs(reserved_shortcuts) do
    used_shortcuts[key] = true
  end

  -- Try first letter of each word
  local words = {}
  for word in category_name:gmatch("%S+") do
    table.insert(words, word)
  end

  -- Try first letter of each word
  for _, word in ipairs(words) do
    local first_char = word:sub(1, 1):lower()
    if not used_shortcuts[first_char] then
      return first_char
    end
  end

  -- Try other letters in the category name
  for i = 1, #category_name do
    local char = category_name:sub(i, i):lower()
    if char:match("[a-z]") and not used_shortcuts[char] then
      return char
    end
  end

  -- Last resort: just use the next available letter
  for c = 97, 122 do -- ASCII 'a' to 'z'
    local char = string.char(c)
    if not used_shortcuts[char] and not reserved_shortcuts[char] then
      return char
    end
  end

  -- If all fails, use a non-reserved number
  for i = 0, 0 do -- Only try 0, as 1-9 are reserved for priorities
    local char = tostring(i)
    if not used_shortcuts[char] then
      return char
    end
  end

  return "?" -- Should never happen unless you have more than 35 categories
end

-- Get all categories from the entire buffer
function M.get_all_categories()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  return M.get_all_categories_from_lines(lines)
end

-- Find the category of a given line
function M.find_line_category(line_num, categories)
  for i = #categories, 1, -1 do
    if categories[i].line_num < line_num then
      return categories[i]
    end
  end

  return nil -- Line is before any category
end

-- Find sub-items for a given parent item
function M.find_sub_items(parent_line_num)
  local buffer_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local block = M.get_task_block_lines(buffer_lines, parent_line_num)

  if not block then
    return {}
  end

  local sub_items = {}
  for i = block.start_line + 1, block.end_line do
    table.insert(sub_items, {
      content = buffer_lines[i],
      line_num = i,
    })
  end

  return sub_items
end

-- Move a line and its task block from one category to another
function M.move_to_category(line, line_num, source_category, target_category)
  local target_category_line = target_category and target_category.line_num
  local start_line = line_num

  if type(line) == "number" and not line_num then
    start_line = line
  end

  if not start_line or not target_category_line then
    return nil
  end

  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local block = M.get_task_block_lines(lines, start_line)

  if not block then
    return nil
  end

  local block_lines = {}
  for idx = block.start_line, block.end_line do
    local block_line = lines[idx]
    if idx == block.start_line then
      block_line = M.strip_task_priority(block_line)
    end
    table.insert(block_lines, block_line)
  end

  local adjusted_target = target_category_line
  local block_len = block.end_line - block.start_line + 1

  if block.start_line < target_category_line then
    adjusted_target = adjusted_target - block_len
  end

  for i = block.end_line, block.start_line, -1 do
    table.remove(lines, block.start_line)
  end

  if adjusted_target < 1 then
    adjusted_target = 1
  elseif adjusted_target > #lines + 1 then
    adjusted_target = #lines + 1
  end

  local target_end = M.find_category_end(lines, adjusted_target)

  for i = #block_lines, 1, -1 do
    table.insert(lines, target_end, block_lines[i])
  end

  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

  return target_end
end

-- Move a checked item to the bottom of its current section/category
function M.move_item_to_section_bottom(line_num)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local line = lines[line_num]

  if not line or M.is_markdown_heading(line) then
    return line_num
  end

  local block = M.get_task_block_lines(lines, line_num)
  if not block then
    return line_num
  end

  local lines_to_move = {}
  for _, block_line in ipairs(block.lines) do
    table.insert(lines_to_move, block_line)
  end

  for i = block.end_line, block.start_line, -1 do
    table.remove(lines, block.start_line)
  end

  local line_to_move = lines_to_move[1]
  local indent_level = M.get_indent_level(line_to_move)
  local insert_pos = nil

  if not M.is_sub_item(line_to_move) then
    local section_level = select(2, M.find_enclosing_section_heading(block.start_line))

    if section_level then
      insert_pos = M.find_section_boundary(lines, block.start_line, section_level)
    else
      insert_pos = #lines + 1
      for i = block.start_line, #lines do
        if M.is_category_heading(lines[i]) then
          insert_pos = i
          break
        end
      end
    end

    local trim_end = insert_pos - 1
    while trim_end >= block.start_line and M.is_blank_line(lines[trim_end]) do
      insert_pos = trim_end
      trim_end = trim_end - 1
    end
  else
    insert_pos = block.start_line
    local i = insert_pos
    local buffer_len = #lines

    while i <= buffer_len do
      local current_line = lines[i]

      if not current_line or M.is_blank_line(current_line) then
        break
      end

      local current_indent = M.get_indent_level(current_line)

      if current_indent < indent_level then
        break
      elseif current_indent == indent_level then
        if not M.is_list_item(current_line) then
          break
        end

        local j = i + 1
        while j <= buffer_len do
          local next_line = lines[j]
          if not next_line or M.is_blank_line(next_line) then
            break
          end

          local next_indent = M.get_indent_level(next_line)
          if next_indent <= indent_level then
            break
          end

          j = j + 1
        end

        insert_pos = j
        i = j
      else
        i = i + 1
      end
    end
  end

  if not insert_pos then
    for _, line in ipairs(lines_to_move) do
      table.insert(lines, line)
    end
  else
    if insert_pos > #lines + 1 then
      insert_pos = #lines + 1
    end
    for i = #lines_to_move, 1, -1 do
      table.insert(lines, insert_pos, lines_to_move[i])
    end
  end

  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

  if not insert_pos then
    return line_num
  end

  return insert_pos
end

-- Display a formatted table of categories and their shortcuts
function M.display_category_shortcuts(categories)
  -- Calculate the maximum length of category names for formatting
  local max_length = 0
  for _, cat in ipairs(categories) do
    max_length = math.max(max_length, #cat.name)
  end

  -- Build the message
  local msg = { { "Category Shortcuts:\n", "Title" } }

  -- Add headers
  table.insert(msg, { "Key", "Special" })
  table.insert(msg, { " | ", "Normal" })
  table.insert(msg, { "Category", "Special" })
  table.insert(msg, { "\n" .. string.rep("-", 15 + max_length) .. "\n", "Normal" })

  -- Add each category with its shortcut
  for _, cat in ipairs(categories) do
    table.insert(msg, { " " .. cat.shortcut .. " ", "Question" })
    table.insert(msg, { " | ", "Normal" })
    table.insert(msg, { cat.name .. "\n", "Normal" })
  end

  -- Add instruction for numbers, shortcuts, skipping, and quitting
  table.insert(msg, { "\nUse ", "Normal" })
  table.insert(msg, { "1-9", "Question" })
  table.insert(msg, { " for priorities, ", "Normal" })
  table.insert(msg, { "0", "Question" })
  table.insert(msg, { " to clear, ", "Normal" })
  table.insert(msg, { "letter shortcuts", "Question" })
  table.insert(msg, { " to move between categories, ", "Normal" })
  table.insert(msg, { "s", "Question" })
  table.insert(msg, { " to skip, or ", "Normal" })
  table.insert(msg, { "q", "Question" })
  table.insert(msg, { " to quit.\n", "Normal" })

  -- Display the message
  vim.api.nvim_echo(msg, true, {})
end

-- Function to toggle checkbox state in Markdown lists
function M.toggle_checkbox()
  -- Get the current line
  local line_num = vim.fn.line(".")
  local line = vim.fn.getline(line_num)
  M.toggle_checkbox_for_line(line_num, line)
end

local function analyze_checkbox_line(line)
  local indent, marker = M.get_list_marker(line)

  if marker == "" then
    -- blank lines and headings stay no-op
    if line:match("^%s*$") or line:match("^%s*#") then
      return nil
    end

    -- plain text line: checkbox-able, but needs a bullet prepended
    return {
      has_checkbox = false,
      insert_pos = #indent,
      needs_bullet = true,
    }
  end

  local prefix_len = #indent + #marker
  local rest = line:sub(prefix_len + 1)
  local rest_len = #rest
  local i = 1

  while i <= rest_len do
    local char = rest:sub(i, i)

    if char:match("%s") then
      i = i + 1
    elseif char == "[" then
      local closing = rest:find("]", i, true)
      if not closing then
        break
      end

      local content = rest:sub(i + 1, closing - 1)

      if content:match("^[xX%s]?$") then
        local prefix = line:sub(1, prefix_len + i - 1)
        local suffix = rest:sub(closing + 1)

        return {
          has_checkbox = true,
          prefix = prefix,
          suffix = suffix,
          state = content,
        }
      else
        local next_i = closing + 1

        while next_i <= rest_len and rest:sub(next_i, next_i):match("%s") do
          next_i = next_i + 1
        end

        i = next_i
      end
    else
      break
    end
  end

  return {
    has_checkbox = false,
    insert_pos = prefix_len,
  }
end

-- Helper function to toggle checkbox for a single line
function M.toggle_checkbox_for_line(line_num, line)
  local analysis = analyze_checkbox_line(line)

  if not analysis then
    vim.api.nvim_echo({ { string.format("No list item found on line %d", line_num), "WarningMsg" } }, true, {})
    return
  end

  if analysis.has_checkbox then
    local state = analysis.state or ""
    local is_checked = state:lower() == "x"
    local new_state = is_checked and " " or "x"
    local new_line = analysis.prefix .. "[" .. new_state .. "]" .. (analysis.suffix or "")

    vim.api.nvim_buf_set_lines(0, line_num - 1, line_num, true, { new_line })

    if new_state == "x" then
      local new_position = M.move_item_to_section_bottom(line_num)
      local moved = new_position ~= line_num
      local message = moved and "Checkbox toggled (checked -> moved to bottom)" or "Checkbox toggled (checked)"
      vim.api.nvim_echo({ { message, "Normal" } }, true, {})
    else
      vim.api.nvim_echo({ { "Checkbox toggled (unchecked)", "Normal" } }, true, {})
    end
  else
    if vim.bo.filetype == "markdown" then
      local insert_pos = math.max(analysis.insert_pos or 0, 0)
      local before = line:sub(1, insert_pos)
      local after = line:sub(insert_pos + 1)

      local bullet = analysis.needs_bullet and "- " or ""
      -- when prepending a bullet the space-before logic is unnecessary
      local needs_space_before = bullet == "" and before ~= "" and not before:match("%s$")
      local insertion = bullet .. (needs_space_before and " " or "") .. "[x]"

      if after == "" or not after:match("^%s") then
        insertion = insertion .. " "
      end

      local new_line = before .. insertion .. after

      vim.api.nvim_buf_set_lines(0, line_num - 1, line_num, true, { new_line })

      local new_position = M.move_item_to_section_bottom(line_num)
      local moved = new_position ~= line_num
      local message = moved and "Checkbox created (checked -> moved to bottom)" or "Checkbox created (checked)"
      vim.api.nvim_echo({ { message, "Normal" } }, true, {})
    else
      vim.api.nvim_echo({ { string.format("No list item found on line %d", line_num), "WarningMsg" } }, true, {})
    end
  end
end

-- Function to toggle checkbox state for multiple lines in visual mode
function M.toggle_checkbox_visual()
  -- Get the visual selection range
  local start_line = vim.fn.line("'<")
  local end_line = vim.fn.line("'>")

  -- Process each line in the selection
  for line_num = end_line, start_line, -1 do
    local line = vim.fn.getline(line_num)
    M.toggle_checkbox_for_line(line_num, line)
  end
end

-- Check if a line has a checked checkbox
function M.is_checked_item(line)
  local analysis = analyze_checkbox_line(line)
  if not analysis or not analysis.has_checkbox then
    return false
  end

  return analysis.state:lower() == "x"
end

function M._apply_prioritize_changes(changes, original_start_line, original_end_line)
  if not changes or (#changes.lines == 0 and #changes.moves == 0) then
    return false
  end

  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local move_blocks = {}

  for i, move in ipairs(changes.moves) do
    local block = M.get_task_block_lines(lines, move.from)
    if block then
      local block_lines = {}
      for idx, block_line in ipairs(block.lines) do
        if idx == 1 then
          table.insert(block_lines, M.strip_task_priority(block_line))
        else
          table.insert(block_lines, block_line)
        end
      end

      table.insert(move_blocks, {
        from = block.start_line,
        to = block.end_line,
        len = #block_lines,
        lines = block_lines,
        order = i,
        target_category_line = move.target_category and move.target_category.line_num,
      })
    end
  end

  table.sort(move_blocks, function(a, b)
    return a.from > b.from
  end)

  for _, move in ipairs(move_blocks) do
    for i = move.to, move.from, -1 do
      table.remove(lines, move.from)
    end
  end

  local adjusted_changes = {}
  for _, change in ipairs(changes.lines) do
    local line_num = change.line_num

    for _, move in ipairs(move_blocks) do
      if change.line_num > move.to then
        line_num = line_num - move.len
      end
    end

    table.insert(adjusted_changes, {
      line_num = line_num,
      content = change.content,
    })
  end

  table.sort(adjusted_changes, function(a, b)
    return a.line_num < b.line_num
  end)

  for _, change in ipairs(adjusted_changes) do
    if change.line_num >= 1 and change.line_num <= #lines + 1 then
      if change.line_num == #lines + 1 then
        table.insert(lines, change.content)
      else
        lines[change.line_num] = change.content
      end
    end
  end

  local insertions = {}
  for _, move in ipairs(move_blocks) do
    local target_line = move.target_category_line
    if target_line then
      local adjusted_target_line = target_line
      for _, removed in ipairs(move_blocks) do
        if removed.from < target_line then
          adjusted_target_line = adjusted_target_line - removed.len
        end
      end

      local target_end = M.find_category_end(lines, adjusted_target_line)

      table.insert(insertions, {
        lines = move.lines,
        len = move.len,
        insert_pos = target_end,
        order = move.order,
      })
    end
  end

  table.sort(insertions, function(a, b)
    if a.insert_pos ~= b.insert_pos then
      return a.insert_pos < b.insert_pos
    end

    return a.order < b.order
  end)

  local inserted = 0
  for _, insertion in ipairs(insertions) do
    local insert_pos = insertion.insert_pos + inserted
    for i = insertion.len, 1, -1 do
      table.insert(lines, insert_pos, insertion.lines[i])
    end
    inserted = inserted + insertion.len
  end

  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

  local moved_lines = {}
  for _, move in ipairs(changes.moves) do
    moved_lines[move.from] = true
  end

  local new_start_line = nil
  local new_end_line = nil
  local lines_removed = 0

  for line_num = original_start_line, original_end_line do
    if moved_lines[line_num] then
      lines_removed = lines_removed + 1
    else
      local adjusted_line_num = line_num - lines_removed
      if new_start_line == nil then
        new_start_line = adjusted_line_num
      end
      new_end_line = adjusted_line_num
    end
  end

  if new_start_line and new_end_line and new_start_line <= new_end_line then
    vim.fn.setpos("'<", {0, new_start_line, 1, 0})
    vim.fn.setpos("'>", {0, new_end_line, vim.fn.col("$"), 0})
    vim.cmd("normal! gv")
  end

  return true
end

function M.maybe_sort_after_prioritize(original_start_line, original_end_line)
  if not M.config.auto_sort then
    return
  end

  vim.fn.setpos("'<", { 0, original_start_line, 1, 0 })
  vim.fn.setpos("'>", { 0, original_end_line, vim.fn.col("$"), 0 })
  M.sort_by_priority()
end

-- Interactive prioritization of selected lines
function M.prioritize_selected(skip_prioritized)
  -- Get the original visual selection range
  local original_start_line = vim.fn.line("'<")
  local original_end_line = vim.fn.line("'>")

  -- Get all categories
  local categories = M.get_all_categories()
  local has_categories = #categories > 0

  -- Create a map of shortcuts to categories for quick lookup
  local shortcut_map = {}
  for _, cat in ipairs(categories) do
    shortcut_map[cat.shortcut] = cat
  end

  -- Store all pending changes
  local changes = {
    lines = {}, -- {line_num = N, content = "new content"}
    moves = {}, -- {from = N, target_category = {...}}
  }

  -- Display category shortcuts only if categories exist
  if has_categories then
    M.display_category_shortcuts(categories)
  else
    vim.api.nvim_echo({
      { "No categories found. You can only set priorities.\n", "WarningMsg" },
      { "Use ", "Normal" },
      { "1-9", "Question" },
      { " for priorities, ", "Normal" },
      { "0", "Question" },
      { " to clear, or ", "Normal" },
      { "q", "Question" },
      { " to quit.\n", "Normal" }
    }, true, {})
  end

  -- Get the current visual selection
  local start_line = vim.fn.line("'<")
  local end_line = vim.fn.line(">'")

  -- Determine the baseline indentation for the selection
  local selection_lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, true)
  local base_indent = M.get_base_indent(selection_lines)

  -- Get the lines in the selection
  local lines = {}
  for i = start_line, end_line do
    local line = vim.fn.getline(i)
    if not M.is_checked_item(line) then
      table.insert(lines, {
        content = line,
        line_num = i
      })
    end
  end

  -- Calculate total lines to process (considering skip_prioritized)
  local total_lines = 0
  for _, line_data in ipairs(lines) do
    local line = line_data.content
    local current_priority = M.get_priority(line)
    if not (skip_prioritized and current_priority) then
      total_lines = total_lines + 1
    end
  end

  -- Process each line interactively
  local i = 1
  local processed_lines = 0
  while i <= #lines do
    local line_data = lines[i]
    local line = line_data.content
    local line_num = line_data.line_num

    -- Skip category headings and sub-items
    if M.is_category_heading(line) or M.is_sub_item(line, base_indent) then
      i = i + 1
    else
      local current_priority = M.get_priority(line)

      -- Skip already prioritized items if requested
      if not (skip_prioritized and current_priority) then
        processed_lines = processed_lines + 1

        -- Find the current category for this line
        local current_category = has_categories and M.find_line_category(line_num, categories) or nil

        -- Calculate progress percentage
        local progress = total_lines == 0 and 0 or math.floor((processed_lines / total_lines) * 100)

        -- Prompt for priority or category change
        local prompt = string.format("Line %d (%d%%)", line_num, progress)
        if current_category then
          prompt = prompt .. string.format(" (in %s)", current_category.name)
        end
        if current_priority then
          prompt = prompt .. string.format(" (was p%d)", current_priority)
        end
        prompt = prompt .. ": "

        -- Get the line content without priority for display
        local display_line = M.strip_task_priority(line):gsub("^%s+", "")

        vim.api.nvim_echo({
          { prompt,                "Question" },
          { display_line, "Normal" }
        }, true, {})

        local char = vim.fn.getchar()
        local input = char == 27 and "q" or vim.fn.nr2char(char)

        -- Process input
        if input == "q" then
          if #changes.lines > 0 or #changes.moves > 0 then
            vim.api.nvim_echo({
              { "You have pending changes. Apply them? (y/n): ", "Question" }
            }, true, {})

            local confirm_char = vim.fn.getchar()
            local confirm_input = confirm_char == 27 and "n" or vim.fn.nr2char(confirm_char)

            if confirm_input == "y" then
              M._apply_prioritize_changes(changes, original_start_line, original_end_line)
              M.maybe_sort_after_prioritize(original_start_line, original_end_line)
              vim.api.nvim_echo({ { "Changes applied", "Normal" } }, true, {})
              return
            end

            vim.api.nvim_echo({ { "Operation cancelled", "WarningMsg" } }, true, {})
            return
          end

          vim.api.nvim_echo({ { "Operation cancelled", "WarningMsg" } }, true, {})
          return
        elseif input == "s" then
          -- Skip this item
          vim.api.nvim_echo({ { "Skipped", "Normal" } }, true, {})
        elseif input == "0" then
          local new_line = M.strip_task_priority(line)
          table.insert(changes.lines, {
            line_num = line_num,
            content = new_line
          })
          vim.api.nvim_echo({ { "Priority cleared", "Normal" } }, true, {})
        elseif input:match("[1-9]") then
          -- Queue priority change
          local priority = tonumber(input)
          local new_line = M.format_with_priority(line, priority, base_indent)
          table.insert(changes.lines, {
            line_num = line_num,
            content = new_line
          })
        elseif has_categories and shortcut_map[input] then
          -- Queue category move
          local target_category = shortcut_map[input]
          if current_category and current_category.name ~= target_category.name then
            table.insert(changes.moves, {
              from = line_num,
              target_category = target_category,
            })

            vim.api.nvim_echo({
              { string.format("Will move to %s (priority cleared)", target_category.name), "Normal" }
            }, true, {})
          end
        end
      end
    end

    i = i + 1
  end

  if #changes.lines > 0 or #changes.moves > 0 then
    M._apply_prioritize_changes(changes, original_start_line, original_end_line)
    M.maybe_sort_after_prioritize(original_start_line, original_end_line)
    vim.api.nvim_echo({ { "All changes applied", "Normal" } }, true, {})
  else
    vim.api.nvim_echo({ { "No changes made", "Normal" } }, true, {})
  end
end

-- Sort selected lines by priority (stable sort within categories)
function M.sort_by_priority()
  -- Get the current visual selection
  local start_line = vim.fn.line("'<")
  local end_line = vim.fn.line("'>")

  -- Get all categories
  local categories = M.get_all_categories()

  -- Get the lines in the selection
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, true)

  -- Identify contiguous blocks of lines within the same category
  local blocks = {}
  local current_block = nil

  for i, line in ipairs(lines) do
    if M.is_category_heading(line) then
      if current_block then
        table.insert(blocks, current_block)
      end

      current_block = {
        category = M.get_category_name(line),
        lines = { line }
      }
    elseif current_block then
      table.insert(current_block.lines, line)
    else
      local line_category = M.find_line_category(start_line + i - 1, categories)
      local category_name = line_category and line_category.name or "Uncategorized"

      current_block = {
        category = category_name,
        lines = { line }
      }
    end
  end

  if current_block then
    table.insert(blocks, current_block)
  end

  for _, block in ipairs(blocks) do
    if #block.lines > 1 then
      local heading = nil
      if M.is_category_heading(block.lines[1]) then
        heading = table.remove(block.lines, 1)
      end

      local base_indent = M.get_base_indent(block.lines)
      local item_groups = {}
      local i = 1

      while i <= #block.lines do
        local line = block.lines[i]
        if M.is_sub_item(line, base_indent) then
          i = i + 1
        else
          local block_data = M.get_task_block_lines(block.lines, i)

          if block_data and block_data.start_line == i then
            local lines_to_sort = {}
            for block_idx = block_data.start_line, block_data.end_line do
              table.insert(lines_to_sort, block.lines[block_idx])
            end

            table.insert(item_groups, {
              lines = lines_to_sort,
              original_pos = i,
              is_checked = M.is_checked_item(lines_to_sort[1]),
              priority = M.get_priority(lines_to_sort[1])
            })

            i = block_data.end_line + 1
          else
            table.insert(item_groups, {
              lines = { line },
              original_pos = i,
              is_checked = M.is_checked_item(line),
              priority = M.is_list_item(line) and M.get_priority(line) or nil,
            })
            i = i + 1
          end
        end
      end

      table.sort(item_groups, function(a, b)
        if a.is_checked ~= b.is_checked then
          return not a.is_checked
        end

        if a.priority and b.priority then
          if a.priority ~= b.priority then
            return a.priority < b.priority
          end
          return a.original_pos < b.original_pos
        end

        if a.priority and not b.priority then
          return true
        end

        if not a.priority and b.priority then
          return false
        end

        return a.original_pos < b.original_pos
      end)

      local sorted_lines = {}
      for _, item_group in ipairs(item_groups) do
        for _, item_line in ipairs(item_group.lines) do
          table.insert(sorted_lines, item_line)
        end
      end

      if heading then
        table.insert(sorted_lines, 1, heading)
      end

      block.lines = sorted_lines
    end
  end

  local sorted_lines = {}
  for _, block in ipairs(blocks) do
    for _, line in ipairs(block.lines) do
      table.insert(sorted_lines, line)
    end
  end

  vim.api.nvim_buf_set_lines(0, start_line - 1, end_line, true, sorted_lines)

  -- Restore visual selection to keep the sorted lines selected
  vim.fn.setpos("'<", {0, start_line, 1, 0})
  vim.fn.setpos("'>", {0, start_line + #sorted_lines - 1, vim.fn.col("$"), 0})

  -- Enter visual line mode to show the selection
  vim.cmd("normal! gv")

  -- Notify the user that the operation is complete
  vim.api.nvim_echo({ { "Sorting complete", "Normal" } }, true, {})
end

return M
