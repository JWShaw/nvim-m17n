-- nvim-m17n: toggle an m17n (.mim) input method in Insert mode.
--
-- The heavy lifting is done by Neovim's built-in language mappings (:lmap),
-- which are consulted only when the buffer-local 'iminsert' option is 1.
-- Language mappings support multi-key sequences and the "dead key" behaviour
-- (waiting for the next key when the current sequence could still be extended),
-- which is exactly what transliteration style m17n input methods need.
--
-- 'iminsert' is also honoured by single-character Normal-mode commands such as
-- "r" and "f".  To keep every non-Insert mode behaving normally, this plugin
-- keeps the logical on/off state in Lua and only turns 'iminsert' on while
-- actually inside Insert mode:
--
--   InsertEnter -> restore 'iminsert' from the logical state
--   InsertLeave -> remember the real 'iminsert' (so built-in <C-^> works)
--                  and reset it to 0
--
-- Searching also honours language mappings, but through 'imsearch'; by default
-- the plugin keeps 'imsearch' at 0 so "/" searches stay literal.

local mim = require("m17n.mim")

local M = {}

--- @class M17nConfig
--- @field mim string             Name of a bundled `mim/<name>.mim` file, or a path to a .mim file.
--- @field search boolean         Also translate while typing search patterns ('imsearch').
--- @field default_on boolean     Enable the input method in every buffer automatically.
--- @field toggle_keymap string|nil  Optional Insert-mode mapping that toggles the input method.

M.config = {
  mim = "ru-translit",
  search = false,
  default_on = false,
  toggle_keymap = nil,
}

local state = {
  entries = nil, -- parsed keymap entries, or false when loading failed
  applied = {}, -- bufnr -> true once language mappings have been installed
  enabled = {}, -- bufnr -> logical on/off state (nil = never used)
}

local core_group = vim.api.nvim_create_augroup("m17n", { clear = true })
local setup_group = vim.api.nvim_create_augroup("m17n_setup", { clear = true })

local function notify(msg, level)
  vim.notify("m17n: " .. msg, level or vim.log.levels.WARN)
end

local function norm(buf)
  if buf == nil or buf == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return buf
end

local function in_insert_mode()
  return vim.fn.mode():sub(1, 1) == "i"
end

--- Resolve `M.config.mim` to a readable file path.
local function resolve_path(name)
  if type(name) ~= "string" then return nil end
  if vim.fn.filereadable(name) == 1 then return name end

  local base = name:gsub("%.mim$", "")
  local matches = vim.fn.globpath(vim.o.runtimepath, "mim/" .. base .. ".mim", false, true)
  return matches[1]
end

--- Load (and cache) the parsed keymap entries.  Returns nil on failure.
local function load_entries()
  if state.entries ~= nil then
    return state.entries or nil
  end

  local path = resolve_path(M.config.mim)
  if not path then
    notify(("could not find input method %q"):format(M.config.mim))
    state.entries = false
    return nil
  end

  local entries, err = mim.parse_file(path)
  if not entries then
    notify(("could not read %s: %s"):format(path, err))
    state.entries = false
    return nil
  end

  state.entries = entries
  return entries
end

--- Escape characters that would be interpreted specially in a mapping lhs.
local function escape_lhs(lhs)
  return (lhs:gsub("<", "\\<"))
end

--- Install the language mappings on a buffer (idempotent).
local function apply_to_buffer(buf)
  if state.applied[buf] then
    return true
  end

  local entries = load_entries()
  if not entries then
    return false
  end

  local failed = 0
  for _, entry in ipairs(entries) do
    local ok = pcall(vim.api.nvim_buf_set_keymap, buf, "l", escape_lhs(entry.lhs), entry.rhs,
      { noremap = true, silent = true })
    if not ok then
      failed = failed + 1
    end
  end

  if failed > 0 then
    notify(("%d mapping(s) could not be installed"):format(failed))
  end

  state.applied[buf] = true
  return true
end

--- Enable the input method for a buffer (defaults to the current buffer).
function M.enable(buf)
  buf = norm(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return false end
  if not apply_to_buffer(buf) then return false end

  state.enabled[buf] = true
  vim.bo[buf].imsearch = M.config.search and -1 or 0
  -- Only turn 'iminsert' on inside Insert mode; elsewhere it stays 0 so that
  -- "r", "f" and friends behave normally (see InsertEnter autocommand).
  if in_insert_mode() and vim.api.nvim_get_current_buf() == buf then
    vim.bo[buf].iminsert = 1
  end
  return true
end

--- Disable the input method for a buffer (defaults to the current buffer).
function M.disable(buf)
  buf = norm(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return false end

  state.enabled[buf] = false
  if in_insert_mode() and vim.api.nvim_get_current_buf() == buf then
    vim.bo[buf].iminsert = 0
  end
  return true
end

--- Toggle the input method.  Returns true when it is now enabled.
function M.toggle(buf)
  buf = norm(buf)
  if state.enabled[buf] == true then
    M.disable(buf)
    return false
  end
  M.enable(buf)
  return state.enabled[buf] == true
end

--- Whether the input method is logically active for a buffer.
function M.status(buf)
  return state.enabled[norm(buf)] == true
end

--- Re-read the .mim file and reinstall mappings on buffers already using it.
function M.reload()
  state.entries = nil
  local buffers = vim.tbl_keys(state.applied)
  state.applied = {}
  for _, buf in ipairs(buffers) do
    if vim.api.nvim_buf_is_valid(buf) then
      apply_to_buffer(buf)
    end
  end
end

-- Restore 'iminsert' when entering Insert mode; reset it when leaving so that
-- other modes never use language mappings.
vim.api.nvim_create_autocmd("InsertEnter", {
  group = core_group,
  callback = function(args)
    local buf = args.buf
    if state.enabled[buf] ~= nil then
      vim.bo[buf].iminsert = state.enabled[buf] and 1 or 0
    end
  end,
})

vim.api.nvim_create_autocmd("InsertLeave", {
  group = core_group,
  callback = function(args)
    local buf = args.buf
    if state.applied[buf] then
      -- Capture a change made with the built-in <C-^> toggle, then disable it
      -- outside Insert mode.
      state.enabled[buf] = vim.bo[buf].iminsert == 1
      vim.bo[buf].iminsert = 0
    end
  end,
})

--- Configure the plugin.  Call once from your config.
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  state.entries = nil
  state.applied = {}

  vim.api.nvim_clear_autocmds({ group = setup_group })

  if M.config.default_on then
    vim.api.nvim_create_autocmd("BufEnter", {
      group = setup_group,
      callback = function(args) M.enable(args.buf) end,
    })
  end

  if M.config.toggle_keymap then
    vim.keymap.set("i", M.config.toggle_keymap, function() M.toggle() end,
      { desc = "m17n: toggle input method" })
  end

  return M
end

return M
