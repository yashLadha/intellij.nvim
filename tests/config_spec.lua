local h = require('helpers')

return {
  defaults = function()
    h.reset()
    local cfg = require('intellij.config').get()
    h.eq({ 'java' }, cfg.filetypes)
    h.eq({}, cfg.jvm_options)
    h.eq(vim.fs.joinpath(vim.fn.stdpath('data'), 'intellij'), cfg.data_dir)
    h.eq(vim.env.JAVA_HOME, cfg.java_home)
    h.eq(nil, cfg.server_dir)
  end,

  ['set overrides and replaces lists'] = function()
    h.reset()
    local config = require('intellij.config')
    config.set({ filetypes = { 'kotlin' }, jvm_options = { '-Xmx4g' }, server_dir = '/srv' })
    local cfg = config.get()
    h.eq({ 'kotlin' }, cfg.filetypes)
    h.eq({ '-Xmx4g' }, cfg.jvm_options)
    h.eq('/srv', cfg.server_dir)
    config.set({ filetypes = { 'java', 'kotlin' } })
    h.eq({ 'java', 'kotlin' }, config.get().filetypes)
    h.eq({}, config.get().jvm_options)
  end,

  ['set validates options'] = function()
    h.reset()
    local config = require('intellij.config')
    h.errors(function()
      config.set({ filetypes = 'java' })
    end, 'filetypes')
    h.errors(function()
      config.set({ data_dir = 1 })
    end, 'data_dir')
    h.errors(function()
      config.set({ jvm_options = { a = 1 } })
    end, 'jvm_options')
  end,

  ['vim.g.intellij is used without setup'] = function()
    h.reset()
    vim.g.intellij = { filetypes = { 'kotlin' } }
    h.eq({ 'kotlin' }, require('intellij.config').get().filetypes)
    require('intellij.config').set({})
    h.eq({ 'java' }, require('intellij.config').get().filetypes)
    h.reset()
  end,
}
