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

-- Rotate source BB and blit pixels into destination BB
-- Can exclude a specific color (treated as transparent)
rotate_bb = (source, dest, center_x, center_y, angle_rad, only_color) ->
    w, h = source\getWidth!, source\getHeight!
    w, h = w - 1, h - 1
    s, c = math.sin(angle_rad), math.cos(angle_rad)

    for x = 0, w
        for y = 0, h
            rel_x, rel_y = x - center_x, y - center_y
            old_x = math.floor(center_x + (rel_x * c - rel_y * s) + 0.5)
            old_y = math.floor(center_y + (rel_x * s + rel_y * c) + 0.5)
            if old_x >= 0 and old_x <= w and old_y >= 0 and old_y <= h
                pixel = source\getPixel(old_x, old_y)
                -- Only set non-black pixels (ignore transparency)
                if (not only_color) or (pixel == only_color)
                    dest\setPixel x, y, pixel


-- Paint a single minute tick into destination BB at specified rotation angle
-- Tick template is drawn at 12 o'clock then rotated into position
-- If is_hour is true, draw a larger tick for hour markers
paint_minute_tick = (size, dest_bb, is_hour) ->
    center = size / 2

    -- Tick dimensions - hour ticks are larger
    tick_length = is_hour and size / 16 or size / 24
    tick_width = is_hour and size / 66 or size / 100

    -- Draw vertical tick at top center (12 o'clock) in BLACK
    x = math.floor(center - tick_width / 2)
    y = math.floor(size * 0.05)  -- small margin from edge
    w = math.floor(tick_width)
    h = math.floor(tick_length)

    -- Create temporary BB for tick template, then rotate into destination
    dest_bb\paintRect x, y, w, h, Blitbuffer.COLOR_BLACK

-- Build full dial by rotating hour segments directly into destination BB
draw_face = (size) ->
    t0 = os.clock!
    bb = Blitbuffer.new size, size, Screen.bb\getType!
    bb\fill Blitbuffer.COLOR_WHITE

    center = size / 2
    hour_angle = math.pi / 6  -- 30 degrees per hour (2π/12)

    -- Build all 12 hours by rotating hour segments in-place
    -- Each hour segment has 4 minute ticks + 1 hour marker
    angle = math.pi / 30  -- 6 degrees per minute

    -- Add 4 minute ticks first (no hour marker yet)
    paint_minute_tick size, bb, false
    rotate_bb bb, bb, center, center, angle, Blitbuffer.COLOR_BLACK
    rotate_bb bb, bb, center, center, angle, Blitbuffer.COLOR_BLACK
    rotate_bb bb, bb, center, center, 2 * angle, Blitbuffer.COLOR_BLACK

    -- Then add hour marker (larger tick) at the base angle
    paint_minute_tick size, bb, true

    -- Replicate for hours
    rotate_bb bb, bb, center, center, hour * hour_angle, Blitbuffer.COLOR_BLACK for hour = 1, 2
    rotate_bb bb, bb, center, center, hour_angle*3, Blitbuffer.COLOR_BLACK
    rotate_bb bb, bb, center, center, hour_angle*6, Blitbuffer.COLOR_BLACK

    -- Draw center circle for aesthetics
    radius = math.floor(size / 20)
    bb\paintCircle center, center, radius, Blitbuffer.COLOR_BLACK
    elapsed = math.floor((os.clock! - t0) * 1000 + 0.5)
    logger.dbg "ClockWidget: draw_face completed in", elapsed, "ms"
    bb

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
    _hands: {},
    _display_hands: nil,
    _prepare_hands: nil,
    _last_prepared_minute: -1

ClockWidget.init = =>
    @_hands = {}
    @_display_hands = nil
    @_prepare_hands = nil
    @_last_prepared_minute = -1
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
        @_display_hands\free! if @_display_hands
        @_prepare_hands\free! if @_prepare_hands
        @_face_bb, @_hours_hand_bb, @_minutes_hand_bb = nil, nil, nil
        @_display_hands, @_prepare_hands = nil, nil
        @_hands = {}
        @_last_prepared_minute = -1
    @_last_face_dim = @face_dim

    -- Create full-screen blitbuffer and permanent hand buffers
    logger.dbg "ClockWidget: Creating screen-sized BB:", @width, "x", @height
    @_screen_bb = Blitbuffer.new @width, @height, Screen.bb\getType!
    @_display_hands = Blitbuffer.new @face_dim, @face_dim, Screen.bb\getType!
    @_prepare_hands = Blitbuffer.new @face_dim, @face_dim, Screen.bb\getType!
    @_display_hands\fill Blitbuffer.COLOR_WHITE
    @_prepare_hands\fill Blitbuffer.COLOR_WHITE
    -- Force a hands preparation on next paint
    @_last_prepared_minute = -1

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
    current_minute = 60 * h + m

    -- Prepare hands for next minute if needed (background work)
    if @_last_prepared_minute != current_minute
        t0 = os.clock!
        @_prepareHands h, m
        elapsed = math.floor((os.clock! - t0) * 1000 + 0.5)
        logger.dbg "ClockWidget: paintTo prepareHands took", elapsed, "ms"
        @_last_prepared_minute = current_minute

    -- Fill our screen BB with white
    @_screen_bb\fill Blitbuffer.COLOR_WHITE

    -- Center the clock face in the available space
    cx = math.floor((@width - @face_dim) / 2)
    cy = math.floor((@height - @face_dim) / 2)

    -- Blit face image onto screen BB
    if @_face_bb
        face_w, face_h = @_face_bb\getWidth!, @_face_bb\getHeight!
        @_screen_bb\blitFrom @_face_bb, cx, cy, 0, 0, face_w, face_h

    -- Blit display hands onto screen BB
    if @_display_hands
        hbb_w, hbb_h = @_display_hands\getWidth!, @_display_hands\getHeight!
        hcx = cx + math.floor((@face_dim - hbb_w) / 2)
        hcy = cy + math.floor((@face_dim - hbb_h) / 2)
        @_screen_bb\pmulalphablitFrom @_display_hands, hcx, hcy, 0, 0, hbb_w, hbb_h

    -- Finally, blit the entire screen BB to the actual screen
    bb\blitFrom @_screen_bb, x, y, 0, 0, @width, @height
    total_elapsed = math.floor((os.clock! - t_start) * 1000 + 0.5)
    logger.dbg "ClockWidget: paintTo total time:", total_elapsed, "ms"

ClockWidget._prepareHands = (hours, minutes) =>
    t_start = os.clock!
    -- Ensure base images are loaded
    @_ensureBaseImages!
    return unless @_hours_hand_bb and @_minutes_hand_bb and @_face_bb

    -- Start with dial background
    @_prepare_hands\blitFrom @_face_bb, 0, 0, 0, 0, @face_dim, @face_dim

    hour_rad, minute_rad = -math.pi / 6, -math.pi / 30
    center = @face_dim / 2

    t0 = os.clock!
    rotate_bb(
        @_hours_hand_bb,
        @_prepare_hands,
        center,
        center,
        (hours + minutes/60) * hour_rad,
        Blitbuffer.COLOR_BLACK
    )
    elapsed_h = math.floor((os.clock! - t0) * 1000 + 0.5)

    t0 = os.clock!
    rotate_bb(
        @_minutes_hand_bb,
        @_prepare_hands,
        center,
        center,
        minutes * minute_rad,
        Blitbuffer.COLOR_BLACK
    )
    elapsed_m = math.floor((os.clock! - t0) * 1000 + 0.5)

    total_elapsed = math.floor((os.clock! - t_start) * 1000 + 0.5)
    logger.dbg "ClockWidget: _prepareHands for", hours, minutes, ": hours_rotate", elapsed_h, "ms, minutes_rotate", elapsed_m, "ms, total", total_elapsed, "ms"

    -- Swap buffers: prepare becomes display for next paint
    @_display_hands, @_prepare_hands = @_prepare_hands, @_display_hands

ClockWidget._updateHands = =>
    hours, minutes = tonumber(date "%H"), tonumber(date "%M")
    t_start = os.clock!
    logger.dbg "ClockWidget: _updateHands starting for", hours, ":", minutes

    -- Prepare hands immediately
    @_prepareHands hours, minutes

    -- Schedule preparation for next minute
    UIManager\scheduleIn 50, ->
        fut_minutes = minutes + 1
        fut_hours = math.fmod(hours + math.floor(fut_minutes / 60), 24)
        fut_minutes = math.fmod(fut_minutes, 60)
        @_prepareHands fut_hours, fut_minutes

    elapsed = math.floor((os.clock! - t_start) * 1000 + 0.5)
    logger.dbg "ClockWidget: _updateHands completed in", elapsed, "ms"

ClockWidget.onShow = => @autoRefreshTime!
ClockWidget.onCloseWidget = => UIManager\unschedule @autoRefreshTime
ClockWidget.onSuspend = => UIManager\unschedule @autoRefreshTime
ClockWidget.onResume = => @autoRefreshTime!

return ClockWidget
