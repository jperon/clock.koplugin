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
ClockWidget = require("clockwidget")


AnalogClock = InputContainer\new
    name: "analogclock",
    is_doc_only: false,
    modal: true,
    is_doc_only: false,
    modal: true,
    scale_factor: 0,
    dismiss_callback: =>
        PluginShare.pause_auto_suspend = false
        @_was_suspending = false

AnalogClock.init = =>
    @key_events = AnyKeyPressed: { {Input.group.Any}, seqtext: "any key", doc: "close dialog" } if Device\hasKeys!
    @ges_events.TapClose = {GestureRange\new
        ges: "tap",
        range: Geom\new
            x: 0, y: 0,
            w: Screen\getWidth!,
            h: Screen\getHeight!,} if Device\isTouchDevice!

    @width = Screen\getWidth!
    @height = Screen\getHeight!
    padding = Size.padding.fullscreen

    @[1] = ClockWidget\new width: @width, height: @height, :padding
    @onDispatcherRegisterAction!

AnalogClock.onResize = =>
    @width = Screen\getWidth!
    @height = Screen\getHeight!
    @ges_events.TapClose[1].range.w = @width
    @ges_events.TapClose[1].range.h = @height
    @[1]\updateDimen @width, @height
    UIManager\setDirty nil, -> "ui", @[1].dimen

AnalogClock.addToMainMenu = (menu_items) =>
    menu_items.analogclock = {text: _("Analog Clock"), sorting_hint: "more_tools", callback: -> UIManager\show @}

AnalogClock.onCloseWidget = =>
    UIManager\setDirty nil, -> "ui", @[1].dimen

AnalogClock.onShow = =>
    -- Update dimensions in case rotation happened while hidden
    @width = Screen\getWidth!
    @height = Screen\getHeight!
    @dimen = Geom\new{w: @width, h: @height}
    if @ges_events.TapClose
        @ges_events.TapClose[1].range.w = @width
        @ges_events.TapClose[1].range.h = @height
    @[1]\updateDimen @width, @height
    UIManager\setDirty nil, -> "ui", @[1].dimen

    -- triggered by the UIManager after we got successfully shown (not yet painted)
    UIManager\scheduleIn(@timeout, -> UIManager\close @) if @timeout
    PluginShare.pause_auto_suspend = true

AnalogClock.onSuspend = =>

AnalogClock.onResume = =>
    @onShow! if @_was_suspending
    @_was_suspending = false

AnalogClock.onAnyKeyPressed = =>
    @dismiss_callback!
    UIManager\close @

AnalogClock.onTapClose = =>
    @dismiss_callback!
    UIManager\close @

AnalogClock.onAnalogClockShow = => UIManager\show @

AnalogClock.onDispatcherRegisterAction = =>
    Dispatcher\registerAction("analogclock_show", {
        category: "none",
        event: "AnalogClockShow",
        title: _("Show analog clock"),
        device: true,
    })

return AnalogClock
