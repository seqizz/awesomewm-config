local naughty = require("naughty")
-- app_name opts the error toasts into notification_history: dbus-only
-- notifications are recorded, internal popups need this stamp.
local notification_history = require("my_modules/notification_history")

if awesome.startup_errors then
  naughty.notification({
    urgency = 'critical',
    timeout = 0,
    app_name = notification_history.internal_app,
    title = "Oops, there were errors during startup!",
    text = awesome.startup_errors
  })
end
do
  local in_error = false
  awesome.connect_signal("debug::error", function(err)
    -- Make sure we don't go into an endless error loop
    if in_error then
      return
    end
    in_error = true

    naughty.notification({
      urgency = 'critical',
      timeout = 0,
      app_name = notification_history.internal_app,
      title = "Oops, an error happened!",
      text = tostring(err)
    })
    in_error = false
  end)
end
