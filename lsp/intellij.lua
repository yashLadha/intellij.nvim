---@type vim.lsp.Config
return {
  filetypes = { 'java' },
  cmd = function(dispatchers, config)
    return require('intellij.lsp').cmd(dispatchers, config)
  end,
  root_dir = function(bufnr, on_dir)
    require('intellij.lsp').root_dir(bufnr, on_dir)
  end,
  before_init = function(params, config)
    require('intellij.lsp').before_init(params, config)
  end,
  handlers = require('intellij.lsp').handlers,
  workspace_required = true,
}
