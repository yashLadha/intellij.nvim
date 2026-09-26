local root = vim.fs.dirname(vim.fs.dirname(vim.fs.abspath(debug.getinfo(1, 'S').source:sub(2))))
vim.opt.runtimepath:prepend(root)
package.path = vim.fs.joinpath(root, 'tests', '?.lua') .. ';' .. package.path

local failed, total = 0, 0
local specs = vim.fn.glob(vim.fs.joinpath(root, 'tests', '*_spec.lua'), false, true)
table.sort(specs)
for _, file in ipairs(specs) do
  local tests = dofile(file)
  local names = vim.tbl_keys(tests)
  table.sort(names)
  for _, name in ipairs(names) do
    total = total + 1
    local ok, err = pcall(tests[name])
    local label = vim.fn.fnamemodify(file, ':t:r') .. ': ' .. name
    if ok then
      print('ok   ' .. label)
    else
      failed = failed + 1
      print('FAIL ' .. label .. '\n     ' .. tostring(err))
    end
  end
end
print(('%d/%d passed'):format(total - failed, total))
os.exit(failed > 0 and 1 or 0)
