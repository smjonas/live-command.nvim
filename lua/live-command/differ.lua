local M = {}

M.get_diff = function(old_lines, new_lines)
  return vim.diff(table.concat(old_lines, "\n"), table.concat(new_lines, "\n"), {
    result_type = "indices",
  })
end

return M
