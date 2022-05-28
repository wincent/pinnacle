local pinnacle = {}

local prefix = 'cterm'

if vim.fn.has('gui') == 1 then
  prefix = 'gui'
elseif vim.fn.has('termguicolors') == 1 and vim.api.nvim_get_option('termguicolors') then
  prefix = 'gui'
end

-- Gets the current value of a highlight group.
pinnacle.capture_highlight = function(group)
  return group .. ' xxx ' .. pinnacle.extract_highlight(group)
end

-- Returns a copy of `group` decorated with `style` (eg. "bold",
-- "italic" etc) suitable for passing to `:highlight`.
--
-- To decorate with multiple styles, `style` should be a comma-separated
-- list.
pinnacle.decorate = function(style, group)
  local original = pinnacle.extract_highlight(group)

  for _, lhs in ipairs({'gui', 'term', 'cterm'}) do
    local before, setting, after = original:match(''
      .. '^(.*)'
      .. '%f[%a](' .. lhs .. '=%S+)'
      .. '(.*)$'
    )

    if setting == nil then
      -- No setting: add one with just style in it.
      original = original .. ' ' .. lhs .. '=' .. style
    else
      for s in vim.gsplit(style, ',') do
        local trimmed = vim.trim(s)
        if not setting:match('%f[%a]' .. trimmed .. '%f[%A]') then
          setting = setting .. ',' .. trimmed
        end
      end
      original = before .. setting .. after
    end

    return original
  end
end

-- Returns a dictionary representation of the specified highlight group.
pinnacle.dump = function(group)
  local result = {}

  for _, component in ipairs({'bg', 'fg'}) do
    local value = pinnacle.extract_component(group, component)
    if value ~= '' then
      result[component] = value
    end
  end

  local active = {}

  for _, component in ipairs({'bold', 'inverse', 'italic', 'reverse', 'standout', 'undercurl', 'underline'}) do
    if pinnacle.extract_component(group, component) == '1' then
      table.insert(active, component)
    end
  end

  if #active > 0 then
    result[prefix] = table.concat(active, ',')
  end

  return result
end

-- Returns an bold copy of `group` suitable for passing to `:highlight`.
pinnacle.embolden = function(group)
  return pinnacle.decorate('bold', group)
end

-- Extracts just the "bg" portion of the specified highlight group.
pinnacle.extract_bg = function(group)
  return pinnacle.extract_component(group, 'bg')
end

-- Extracts a single component (eg. "bg", "fg", "italic" etc) from the
-- specified highlight group.
pinnacle.extract_component = function(group, component)
  return vim.fn.synIDattr(
    vim.fn.synIDtrans(vim.fn.hlID(group)),
    component
  )
end

-- Extracts just the "fg" portion of the specified highlight group.
pinnacle.extract_fg = function(group)
  return pinnacle.extract_component(group, 'fg')
end

-- Extracts a highlight string from a group, recursively traversing
-- linked groups, and returns a string suitable for passing to
-- `:highlight` (effectively extracts the bit after "xxx").
pinnacle.extract_highlight = function(group)
  -- We originally relied on:
  --
  --    vim.api.nvim_exec('0verbose highlight ' .. group, true)
  --
  -- But for some reason it sometimes returns an empty string, so we do this
  -- instead:
  return pinnacle.highlight(pinnacle.dump(group))
end

-- Returns a string representation of a table containing bg, fg, term,
-- cterm and guiterm entries.
pinnacle.highlight = function(highlight)
  local result = {}

  for _, key in ipairs({'bg', 'fg'}) do
    if highlight[key] ~= nil then
      table.insert(result, prefix .. key .. '=' .. highlight[key])
    end
  end

  for _, key in ipairs({'term', 'cterm', 'guiterm'}) do
    if highlight[key] ~= nil then
      table.insert(result, prefix .. '=' .. highlight[key])
    end
  end

  return table.concat(result, ' ')
end

-- Returns an italicized copy of `group` suitable for passing to
-- `:highlight`.
pinnacle.italicize = function(group)
  return pinnacle.decorate('italic', group)
end

-- Returns an underlined copy of `group` suitable for passing to
-- `:highlight`.
pinnacle.underline = function(group)
  return pinnacle.decorate('underline', group)
end

local clamp = function (value, lower, upper)
  return math.max(lower, math.min(upper, value))
end

local round = function(value)
  -- There is no math.round, so adjust and use math.floor. As noted here, this
  -- is subject to small but acceptable precision errors:
  -- https://stackoverflow.com/a/18313481/2103996
  return math.floor(value + 0.5)
end

-- Receives red/green/blue values in the range of 0 to 255.
-- Returns hue (0 to 360), saturation (0 to 100), and lightness (0 to 100).
local rgb_to_hsl = function(r, g, b)
  -- Based on:
  -- https://css-tricks.com/converting-color-spaces-in-javascript/#aa-rgb-to-hsl
  local h = nil
  local s = nil
  local l = nil
  local r_f = r / 255
  local g_f = g / 255
  local b_f = b / 255
  local min = math.min(r_f, g_f, b_f)
  local max = math.max(r_f, g_f, b_f)
  local delta = max - min
  if delta == 0 then
    h = 0
  elseif max == r_f then
    h = ((g_f - b_f) / delta) % 6
  elseif max == g_f then
    h = (b_f - r_f) / delta + 2
  else -- max == b_f
    h = (r_f - g_f) / delta + 4
  end
  h = round(h * 60)
  if h < 0 then
    h = h + 360
  end
  l = (min + max) / 2
  if delta == 0 then
    s = 0
  else
    s = delta / (1 - math.abs(2 * l - 1))
  end
  s = s * 100
  l = l * 100
  return h, s, l
end

-- Receives a hue (0 to 360), saturation (0 to 100), and lightness (0 to 100).
-- Returns red/green/blue values in the range of 0 to 255.
local hsl_to_rgb = function(h, s, l)
  -- Based on:
  -- https://css-tricks.com/converting-color-spaces-in-javascript/#aa-hsl-to-rgb
  local s_f = s / 100
  local l_f = l / 100
  local c = (1 - math.abs(2 * l_f - 1)) * s_f -- chroma (color intensity)
  local x = c * (1 - math.abs((h / 60) % 2 - 1)) -- second largest component
  local m = l_f - c / 2 -- lightness
  local r = 0
  local g = 0
  local b = 0
  if 0 <= h and h < 60 then
    r = c
    g = x
    b = 0
  elseif 60 <= h and h < 120 then
    r = x
    g = c
    b = 0
  elseif 120 <= h and h < 180 then
    r = 0
    g = c
    b = x
  elseif 180 <= h and h < 240 then
    r = 0
    g = x
    b = c
  elseif 240 <= h and h < 300 then
    r = x
    g = 0
    b = c
  elseif 300 <= h and h < 360 then
    r = c
    g = 0
    b = x
  end
  r = round((r + m) * 255)
  g = round((g + m) * 255)
  b = round((b + m) * 255)
  return r, g, b
end

local to_hex = function(value)
  return string.format('%.2x', value)
end

-- Returns a dictionary representation of the specified `group`, with all color
-- values darkened by `percentage` (a number between 0 and 1).
--
-- Percentages are absolute and not relative to the lightness of the colors in
-- the group. For example, given an HSL color space with possible lightness
-- values ranging from 0 to 100, passing in a percentage of 0.1 here will
-- decrease the lightness of each color by 10.
pinnacle.darken = function(group, percentage)
  return pinnacle.adjust_lightness(group, percentage * -1)
end

-- Returns a dictionary representation of the specified `group`, with all color
-- values brightened by `percentage` (a number between 0 and 1).
--
-- Percentages are absolute and not relative to the lightness of the colors in
-- the group. For example, given an HSL color space with possible lightness
-- values ranging from 0 to 100, passing in a percentage of 0.1 here will
-- increase the lightness of each color by 10.
pinnacle.brighten = function(group, percentage)
  return pinnacle.adjust_lightness(group, percentage * 1)
end

-- Returns a dictionary representation of the specified `group`, with all color
-- values darkened or brightened by `percentage` (a number between -1 and 1).
-- Negative percentages make the colors darker, positive numbers make the colors
-- brighter, and a value of zero results in no change.
--
-- Percentages are absolute and not relative to the lightness of the colors in
-- the group. For example, given an HSL color space with possible lightness
-- values ranging from 0 to 100, passing in a percentage of plus or minus 0.1
-- here will increase or decrease the lightness of each color by 10.
pinnacle.adjust_lightness = function(group, percentage)
  local dict = pinnacle.dump(group)
  for key, value in pairs(dict) do
    -- 'Grey70' → 11776947, '#839496' → 8623254, 'reverse' → -1
    local rgb = vim.api.nvim_get_color_by_name(value)
    if rgb ~= -1 then
      local r = bit.rshift(rgb, 16)
      local g = bit.band(bit.rshift(rgb, 8), 0xff)
      local b = bit.band(rgb, 0xff)
      local h, s, l = rgb_to_hsl(r, g, b)
      l = l + (percentage * 100)
      l = clamp(l, 0, 100)
      r, g, b = hsl_to_rgb(h, s, l)
      dict[key] = '#' .. to_hex(r) .. to_hex(g) .. to_hex(b)
    end
  end
  return dict
end

return pinnacle
