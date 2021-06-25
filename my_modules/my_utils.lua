local awful = require("awful")

local my_utils = {}

function my_utils.am_i_on_screen(screen_name)
    local answer = false
    for out,_ in pairs(awful.screen.focused().outputs) do
        if out == screen_name then
            answer = true
        end
    end
    return answer
end

function my_utils.is_screen_primary(s)
    local answer = false
		if screen_table[s]["role"] == "primary" then
      answer = true
    end
    return answer
end

function my_utils.dump(o, level)
  -- a shitty pretty print implementation
  level = level or 0
  if type(o) == 'table' then
    local l = string.rep('  ', level)
    local s = l .. '{\n'
    local c = l .. '}'
    for k,v in pairs(o) do
      if type(k) ~= 'number' then
        k = '"'..tostring(k)..'"'
      end
      s = s .. l .. '['..tostring(k)..'] = ' .. my_utils.dump(v, level + 1) .. ',\n'
    end
    return s .. c
   else
    return tostring(o)
   end
end

function my_utils.table_contains(table, element, check_key)
  check_key = check_key or false
  for key, value in pairs(table) do
    -- lua doesn't have ternary operator.. as expected
    if check_key then
      control_value = key
    else
      control_value = value
    end
    if control_value == element then
      return true
    end
  end
  return false
end

function my_utils.table_removekey(inputtable, key)
	local e
	for i = 1, #inputtable do
			if (inputtable[i] == key) then
					e = i
			end
	end
	if e then table.remove(inputtable, e) end
end

function my_utils.table_length(inputtable)
  local count = 0
  for _ in pairs(inputtable) do count = count + 1 end
  return count
end

function my_utils.get_randomseed(b, m, r)
  urand = assert (io.open ('/dev/urandom', 'rb'))
  b = b or 4
  m = m or 256
  r = r or urand
  local n, s = 0, r:read (b)

  for i = 1, s:len () do
    n = m * n + s:byte (i)
  end

  return n
end

function my_utils.create_markup(arg)
  arg.size = arg.size or "medium"
  arg.rise = arg.rise or "0"

  result = '<span size="' .. arg.size ..'" rise="' .. arg.rise .. '" '
  if arg.fg ~= nil then
    result = result .. 'foreground="' .. arg.fg .. '" '
  end
  if arg.bg ~= nil then
    result = result .. 'background="' .. arg.bg .. '" '
  end
  if arg.font ~= nil then
    result = result .. 'font="' .. arg.font .. '" '
  end

  result = result .. '>' .. arg.text .. '</span>'
  return result
end

function my_utils.file_exists(name)
   local f=io.open(name,"r")
   if f~=nil then io.close(f) return true else return false end
end

function my_utils.sleep(seconds)
  os.execute("sleep " .. seconds)
end

-- Returns true if one value is falsey and the other is truthy, returns false otherwise
function my_utils.xor(a, b)
  return a ~= b
end

return my_utils
