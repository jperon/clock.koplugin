Blitbuffer = require("ffi/blitbuffer")
CenterContainer = require("ui/widget/container/centercontainer")
Device = require("device")
ImageWidget = require("ui/widget/imagewidget")
RenderImage = require("ui/renderimage")
UIManager = require("ui/uimanager")
Screen = Device.screen
Size = require("ui/size")
WidgetContainer = require("ui/widget/container/widgetcontainer")
_ = require("gettext")
logger = require("logger")
import date from os

PLUGIN_ROOT = package.path\match('([^;]*clock%.koplugin/)')

rotate_point = (point_x, point_y, center_x, center_y, angle_rad) ->
    {:sin, :cos, :floor} = math
    s, c = sin(angle_rad), cos(angle_rad)
    x, y = (point_x - center_x), (point_y - center_y)
    new_x, new_y = (x * c - y * s), (x * s + y * c)
    floor(center_x + new_x + 0.5), floor(center_y + new_y + 0.5)

rotate_bb = (bb, center_x, center_y, angle_rad) ->
    w, h = bb\getWidth!, bb\getHeight!
    rot_bb = Blitbuffer.new w, h, bb\getType!
    w, h = w - 1, h - 1
    for x = 0, w
        for y = 0, h
            old_x, old_y = rotate_point x, y, center_x, center_y, angle_rad
            if old_x >= 0 and old_x <= w and old_y >= 0 and old_y <= h
                rot_bb\setPixel x, y, bb\getPixel(old_x, old_y)
    rot_bb

ClockWidget = WidgetContainer\new
    width: Screen\scaleBySize 200,
    height: Screen\scaleBySize 200,
    padding: Size.padding.large,
    scale_factor: 0,
    _hands: {}

ClockWidget.init = =>
    padding = @padding
    width, height = @width - 2 * padding, @height - 2 * padding
    @_orig_screen_mode = Screen\getScreenMode!

    @face = CenterContainer\new{
        dimen: @getSize!,
        ImageWidget\new
            file: "#{PLUGIN_ROOT}face.png",
            :width, :height,
            scale_factor: @scale_factor,
            alpha: true
    }
    @_hours_hand_bb = RenderImage\renderImageFile "#{PLUGIN_ROOT}hours.png"
    @_minutes_hand_bb = RenderImage\renderImageFile "#{PLUGIN_ROOT}minutes.png"

    @autoRefreshTime = ->
        UIManager\setDirty "all", -> "ui", @dimen, true
        UIManager\scheduleIn 60 - tonumber(date "%S"), @autoRefreshTime

ClockWidget.paintTo = (bb, x, y) =>
    h, m = tonumber(date "%H"), tonumber(date "%M")
    hands = @_hands[60 * h + m] or @_updateHands h, m
    bb\fill Blitbuffer.COLOR_WHITE
    size = @getSize!
    x, y = x + @width / 2, y + @height / 2
    x, y = y, x if Screen\getScreenMode! ~= @_orig_screen_mode
    @face\paintTo bb, x, y
    hands.hours\paintTo bb, x, y
    hands.minutes\paintTo bb, x, y
    bb\invertRect x, y, size.w, size.h if Screen.night_mode

ClockWidget._prepareHands = (hours, minutes) =>
    idx = hours * 60 + minutes
    return @_hands[idx] if @_hands[idx]
    @_hands[idx] = {}
    hour_rad, minute_rad = -math.pi / 6, -math.pi / 30
    padding = @padding
    width, height = @width - 2 * padding, @height - 2 * padding

    hours_hand_bb = rotate_bb(
        @_hours_hand_bb,
        @_hours_hand_bb\getWidth! / 2,
        @_hours_hand_bb\getHeight! / 2,
        (hours + minutes/60) * hour_rad
    )
    minutes_hand_bb = rotate_bb(
        @_minutes_hand_bb,
        @_minutes_hand_bb\getWidth! / 2,
        @_minutes_hand_bb\getHeight! / 2,
        minutes * minute_rad
    )

    hours_hand_widget = ImageWidget\new
        image: hours_hand_bb,
        width: width,
        height: height,
        scale_factor: @scale_factor,
        alpha: true,
    minutes_hand_widget = ImageWidget\new
        image: minutes_hand_bb,
        width: width,
        height: height,
        scale_factor: @scale_factor,
        alpha: true,

    @_hands[idx].hours = CenterContainer\new{
        dimen: @getSize!,
        hours_hand_widget,
    }
    @_hands[idx].minutes = CenterContainer\new{
        dimen: @getSize!,
        minutes_hand_widget,
    }
    n_hands = 0
    n_hands += 1 for __ in pairs @_hands
    logger.dbg "ClockWidget: hands ready for", hours, minutes, ":", n_hands, "position(s) in memory."
    @_hands[idx]

ClockWidget._updateHands = =>
    hours, minutes = tonumber(date "%H"), tonumber(date "%M")
    {:floor, :fmod} = math
    -- Schedule removal of past minutes' hands, and creation of next one's.
    UIManager\scheduleIn 50, ->
        idx = hours * 60 + minutes
        for k in pairs @_hands
            @_hands[k] = nil if (idx < 24 * 60 - 2) and (k - idx < 0) or (k - idx > 2)
        fut_minutes = minutes + 1
        fut_hours = fmod hours + floor(fut_minutes / 60), 24
        fut_minutes = fmod fut_minutes, 60
        @_prepareHands fut_hours, fut_minutes
    -- Prepare this minute's hands at once (if necessary).
    @_prepareHands hours, minutes

ClockWidget.onShow = => @autoRefreshTime!
ClockWidget.onCloseWidget = => UIManager\unschedule @autoRefreshTime
ClockWidget.onSuspend = => UIManager\unschedule @autoRefreshTime
ClockWidget.onResume = => @autoRefreshTime!

return ClockWidget
