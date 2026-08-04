local M = {}

-- Helper to get all workspace image files for Snacks picker
local function get_image_files()
  local items = {}
  local exts = { 'png', 'jpg', 'jpeg', 'gif', 'webp', 'svg', 'bmp', 'tiff', 'avif', 'pdf' }
  local args = { 'fd', '--type', 'f', '--color=never' }
  for _, ext in ipairs(exts) do
    table.insert(args, '-e')
    table.insert(args, ext)
  end

  local result = vim.fn.systemlist(args)
  local cwd = vim.fn.getcwd()

  for _, rel in ipairs(result) do
    local full = vim.fs.normalize(cwd .. '/' .. rel)
    table.insert(items, {
      text = rel,
      file = full,
    })
  end

  return items
end

-- Search images with live preview and insert relative markdown link into current buffer
function M.search_and_insert_image()
  local target_buf = vim.api.nvim_get_current_buf()
  local is_markdown = (vim.bo[target_buf].filetype == 'markdown' or vim.bo[target_buf].filetype == 'text')
  local win = vim.api.nvim_get_current_win()
  local cursor_pos = vim.api.nvim_win_get_cursor(win)

  Snacks.picker({
    title = 'Search & Insert Image',
    finder = function()
      return get_image_files()
    end,
    format = 'file',
    preview = 'file',
    confirm = function(picker, item)
      picker:close()
      if not item or not item.file then
        return
      end

      if not is_markdown then
        vim.cmd('edit ' .. vim.fn.fnameescape(item.file))
        return
      end

      -- Calculate relative path from current markdown file
      local buf_path = vim.api.nvim_buf_get_name(target_buf)
      local buf_dir = (buf_path ~= '' and vim.fs.dirname(buf_path)) or vim.fn.getcwd()
      local rel_path = vim.fs.relpath(buf_dir, item.file)

      if not rel_path then
        rel_path = item.file
      elseif not rel_path:find('^%.') and not rel_path:find('^/') then
        rel_path = './' .. rel_path
      end

      local base_name = vim.fs.basename(item.file):gsub('%.%w+$', ''):gsub('[-_]', ' ')
      local md_link = string.format('![%s](%s)', base_name, rel_path)

      -- Insert markdown link at cursor position
      local cur_line = vim.api.nvim_buf_get_lines(target_buf, cursor_pos[1] - 1, cursor_pos[1], false)[1] or ''
      local new_line
      if cur_line:match('^%s*$') then
        new_line = md_link
      else
        local col = cursor_pos[2]
        new_line = cur_line:sub(1, col) .. md_link .. cur_line:sub(col + 1)
      end

      vim.api.nvim_buf_set_lines(target_buf, cursor_pos[1] - 1, cursor_pos[1], false, { new_line })
      vim.notify('Inserted image link: ' .. rel_path, vim.log.levels.INFO, { title = 'Snacks Image' })
    end,
  })
end

_G.SnacksImageUtils = M

return {
  'folke/snacks.nvim',
  ---@type snacks.Config
  opts = {
    image = {
      enabled = true,
      doc = {
        -- Render images inline directly in markdown, latex, and text documents
        inline = true,
        -- Display images in a floating window when hovered
        float = true,
        max_width = 80,
        max_height = 40,
      },
    },
  },
  keys = {
    -- Search images and insert relative markdown link into buffer
    {
      '<leader>mi',
      function()
        M.search_and_insert_image()
      end,
      desc = 'Insert Image',
      mode = { 'n', 'v' },
    },
    -- Global finder for images in picker
    {
      '<leader>fi',
      function()
        Snacks.picker({
          title = 'Workspace Images',
          finder = function()
            return get_image_files()
          end,
          format = 'file',
          preview = 'file',
        })
      end,
      desc = 'Images',
    },
  },
}
