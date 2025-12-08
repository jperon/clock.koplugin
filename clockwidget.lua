local Blitbuffer = require("ffi/blitbuffer")
local DataStorage = require("datastorage")
local Device = require("device")
local Geom = require("ui/geometry")
local lfs = require("libs/libkoreader-lfs")
local UIManager = require("ui/uimanager")
local Screen = Device.screen
local Size = require("ui/size")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local logger = require("logger")
local util = require("util")
local date
date = os.date
local CACHE_DIR = DataStorage:getDataDir() .. "/cache/analogclock"
local rotate_bb
rotate_bb = function(source, dest, center_x, center_y, angle_rad, only_color)
  local w, h = source:getWidth(), source:getHeight()
  w, h = w - 1, h - 1
  local s, c = math.sin(angle_rad), math.cos(angle_rad)
  for x = 0, w do
    for y = 0, h do
      local rel_x, rel_y = x - center_x, y - center_y
      local old_x = math.floor(center_x + (rel_x * c - rel_y * s) + 0.5)
      local old_y = math.floor(center_y + (rel_x * s + rel_y * c) + 0.5)
      if old_x >= 0 and old_x <= w and old_y >= 0 and old_y <= h then
        local pixel = source:getPixel(old_x, old_y)
        if (not only_color) or (pixel == only_color) then
          dest:setPixel(x, y, pixel)
        end
      end
    end
  end
end
local paint_minute_tick
paint_minute_tick = function(size, dest_bb, is_hour)
  local center = size / 2
  local tick_length = is_hour and size / 16 or size / 24
  local tick_width = is_hour and size / 66 or size / 100
  local x = math.floor(center - tick_width / 2)
  local y = math.floor(size * 0.05)
  local w = math.floor(tick_width)
  local h = math.floor(tick_length)
  return dest_bb:paintRect(x, y, w, h, Blitbuffer.COLOR_BLACK)
end
local draw_face
draw_face = function(size)
  local t0 = os.clock()
  local bb = Blitbuffer.new(size, size, Screen.bb:getType())
  bb:fill(Blitbuffer.COLOR_WHITE)
  local center = size / 2
  local hour_angle = math.pi / 6
  local angle = math.pi / 30
  paint_minute_tick(size, bb, false)
  rotate_bb(bb, bb, center, center, angle, Blitbuffer.COLOR_BLACK)
  rotate_bb(bb, bb, center, center, angle, Blitbuffer.COLOR_BLACK)
  rotate_bb(bb, bb, center, center, 2 * angle, Blitbuffer.COLOR_BLACK)
  paint_minute_tick(size, bb, true)
  for hour = 1, 2 do
    rotate_bb(bb, bb, center, center, hour * hour_angle, Blitbuffer.COLOR_BLACK)
  end
  rotate_bb(bb, bb, center, center, hour_angle * 3, Blitbuffer.COLOR_BLACK)
  rotate_bb(bb, bb, center, center, hour_angle * 6, Blitbuffer.COLOR_BLACK)
  local radius = math.floor(size / 20)
  bb:paintCircle(center, center, radius, Blitbuffer.COLOR_BLACK)
  local elapsed = math.floor((os.clock() - t0) * 1000 + 0.5)
  logger.dbg("ClockWidget: draw_face completed in", elapsed, "ms")
  return bb
end
local draw_hand
draw_hand = function(size, length_ratio, base_width_ratio, tip_width_ratio)
  local t0 = os.clock()
  local bb = Blitbuffer.new(size, size, Screen.bb:getType())
  local center = size / 2
  local hand_length = size * length_ratio
  local base_w = size * base_width_ratio
  local tip_w = size * tip_width_ratio
  local y_tip = center - hand_length
  local y_base = center
  for y = math.floor(y_tip), math.floor(y_base) do
    local progress = (y - y_tip) / (y_base - y_tip)
    local width = tip_w + (base_w - tip_w) * progress
    local left = center - width / 2
    bb:paintRect(math.floor(left), y, math.floor(width), 1, Blitbuffer.COLOR_BLACK)
  end
  local radius = math.floor(tip_w / 2)
  bb:paintCircle(math.floor(center), math.floor(y_tip), radius, Blitbuffer.COLOR_BLACK)
  local elapsed = math.floor((os.clock() - t0) * 1000 + 0.5)
  logger.dbg("ClockWidget: draw_hand completed in", elapsed, "ms")
  return bb
end
local draw_hours_hand
draw_hours_hand = function(size)
  return draw_hand(size, 0.25, 1 / 18, 1 / 32)
end
local draw_minutes_hand
draw_minutes_hand = function(size)
  return draw_hand(size, 0.35, 1 / 18, 1 / 32)
end
local get_dial_cache_path
get_dial_cache_path = function(size)
  return tostring(CACHE_DIR) .. "/dial_" .. tostring(size) .. ".png"
end
local ensure_cache_dir
ensure_cache_dir = function()
  return util.makePath(CACHE_DIR)
end
local save_dial_to_cache
save_dial_to_cache = function(bb, size)
  ensure_cache_dir()
  local path = get_dial_cache_path(size)
  local bb_white = Blitbuffer.new(size, size)
  bb_white:fill(Blitbuffer.COLOR_WHITE)
  bb_white:blitFrom(bb, 0, 0, 0, 0, size, size)
  bb_white:writePNG(path)
  bb_white:free()
  return logger.dbg("ClockWidget: Saved dial to cache (BB8, no alpha):", path)
end
local load_dial_from_cache
load_dial_from_cache = function(size)
  local path = get_dial_cache_path(size)
  local attr = lfs.attributes(path)
  if not (attr) then
    return nil
  end
  local RenderImage = require("ui/renderimage")
  local bb = RenderImage:renderImageFile(path, false, size, size)
  if bb then
    logger.dbg("ClockWidget: Loaded dial from cache:", path, "size:", bb:getWidth(), "x", bb:getHeight())
    if bb:getWidth() ~= size or bb:getHeight() ~= size then
      logger.dbg("ClockWidget: Cache size mismatch, expected", size)
      bb:free()
      return nil
    end
  end
  return bb
end
local ClockWidget = WidgetContainer:new({
  padding = Size.padding.large,
  scale_factor = 0,
  _hands = { },
  _display_hands = nil,
  _prepare_hands = nil,
  _last_prepared_minute = -1
})
ClockWidget.init = function(self)
  self._hands = { }
  self._display_hands = nil
  self._prepare_hands = nil
  self._last_prepared_minute = -1
  return self:updateDimen(self.width, self.height)
end
ClockWidget.updateDimen = function(self, w, h)
  self.width, self.height = w, h
  self.face_dim = math.min(self.width, self.height) - 2 * self.padding
  self.dimen = Geom:new({
    w = self.width,
    h = self.height
  })
  if self._last_face_dim and self._last_face_dim ~= self.face_dim then
    if self._face_bb then
      self._face_bb:free()
    end
    if self._hours_hand_bb then
      self._hours_hand_bb:free()
    end
    if self._minutes_hand_bb then
      self._minutes_hand_bb:free()
    end
    if self._display_hands then
      self._display_hands:free()
    end
    if self._prepare_hands then
      self._prepare_hands:free()
    end
    self._face_bb, self._hours_hand_bb, self._minutes_hand_bb = nil, nil, nil
    self._display_hands, self._prepare_hands = nil, nil
    self._hands = { }
    self._last_prepared_minute = -1
  end
  self._last_face_dim = self.face_dim
  logger.dbg("ClockWidget: Creating screen-sized BB:", self.width, "x", self.height)
  self._screen_bb = Blitbuffer.new(self.width, self.height, Screen.bb:getType())
  self._display_hands = Blitbuffer.new(self.face_dim, self.face_dim, Screen.bb:getType())
  self._prepare_hands = Blitbuffer.new(self.face_dim, self.face_dim, Screen.bb:getType())
  self._display_hands:fill(Blitbuffer.COLOR_WHITE)
  self._prepare_hands:fill(Blitbuffer.COLOR_WHITE)
  self._last_prepared_minute = -1
  self.autoRefreshTime = function()
    UIManager:setDirty("all", function()
      return "ui", self.dimen, true
    end)
    return UIManager:scheduleIn(60 - tonumber(date("%S")), self.autoRefreshTime)
  end
end
ClockWidget._ensureBaseImages = function(self)
  if self._face_bb and self._hours_hand_bb and self._minutes_hand_bb then
    return 
  end
  local t_start = os.clock()
  logger.dbg("ClockWidget: Ensuring base images for size", self.face_dim)
  if not self._face_bb then
    local t0 = os.clock()
    self._face_bb = load_dial_from_cache(self.face_dim)
    if self._face_bb then
      local elapsed = math.floor((os.clock() - t0) * 1000 + 0.5)
      logger.dbg("ClockWidget: _ensureBaseImages face loaded from cache in", elapsed, "ms")
    else
      logger.dbg("ClockWidget: Drawing procedural face at size", self.face_dim)
      self._face_bb = draw_face(self.face_dim)
      local elapsed = math.floor((os.clock() - t0) * 1000 + 0.5)
      logger.dbg("ClockWidget: _ensureBaseImages face creation took", elapsed, "ms")
      save_dial_to_cache(self._face_bb, self.face_dim)
    end
  end
  if not self._hours_hand_bb then
    local t0 = os.clock()
    logger.dbg("ClockWidget: Drawing procedural hours hand")
    self._hours_hand_bb = draw_hours_hand(self.face_dim)
    local elapsed = math.floor((os.clock() - t0) * 1000 + 0.5)
    logger.dbg("ClockWidget: _ensureBaseImages hours hand creation took", elapsed, "ms")
  end
  if not self._minutes_hand_bb then
    local t0 = os.clock()
    logger.dbg("ClockWidget: Drawing procedural minutes hand")
    self._minutes_hand_bb = draw_minutes_hand(self.face_dim)
    local elapsed = math.floor((os.clock() - t0) * 1000 + 0.5)
    logger.dbg("ClockWidget: _ensureBaseImages minutes hand creation took", elapsed, "ms")
  end
  if not (self._face_bb and self._hours_hand_bb and self._minutes_hand_bb) then
    return logger.err("ClockWidget: Failed to create base images!")
  else
    local total_elapsed = math.floor((os.clock() - t_start) * 1000 + 0.5)
    return logger.dbg("ClockWidget: _ensureBaseImages total time:", total_elapsed, "ms")
  end
end
ClockWidget.paintTo = function(self, bb, x, y)
  local t_start = os.clock()
  self:_ensureBaseImages()
  local h, m = tonumber(date("%H")), tonumber(date("%M"))
  local current_minute = 60 * h + m
  if self._last_prepared_minute ~= current_minute then
    local t0 = os.clock()
    self:_prepareHands(h, m)
    local elapsed = math.floor((os.clock() - t0) * 1000 + 0.5)
    logger.dbg("ClockWidget: paintTo prepareHands took", elapsed, "ms")
    self._last_prepared_minute = current_minute
  end
  self._screen_bb:fill(Blitbuffer.COLOR_WHITE)
  local cx = math.floor((self.width - self.face_dim) / 2)
  local cy = math.floor((self.height - self.face_dim) / 2)
  if self._face_bb then
    local face_w, face_h = self._face_bb:getWidth(), self._face_bb:getHeight()
    self._screen_bb:blitFrom(self._face_bb, cx, cy, 0, 0, face_w, face_h)
  end
  if self._display_hands then
    local hbb_w, hbb_h = self._display_hands:getWidth(), self._display_hands:getHeight()
    local hcx = cx + math.floor((self.face_dim - hbb_w) / 2)
    local hcy = cy + math.floor((self.face_dim - hbb_h) / 2)
    self._screen_bb:pmulalphablitFrom(self._display_hands, hcx, hcy, 0, 0, hbb_w, hbb_h)
  end
  bb:blitFrom(self._screen_bb, x, y, 0, 0, self.width, self.height)
  local total_elapsed = math.floor((os.clock() - t_start) * 1000 + 0.5)
  return logger.dbg("ClockWidget: paintTo total time:", total_elapsed, "ms")
end
ClockWidget._prepareHands = function(self, hours, minutes)
  local t_start = os.clock()
  self:_ensureBaseImages()
  if not (self._hours_hand_bb and self._minutes_hand_bb and self._face_bb) then
    return 
  end
  self._prepare_hands:blitFrom(self._face_bb, 0, 0, 0, 0, self.face_dim, self.face_dim)
  local hour_rad, minute_rad = -math.pi / 6, -math.pi / 30
  local center = self.face_dim / 2
  local t0 = os.clock()
  rotate_bb(self._hours_hand_bb, self._prepare_hands, center, center, (hours + minutes / 60) * hour_rad, Blitbuffer.COLOR_BLACK)
  local elapsed_h = math.floor((os.clock() - t0) * 1000 + 0.5)
  t0 = os.clock()
  rotate_bb(self._minutes_hand_bb, self._prepare_hands, center, center, minutes * minute_rad, Blitbuffer.COLOR_BLACK)
  local elapsed_m = math.floor((os.clock() - t0) * 1000 + 0.5)
  local total_elapsed = math.floor((os.clock() - t_start) * 1000 + 0.5)
  logger.dbg("ClockWidget: _prepareHands for", hours, minutes, ": hours_rotate", elapsed_h, "ms, minutes_rotate", elapsed_m, "ms, total", total_elapsed, "ms")
  self._display_hands, self._prepare_hands = self._prepare_hands, self._display_hands
end
ClockWidget._updateHands = function(self)
  local hours, minutes = tonumber(date("%H")), tonumber(date("%M"))
  local t_start = os.clock()
  logger.dbg("ClockWidget: _updateHands starting for", hours, ":", minutes)
  self:_prepareHands(hours, minutes)
  UIManager:scheduleIn(50, function()
    local fut_minutes = minutes + 1
    local fut_hours = math.fmod(hours + math.floor(fut_minutes / 60), 24)
    fut_minutes = math.fmod(fut_minutes, 60)
    return self:_prepareHands(fut_hours, fut_minutes)
  end)
  local elapsed = math.floor((os.clock() - t_start) * 1000 + 0.5)
  return logger.dbg("ClockWidget: _updateHands completed in", elapsed, "ms")
end
ClockWidget.onShow = function(self)
  return self:autoRefreshTime()
end
ClockWidget.onCloseWidget = function(self)
  return UIManager:unschedule(self.autoRefreshTime)
end
ClockWidget.onSuspend = function(self)
  return UIManager:unschedule(self.autoRefreshTime)
end
ClockWidget.onResume = function(self)
  return self:autoRefreshTime()
end
return ClockWidget
