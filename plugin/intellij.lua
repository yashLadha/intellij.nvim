if vim.g.loaded_intellij then
  return
end
vim.g.loaded_intellij = true

if vim.fn.has('nvim-0.12') == 0 then
  vim.notify('intellij.nvim requires Neovim >= 0.12', vim.log.levels.ERROR)
  return
end

local function notify(msg, level)
  vim.notify('intellij: ' .. msg, level or vim.log.levels.INFO)
end

---@param dir string
local function accept_eula(dir)
  require('intellij.server').accept_eula(dir, function(accepted)
    if not accepted then
      notify('EULA declined; the server will not start', vim.log.levels.WARN)
      return
    end
    notify('EULA accepted; IntelliJ buffers will attach')
    if vim.lsp.is_enabled('intellij') then
      vim.lsp.enable('intellij')
    end
  end)
end

---@class intellij.Subcommand
---@field impl fun()

---@type table<string, intellij.Subcommand>
local subcommands = {
  install = {
    impl = function()
      local server = require('intellij.server')
      server.install(function(err, dir)
        if err or not dir then
          notify('install failed: ' .. tostring(err), vim.log.levels.ERROR)
          return
        end
        notify('installed server to ' .. dir)
        if server.eula_accepted(dir) then
          if vim.lsp.is_enabled('intellij') then
            vim.lsp.enable('intellij')
          end
        else
          accept_eula(dir)
        end
      end)
    end,
  },
  eula = {
    impl = function()
      local dir = require('intellij.server').dir()
      if not dir then
        notify('no server found; run :IntelliJ install', vim.log.levels.ERROR)
        return
      end
      accept_eula(dir)
    end,
  },
  reload = {
    impl = function()
      require('intellij.lsp').reload(0)
    end,
  },
  log = {
    impl = function()
      local lsp = require('intellij.lsp')
      local client = lsp.client(0)
      if client and client.root_dir then
        local path =
          vim.fs.joinpath(lsp.system_path(client.root_dir), 'system', 'log', 'intellij-server.log')
        if vim.uv.fs_stat(path) then
          vim.cmd.tabnew(vim.fn.fnameescape(path))
          return
        end
      end
      vim.cmd.tabnew(vim.fn.fnameescape(vim.lsp.log.get_filename()))
    end,
  },
}

vim.api.nvim_create_user_command('IntelliJ', function(args)
  local sub = subcommands[args.fargs[1]]
  if not sub then
    notify('unknown subcommand: ' .. args.fargs[1], vim.log.levels.ERROR)
    return
  end
  sub.impl()
end, {
  nargs = 1,
  desc = 'IntelliJ language server',
  complete = function(arglead)
    local names = vim.tbl_filter(function(name)
      return vim.startswith(name, arglead)
    end, vim.tbl_keys(subcommands))
    table.sort(names)
    return names
  end,
})

vim.api.nvim_create_autocmd('BufReadCmd', {
  group = vim.api.nvim_create_augroup('intellij', { clear = true }),
  pattern = { 'jar://*', 'jrt:/*' },
  callback = function(ev)
    require('intellij.decompile').load(ev.buf)
  end,
})
