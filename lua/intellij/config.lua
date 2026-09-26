local M = {}

---@class intellij.Config
---@field filetypes string[]
---@field server_dir? string
---@field data_dir string
---@field java_home? string
---@field jvm_options string[]

---@class intellij.Opts
---@field filetypes? string[]
---@field server_dir? string
---@field data_dir? string
---@field java_home? string
---@field jvm_options? string[]

---@return intellij.Config
local function defaults()
  return {
    filetypes = { 'java' },
    data_dir = vim.fs.joinpath(vim.fn.stdpath('data'), 'intellij'),
    java_home = vim.env.JAVA_HOME,
    jvm_options = {},
  }
end

---@type intellij.Config?
local current

---@param opts intellij.Opts
---@return intellij.Config
local function build(opts)
  vim.validate('opts', opts, 'table')
  vim.validate('filetypes', opts.filetypes, vim.islist, true, 'list of filetypes')
  vim.validate('server_dir', opts.server_dir, 'string', true)
  vim.validate('data_dir', opts.data_dir, 'string', true)
  vim.validate('java_home', opts.java_home, 'string', true)
  vim.validate('jvm_options', opts.jvm_options, vim.islist, true, 'list of strings')
  return vim.tbl_deep_extend('force', defaults(), opts)
end

---@param opts? intellij.Opts
function M.set(opts)
  current = build(opts or {})
end

---@return intellij.Config
function M.get()
  return current or build(vim.g.intellij or {})
end

return M
