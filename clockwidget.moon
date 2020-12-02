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
    scale_factor: 0

ClockWidget.init = =>
    padding = self.padding
    width, height = self.width - 2 * padding, self.height - 2 * padding
    self._orig_screen_mode = Screen\getScreenMode!

    self.face = CenterContainer\new{
        dimen: self\getSize!,
        ImageWidget\new
            file: PLUGIN_ROOT .. "face.png",
            :width, :height,
            scale_factor: self.scale_factor,
            alpha: true
    }
    self._hours_hand_bb = RenderImage\renderImageFile "#{PLUGIN_ROOT}hours.png"
    self._minutes_hand_bb = RenderImage\renderImageFile "#{PLUGIN_ROOT}minutes.png"
    self\_updateHands!

ClockWidget.paintTo = (bb, x, y) =>
    hands = self._hands[60 * tonumber(date "%H") + tonumber(date "%M")]
    bb\fill Blitbuffer.COLOR_WHITE
    size = self\getSize!
    x, y = x + self.width / 2, y + self.height / 2
    x, y = y, x if Screen\getScreenMode! ~= self._orig_screen_mode
    self.face\paintTo bb, x, y
    hands.hours\paintTo bb, x, y
    hands.minutes\paintTo bb, x, y
    bb\invertRect x, y, size.w, size.h if Screen.night_mode

ClockWidget._prepare_hands = (hours, minutes) =>
    idx = hours * 60 + minutes
    return if self._hands[idx]
    self._hands[idx] = {}
    hour_rad, minute_rad = -math.pi / 6, -math.pi / 30
    padding = self.padding
    width, height = self.width - 2 * padding, self.height - 2 * padding

    hours_hand_bb = rotate_bb(
        self._hours_hand_bb,
        self._hours_hand_bb\getWidth! / 2,
        self._hours_hand_bb\getHeight! / 2,
        (hours + minutes/60) * hour_rad
    )
    minutes_hand_bb = rotate_bb(
        self._minutes_hand_bb,
        self._minutes_hand_bb\getWidth! / 2,
        self._minutes_hand_bb\getHeight! / 2,
        minutes * minute_rad
    )

    hours_hand_widget = ImageWidget\new
        image: hours_hand_bb,
        width: width,
        height: height,
        scale_factor: self.scale_factor,
        alpha: true,
    minutes_hand_widget = ImageWidget\new
        image: minutes_hand_bb,
        width: width,
        height: height,
        scale_factor: self.scale_factor,
        alpha: true,

    self._hands[idx].hours = CenterContainer\new{
        dimen: self\getSize!,
        hours_hand_widget,
    }
    self._hands[idx].minutes = CenterContainer\new{
        dimen: self\getSize!,
        minutes_hand_widget,
    }
    self._hands[idx].bbs = {hours_hand_bb, minutes_hand_bb}
    n_hands = 0
    n_hands += 1 for __ in pairs self._hands
    logger.dbg "ClockWidget: hands ready for", hours, minutes, ":", n_hands, "position(s) in memory."

ClockWidget._updateHands = =>
    self._hands = self._hands or {}
    hours, minutes = tonumber(date "%H"), tonumber(date "%M")
    {:floor, :fmod} = math
    --  We prepare this minute's hands at once (if necessary).
    self\_prepare_hands hours, minutes
    --  Then we schedule preparation of next minute's hands.
    fut_minutes = minutes + 1
    fut_hours = fmod hours + floor(fut_minutes / 60), 24
    fut_minutes = fmod fut_minutes, 60
    UIManager\scheduleIn 2, -> self\_prepare_hands fut_hours, fut_minutes
    --  Then we schedule removing of past minutes' hands.
    UIManager\scheduleIn 30, ->
        idx = hours * 60 + minutes
        for k in pairs self._hands
            self._hands[k] = nil if (idx < 24 * 60 - 2) and (k - idx < 0) or (k - idx > 2)

ClockWidget.onShow = =>
    self\_updateHands!
    UIManager\setDirty nil, "full"
    self\setupAutoRefreshTime!

ClockWidget.setupAutoRefreshTime = =>
    if not self.autoRefreshTime
        self.autoRefreshTime = ->
            UIManager\setDirty "all", -> "ui", self.dimen, true
            self\_updateHands!
            UIManager\scheduleIn 60 - tonumber(date "%S"), self.autoRefreshTime
    self.onCloseWidget = -> UIManager\unschedule self.autoRefreshTime
    self.onSuspend = -> UIManager\unschedule self.autoRefreshTime
    self.onResume = self.autoRefreshTime
    UIManager\scheduleIn 60 - tonumber(date "%S"), self.autoRefreshTime

return ClockWidget
