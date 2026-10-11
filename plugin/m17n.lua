-- nvim-m17n: user commands.
-- The Lua API lives in lua/m17n/init.lua.

if vim.g.loaded_nvim_m17n == 1 then
  return
end
vim.g.loaded_nvim_m17n = 1

local m17n = require("m17n")

vim.api.nvim_create_user_command("M17nToggle", function()
  local on = m17n.toggle()
  vim.notify("m17n: input method " .. (on and "ON" or "OFF"), vim.log.levels.INFO)
end, { desc = "Toggle the m17n input method for the current buffer" })

vim.api.nvim_create_user_command("M17nEnable", function()
  m17n.enable()
end, { desc = "Enable the m17n input method for the current buffer" })

vim.api.nvim_create_user_command("M17nDisable", function()
  m17n.disable()
end, { desc = "Disable the m17n input method for the current buffer" })

vim.api.nvim_create_user_command("M17nStatus", function()
  print("m17n: input method is " .. (m17n.status() and "ON" or "OFF"))
end, { desc = "Show the m17n input method status" })

vim.api.nvim_create_user_command("M17nReload", function()
  m17n.reload()
  vim.notify("m17n: reloaded " .. tostring(m17n.config.mim), vim.log.levels.INFO)
end, { desc = "Re-read the configured .mim file" })

vim.api.nvim_create_user_command("M17nSetMim", function(args)
  m17n.config.mim = args.args
  m17n.reload()
  vim.notify("m17n: using " .. args.args, vim.log.levels.INFO)
end, { nargs = 1, complete = "file", desc = "Use another .mim file (name or path)" })
