local h = require('helpers')

--- In-process stand-in for the server so attach decisions can be tested without spawning it.
---@param dispatchers vim.lsp.rpc.Dispatchers
---@return vim.lsp.rpc.PublicClient
local function fake_rpc(dispatchers)
  local closing = false
  local id = 0
  return {
    request = function(method, _, callback)
      id = id + 1
      local result = method == 'initialize' and { capabilities = {} } or vim.NIL
      vim.schedule(function()
        callback(nil, result)
      end)
      return true, id
    end,
    notify = function(method)
      if method == 'exit' then
        closing = true
        vim.schedule(function()
          dispatchers.on_exit(0, 0)
        end)
      end
      return true
    end,
    is_closing = function()
      return closing
    end,
    terminate = function()
      closing = true
    end,
  }
end

---@param filetype string
---@return integer
local function open(filetype)
  local root = h.tmpdir()
  h.tree(root, { '.git/', 'src/A.' .. filetype })
  local bufnr = h.buf(vim.fs.joinpath(root, 'src', 'A.' .. filetype))
  vim.api.nvim_set_current_buf(bufnr)
  vim.bo[bufnr].filetype = filetype
  return bufnr
end

---@param bufnr integer
---@return boolean
local function attached(bufnr)
  return vim.wait(1000, function()
    return #vim.lsp.get_clients({ name = 'intellij', bufnr = bufnr }) > 0
  end, 10)
end

return {
  ['setup configures filetypes and enables the config'] = function()
    h.reset()
    require('intellij').setup({ filetypes = { 'java', 'kotlin' }, data_dir = h.tmpdir() })
    h.eq({ 'java', 'kotlin' }, vim.lsp.config.intellij.filetypes)
    h.eq(true, vim.lsp.is_enabled('intellij'))
    vim.lsp.enable('intellij', false)
  end,

  ['attaches only to configured filetypes'] = function()
    h.reset()
    local server_dir, data_dir = h.tmpdir(), h.tmpdir()
    h.fake_server(server_dir)
    require('intellij').setup({
      filetypes = { 'java' },
      server_dir = server_dir,
      data_dir = data_dir,
    })
    vim.fn.writefile(
      { require('intellij.server').eula_hash(server_dir) },
      vim.fs.joinpath(data_dir, 'eula')
    )
    require('intellij.lsp').cmd = fake_rpc
    local java, kotlin = open('java'), open('kotlin')
    h.eq(true, attached(java))
    h.eq(false, attached(kotlin))
    for _, client in ipairs(vim.lsp.get_clients({ name = 'intellij' })) do
      client:stop(true)
    end
    vim.lsp.enable('intellij', false)
  end,
}
