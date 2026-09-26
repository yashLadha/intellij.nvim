local h = require('helpers')

return {
  [':IntelliJ exists and completes subcommands'] = function()
    vim.cmd.runtime('plugin/intellij.lua')
    h.eq(2, vim.fn.exists(':IntelliJ'))
    h.eq({ 'eula', 'install', 'log', 'reload' }, vim.fn.getcompletion('IntelliJ ', 'cmdline'))
    h.eq({ 'reload' }, vim.fn.getcompletion('IntelliJ re', 'cmdline'))
  end,
}
