ClockWidget = require("clockwidget")
Device = require("device")
Dispatcher = require("dispatcher")
Geom = require("ui/geometry")
GestureRange = require("ui/gesturerange")
InputContainer = require("ui/widget/container/inputcontainer")
PluginShare = require("pluginshare")
UIManager = require("ui/uimanager")
Input = Device.input
Screen = Device.screen
Size = require("ui/size")
_ = require("gettext")


Clock = InputContainer\new
    name: "clock",
    is_doc_only: false,
    modal: true,
    width: Screen\getWidth!,
    height: Screen\getHeight!,
    scale_factor: 0,
    dismiss_callback: =>
        PluginShare.pause_auto_suspend = false
        self._was_suspending = false

Clock.init = =>
    self.key_events = AnyKeyPressed: { {Input.group.Any}, seqtext: "any key", doc: "close dialog" } if Device\hasKeys!
    self.ges_events.TapClose = {GestureRange\new
        ges: "tap",
        range: Geom\new
            x: 0, y: 0,
            w: Screen\getWidth!,
            h: Screen\getHeight!,} if Device\isTouchDevice!

    {:width, :height} = self
    padding = Size.padding.fullscreen

    self[1] = ClockWidget\new :width, :height, :padding
    self.ui.menu\registerToMainMenu self
    self\onDispatcherRegisterAction!

Clock.addToMainMenu = (menu_items) =>
    menu_items.clock = {text: _("Clock"), sorting_hint: "more_tools", callback: -> UIManager\show self}

Clock.onCloseWidget = =>
    UIManager\setDirty nil, -> "ui", self[1].dimen
    true

Clock.onShow = =>
    -- triggered by the UIManager after we got successfully shown (not yet painted)
    UIManager\setDirty self, -> "ui", self[1].dimen
    UIManager\scheduleIn(self.timeout, -> UIManager\close self) if self.timeout
    PluginShare.pause_auto_suspend = true
    return true

Clock.onSuspend = =>
    if G_reader_settings\readSetting("clock_on_suspend") and not self._was_suspending
        UIManager\show self
        self._was_suspending = true

Clock.onResume = =>
    self\onShow! if self._was_suspending
    self._was_suspending = false

Clock.onAnyKeyPressed = =>
    self\dismiss_callback!
    UIManager\close self

Clock.onTapClose = =>
    self\dismiss_callback!
    UIManager\close self

Clock.onClockShow = => UIManager\show self

Clock.onDispatcherRegisterAction = =>
    Dispatcher\registerAction("clock_show", {
        category: "none",
        event: "ClockShow",
        title: _("Show clock"),
        device: true,
    })

return Clock
