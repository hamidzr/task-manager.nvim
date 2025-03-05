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
    prioritize_all = "ta",      -- (t)odo (a)ll prioritize
    prioritize_new = "tn",      -- (t)odo (n)ew prioritize
    sort_by_priority = "ts",    -- (t)odo (s)ort
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
end

-- Extract existing priority from a line, if any
function M.get_priority(line)
  local priority = line:match(M.config.priority_pattern)
  return priority and tonumber(priority) or nil
end

-- Extract the list marker from the beginning of a line (if any)
function M.get_list_marker(line)
  -- Match common list markers like "- ", "* ", "1. ", etc.
  local marker = line:match("^%s*([%-%*%+]%s+)")
  if marker then
    return marker
  end

  -- Match numbered lists
  marker = line:match("^%s*(%d+%.%s+)")
  if marker then
    return marker
  end

  return ""
end

-- Extract the content of a line without list marker and priority
function M.get_content(line)
  -- Remove list marker
  local content = line:gsub("^%s*[%-%*%+]%s+", "")
  content = content:gsub("^%s*%d+%.%s+", "")

  -- Remove priority tag if it exists
  content = content:gsub("%s*%[p%d+%]%s*", " ")

  -- Trim leading/trailing whitespace
  content = content:gsub("^%s*(.-)%s*$", "%1")

  return content
end

-- Format a line with the given priority
function M.format_with_priority(line, priority)
  local list_marker = M.get_list_marker(line)
  local content = M.get_content(line)

  return string.format(M.config.priority_format, list_marker, priority, content)
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
    if not used_shortcuts[char] then
      return char
    end
  end

  -- If all fails, use a number
  for i = 1, 9 do
    local char = tostring(i)
    if not used_shortcuts[char] then
      return char
    end
  end

  return "?"  -- Should never happen unless you have more than 35 categories
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

  return nil  -- Line is before any category
end

-- Move a line from one category to another
function M.move_to_category(line, line_num, source_category, target_category)
  -- Delete the line from its current position
  vim.api.nvim_buf_set_lines(0, line_num-1, line_num, true, {})

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

  -- Insert the line at the end of the target category
  vim.api.nvim_buf_set_lines(0, target_end-1, target_end-1, true, {line})

  -- Return the new line number
  return target_end-1
end

-- Display a formatted table of categories and their shortcuts
function M.display_category_shortcuts(categories)
  -- Calculate the maximum length of category names for formatting
  local max_length = 0
  for _, cat in ipairs(categories) do
    max_length = math.max(max_length, #cat.name)
  end

  -- Build the message
  local msg = {{"Category Shortcuts:\n", "Title"}}

  -- Add headers
  table.insert(msg, {"Key", "Special"})
  table.insert(msg, {" | ", "Normal"})
  table.insert(msg, {"Category", "Special"})
  table.insert(msg, {"\n" .. string.rep("-", 15 + max_length) .. "\n", "Normal"})

  -- Add each category with its shortcut
  for _, cat in ipairs(categories) do
    table.insert(msg, {" " .. cat.shortcut .. " ", "Question"})
    table.insert(msg, {" | ", "Normal"})
    table.insert(msg, {cat.name .. "\n", "Normal"})
  end

  -- Add instruction for numbers
  table.insert(msg, {"\nUse ", "Normal"})
  table.insert(msg, {"1-9", "Question"})
  table.insert(msg, {" for priorities, ", "Normal"})
  table.insert(msg, {"letter shortcuts", "Question"})
  table.insert(msg, {" to move between categories, or ", "Normal"})
  table.insert(msg, {"q", "Question"})
  table.insert(msg, {" to quit.\n", "Normal"})

  -- Display the message
  vim.api.nvim_echo(msg, true, {})
end

-- Interactive prioritization of selected lines
function M.prioritize_selected(skip_prioritized)
  -- Get all categories
  local categories = M.get_all_categories()
  if #categories == 0 then
    vim.api.nvim_echo({{"No categories found in the document", "ErrorMsg"}}, true, {})
    return
  end

  -- Create a map of shortcuts to categories for quick lookup
  local shortcut_map = {}
  for _, cat in ipairs(categories) do
    shortcut_map[cat.shortcut] = cat
  end

  -- Display category shortcuts
  M.display_category_shortcuts(categories)

  -- Get the current visual selection
  local start_line = vim.fn.line("'<")
  local end_line = vim.fn.line("'>")

  -- Get the lines in the selection
  local lines = {}
  for i = start_line, end_line do
    table.insert(lines, {
      content = vim.fn.getline(i),
      line_num = i
    })
  end

  -- Process each line interactively
  local i = 1
  while i <= #lines do
    local line_data = lines[i]
    local line = line_data.content
    local line_num = line_data.line_num

    -- Skip category headings
    if M.is_category_heading(line) then
      i = i + 1
      goto continue
    end

    local current_priority = M.get_priority(line)

    -- Skip already prioritized items if requested
    if not (skip_prioritized and current_priority) then
      -- Find the current category for this line
      local current_category = M.find_line_category(line_num, categories)

      -- Save cursor position
      local saved_view = vim.fn.winsaveview()

      -- Highlight the current line
      vim.api.nvim_win_set_cursor(0, {line_num, 0})
      vim.cmd("normal! V")

      -- Prompt for priority or category change
      local prompt = string.format("Line %d", line_num)
      if current_category then
        prompt = prompt .. string.format(" (in %s)", current_category.name)
      end
      prompt = prompt .. ": "

      vim.api.nvim_echo({
        {prompt, "Question"},
        {line:gsub("^%s+", ""), "Normal"}
      }, true, {})

      local char = vim.fn.getchar()
      local input = char == 27 and "q" or vim.fn.nr2char(char)

      -- Clear visual selection
      vim.cmd("normal! <Esc>")

      -- Process input
      if input == "q" then
        break
      elseif input:match("[1-9]") then
        -- Assign priority
        local priority = tonumber(input)
        local new_line = M.format_with_priority(line, priority)
        vim.api.nvim_buf_set_lines(0, line_num-1, line_num, true, {new_line})
      elseif shortcut_map[input] then
        -- Move to another category
        local target_category = shortcut_map[input]
        if current_category and current_category.name ~= target_category.name then
          -- Move the line to the new category
          local new_line_num = M.move_to_category(line, line_num, current_category, target_category)

          -- Update the line data for the next iteration
          line_data.line_num = new_line_num

          -- Notify about the move
          vim.api.nvim_echo({
            {string.format("Moved to %s", target_category.name), "Normal"}
          }, true, {})

          -- Special handling: since we moved the line, we may need to adjust other line numbers
          for j = i+1, #lines do
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
  vim.api.nvim_echo({{"Prioritization complete", "Normal"}}, true, {})
end

-- Sort selected lines by priority (stable sort within categories)
function M.sort_by_priority()
  -- Get the current visual selection
  local start_line = vim.fn.line("'<")
  local end_line = vim.fn.line("'>")

  -- Get all categories
  local categories = M.get_all_categories()

  -- Get the lines in the selection
  local lines = vim.api.nvim_buf_get_lines(0, start_line-1, end_line, true)

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
        lines = {line}
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
        lines = {line}
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

      -- Sort the rest by priority (stable sort)
      -- We'll use a stable sort implementation to preserve original order
      -- First, tag each line with its original position
      local tagged_lines = {}
      for i, line in ipairs(block.lines) do
        tagged_lines[i] = {
          line = line,
          original_pos = i,
          priority = M.get_priority(line)
        }
      end

      -- Perform the stable sort
      table.sort(tagged_lines, function(a, b)
        -- Both have priorities
        if a.priority and b.priority then
          if a.priority ~= b.priority then
            return a.priority < b.priority
          end
          -- Same priority - maintain original order
          return a.original_pos < b.original_pos
        end

        -- Only a has priority
        if a.priority and not b.priority then
          return true
        end

        -- Only b has priority
        if not a.priority and b.priority then
          return false
        end

        -- Neither has priority - maintain original order
        return a.original_pos < b.original_pos
      end)

      -- Extract the sorted lines
      for i, tagged_line in ipairs(tagged_lines) do
        block.lines[i] = tagged_line.line
      end

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
  vim.api.nvim_buf_set_lines(0, start_line-1, end_line, true, sorted_lines)

  -- Notify the user that the operation is complete
  vim.api.nvim_echo({{"Sorting complete", "Normal"}}, true, {})
end

return M
