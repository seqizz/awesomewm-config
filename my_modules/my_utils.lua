local awful = require("awful")

local my_utils = {}

-- @Reference, not used
function my_utils.am_i_on_screen(screen_name)
    local answer = false
    for out,_ in pairs(awful.screen.focused().outputs) do
        if out == screen_name then
            answer = true
        end
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

function my_utils.file_age(file, printmore)
  -- get seconds from file's last modification time
  local f = io.popen("stat -c %Y " .. file)
  local file_age = f:read()
  local myval = os.difftime(os.time(), file_age)
  debug_print("file_age: " .. myval .. " seconds", printmore)
  f:close()
  return myval
end

function my_utils.read_lines_from(file)
  if not my_utils.file_exists(file) then return {} end
  lines = {}
  for line in io.lines(file) do
    lines[#lines + 1] = line
  end
  return lines
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

function my_utils.get_first_word(s)
  local spaces_removed = s:match("(%S+)")
  local under_removed = spaces_removed:match("([^_]+)")
  -- words[1], words[2] = s:match("(%w+)(%W+)")
  -- if under_removed == nil then under_removed = s end
  return under_removed
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

function my_utils.find_screen_by_name(name)
  for s in screen do
    if my_utils.table_length(s.outputs) == 0 and name == "fake_screen" then
        return s
    end
    for screen_name, _ in pairs(s.outputs) do
      if screen_name == name then
        return s
      end
    end
  end
end

function my_utils.split_string(pString, pPattern)
   local Table = {n = 0}
   local fpat = "(.-)" .. pPattern
   local last_end = 1
   local s, e, cap = pString:find(fpat, 1)
   while s do
      if s ~= 1 or cap ~= "" then
     table.insert(Table,cap)
      end
      last_end = e+1
      s, e, cap = pString:find(fpat, last_end)
   end
   if last_end <= #pString then
      cap = pString:sub(last_end)
      table.insert(Table, cap)
   end
   return Table
end

local charset = {}  do -- [0-9a-zA-Z]
    for c = 48, 57  do table.insert(charset, string.char(c)) end
    for c = 65, 90  do table.insert(charset, string.char(c)) end
    for c = 97, 122 do table.insert(charset, string.char(c)) end
end

function my_utils.random_string(length)
    if not length or length <= 0 then return '' end
    math.randomseed(os.clock()^5)
    return my_utils.random_string(length - 1) .. charset[math.random(1, #charset)]
end

return my_utils
-- vim: set ts=2 sw=2 tw=0 et :
