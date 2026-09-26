---@type vim.lsp.Config
return {
  filetypes = require('intellij.config').get().filetypes,
  cmd = function(dispatchers, config)
    return require('intellij.lsp').cmd(dispatchers, config)
  end,
  root_dir = function(bufnr, on_dir)
    local lsp = require('intellij.lsp')
    if lsp.ready() then
      lsp.root_dir(bufnr, on_dir)
    end
  end,
  before_init = function(params, config)
    require('intellij.lsp').before_init(params, config)
  end,
  handlers = require('intellij.lsp').handlers,
  on_exit = function(code)
    require('intellij.lsp').on_exit(code)
  end,
  workspace_required = true,
}
