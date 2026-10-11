-- nvim-m17n: toggle an m17n (.mim) input method in Insert mode.
--
-- The heavy lifting is done by Neovim's built-in language mappings (:lmap),
-- which are enabled per-buffer with the 'iminsert' option.  Language mappings
-- support multi-key sequences and the "dead key" behaviour (waiting for the
-- next key when the current sequence could still be extended), which is exactly
-- what transliteration style m17n input methods need.
--
-- 'iminsert' is simply set to 1 while the input method is on and 0 while it is
-- off.  Note that Neovim also consults 'iminsert' for the character arguments
-- of single-character Normal-mode commands such as "r" and "f", and for search
-- via 'imsearch'.  That is the same behaviour as Vim's built-in keymaps.

local mim = require("m17n.mim")

local M = {}

--- @class M17nConfig
--- @field mim string             Name of a bundled `mim/<name>.mim` file, or a path to a .mim file.
--- @field search boolean         Also translate while typing search patterns ('imsearch').
--- @field default_on boolean     Enable the input method in every buffer automatically.
--- @field toggle_keymap string|nil  Optional Insert-mode mapping that toggles the input method.

M.config = {
  mim = "ru-translit",
  search = true,
  default_on = false,
  toggle_keymap = nil,
}

local state = {
  entries = nil, -- parsed keymap entries, or false when loading failed
  applied = {}, -- bufnr -> true once language mappings have been installed
}

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
    -- NOTE: do *not* pass `silent = true` here.  A silent language mapping
    -- suppresses the command-line redraw, so mapped characters typed while
    -- searching (/) are not shown until the next unmapped key.
    local ok = pcall(vim.api.nvim_buf_set_keymap, buf, "l", escape_lhs(entry.lhs), entry.rhs,
      { noremap = true })
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

  vim.bo[buf].iminsert = 1
  vim.bo[buf].imsearch = M.config.search and -1 or 0
  return true
end

--- Disable the input method for a buffer (defaults to the current buffer).
function M.disable(buf)
  buf = norm(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return false end
  vim.bo[buf].iminsert = 0
  return true
end

--- Toggle the input method.  Returns true when it is now enabled.
function M.toggle(buf)
  buf = norm(buf)
  if vim.bo[buf].iminsert == 1 then
    M.disable(buf)
    return false
  end
  M.enable(buf)
  return vim.bo[buf].iminsert == 1
end

--- Whether the input method is currently active for a buffer.
function M.status(buf)
  return vim.bo[norm(buf)].iminsert == 1
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
