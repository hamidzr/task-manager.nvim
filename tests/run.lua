vim.opt.runtimepath:prepend(vim.loop.cwd())

local tm = require("task-manager")

local failures = 0

local function fail(name, message)
  failures = failures + 1
  print("not ok - " .. name .. ": " .. message)
end

local function assert_true(name, value, expected)
  if value ~= expected then
    fail(name, "expected " .. tostring(expected) .. ", got " .. tostring(value))
  end
end

local function assert_eq(name, actual, expected)
  if actual ~= expected then
    fail(name, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
  end
end

local function assert_lines(name, actual, expected)
  if #actual ~= #expected then
    fail(name, "line count " .. tostring(#actual) .. " != " .. tostring(#expected))
    return
  end

  for i, value in ipairs(expected) do
    if actual[i] ~= value then
      fail(name, "line " .. tostring(i) .. " expected " .. tostring(value) .. ", got " .. tostring(actual[i]))
      return
    end
  end
end

local function with_buffer(initial_lines, fn)
  local original_buf = vim.api.nvim_get_current_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial_lines)
  vim.api.nvim_set_current_buf(buf)

  local status, result = pcall(function()
    return fn(buf)
  end)

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  vim.api.nvim_set_current_buf(original_buf)
  vim.api.nvim_buf_delete(buf, { force = true })

  if not status then
    error(result)
  end

  return lines, result
end

local function set_marked_range(start_line, end_line)
  vim.fn.setpos("'<", { 0, start_line, 1, 0 })
  vim.fn.setpos("'>", { 0, end_line, vim.fn.col("$"), 0 })
end

local default_config = vim.deepcopy(tm.config)

local function reset_config()
  tm.config = vim.deepcopy(default_config)
end

local function run_test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    print("ok - " .. name)
  else
    failures = failures + 1
    print("not ok - " .. name .. ": " .. tostring(err))
  end
end

run_test("checked markers support", function()
  local cases = {
    {"- [x] dash", true},
    {"- [X] upper", true},
    {"* [x] star", true},
    {"+ [x] plus", true},
    {"1. [x] numbered", true},
    {"- [p1] [x] prioritized", true},
    {"- [ ] unchecked", false},
    {"- [p1] task", false},
  }

  for _, case in ipairs(cases) do
    local line = case[1]
    local expected = case[2]
    assert_true("is_checked_item(" .. line .. ")", tm.is_checked_item(line), expected)
  end
end)

run_test("move preserves blank-separated descendants", function()
  local out = with_buffer({
    "## A",
    "- parent",
    "",
    "  - child",
    "## B",
  }, function()
    local categories = tm.get_all_categories()
    tm.move_to_category(nil, 2, nil, categories[2])
  end)

  assert_lines("move_with_blank_descendants", out, {
    "## A",
    "## B",
    "- parent",
    "",
    "  - child",
  })
end)

run_test("multiple queued moves keep headings and avoid duplication", function()
  local out = with_buffer({
    "## A",
    "- one",
    "- two",
    "## B",
  }, function()
    local changes = {
      lines = {},
      moves = {
        { from = 2, target_category = { line_num = 4, name = "B" } },
        { from = 3, target_category = { line_num = 4, name = "B" } },
      },
    }
    tm._apply_prioritize_changes(changes, 1, 4)
  end)

  assert_lines("multiple_moves_to_same_category", out, {
    "## A",
    "## B",
    "- one",
    "- two",
  })
end)

run_test("multiple moves to later category", function()
  local out = with_buffer({
    "## A",
    "- one",
    "## B",
    "- two",
    "## C",
  }, function()
    local changes = {
      lines = {},
      moves = {
        { from = 2, target_category = { line_num = 5, name = "C" } },
        { from = 4, target_category = { line_num = 5, name = "C" } },
      },
    }
    tm._apply_prioritize_changes(changes, 1, 5)
  end)

  assert_lines("moves_to_later_category", out, {
    "## A",
    "## B",
    "## C",
    "- one",
    "- two",
  })
end)

run_test("sort keeps descendant blocks and checked items", function()
  local out = with_buffer({
    "## A",
    "- [p2] low",
    "  - low child",
    "- [p1] high",
    "  - high child",
    "- [x] done",
    "  - done child",
    "- plain",
    "  - plain child",
  }, function()
    set_marked_range(1, 9)
    tm.sort_by_priority()
  end)

  assert_lines("sort_by_priority", out, {
    "## A",
    "- [p1] high",
    "  - high child",
    "- [p2] low",
    "  - low child",
    "- plain",
    "  - plain child",
    "- [x] done",
    "  - done child",
  })
end)

run_test("config deep merge and checkbox setup", function()
  reset_config()
  tm.setup({ keybindings = { prioritize_new = "t" } })
  assert_eq("prioritize_all preserved", tm.config.keybindings.prioritize_all, "ta")
  assert_eq("prioritize_new set", tm.config.keybindings.prioritize_new, "t")

  tm.setup({ keybindings = { toggle_checkbox = "y" } })
  assert_eq("toggle_checkbox merged", tm.config.keybindings.toggle_checkbox, "y")
  assert_eq("sort_by_priority still present", tm.config.keybindings.sort_by_priority, "ts")

  reset_config()
end)

run_test("custom priority pattern and formats", function()
  reset_config()

  tm.setup({
    priority_pattern = "%[P(%d+)%]",
    priority_format = "%s [P%d] %s",
  })

  local line = "- [P2] task"
  assert_eq("custom priority read", tm.get_priority(line), 2)
  assert_eq("custom get_content", tm.get_content(line), "task")

  local reprioritized = tm.format_with_priority("- [P2] task", 2, 0)
  assert_eq("reprioritize idempotent", reprioritized, "- [P2] task")

  local moved = with_buffer({
    "## A",
    "- [P2] task",
    "  - child",
    "## B",
  }, function()
    local categories = tm.get_all_categories()
    tm.move_to_category(nil, 2, nil, categories[2])
  end)

  assert_lines("custom priority move", moved, {
    "## A",
    "## B",
    "- task",
    "  - child",
  })

  reset_config()
end)

run_test("move checked block to section bottom keeps descendants", function()
  local out = with_buffer({
    "## A",
    "- [ ] one",
    "  - child",
    "- two",
    "## B",
  }, function()
    vim.api.nvim_buf_set_option(0, "filetype", "markdown")
    tm.move_item_to_section_bottom(2)
  end)

  assert_lines("checked move keeps descendants", out, {
    "## A",
    "- two",
    "- [ ] one",
    "  - child",
    "## B",
  })
end)

if failures > 0 then
  print("FAILED: " .. failures .. " test(s)")
  os.exit(1)
end

print("PASS: all tests")
