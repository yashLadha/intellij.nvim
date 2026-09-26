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
}
