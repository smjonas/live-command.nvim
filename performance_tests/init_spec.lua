local cmd_preview = require("cmd_preview")

local measure_time = function(f)
  return function()
    local start_s, start_us = vim.loop.gettimeofday()
    f()
    local end_s, end_us = vim.loop.gettimeofday()
    local start_ms = start_s * 1000.0 + start_us / 1000.0
    local end_ms = end_s * 1000.0 + end_us / 1000.0
    print(("Took %d ms."):format(end_ms - start_ms))
  end
end

describe(
  "Performance test",
  it(
    "for Levenshtein distance algorithm",
    measure_time(function()
      local a = ("A"):rep(20000)
      local b = ("B"):rep(20000)
      local _, _ = cmd_preview._get_levenshtein_edits(a, b)
    end)
  )
)

-- it(
--   "performance test (common prefix and suffix)",
--   measure_time(function()
--     local a = ("A"):rep(10000) .. "a" .. ("B"):rep(10000)
--     local b = ("A"):rep(10000) .. "b" .. ("B"):rep(10000)
--     local edits, matrix = cmd_preview._get_levenshtein_edits(a, b)

--     assert.are_same({
--       { type = "replacement", start_pos = 10001, end_pos = 10002 },
--     }, edits)
--     assert.are_same({
--       { [0] = 0, 1 },
--       { [0] = 1, 1 },
--     }, matrix)
--   end)
-- )
