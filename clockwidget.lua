local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local Screen = Device.screen
local Size = require("ui/size")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local logger = require("logger")
local date
date = os.date
local rotate_point
rotate_point = function(point_x, point_y, center_x, center_y, angle_rad)
  local sin, cos, floor
  do
    local _obj_0 = math
    sin, cos, floor = _obj_0.sin, _obj_0.cos, _obj_0.floor
  end
  local s, c = sin(angle_rad), cos(angle_rad)
  local x, y = (point_x - center_x), (point_y - center_y)
  local new_x, new_y = (x * c - y * s), (x * s + y * c)
  return floor(center_x + new_x + 0.5), floor(center_y + new_y + 0.5)
end
local rotate_bb
rotate_bb = function(bb, center_x, center_y, angle_rad)
  local w, h = bb:getWidth(), bb:getHeight()
  local rot_bb = Blitbuffer.new(w, h, bb:getType())
  w, h = w - 1, h - 1
  for x = 0, w do
    for y = 0, h do
      local old_x, old_y = rotate_point(x, y, center_x, center_y, angle_rad)
      if old_x >= 0 and old_x <= w and old_y >= 0 and old_y <= h then
        rot_bb:setPixel(x, y, bb:getPixel(old_x, old_y))
      end
    end
  end
  return rot_bb
end
local merge_bb
merge_bb = function(dest, source)
  local w, h = source:getWidth(), source:getHeight()
  return dest:pmulalphablitFrom(source, 0, 0, 0, 0, w, h)
end
local draw_minute_tick
draw_minute_tick = function(size, is_hour)
  local bb = Blitbuffer.new(size, size, Screen.bb:getType())
  local center = size / 2
  local tick_length = is_hour and size / 12 or size / 24
  local tick_width = is_hour and size / 50 or size / 100
  local x = math.floor(center - tick_width / 2)
  local y = math.floor(size * 0.05)
  local w = math.floor(tick_width)
  local h = math.floor(tick_length)
  bb:paintRect(x, y, w, h, Blitbuffer.COLOR_WHITE)
  return bb
end
local draw_hour_segment
draw_hour_segment = function(size)
  local center = size / 2
  local angle = math.pi / 30
  local bb = draw_minute_tick(size, true)
  for i = 1, 4 do
    local minute_bb = draw_minute_tick(size, false)
    local rotated = rotate_bb(minute_bb, center, center, i * angle)
    merge_bb(bb, rotated)
    rotated:free()
    minute_bb:free()
  end
  return bb
end
local draw_quarter
draw_quarter = function(size)
  local center = size / 2
  local hour_angle = math.pi / 6
  local bb_h = draw_hour_segment(size)
  local bb_q = Blitbuffer.new(size, size, Screen.bb:getType())
  merge_bb(bb_q, bb_h)
  for i = 1, 2 do
    local rotated = rotate_bb(bb_h, center, center, i * hour_angle)
    merge_bb(bb_q, rotated)
    rotated:free()
  end
  bb_h:free()
  return bb_q
end
local draw_face
draw_face = function(size)
  local bb_q = draw_quarter(size)
  local bb_cadran = Blitbuffer.new(size, size, Screen.bb:getType())
  for i = 0, 3 do
    local temp = bb_q:rotatedCopy(i * 90)
    merge_bb(bb_cadran, temp)
    temp:free()
  end
  bb_q:free()
  bb_cadran:invert()
  local center = math.floor(size / 2)
  local radius = math.floor(size / 18)
  bb_cadran:paintCircle(center, center, radius, Blitbuffer.COLOR_BLACK)
  return bb_cadran
end
local draw_hand
draw_hand = function(size, length_ratio, base_width_ratio, tip_width_ratio)
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
  return bb
end
local draw_hours_hand
draw_hours_hand = function(size)
  return draw_hand(size, 0.22, 1 / 18, 1 / 32)
end
local draw_minutes_hand
draw_minutes_hand = function(size)
  return draw_hand(size, 0.32, 1 / 18, 1 / 32)
end
local ClockWidget = WidgetContainer:new({
  padding = Size.padding.large,
  scale_factor = 0,
  _hands = { }
})
ClockWidget.init = function(self)
  self._hands = { }
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
    self._face_bb, self._hours_hand_bb, self._minutes_hand_bb = nil, nil, nil
    self._hands = { }
  end
  self._last_face_dim = self.face_dim
  logger.dbg("ClockWidget: Creating screen-sized BB:", self.width, "x", self.height)
  self._screen_bb = Blitbuffer.new(self.width, self.height, Screen.bb:getType())
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
  logger.dbg("ClockWidget: Ensuring base images for size", self.face_dim)
  if not self._face_bb then
    logger.dbg("ClockWidget: Drawing procedural face at size", self.face_dim)
    self._face_bb = draw_face(self.face_dim)
  end
  if not self._hours_hand_bb then
    logger.dbg("ClockWidget: Drawing procedural hours hand")
    self._hours_hand_bb = draw_hours_hand(self.face_dim)
  end
  if not self._minutes_hand_bb then
    logger.dbg("ClockWidget: Drawing procedural minutes hand")
    self._minutes_hand_bb = draw_minutes_hand(self.face_dim)
  end
  if not (self._face_bb and self._hours_hand_bb and self._minutes_hand_bb) then
    return logger.err("ClockWidget: Failed to create base images!")
  end
end
ClockWidget.paintTo = function(self, bb, x, y)
  self:_ensureBaseImages()
  local h, m = tonumber(date("%H")), tonumber(date("%M"))
  local hands = self._hands[60 * h + m] or self:_updateHands(h, m)
  self._screen_bb:fill(Blitbuffer.COLOR_WHITE)
  local cx = math.floor((self.width - self.face_dim) / 2)
  local cy = math.floor((self.height - self.face_dim) / 2)
  if self._face_bb then
    local face_w, face_h = self._face_bb:getWidth(), self._face_bb:getHeight()
    self._screen_bb:blitFrom(self._face_bb, cx, cy, 0, 0, face_w, face_h)
  end
  if hands and hands.hours_bb then
    local hbb_w, hbb_h = hands.hours_bb:getWidth(), hands.hours_bb:getHeight()
    local hcx = cx + math.floor((self.face_dim - hbb_w) / 2)
    local hcy = cy + math.floor((self.face_dim - hbb_h) / 2)
    self._screen_bb:pmulalphablitFrom(hands.hours_bb, hcx, hcy, 0, 0, hbb_w, hbb_h)
  end
  if hands and hands.minutes_bb then
    local mbb_w, mbb_h = hands.minutes_bb:getWidth(), hands.minutes_bb:getHeight()
    local mcx = cx + math.floor((self.face_dim - mbb_w) / 2)
    local mcy = cy + math.floor((self.face_dim - mbb_h) / 2)
    self._screen_bb:pmulalphablitFrom(hands.minutes_bb, mcx, mcy, 0, 0, mbb_w, mbb_h)
  end
  return bb:blitFrom(self._screen_bb, x, y, 0, 0, self.width, self.height)
end
ClockWidget._prepareHands = function(self, hours, minutes)
  local idx = hours * 60 + minutes
  if self._hands[idx] then
    return self._hands[idx]
  end
  self:_ensureBaseImages()
  if not (self._hours_hand_bb and self._minutes_hand_bb) then
    return { }
  end
  self._hands[idx] = { }
  local hour_rad, minute_rad = -math.pi / 6, -math.pi / 30
  local hours_hand_bb = rotate_bb(self._hours_hand_bb, self._hours_hand_bb:getWidth() / 2, self._hours_hand_bb:getHeight() / 2, (hours + minutes / 60) * hour_rad)
  local minutes_hand_bb = rotate_bb(self._minutes_hand_bb, self._minutes_hand_bb:getWidth() / 2, self._minutes_hand_bb:getHeight() / 2, minutes * minute_rad)
  self._hands[idx].hours_bb = hours_hand_bb
  self._hands[idx].minutes_bb = minutes_hand_bb
  local n_hands = 0
  for __ in pairs(self._hands) do
    n_hands = n_hands + 1
  end
  logger.dbg("ClockWidget: hands ready for", hours, minutes, ":", n_hands, "position(s) in memory.")
  return self._hands[idx]
end
ClockWidget._updateHands = function(self)
  local hours, minutes = tonumber(date("%H")), tonumber(date("%M"))
  local floor, fmod
  do
    local _obj_0 = math
    floor, fmod = _obj_0.floor, _obj_0.fmod
  end
  UIManager:scheduleIn(50, function()
    local idx = hours * 60 + minutes
    for k in pairs(self._hands) do
      if (idx < 24 * 60 - 2) and (k - idx < 0) or (k - idx > 2) then
        self._hands[k] = nil
      end
    end
    local fut_minutes = minutes + 1
    local fut_hours = fmod(hours + floor(fut_minutes / 60), 24)
    fut_minutes = fmod(fut_minutes, 60)
    return self:_prepareHands(fut_hours, fut_minutes)
  end)
  return self:_prepareHands(hours, minutes)
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
