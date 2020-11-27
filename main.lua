local ClockWidget = require("clockwidget")
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


local Clock = InputContainer:new{
    name = "clock",
    is_doc_only = false,
    modal = true,
    width = Screen:getWidth(),
    height = Screen:getHeight(),
    scale_factor = 0,
    dismiss_callback = function(self)
        PluginShare.pause_auto_suspend = false
        self._was_suspending = false
    end,
}

function Clock:init()
    if Device:hasKeys() then
        self.key_events = {
            AnyKeyPressed = { { Input.group.Any },
                seqtext = "any key", doc = "close dialog" }
        }
    end
    if Device:isTouchDevice() then
        self.ges_events.TapClose = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = 0, y = 0,
                    w = Screen:getWidth(),
                    h = Screen:getHeight(),
                }
            }
        }
    end

    local width, height = self.width, self.height
    local padding = Size.padding.fullscreen

    self[1] = ClockWidget:new{
        width = width,
        height = height,
        padding = padding
    }
    self.ui.menu:registerToMainMenu(self)
    self:onDispatcherRegisterAction()
end

function Clock:addToMainMenu(menu_items)
    menu_items.clock = {
        text = _("Clock"),
        sorting_hint = "more_tools",
        callback = function()
            UIManager:show(self)
        end,
    }
end

function Clock:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", self[1].dimen
    end)
    return true
end

function Clock:onShow()
    -- triggered by the UIManager after we got successfully shown (not yet painted)
    UIManager:setDirty(self, function()
        return "ui", self[1].dimen
    end)
    if self.timeout then
        UIManager:scheduleIn(self.timeout, function() UIManager:close(self) end)
    end
    PluginShare.pause_auto_suspend = true
    return true
end

function Clock:onSuspend()
    if G_reader_settings:readSetting("clock_on_suspend") and not self._was_suspending then
        UIManager:show(self)
        self._was_suspending = true
    end
end

function Clock:onResume()
    if self._was_suspending then
        self:onShow()
    end
    self._was_suspending = false
end

function Clock:onAnyKeyPressed()
    -- triggered by our defined key events
    self:dismiss_callback()
    UIManager:close(self)
end

function Clock:onTapClose()
    self:dismiss_callback()
    UIManager:close(self)
end

function Clock:onClockShow()
    UIManager:show(self)
end

function Clock:onDispatcherRegisterAction()
    Dispatcher:registerAction("clock_show", {
        category = "none",
        event = "ClockShow",
        title = _("Show clock"),
        device = true,
    })
end

return Clock
