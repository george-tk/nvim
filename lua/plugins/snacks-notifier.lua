return {
  'folke/snacks.nvim',
  priority = 1000,
  lazy = false,
  opts = {
    notifier = {
      filter = function(notif)
        local msg = type(notif) == 'table' and notif.msg or ''
        if type(msg) == 'string' and (msg:find('^sqmeow: disconnected from ') or msg:find('^sqmeow: lost connection to ')) then
          return false
        end
        return true
      end,
    },
  },
}
