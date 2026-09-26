local M = {}

---@param opts? intellij.Opts
function M.setup(opts)
  local config = require('intellij.config')
  config.set(opts)
  vim.lsp.config('intellij', { filetypes = config.get().filetypes })
  vim.lsp.enable('intellij')
end

return M
