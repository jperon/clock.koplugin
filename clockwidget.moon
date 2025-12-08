Blitbuffer = require("ffi/blitbuffer")
DataStorage = require("datastorage")
Device = require("device")
Geom = require("ui/geometry")
lfs = require("libs/libkoreader-lfs")
UIManager = require("ui/uimanager")
Screen = Device.screen
Size = require("ui/size")
WidgetContainer = require("ui/widget/container/widgetcontainer")
_ = require("gettext")
logger = require("logger")
util = require("util")
import date from os

-- Cache directory for dial image
CACHE_DIR = DataStorage\getDataDir! .. "/cache/analogclock"

rotate_bb = (bb, center_x, center_y, angle_rad) ->
    w, h = bb\getWidth!, bb\getHeight!
    rot_bb = Blitbuffer.new w, h, bb\getType!
    w, h = w - 1, h - 1
    s, c = math.sin(angle_rad), math.cos(angle_rad)

    for x = 0, w
        for y = 0, h
            rel_x, rel_y = x - center_x, y - center_y
            old_x = math.floor(center_x + (rel_x * c - rel_y * s) + 0.5)
            old_y = math.floor(center_y + (rel_x * s + rel_y * c) + 0.5)
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
    tick_length = is_hour and size / 16 or size / 24
    tick_width = is_hour and size / 66 or size / 100

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
    t0 = os.clock!
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
    radius = math.floor(size / 20)
    bb_cadran\paintCircle center, center, radius, Blitbuffer.COLOR_BLACK
    elapsed = math.floor((os.clock! - t0) * 1000 + 0.5)
    logger.dbg "ClockWidget: draw_face completed in", elapsed, "ms"
    bb_cadran

-- Generic hand drawing function with trapezoid shape and rounded tip
draw_hand = (size, length_ratio, base_width_ratio, tip_width_ratio) ->
    t0 = os.clock!
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
    elapsed = math.floor((os.clock! - t0) * 1000 + 0.5)
    logger.dbg "ClockWidget: draw_hand completed in", elapsed, "ms"

    bb

draw_hours_hand = (size) -> draw_hand size, 0.25, 1/18, 1/32
draw_minutes_hand = (size) -> draw_hand size, 0.35, 1/18, 1/32

-- Cache functions for dial image only
get_dial_cache_path = (size) ->
    "#{CACHE_DIR}/dial_#{size}.png"

ensure_cache_dir = ->
    util.makePath CACHE_DIR

save_dial_to_cache = (bb, size) ->
    ensure_cache_dir!
    path = get_dial_cache_path size

    -- Create a white background blitbuffer without alpha (BB8 for e-ink)
    bb_white = Blitbuffer.new size, size
    bb_white\fill Blitbuffer.COLOR_WHITE

    -- Blit the dial onto white background
    bb_white\blitFrom bb, 0, 0, 0, 0, size, size

    -- Save the composited result
    bb_white\writePNG path
    bb_white\free!
    logger.dbg "ClockWidget: Saved dial to cache (BB8, no alpha):", path

load_dial_from_cache = (size) ->
    path = get_dial_cache_path size
    -- Check if file exists
    attr = lfs.attributes path
    return nil unless attr

    -- Try to load as PNG
    RenderImage = require("ui/renderimage")
    bb = RenderImage\renderImageFile path, false, size, size
    if bb
        logger.dbg "ClockWidget: Loaded dial from cache:", path, "size:", bb\getWidth!, "x", bb\getHeight!
        -- Verify size matches
        if bb\getWidth! != size or bb\getHeight! != size
            logger.dbg "ClockWidget: Cache size mismatch, expected", size
            bb\free!
            return nil
    bb


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

    t_start = os.clock!
    logger.dbg "ClockWidget: Ensuring base images for size", @face_dim

    -- Face
    if not @_face_bb
        t0 = os.clock!
        -- Try to load from cache first
        @_face_bb = load_dial_from_cache @face_dim
        if @_face_bb
            elapsed = math.floor((os.clock! - t0) * 1000 + 0.5)
            logger.dbg "ClockWidget: _ensureBaseImages face loaded from cache in", elapsed, "ms"
        else
            logger.dbg "ClockWidget: Drawing procedural face at size", @face_dim
            @_face_bb = draw_face @face_dim
            elapsed = math.floor((os.clock! - t0) * 1000 + 0.5)
            logger.dbg "ClockWidget: _ensureBaseImages face creation took", elapsed, "ms"
            -- Save to cache for next time
            save_dial_to_cache @_face_bb, @face_dim

    -- Hours hand
    if not @_hours_hand_bb
        t0 = os.clock!
        logger.dbg "ClockWidget: Drawing procedural hours hand"
        @_hours_hand_bb = draw_hours_hand @face_dim
        elapsed = math.floor((os.clock! - t0) * 1000 + 0.5)
        logger.dbg "ClockWidget: _ensureBaseImages hours hand creation took", elapsed, "ms"

    -- Minutes hand
    if not @_minutes_hand_bb
        t0 = os.clock!
        logger.dbg "ClockWidget: Drawing procedural minutes hand"
        @_minutes_hand_bb = draw_minutes_hand @face_dim
        elapsed = math.floor((os.clock! - t0) * 1000 + 0.5)
        logger.dbg "ClockWidget: _ensureBaseImages minutes hand creation took", elapsed, "ms"

    -- Verify all BBs are created
    if not (@_face_bb and @_hours_hand_bb and @_minutes_hand_bb)
        logger.err "ClockWidget: Failed to create base images!"
    else
        total_elapsed = math.floor((os.clock! - t_start) * 1000 + 0.5)
        logger.dbg "ClockWidget: _ensureBaseImages total time:", total_elapsed, "ms"

ClockWidget.paintTo = (bb, x, y) =>
    t_start = os.clock!
    -- Lazy loading: create base images on first paint
    @_ensureBaseImages!

    h, m = tonumber(date "%H"), tonumber(date "%M")
    t0 = os.clock!
    hands = @_hands[60 * h + m] or @_updateHands h, m
    elapsed = math.floor((os.clock! - t0) * 1000 + 0.5)
    logger.dbg "ClockWidget: paintTo updateHands took", elapsed, "ms"

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
    total_elapsed = math.floor((os.clock! - t_start) * 1000 + 0.5)
    logger.dbg "ClockWidget: paintTo total time:", total_elapsed, "ms"

ClockWidget._prepareHands = (hours, minutes) =>
    idx = hours * 60 + minutes
    return @_hands[idx] if @_hands[idx]

    t_start = os.clock!
    -- Ensure base images are loaded (may be called from scheduled callback)
    @_ensureBaseImages!
    return {} unless @_hours_hand_bb and @_minutes_hand_bb

    @_hands[idx] = {}
    hour_rad, minute_rad = -math.pi / 6, -math.pi / 30

    t0 = os.clock!
    hours_hand_bb = rotate_bb(
        @_hours_hand_bb,
        @_hours_hand_bb\getWidth! / 2,
        @_hours_hand_bb\getHeight! / 2,
        (hours + minutes/60) * hour_rad
    )
    elapsed_h = math.floor((os.clock! - t0) * 1000 + 0.5)

    t0 = os.clock!
    minutes_hand_bb = rotate_bb(
        @_minutes_hand_bb,
        @_minutes_hand_bb\getWidth! / 2,
        @_minutes_hand_bb\getHeight! / 2,
        minutes * minute_rad
    )
    elapsed_m = math.floor((os.clock! - t0) * 1000 + 0.5)

    @_hands[idx].hours_bb = hours_hand_bb
    @_hands[idx].minutes_bb = minutes_hand_bb

    n_hands = 0
    n_hands += 1 for __ in pairs @_hands
    total_elapsed = math.floor((os.clock! - t_start) * 1000 + 0.5)
    logger.dbg "ClockWidget: _prepareHands for", hours, minutes, ": hours_rotate", elapsed_h, "ms, minutes_rotate", elapsed_m, "ms, total", total_elapsed, "ms"
    logger.dbg "ClockWidget: hands ready:", n_hands, "position(s) in memory."
    @_hands[idx]

ClockWidget._updateHands = =>
    hours, minutes = tonumber(date "%H"), tonumber(date "%M")
    {:floor, :fmod} = math
    t_start = os.clock!
    logger.dbg "ClockWidget: _updateHands starting for", hours, ":", minutes
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
    result = @_prepareHands hours, minutes
    elapsed = math.floor((os.clock! - t_start) * 1000 + 0.5)
    logger.dbg "ClockWidget: _updateHands completed in", elapsed, "ms"
    result

ClockWidget.onShow = => @autoRefreshTime!
ClockWidget.onCloseWidget = => UIManager\unschedule @autoRefreshTime
ClockWidget.onSuspend = => UIManager\unschedule @autoRefreshTime
ClockWidget.onResume = => @autoRefreshTime!

return ClockWidget
