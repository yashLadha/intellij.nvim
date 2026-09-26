local h = require('helpers')

---@param opts intellij.Opts
local function setup_config(opts)
  h.reset()
  require('intellij.config').set(vim.tbl_extend('force', { data_dir = h.tmpdir() }, opts))
  return require('intellij.lsp'), require('intellij.server')
end

return {
  ['init_options sends defaultSdk from java_home'] = function()
    local lsp = setup_config({ java_home = '/jdk' })
    h.eq({ intellijExtensions = true, defaultSdk = '/jdk' }, lsp.init_options())
  end,

  ['before_init lets user init_options win'] = function()
    local lsp = setup_config({ java_home = '/jdk' })
    local params = {}
    lsp.before_init(params, { init_options = { defaultSdk = '/other', extra = 1 } })
    h.eq(
      { intellijExtensions = true, defaultSdk = '/other', extra = 1 },
      params.initializationOptions
    )
  end,

  ['cmd errors when server is missing'] = function()
    local lsp = setup_config({})
    h.errors(function()
      lsp.cmd({}, { root_dir = h.tmpdir() })
    end, 'IntelliJ install')
  end,

  ['cmd errors when EULA is not accepted'] = function()
    local dir = h.tmpdir()
    h.fake_server(dir)
    local lsp = setup_config({ server_dir = dir })
    h.errors(function()
      lsp.cmd({}, { root_dir = h.tmpdir() })
    end, 'IntelliJ eula')
  end,

  ['editor.action.rename renames through the sending client'] = function()
    setup_config({})
    local calls = {}
    local rename = vim.lsp.buf.rename
    vim.lsp.buf.rename = function(new_name, opts)
      calls[#calls + 1] = { new_name = new_name, opts = opts }
    end
    local ok, err = pcall(
      vim.lsp.commands['editor.action.rename'],
      {},
      { client_id = 7, bufnr = 3 }
    )
    vim.lsp.buf.rename = rename
    assert(ok, err)
    h.eq(1, #calls)
    h.eq(nil, calls[1].new_name)
    h.eq(3, calls[1].opts.bufnr)
    h.eq(true, calls[1].opts.filter({ id = 7 }))
    h.eq(false, calls[1].opts.filter({ id = 8 }))
  end,

  ['completion apply answers a ChooseAction with the selected index'] = function()
    setup_config({})
    local requests = {}
    local client = {
      request = function(_, method, params)
        requests[#requests + 1] = { method, params }
      end,
    }
    local get_client, select = vim.lsp.get_client_by_id, vim.ui.select
    vim.lsp.get_client_by_id = function()
      return client
    end
    local prompt
    vim.ui.select = function(items, opts, on_choice)
      prompt = opts.prompt
      on_choice(items[2])
    end
    local choose = {
      kind = 'com.jetbrains.ls.kotlinLsp.requests.core.ModCommandData.ChooseAction',
      sessionId = 5,
      title = 'Multiple occurrences found',
      entries = { { index = 0, name = 'this only' }, { index = 1, name = 'all' } },
    }
    local apply = vim.lsp.commands['jetbrains.java.completion.apply']
    local ok, err = pcall(function()
      apply(
        { command = 'jetbrains.java.completion.apply', arguments = { choose } },
        { client_id = 1 }
      )
      apply({ command = 'jetbrains.java.completion.apply', arguments = { 'x' } }, { client_id = 1 })
    end)
    vim.lsp.get_client_by_id, vim.ui.select = get_client, select
    assert(ok, err)
    h.eq('Multiple occurrences found', prompt)
    h.eq({
      {
        'workspace/executeCommand',
        { command = 'chooseModCommandAction', arguments = { 5, 1 } },
      },
      {
        'workspace/executeCommand',
        { command = 'jetbrains.java.completion.apply', arguments = { 'x' } },
      },
    }, requests)
  end,

  ['server edits apply to a modified buffer'] = function()
    local lsp = setup_config({})
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, vim.fs.joinpath(h.tmpdir(), 'A.java'))
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'int length = 1;' })
    vim.lsp.util.buf_versions[bufnr] = 5
    local uri = vim.uri_from_bufnr(bufnr)
    local pos = function(character)
      return { line = 0, character = character }
    end
    local edit = {
      documentChanges = {
        {
          textDocument = { uri = uri, version = 1 },
          edits = { { range = { start = pos(4), ['end'] = pos(10) }, newText = 'len' } },
        },
      },
    }
    local get_client = vim.lsp.get_client_by_id
    vim.lsp.get_client_by_id = function()
      return { offset_encoding = 'utf-16' }
    end
    local ok, result = pcall(
      lsp.handlers['workspace/applyEdit'],
      nil,
      { edit = edit },
      { client_id = 1 }
    )
    vim.lsp.get_client_by_id = get_client
    assert(ok, result)
    h.eq(true, result.applied)
    h.eq({ 'int len = 1;' }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end,

  ['ready is false until the server is installed and the EULA accepted'] = function()
    local dir = h.tmpdir()
    h.fake_server(dir)
    local lsp, server = setup_config({ server_dir = dir })
    h.eq(false, lsp.ready())
    vim.fn.writefile(
      { server.eula_hash(dir) },
      vim.fs.joinpath(require('intellij.config').get().data_dir, 'eula')
    )
    h.eq(true, lsp.ready())
  end,
}
