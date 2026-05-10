local m = {}

-- プレビューウィンドウのid（グローバル状態）
---@type number | nil プレビューウィンドウid
m.preview_win = nil

---@type number | nil プレビューバッファid
m.preview_buf = nil

---プレビューバッファを作成する
---@return number バッファid
local function create_preview_buffer()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  return buf
end

---プレビューウィンドウを作成する
---右側に固定、高さはpickerと同じ、幅は自動計算
---pickerのボーダー・ハイライト・autocommand設定を継承
---@return number | nil ウィンドウid、失敗時はnil
function m.open()
  -- 既存ウィンドウをクローズ
  m.close()

  -- プレビューバッファ作成
  m.preview_buf = create_preview_buffer()

  -- pickerウィンドウ（親ウィンドウ）を取得
  local picker_win = vim.api.nvim_get_current_win()

  -- ウィンドウが有効か確認
  if not vim.api.nvim_win_is_valid(picker_win) then
    return nil
  end

  local picker_win_config = vim.api.nvim_win_get_config(picker_win)

  -- pickerウィンドウが浮動ウィンドウであることを確認
  if not picker_win_config.relative or picker_win_config.relative == "" then
    return nil
  end

  -- プレビューウィンドウの左端を計算
  -- anchor は nvim_win_get_config から大文字で返る ("NW", "SW", "NE", "SE")
  local col
  local width
  if picker_win_config.anchor == "NW" or picker_win_config.anchor == "SW" then
    col = picker_win_config.col + picker_win_config.width + 4
    width = vim.o.columns - col
  else
    col = vim.o.columns
    width = vim.o.columns - (picker_win_config.col + 2)
  end

  local row = picker_win_config.row
  local height = picker_win_config.height

  -- プレビューウィンドウの設定
  local preview_config = {
    relative = "editor",
    focusable = false,
    style = "minimal",
    border = picker_win_config.border,
    noautocmd = picker_win_config.noautocmd,
    anchor = picker_win_config.anchor,
    zindex = (picker_win_config.zindex or 1) - 1,
    height = height,
    row = row,
    col = col,
    width = width,
  }

  -- プレビューウィンドウ作成
  pcall(function()
    m.preview_win = vim.api.nvim_open_win(m.preview_buf, false, preview_config)
  end)

  -- ハイライトをpickerから継承
  -- highlight group名は大文字小文字を区別する（MiniPickNormal, MiniPickBorder）
  if m.preview_win and vim.api.nvim_win_is_valid(m.preview_win) then
    pcall(function()
      vim.api.nvim_set_hl(0, "MiniPickPreviewNormal", { link = "MiniPickNormal" })
      vim.api.nvim_set_hl(0, "MiniPickPreviewBorder", { link = "MiniPickBorder" })
      vim.api.nvim_win_set_config(
        m.preview_win,
        { winhighlight = "Normal:MiniPickPreviewNormal,FloatBorder:MiniPickPreviewBorder" }
      )
    end)
  end

  return m.preview_win
end

---プレビューウィンドウをクローズする
function m.close()
  if m.preview_win and vim.api.nvim_win_is_valid(m.preview_win) then
    vim.api.nvim_win_close(m.preview_win, true)
    m.preview_win = nil
  end

  if m.preview_buf and vim.api.nvim_buf_is_valid(m.preview_buf) then
    vim.api.nvim_buf_delete(m.preview_buf, { force = true })
    m.preview_buf = nil
  end
end

---プレビューウィンドウが表示中かどうか
---@return boolean 表示中ならtrue
function m.is_open()
  return m.preview_win ~= nil and vim.api.nvim_win_is_valid(m.preview_win)
end

---プレビューバッファのidを取得
---@return number | nil バッファid、表示中でなければnil
function m.get_preview_buf()
  return m.preview_buf
end

---プレビューウィンドウをスクロールする
-- "\x05" は <C-e>（下スクロール）、"\x19" は <C-y>（上スクロール）
---@param direction string "up" または "down"
function m.scroll(direction)
  if not m.is_open() then return end
  local win = m.preview_win
  local keys = direction == "down" and "5\x05" or "5\x19"
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_call(win, function()
      vim.cmd("normal! " .. keys)
    end)
  end
end

---ターミナルリサイズ時にプレビューウィンドウの位置・サイズを再計算する
function m.respawn()
  if not m.is_open() then return end

  local picker_win = vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(picker_win) then return end

  local picker_win_config = vim.api.nvim_win_get_config(picker_win)

  -- pickerウィンドウが浮動ウィンドウであることを確認
  if not picker_win_config.relative or picker_win_config.relative == "" then return end

  local col
  local width
  if picker_win_config.anchor == "NW" or picker_win_config.anchor == "SW" then
    col = picker_win_config.col + picker_win_config.width + 4
    width = vim.o.columns - col
  else
    col = vim.o.columns
    width = vim.o.columns - (picker_win_config.col + 2)
  end

  local preview_config = {
    relative = "editor",
    row = picker_win_config.row,
    col = col,
    width = width,
    height = picker_win_config.height,
  }

  vim.api.nvim_win_set_config(m.preview_win, preview_config)
end

return m
