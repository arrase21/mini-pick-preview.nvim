local M = {}

local window = require("mini-pick-preview.window")

---アイテムがgitコミットハッシュかどうかを判定する
---@param item any 判定対象
---@return boolean
local function is_git_commit(item)
  if type(item) ~= "string" then return false end
  return item:match("^%x%x%x%x%x%x%x") ~= nil
end

---アイテムがgitブランチ行かどうかを判定する
---@param item any 判定対象
---@return boolean
local function is_git_branch(item)
  if type(item) ~= "string" then return false end
  return item:match("^[%*%s][%s]%S") ~= nil and not is_git_commit(item)
end

---gitコミットの内容をプレビューバッファに表示する
---@param preview_buf number バッファID
---@param hash string コミットハッシュ文字列
local function preview_git_commit(preview_buf, hash)
  local clean_hash = hash:match("^(%x+)")
  if not clean_hash then return end
  local ok, result = pcall(vim.fn.systemlist, "git show --stat --color=never " .. clean_hash)
  if not ok or vim.v.shell_error ~= 0 then return end
  vim.bo[preview_buf].modifiable = true
  vim.bo[preview_buf].filetype = "git"
  vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, result)
  vim.bo[preview_buf].modifiable = false
end

---gitブランチのログをプレビューバッファに表示する
---@param preview_buf number バッファID
---@param branch_line string ブランチ行文字列
local function preview_git_branch(preview_buf, branch_line)
  local branch = branch_line:match("^%*?%s*(.-)%s*$")
  branch = branch:match("^%((.-)%)$") or branch
  if not branch or branch == "" then return end
  local ok, result = pcall(vim.fn.systemlist, "git log --oneline -20 --color=never " .. branch)
  if not ok or vim.v.shell_error ~= 0 then return end
  vim.bo[preview_buf].modifiable = true
  vim.bo[preview_buf].filetype = "git"
  vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, result)
  vim.bo[preview_buf].modifiable = false
end

---プレビューバッファをリセットする
---@param preview_buf number バッファID
local function reset_preview_buf(preview_buf)
  vim.bo[preview_buf].modifiable = true
  vim.bo[preview_buf].filetype = ""
  vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, {})
end

-- タイマー状態管理
local current_timer = nil
local last_item = nil

---プレビューを更新する（共通処理）
---@param item any 現在選択されているアイテム
local function update_preview(item)
  -- プレビューウィンドウが表示中か確認
  if not window.is_open() then return end
  if not MiniPick or not MiniPick.default_preview then return end

  -- プレビューバッファに表示
  local preview_buf = window.get_preview_buf()
  if not preview_buf or not vim.api.nvim_buf_is_valid(preview_buf) then return end

  pcall(function()
    if type(item) == "string" and is_git_commit(item) then
      preview_git_commit(preview_buf, item)
    elseif type(item) == "string" and is_git_branch(item) then
      preview_git_branch(preview_buf, item)
    else
      reset_preview_buf(preview_buf)
      -- 非同期処理を待ってから画面更新
      MiniPick.default_preview(preview_buf, item)
    end
    vim.defer_fn(function()
      pcall(vim.cmd, "redraw")
    end, MiniPick.config.delay.async)
  end)
end

---タイマーコールバック：カーソル移動を検知してプレビューを更新する
local function on_timer_tick()
  -- fast event contextのため、メインループで実行するようスケジュール
  vim.schedule(function()
    local ok, err = pcall(function()
      -- MiniPick が利用可能か確認
      if not MiniPick or not MiniPick.get_picker_matches then return end

      -- 現在のマッチ情報を取得
      local ok_matches, matches = pcall(MiniPick.get_picker_matches)
      if not ok_matches or not matches then return end

      -- 現在選択されているアイテムを取得
      local item = matches.current
      if not item then return end

      -- 前回のアイテムと比較してプレビューを更新
      if item ~= last_item then
        last_item = item
        update_preview(item)
      end
    end)
    if not ok then
      vim.notify("Error in timer callback: " .. tostring(err), vim.log.levels.ERROR)
    end
  end)
end

---MiniPickStartイベント：picker開始時にプレビューウィンドウを作成する
local function on_pick_start()
  -- プレビューウィンドウ作成（右側、高さ自動、幅自動）
  window.open()

  -- タイマーを開始（100ms間隔でカーソル移動を監視）
  last_item = nil
  current_timer = vim.uv.new_timer()
  current_timer:start(100, 100, on_timer_tick)

  vim.schedule(function()
    if not MiniPick then return end
    local current_mappings = MiniPick.get_picker_opts().mappings or {}

    -- <C-j> / <C-k> でプレビューウィンドウをスクロール
    current_mappings.preview_down = {
      char = "<C-j>",
      func = function()
        window.scroll("down")
      end,
    }
    current_mappings.preview_up = {
      char = "<C-k>",
      func = function()
        window.scroll("up")
      end,
    }
    MiniPick.set_picker_opts({ mappings = current_mappings })
  end)
end

---MiniPickStopイベント：picker終了時にプレビューウィンドウをクローズする
local function on_pick_stop()
  -- タイマーを停止
  if current_timer then
    current_timer:stop()
    current_timer:close()
    current_timer = nil
  end
  last_item = nil
  window.close()
end

---イベントリスナーを登録する
function M.setup()
  local group = vim.api.nvim_create_augroup("MiniPickPreview", { clear = true })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "MiniPickStart",
    callback = on_pick_start,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "MiniPickStop",
    callback = on_pick_stop,
  })
  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      if window.is_open() then
        window.respawn()
      end
    end,
  })
end

return M
