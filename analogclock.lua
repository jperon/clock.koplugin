local Device = require("device")
local Dispatcher = require("dispatcher")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local PluginShare = require("pluginshare")
local UIManager = require("ui/uimanager")
local Input = Device.input
local Screen = Device.screen
local Size = require("ui/size")
local _ = require("gettext")
local ClockWidget = require("clockwidget")
local AnalogClock = InputContainer:new({
  name = "analogclock",
  is_doc_only = false,
  modal = true,
  is_doc_only = false,
  modal = true,
  scale_factor = 0,
  dismiss_callback = function(self)
    PluginShare.pause_auto_suspend = false
    self._was_suspending = false
  end
})
AnalogClock.init = function(self)
  if Device:hasKeys() then
    self.key_events = {
      AnyKeyPressed = {
        {
          Input.group.Any
        },
        seqtext = "any key",
        doc = "close dialog"
      }
    }
  end
  if Device:isTouchDevice() then
    self.ges_events.TapClose = {
      GestureRange:new({
        ges = "tap",
        range = Geom:new({
          x = 0,
          y = 0,
          w = Screen:getWidth(),
          h = Screen:getHeight()
        })
      })
    }
  end
  self.width = Screen:getWidth()
  self.height = Screen:getHeight()
  local padding = Size.padding.fullscreen
  self[1] = ClockWidget:new({
    width = self.width,
    height = self.height,
    padding = padding
  })
  return self:onDispatcherRegisterAction()
end
AnalogClock.onResize = function(self)
  self.width = Screen:getWidth()
  self.height = Screen:getHeight()
  self.ges_events.TapClose[1].range.w = self.width
  self.ges_events.TapClose[1].range.h = self.height
  self[1]:updateDimen(self.width, self.height)
  return UIManager:setDirty(nil, function()
    return "ui", self[1].dimen
  end)
end
AnalogClock.addToMainMenu = function(self, menu_items)
  menu_items.analogclock = {
    text = _("Analog Clock"),
    sorting_hint = "more_tools",
    callback = function()
      return UIManager:show(self)
    end
  }
end
AnalogClock.onCloseWidget = function(self)
  return UIManager:setDirty(nil, function()
    return "ui", self[1].dimen
  end)
end
AnalogClock.onShow = function(self)
  self.width = Screen:getWidth()
  self.height = Screen:getHeight()
  self.dimen = Geom:new({
    w = self.width,
    h = self.height
  })
  if self.ges_events.TapClose then
    self.ges_events.TapClose[1].range.w = self.width
    self.ges_events.TapClose[1].range.h = self.height
  end
  self[1]:updateDimen(self.width, self.height)
  UIManager:setDirty(nil, function()
    return "ui", self[1].dimen
  end)
  if self.timeout then
    UIManager:scheduleIn(self.timeout, function()
      return UIManager:close(self)
    end)
  end
  PluginShare.pause_auto_suspend = true
end
AnalogClock.onSuspend = function(self) end
AnalogClock.onResume = function(self)
  if self._was_suspending then
    self:onShow()
  end
  self._was_suspending = false
end
AnalogClock.onAnyKeyPressed = function(self)
  self:dismiss_callback()
  return UIManager:close(self)
end
AnalogClock.onTapClose = function(self)
  self:dismiss_callback()
  return UIManager:close(self)
end
AnalogClock.onAnalogClockShow = function(self)
  return UIManager:show(self)
end
AnalogClock.onDispatcherRegisterAction = function(self)
  return Dispatcher:registerAction("analogclock_show", {
    category = "none",
    event = "AnalogClockShow",
    title = _("Show analog clock"),
    device = true
  })
end
return AnalogClock
