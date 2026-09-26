local M = {}

---@param bufnr integer
---@param lines string[]
local function set_lines(bufnr, lines)
  local bo = vim.bo[bufnr]
  bo.readonly = false
  bo.modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  bo.modifiable = false
  bo.modified = false
  bo.readonly = true
end

---@param bufnr integer
function M.load(bufnr)
  local uri = vim.api.nvim_buf_get_name(bufnr)
  local bo = vim.bo[bufnr]
  -- 'nofile' keeps vim.lsp.enable() from starting a client for a path that is not a project file.
  bo.buftype = 'nofile'
  bo.swapfile = false

  local client = require('intellij.lsp').client()
  if not client then
    set_lines(bufnr, { 'intellij: no running language server to decompile ' .. uri })
    return
  end

  -- Synchronous because callers like vim.lsp.util.show_document() move the cursor into the
  -- buffer right after bufload() returns.
  local res, err = client:request_sync('workspace/executeCommand', {
    command = 'decompile',
    arguments = { uri },
  }, 30000, bufnr)
  local result = res and res.result
  if not result then
    local msg = res and res.err and res.err.message or err or 'no result'
    set_lines(bufnr, { 'intellij: cannot decompile ' .. uri .. ': ' .. msg })
    return
  end

  set_lines(bufnr, vim.split(result.code, '\r?\n'))
  bo.filetype = result.language
  vim.lsp.buf_attach_client(bufnr, client.id)
end

return M
