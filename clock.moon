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
        @_was_suspending = false

Clock.init = =>
    @key_events = AnyKeyPressed: { {Input.group.Any}, seqtext: "any key", doc: "close dialog" } if Device\hasKeys!
    @ges_events.TapClose = {GestureRange\new
        ges: "tap",
        range: Geom\new
            x: 0, y: 0,
            w: Screen\getWidth!,
            h: Screen\getHeight!,} if Device\isTouchDevice!

    {:width, :height} = @
    padding = Size.padding.fullscreen

    @[1] = ClockWidget\new :width, :height, :padding
    @ui.menu\registerToMainMenu @
    @onDispatcherRegisterAction!

Clock.addToMainMenu = (menu_items) =>
    menu_items.clock = {text: _("Clock"), sorting_hint: "more_tools", callback: -> UIManager\show @}

Clock.onCloseWidget = =>
    UIManager\setDirty nil, -> "ui", @[1].dimen
    true

Clock.onShow = =>
    -- triggered by the UIManager after we got successfully shown (not yet painted)
    UIManager\setDirty @, -> "ui", @[1].dimen
    UIManager\scheduleIn(@timeout, -> UIManager\close @) if @timeout
    PluginShare.pause_auto_suspend = true
    return true

Clock.onSuspend = =>
    if G_reader_settings\readSetting("clock_on_suspend") and not @_was_suspending
        UIManager\show @
        @_was_suspending = true

Clock.onResume = =>
    @onShow! if @_was_suspending
    @_was_suspending = false

Clock.onAnyKeyPressed = =>
    @dismiss_callback!
    UIManager\close @

Clock.onTapClose = =>
    @dismiss_callback!
    UIManager\close @

Clock.onClockShow = => UIManager\show @

Clock.onDispatcherRegisterAction = =>
    Dispatcher\registerAction("clock_show", {
        category: "none",
        event: "ClockShow",
        title: _("Show clock"),
        device: true,
    })

return Clock
