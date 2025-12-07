Blitbuffer = require("ffi/blitbuffer")
Device = require("device")
Geom = require("ui/geometry")
UIManager = require("ui/uimanager")
Screen = Device.screen
Size = require("ui/size")
WidgetContainer = require("ui/widget/container/widgetcontainer")
_ = require("gettext")
logger = require("logger")
import date from os

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

-- Composite source onto dest using premultiplied alpha blitting
-- Black (0) is treated as transparent, non-black as opaque
merge_bb = (dest, source) ->
    w, h = source\getWidth!, source\getHeight!
    dest\pmulalphablitFrom source, 0, 0, 0, 0, w, h

-- Draw a single minute tick at 12 o'clock position (INVERTED: white on black)
-- If is_hour is true, draw a larger tick for hour markers
draw_minute_tick = (size, is_hour) ->
    bb = Blitbuffer.new size, size, Screen.bb\getType!
    -- Leave black background (calloc default)
    center = size / 2
    
    -- Tick dimensions - hour ticks are larger
    tick_length = is_hour and size / 12 or size / 24
    tick_width = is_hour and size / 50 or size / 100
    
    -- Draw vertical tick at top center (12 o'clock) in WHITE
    x = math.floor(center - tick_width / 2)
    y = math.floor(size * 0.05)  -- small margin from edge
    w = math.floor(tick_width)
    h = math.floor(tick_length)
    
    bb\paintRect x, y, w, h, Blitbuffer.COLOR_WHITE
    bb

-- Build one hour segment (5 minutes) by rotating minute ticks
-- First tick is an hour marker (larger), then 4 minute ticks
draw_hour_segment = (size) ->
    center = size / 2
    angle = math.pi / 30  -- 6 degrees per minute
    
    -- Start with hour marker at 12 o'clock
    bb = draw_minute_tick size, true
    
    -- Add 4 minute ticks via rotation (merge to accumulate white on black)
    for i = 1, 4
        minute_bb = draw_minute_tick size, false
        rotated = rotate_bb minute_bb, center, center, i * angle
        merge_bb bb, rotated
        rotated\free!
        minute_bb\free!
    
    bb  -- contains 5 ticks: 1 hour + 4 minutes

-- Build quarter (3 hours = 15 minutes) by rotating hour segments
draw_quarter = (size) ->
    center = size / 2
    hour_angle = math.pi / 6  -- 30 degrees per hour
    
    bb_h = draw_hour_segment size
    bb_q = Blitbuffer.new size, size, Screen.bb\getType!
    -- Black background, merge to accumulate
    merge_bb bb_q, bb_h
    
    -- Add 2 more hour segments (for hours 1 and 2)
    for i = 1, 2
        rotated = rotate_bb bb_h, center, center, i * hour_angle
        merge_bb bb_q, rotated
        rotated\free!
    
    bb_h\free!
    bb_q  -- contains 15 ticks (3 hours)

-- Build full dial by using native rotatedCopy for 4 quadrants
draw_face = (size) ->
    bb_q = draw_quarter size
    bb_cadran = Blitbuffer.new size, size, Screen.bb\getType!
    
    -- Copy 4 quadrants using native rotation (90° increments)
    for i = 0, 3
        temp = bb_q\rotatedCopy i * 90
        merge_bb bb_cadran, temp
        temp\free!
    
    bb_q\free!
    -- Invert: white ticks on black -> black ticks on white
    bb_cadran\invert!
    -- Draw center circle for aesthetics
    center = math.floor(size / 2)
    radius = math.floor(size / 18)
    bb_cadran\paintCircle center, center, radius, Blitbuffer.COLOR_BLACK
    bb_cadran

-- Generic hand drawing function with trapezoid shape and rounded tip
draw_hand = (size, length_ratio, base_width_ratio, tip_width_ratio) ->
    bb = Blitbuffer.new size, size, Screen.bb\getType!

    center = size / 2
    hand_length = size * length_ratio
    base_w = size * base_width_ratio
    tip_w = size * tip_width_ratio
    
    -- Trapezoid: from center upward (position at 12 o'clock)
    y_tip = center - hand_length
    y_base = center
    
    for y = math.floor(y_tip), math.floor(y_base)
        progress = (y - y_tip) / (y_base - y_tip)
        width = tip_w + (base_w - tip_w) * progress
        left = center - width / 2
        bb\paintRect math.floor(left), y, math.floor(width), 1, Blitbuffer.COLOR_BLACK
    
    -- Rounded tip (semi-circle at top)
    radius = math.floor(tip_w / 2)
    bb\paintCircle math.floor(center), math.floor(y_tip), radius, Blitbuffer.COLOR_BLACK
    
    bb

draw_hours_hand = (size) -> draw_hand size, 0.22, 1/18, 1/32
draw_minutes_hand = (size) -> draw_hand size, 0.32, 1/18, 1/32


ClockWidget = WidgetContainer\new
    padding: Size.padding.large,
    scale_factor: 0,
    _hands: {}

ClockWidget.init = =>
    @_hands = {}
    @updateDimen @width, @height

ClockWidget.updateDimen = (w, h) =>
    @width, @height = w, h
    -- Make it square, fitting in the smallest dimension
    @face_dim = math.min(@width, @height) - 2 * @padding
    @dimen = Geom\new w: @width, h: @height

    -- Reset base BBs if dimensions changed
    if @_last_face_dim and @_last_face_dim != @face_dim
        @_face_bb\free! if @_face_bb
        @_hours_hand_bb\free! if @_hours_hand_bb
        @_minutes_hand_bb\free! if @_minutes_hand_bb
        @_face_bb, @_hours_hand_bb, @_minutes_hand_bb = nil, nil, nil
        @_hands = {}
    @_last_face_dim = @face_dim

    -- Create a full-screen blitbuffer
    logger.dbg "ClockWidget: Creating screen-sized BB:", @width, "x", @height
    @_screen_bb = Blitbuffer.new @width, @height, Screen.bb\getType!

    @autoRefreshTime = ->
        UIManager\setDirty "all", -> "ui", @dimen, true
        UIManager\scheduleIn 60 - tonumber(date "%S"), @autoRefreshTime

-- Lazy loading of base images (face, hands) - kept in memory only
ClockWidget._ensureBaseImages = =>
    return if @_face_bb and @_hours_hand_bb and @_minutes_hand_bb
    
    logger.dbg "ClockWidget: Ensuring base images for size", @face_dim
    
    -- Face
    if not @_face_bb
        logger.dbg "ClockWidget: Drawing procedural face at size", @face_dim
        @_face_bb = draw_face @face_dim
    
    -- Hours hand
    if not @_hours_hand_bb
        logger.dbg "ClockWidget: Drawing procedural hours hand"
        @_hours_hand_bb = draw_hours_hand @face_dim
    
    -- Minutes hand
    if not @_minutes_hand_bb
        logger.dbg "ClockWidget: Drawing procedural minutes hand"
        @_minutes_hand_bb = draw_minutes_hand @face_dim
    
    -- Verify all BBs are created
    if not (@_face_bb and @_hours_hand_bb and @_minutes_hand_bb)
        logger.err "ClockWidget: Failed to create base images!"

ClockWidget.paintTo = (bb, x, y) =>
    -- Lazy loading: create base images on first paint
    @_ensureBaseImages!
    
    h, m = tonumber(date "%H"), tonumber(date "%M")
    hands = @_hands[60 * h + m] or @_updateHands h, m
    
    -- Fill our screen BB with white
    @_screen_bb\fill Blitbuffer.COLOR_WHITE
    
    -- Center the clock face in the available space
    cx = math.floor((@width - @face_dim) / 2)
    cy = math.floor((@height - @face_dim) / 2)
    
    -- Blit face image onto screen BB
    if @_face_bb
        face_w, face_h = @_face_bb\getWidth!, @_face_bb\getHeight!
        @_screen_bb\blitFrom @_face_bb, cx, cy, 0, 0, face_w, face_h
    
    -- Blit hours hand onto screen BB
    if hands and hands.hours_bb
        hbb_w, hbb_h = hands.hours_bb\getWidth!, hands.hours_bb\getHeight!
        hcx = cx + math.floor((@face_dim - hbb_w) / 2)
        hcy = cy + math.floor((@face_dim - hbb_h) / 2)
        @_screen_bb\pmulalphablitFrom hands.hours_bb, hcx, hcy, 0, 0, hbb_w, hbb_h
    
    -- Blit minutes hand onto screen BB
    if hands and hands.minutes_bb
        mbb_w, mbb_h = hands.minutes_bb\getWidth!, hands.minutes_bb\getHeight!
        mcx = cx + math.floor((@face_dim - mbb_w) / 2)
        mcy = cy + math.floor((@face_dim - mbb_h) / 2)
        @_screen_bb\pmulalphablitFrom hands.minutes_bb, mcx, mcy, 0, 0, mbb_w, mbb_h
    
    -- Finally, blit the entire screen BB to the actual screen
    bb\blitFrom @_screen_bb, x, y, 0, 0, @width, @height

ClockWidget._prepareHands = (hours, minutes) =>
    idx = hours * 60 + minutes
    return @_hands[idx] if @_hands[idx]
    
    -- Ensure base images are loaded (may be called from scheduled callback)
    @_ensureBaseImages!
    return {} unless @_hours_hand_bb and @_minutes_hand_bb
    
    @_hands[idx] = {}
    hour_rad, minute_rad = -math.pi / 6, -math.pi / 30

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

    @_hands[idx].hours_bb = hours_hand_bb
    @_hands[idx].minutes_bb = minutes_hand_bb
    
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
