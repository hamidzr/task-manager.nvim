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

-- Set up the plugin with user config
function M.setup(user_config)
  -- Merge user config with defaults
  if user_config then
    for k, v in pairs(user_config) do
      M.config[k] = v
    end
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
  local priority = line:match(M.config.priority_pattern)
  return priority and tonumber(priority) or nil
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
function M.is_sub_item(line)
  local indent = line:match("^(%s+)")
  return indent and #indent >= 2
end

-- Extract the content of a line without list marker and priority
function M.get_content(line)
  -- Get the indentation
  local indent = line:match("^(%s*)")

  -- Remove list marker while preserving indentation
  local content = line:gsub("^%s*[%-%*%+]%s+", indent)
  content = content:gsub("^%s*%d+%.%s+", indent)

  -- Remove priority tag if it exists
  content = content:gsub("%s*%[p%d+%]%s*", " ")

  -- Trim trailing whitespace (but keep leading indentation)
  content = content:gsub("^(%s*)%s*(.-)[%s]*$", "%1%2")

  return content
end

-- Format a line with the given priority
function M.format_with_priority(line, priority)
  -- Only add priority to non-sub-items
  if not M.is_sub_item(line) then
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

-- Check if a line is a category heading
function M.is_category_heading(line)
  return line:match(M.config.category_pattern) ~= nil
end

-- Extract category name from heading
function M.get_category_name(heading)
  return heading:match(M.config.category_pattern)
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
  local categories = {}
  local shortcuts = {}

  -- Get all lines in the buffer
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

  -- Find all category headings
  for i, line in ipairs(lines) do
    if M.is_category_heading(line) then
      local category_name = M.get_category_name(line)
      local shortcut = M.generate_category_shortcut(category_name, shortcuts)
      shortcuts[shortcut] = true
      table.insert(categories, {
        name = category_name,
        shortcut = shortcut,
        line_num = i,
      })
    end
  end

  return categories
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
  local sub_items = {}
  local buffer_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local parent_line = buffer_lines[parent_line_num]
  local parent_indent = M.get_indent_level(parent_line)

  -- Collect lines after the parent that are more indented
  local i = parent_line_num + 1
  while i <= #buffer_lines do
    local line = buffer_lines[i]
    local indent = M.get_indent_level(line)

    -- If we find a line with less or equal indentation, we're done
    if indent <= parent_indent then
      break
    end

    -- Add the sub-item exactly as is
    table.insert(sub_items, {
      content = line,
      line_num = i
    })
    i = i + 1
  end

  return sub_items
end

-- Move a line and its sub-items from one category to another
function M.move_to_category(line, line_num, source_category, target_category)
  -- Find any sub-items that should be moved with this line
  local sub_items = M.find_sub_items(line_num)

  -- Calculate how many lines we need to remove
  local total_lines = 1 + #sub_items

  -- Store the original lines exactly as they are before removal
  local original_line = line
  local original_sub_items = {}
  for _, sub_item in ipairs(sub_items) do
    table.insert(original_sub_items, sub_item.content)
  end

  -- Get the list marker and content without priority
  local indent, marker = M.get_list_marker(original_line)
  local content = M.get_content(original_line)

  -- Remove any existing priority tag
  content = content:gsub("%s*%[p%d+%]%s*", " ")

  -- Ensure content has no trailing whitespace
  content = content:gsub("%s+$", "")

  -- Format the line without priority, preserving markers and indentation
  local line_without_priority
  if marker ~= "" then
    -- Strip trailing spaces from the marker to avoid duplicated spaces
    marker = marker:gsub("%s+$", "")
    -- Ensure there's exactly one space between marker and content
    line_without_priority = indent .. marker .. " " .. content:gsub("^%s+", "")
  else
    line_without_priority = indent .. content:gsub("^%s+", "")
  end

  -- Trim any excess whitespace in the final result
  line_without_priority = line_without_priority:gsub("%s+$", "")

  -- Delete the line and its sub-items from their current position
  vim.api.nvim_buf_set_lines(0, line_num - 1, line_num - 1 + total_lines, true, {})

  -- Find the end of the target category
  local target_end = nil
  local buffer_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

  for i = target_category.line_num + 1, #buffer_lines do
    if buffer_lines[i]:match(M.config.category_pattern) then
      target_end = i
      break
    end
  end

  target_end = target_end or #buffer_lines + 1

  -- Prepare all lines to insert (parent line + sub-items)
  local lines_to_insert = { line_without_priority }

  -- Process sub-items one by one - we want to keep them exactly as they are
  for _, sub_item_content in ipairs(original_sub_items) do
    table.insert(lines_to_insert, sub_item_content)
  end

  -- Insert the lines at the end of the target category
  vim.api.nvim_buf_set_lines(0, target_end - 1, target_end - 1, true, lines_to_insert)

  -- Return the new line number of the parent item
  return target_end - 1
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

-- Helper function to toggle checkbox for a single line
function M.toggle_checkbox_for_line(line_num, line)
  -- Pattern to detect checkboxes and list items
  local list_pattern = "^(%s*%-%s+)(.*)$"
  local checkbox_pattern = "^(%s*%-%s+)%[([x%s]?)%](.*)$"

  -- Check if line has a checkbox
  local prefix, state, suffix = line:match(checkbox_pattern)
  
  if prefix then
    -- Toggle existing checkbox
    local new_state = (state == "" or state == " ") and "x" or " "
    local new_line = prefix .. "[" .. new_state .. "]" .. suffix
    vim.api.nvim_buf_set_lines(0, line_num - 1, line_num, true, {new_line})
    
    local status = new_state == "x" and "checked" or "unchecked"
    vim.api.nvim_echo({{string.format("Checkbox toggled (%s)", status), "Normal"}}, true, {})
  else
    -- Check if it's a list item without checkbox
    local list_prefix, content = line:match(list_pattern)
    if list_prefix and vim.bo.filetype == "markdown" then
      -- Create new checkbox in checked state
      local new_line = list_prefix .. "[x] " .. content
      vim.api.nvim_buf_set_lines(0, line_num - 1, line_num, true, {new_line})
      vim.api.nvim_echo({{"Checkbox created (checked)", "Normal"}}, true, {})
    else
      vim.api.nvim_echo({{string.format("No list item found on line %d", line_num), "WarningMsg"}}, true, {})
    end
  end
end

-- Function to toggle checkbox state for multiple lines in visual mode
function M.toggle_checkbox_visual()
  -- Get the visual selection range
  local start_line = vim.fn.line("'<")
  local end_line = vim.fn.line("'>")

  -- Process each line in the selection
  for line_num = start_line, end_line do
    local line = vim.fn.getline(line_num)
    M.toggle_checkbox_for_line(line_num, line)
  end
end

-- Check if a line has a checked checkbox
function M.is_checked_item(line)
  return line:match("^%s*%-%s+%[x%]") ~= nil
end

-- Interactive prioritization of selected lines
function M.prioritize_selected(skip_prioritized)
  -- Get all categories
  local categories = M.get_all_categories()
  local has_categories = #categories > 0

  -- Create a map of shortcuts to categories for quick lookup
  local shortcut_map = {}
  for _, cat in ipairs(categories) do
    shortcut_map[cat.shortcut] = cat
  end

  -- Display category shortcuts only if categories exist
  if has_categories then
    M.display_category_shortcuts(categories)
  else
    vim.api.nvim_echo({
      { "No categories found. You can only set priorities.\n", "WarningMsg" },
      { "Use ", "Normal" },
      { "1-9", "Question" },
      { " for priorities or ", "Normal" },
      { "q", "Question" },
      { " to quit.\n", "Normal" }
    }, true, {})
  end

  -- Get the current visual selection
  local start_line = vim.fn.line("'<")
  local end_line = vim.fn.line("'>")

  -- Get the lines in the selection
  local lines = {}
  for i = start_line, end_line do
    local line = vim.fn.getline(i)
    -- Skip checked items
    if not M.is_checked_item(line) then
      table.insert(lines, {
        content = line,
        line_num = i
      })
    end
  end

  -- Process each line interactively
  local i = 1
  while i <= #lines do
    local line_data = lines[i]
    local line = line_data.content
    local line_num = line_data.line_num

    -- Skip category headings and sub-items
    if M.is_category_heading(line) or M.is_sub_item(line) then
      i = i + 1
      goto continue
    end

    local current_priority = M.get_priority(line)

    -- Skip already prioritized items if requested
    if not (skip_prioritized and current_priority) then
      -- Find the current category for this line
      local current_category = has_categories and M.find_line_category(line_num, categories) or nil

      -- Save cursor position
      local saved_view = vim.fn.winsaveview()

      -- Highlight the current line
      vim.api.nvim_win_set_cursor(0, { line_num, 0 })
      vim.cmd("normal! V")

      -- Prompt for priority or category change
      local prompt = string.format("Line %d", line_num)
      if current_category then
        prompt = prompt .. string.format(" (in %s)", current_category.name)
      end
      prompt = prompt .. ": "

      vim.api.nvim_echo({
        { prompt,                "Question" },
        { line:gsub("^%s+", ""), "Normal" }
      }, true, {})

      local char = vim.fn.getchar()
      local input = char == 27 and "q" or vim.fn.nr2char(char)

      -- Process input
      if input == "q" then
        break
      elseif input == "s" then
        -- Skip this item (do nothing and move to next)
        vim.api.nvim_echo({
          { "Skipped", "Normal" }
        }, true, {})
      elseif input:match("[1-9]") then
        -- Assign priority
        local priority = tonumber(input)
        local new_line = M.format_with_priority(line, priority)
        vim.api.nvim_buf_set_lines(0, line_num - 1, line_num, true, { new_line })
      elseif has_categories and shortcut_map[input] then
        -- Move to another category
        local target_category = shortcut_map[input]
        if current_category and current_category.name ~= target_category.name then
          -- Move the line to the new category
          local new_line_num = M.move_to_category(line, line_num, current_category, target_category)

          -- Update the line data for the next iteration
          line_data.line_num = new_line_num

          -- Notify about the move
          vim.api.nvim_echo({
            { string.format("Moved to %s", target_category.name), "Normal" }
          }, true, {})

          -- Special handling: since we moved the line, we may need to adjust other line numbers
          for j = i + 1, #lines do
            if lines[j].line_num > line_num then
              lines[j].line_num = lines[j].line_num - 1
            end
          end

          -- Skip incrementing i since we need to process the same item again (at its new position)
          goto continue
        end
      end

      -- Restore cursor position
      vim.fn.winrestview(saved_view)
    end

    i = i + 1
    ::continue::
  end

  -- Notify the user that the operation is complete
  vim.api.nvim_echo({ { "Prioritization complete", "Normal" } }, true, {})
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
  local current_category = nil

  for i, line in ipairs(lines) do
    local absolute_line_num = start_line + i - 1

    if M.is_category_heading(line) then
      -- Start a new block for the category heading
      if current_block then
        table.insert(blocks, current_block)
      end

      current_category = M.get_category_name(line)
      current_block = {
        category = current_category,
        start_line = i,
        lines = { line }
      }
    elseif current_block then
      -- Add line to the current block
      table.insert(current_block.lines, line)
    else
      -- Line is before any category - create a block for it
      local line_category = M.find_line_category(absolute_line_num, categories)
      local category_name = line_category and line_category.name or "Uncategorized"

      current_block = {
        category = category_name,
        start_line = i,
        lines = { line }
      }
    end
  end

  -- Add the last block
  if current_block then
    table.insert(blocks, current_block)
  end

  -- For each block, sort the lines by priority (but keep heading at the top)
  for _, block in ipairs(blocks) do
    if #block.lines > 1 then
      -- Separate category heading if present
      local heading = nil
      if M.is_category_heading(block.lines[1]) then
        heading = table.remove(block.lines, 1)
      end

      -- Group parent items with their sub-items
      local item_groups = {}
      local i = 1

      while i <= #block.lines do
        local line = block.lines[i]
        local is_heading = M.is_category_heading(line)
        local is_sub = M.is_sub_item(line)
        local is_checked = M.is_checked_item(line)

        if is_heading or is_sub then
          -- Skip headings and sub-items (we handle them as part of parent items)
          i = i + 1
        else
          -- This is a parent item - find all its sub-items
          local group = {
            parent = {
              line = line,
              priority = M.get_priority(line),
              original_pos = i,
              is_checked = is_checked
            },
            sub_items = {}
          }

          -- Collect sub-items
          local j = i + 1
          while j <= #block.lines and M.is_sub_item(block.lines[j]) do
            table.insert(group.sub_items, block.lines[j])
            j = j + 1
          end

          table.insert(item_groups, group)
          i = j -- Skip past the sub-items
        end
      end

      -- Sort the groups by parent priority (stable sort)
      table.sort(item_groups, function(a, b)
        -- Move checked items to the bottom
        if a.parent.is_checked ~= b.parent.is_checked then
          return not a.parent.is_checked
        end

        -- Both have priorities
        if a.parent.priority and b.parent.priority then
          if a.parent.priority ~= b.parent.priority then
            return a.parent.priority < b.parent.priority
          end
          -- Same priority - maintain original order
          return a.parent.original_pos < b.parent.original_pos
        end

        -- Only a has priority
        if a.parent.priority and not b.parent.priority then
          return true
        end

        -- Only b has priority
        if not a.parent.priority and b.parent.priority then
          return false
        end

        -- Neither has priority - maintain original order
        return a.parent.original_pos < b.parent.original_pos
      end)

      -- Flatten the sorted groups back into lines
      local sorted_lines = {}
      for _, group in ipairs(item_groups) do
        table.insert(sorted_lines, group.parent.line)
        for _, sub_item in ipairs(group.sub_items) do
          table.insert(sorted_lines, sub_item)
        end
      end

      block.lines = sorted_lines

      -- Put the heading back
      if heading then
        table.insert(block.lines, 1, heading)
      end
    end
  end

  -- Reconstruct the sorted lines
  local sorted_lines = {}
  for _, block in ipairs(blocks) do
    for _, line in ipairs(block.lines) do
      table.insert(sorted_lines, line)
    end
  end

  -- Replace the lines in the buffer
  vim.api.nvim_buf_set_lines(0, start_line - 1, end_line, true, sorted_lines)

  -- Notify the user that the operation is complete
  vim.api.nvim_echo({ { "Sorting complete", "Normal" } }, true, {})
end

return M
