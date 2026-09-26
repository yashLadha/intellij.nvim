local h = require('helpers')

---@param stdout string
---@param code integer
---@return string
local function platform_report(stdout, code)
  h.reset()
  local system = vim.system
  require('intellij.server').target = function()
    return 'linux-x64'
  end
  vim.system = function()
    return {
      wait = function()
        return { code = code, stdout = stdout }
      end,
    }
  end
  vim.cmd('checkhealth intellij')
  vim.wait(3000, function()
    return vim.api.nvim_buf_line_count(0) > 5
  end)
  vim.system = system
  return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
end

return {
  ['glibc new enough is ok'] = function()
    assert(platform_report('glibc 2.35\n', 0):find('OK glibc 2.35', 1, true))
  end,

  ['glibc too old is an error'] = function()
    assert(platform_report('glibc 2.17\n', 0):find('glibc 2.17 is too old', 1, true))
  end,

  ['missing glibc is an error'] = function()
    assert(platform_report('', 1):find('Could not detect glibc', 1, true))
  end,
}
