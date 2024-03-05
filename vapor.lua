-- vapor: a notation interpreter
-- author: tosu|diag
-- license: MIT/unlicense
-- inspirations: uxn, uf, konilo, F83

--  need:   conditionals!

-- initialize the interpreter


local dictionary = {}
local stack = {}
local rstack = {}
local memory = {}
local memstore = {}
local whilestack = {}
local startup = false
local interpmsg = false
local argstring = ""
local wordswrap = 6
local prompt = "> "
local controlStack = {}

local tryword = nil

local cell_width = 1

--  procedures

local push, pop, dispatch, main_loop
local make_dispatch_execute_until
local make_dispatch_skip_until

-- implementing forth base

-- stack operations

dictionary['POP'] = function(...)
	io.write(tostring(pop() .. " " or ""))
	io.flush()
end

dictionary['DROP'] = function(...)
	pop()
end

dictionary['NIP'] = function(...)
	local b = pop()
	local a = pop()
	push(b)
end

dictionary['SWAP'] = function(...)
	a = pop()
	b = pop()
	push(a)
	push(b)
end

dictionary['ROT'] = function(...)
	local c = pop()
	local b = pop()
	local a = pop()
	push(b)
	push(c)
	push(a)
end

dictionary['DUP'] = function(...)
  local a = pop()
  push(a, a)
end

dictionary['OVER'] = function(...)
	a = pop()
	b = pop()
	push(b)
	push(a)
	push(b)
end

dictionary['PICK'] = function(...)
  b = pop()
  push(stack[#stack-(b)]) -- this is 0-indexed starting from the top of stack
end

dictionary['DEPTH'] = function(...)
  push(#stack)
end

-- logic operations

dictionary['EQUAL'] = function(...)
	local a, b = pop(2)
	if a==b then
		push(1)
	else
		push(0)
	end
end

dictionary['AND'] = function(...)
    local a, b = pop(2)
    if a == 1 and b == 1 then push(1)
        else push(0)
    end
end

dictionary['NOT'] = function(...)
	local a = pop()
	if a == 1 then push(0)
	elseif a == 0 then push(1)
	elseif a ~= 1 or 0 then push(a*-1)
	end
end

dictionary['OR'] = function(...)
	local a, b = pop(2)
    if a == 1 or b == 1 then push(1)
    else push(0)
    end
end

dictionary['XOR'] = function(...)
	local a, b = pop(2)
	if a == 1 and b == 1 then push(0)
    elseif a == 1 or b == 1 then push(1)
    else push(0)
    end
end

-- control flow: no idea how
-- i think this requires a vm/instruction pointer actually

-- JMP == a b {PC+=c}

-- JCN == a {(b8)PC+=c}

-- JSR == a b {rs.PC PC+=c}

-- math operations

dictionary['ADD'] = function(...)
  local a, b = pop(2)
  push(a + b)
end

dictionary['SUB'] = function(...)
  local a, b = pop(2)
  push(a - b)
end

dictionary['MUL'] = function(...)
  local a, b = pop(2)
  push(a * b)
end

dictionary['DIV'] = function(...)
  local a, b = pop(2)
  push(a / b)
end

dictionary['MOD'] = function(...)
	local a, b = pop(2)
	push(a % b)
end

dictionary['MORE'] = function(...)
  local a, b = pop(2)
	if a > b then
		push(1)
	else
		push(0)
	end
end

dictionary['LESS'] = function(...)
  local a, b = pop(2)
	if a < b then
		push(1)
	else
		push(0)
	end
end

--[[
dictionary['SFT'] = function(...)
  local a = pop()
  local b = pop()
	push(b >> a)
end
]]--

dictionary['EMIT'] = function(...)
	io.write(string.char(pop() or 32))
	io.flush()
end

function display_stack()
	io.write('  DATA STACK: (' .. #stack .. ')',' [')
	for k,v in ipairs(stack) do
		io.write(' ', v)
	end
	io.write(' ]\n')
end

dictionary['SHOW'] = function(...)
	display_stack()
end

function display_rstack()
	io.write('RETURN STACK: (' .. #rstack .. ')',' [')
	for k,v in ipairs(rstack) do
		io.write(' ', v)
	end
	io.write(' ]\n')
end

dictionary['RSHOW'] = function(...)
  display_rstack()
end

dictionary['LOAD'] = function(...)
	local addr = pop()
	local data = memory[addr] or 0
	push(data)
end

dictionary['STORE'] = function(...) -- todo: needs work
	local addr = pop()
	local value = pop()
	memory[addr] = value
	memstore[#memstore + 1] = addr
	memstore[#memstore + 2] = value
end

dictionary['MSHOW'] = function(...) -- todo: needs work
	io.write('      MEMORY: (' .. #memstore .. ')','  ')
	for k,v in ipairs(memstore) do
		io.write(v .. ", " .. v .. "\n")
	end
	io.write('\n')
end

dictionary['DEBUG'] = function(...)
	display_stack()
	display_rstack()
end

dictionary['EMPTY'] = function(...) -- Forth's QUIT
    stack = {}
    rstack = {}
    memory = {}
    restart_dispatch()
end

dictionary['`'] = function(...) -- equivalent to "EMPTY PAGE"
    stack = {}
    rstack = {}
    memory = {}
    restart_dispatch()
    io.write("\27[2J\27[1;1H")
end

dictionary['DUMP'] = function(...) -- Return top-stack value and close interpreter
    -- io.write("\27[2J\27[1;1H")
    io.write(pop())
	os.exit()
end

-- Comment
dictionary['#'] = function(original_dispatcher)
  return make_dispatch_skip_until("#", original_dispatcher)
end

-- Define new symbol
dictionary['DEF'] = function(original_dispatcher)
  local accumulator = {}
  return function(disp, word)
    if word == 'END' then
      local sym = table.remove(accumulator, 1)
      dictionary[sym] = function(disp)
        dispatch_list(original_dispatcher, accumulator)
      end
      return original_dispatcher
    -- hack for case sensitivity  
    elseif word == 'end' then
      local sym = table.remove(accumulator, 1)
      dictionary[sym] = function(disp)
        dispatch_list(original_dispatcher, accumulator)
      end
      return original_dispatcher
    elseif word == ';' then
      local sym = table.remove(accumulator, 1)
      dictionary[sym] = function(disp)
        dispatch_list(original_dispatcher, accumulator)
      end
      return original_dispatcher     
    else
      accumulator[#accumulator+1] = word
    end
  end
end

dictionary['LINE'] = function(...)
	io.write('\n')
	io.flush()
end

dictionary['PAGE'] = function(...)
	--os.execute('clear')
	io.write("\27[2J\27[1;1H")
end

dictionary['RPOP'] = function(...)
	rpop()
end

dictionary['RPUSH'] = function(...)
	rpush()
end

dictionary['BREAK'] = function(...)
	rpop()
	io.write(tostring(pop() .. " " or ""))
	io.flush()
	-- and resume execution at address
end

dictionary['SPACE'] = function(...)
	io.write(" ")
end

dictionary['JOIN'] = function(...)
	local a, b = pop(2)
	push(tostring(a) .. tostring(b))
end

function sleep(s) local ntime = os.time() + s repeat until os.time() > ntime end
dictionary['WAIT'] = function(...)
	sleep(pop())
end

-- duplicated for init wordlist print
function list_words()
    local wordcount = 0
    local words_to_print = {}

    -- Count words and prepare a table for case-insensitive uniqueness
    for word, _ in pairs(dictionary) do
        wordcount = wordcount + 1
        local upper_word = word:upper()
        words_to_print[upper_word] = true
    end

    -- Convert the keys (unique uppercase words) to a list and sort
    local sorted_symbols = {}
    for upper_word, _ in pairs(words_to_print) do
        table.insert(sorted_symbols, upper_word)
    end
    table.sort(sorted_symbols)

    -- Print the words
    for k, v in ipairs(sorted_symbols) do
        io.write(v, '\t')
        if k % wordswrap == 0 then io.write('\n') end
    end

    -- Uncomment if you want to print the word count
    -- io.write('\nTotal Words: ', wordcount, '\n')
end

dictionary['WORDS'] = function(...)
    list_words()
end

dictionary['EXIT'] = function(...)
    io.write("\27[2J\27[1;1H")
	os.exit()
end

--[[ TODO: introspection

dictionary['SEE'] = function(...)
  print(debug.getinfo(1, "n").name);
end

]]--

function pushControlState(state)
    table.insert(controlStack, state)
end

function popControlState()
    return table.remove(controlStack)
end

function currentControlState()
    return controlStack[#controlStack] or {executing = true}
end

dictionary['IF'] = function(original_dispatcher)
  local condition = pop()
  if condition ~= 0 then
    pushControlState({executing = true, type = 'IF'})
    return make_dispatch_execute_until("THEN", original_dispatcher)
  else
    pushControlState({executing = false, type = 'IF'})
    return make_dispatch_skip_until("ELSE", make_dispatch_execute_until("THEN", original_dispatcher))
  end
end

dictionary['if'] = dictionary['IF']

-- ELSE
dictionary['ELSE'] = function(original_dispatcher)
  local controlState = currentControlState()
  if controlState.type == 'IF' then
    controlState.executing = not controlState.executing
  end
  return original_dispatcher
end

dictionary['else'] = dictionary['ELSE']

-- THEN
dictionary['THEN'] = function(original_dispatcher)
  local controlState = popControlState()
  if controlState and controlState.type == 'IF' then
    return original_dispatcher
  else
    error("THEN without a matching IF")
  end
end

dictionary['then'] = dictionary['THEN']

dictionary['."'] = function(original_dispatcher)
  local accumulator = {}
  return function(disp, word)
    if word == '"' then
      local str = table.concat(accumulator, " ")
      push(str)
      return original_dispatcher
    else
      table.insert(accumulator, word)
    end
  end
end

-- todo: file reading from interpreter
-- requires string handling?

dictionary['INCLUDE'] = function(original_dispatcher)
    local filename = pop() -- Get the filename from the stack
    local file = io.open(filename, "r") -- Open the file
    if file then
        local content = file:read("*all") -- Read the entire content
        file:close()

        -- Process each word in the file
        for word in string.gmatch(content, "%S+") do
            local disp_function = dictionary[word]
            if disp_function then
                disp_function(original_dispatcher)
            else
                -- Handle undefined words
                io.write("Undefined word: ", word, "\n")
            end
        end
    else
        io.write("Cannot open file: ", filename, "\n")
    end
end
		
--  dispatcher

-- dispatcher takes:
--   disp: the current dispatcher function
--   word: a string to process
-- it can return a function value which will replace the actual dispatcher.

function dispatch(disp, word)
  --print(word) -- confirms interpreter read word

  if dictionary[word] then
    return dictionary[word](disp)
  elseif dictionary[string.upper(word)] then
    return dictionary[string.upper(word)](disp)
  elseif word:match("-?[%d]*.?[%d]*") == word then
		push(tonumber(word))
  else
    io.write("\n\27[31merror:\27[0m ",word," is undefined\n")
			errorlevel=1
  end
end

function dispatch_list(disp, list)
  for i = 1, #list do
    local res = disp(disp, list[i])
    if res ~= nil then
      disp = res
    end
  end
end

-- Execute until a specific word, then switch back to the original dispatcher
function make_dispatch_execute_until(original_dispatcher, until_word)
  return function(disp, word)
    if word == until_word then
      return original_dispatcher
    else
      return disp  -- continue with the current dispatcher
    end
  end
end

-- Skip until a specific word, then switch back to the original dispatcher
function make_dispatch_skip_until(until_word, original_dispatcher)
  return function(disp, word)
    if word == until_word then
      return original_dispatcher
    else
      return disp  -- continue skipping words
    end
  end
end

--[[

function make_dispatch_skip_until(until_word, after_dispatcher)
  return function(disp, word)
    if word == until_word then
      return after_dispatcher or original_dispatcher
    else
      return disp  -- continue skipping words
    end
  end
end

]]--

function make_dispatch_execute_until(until_word, original_dispatcher)
  return function(disp, word)
    local controlState = currentControlState()
    if word == until_word then
      popControlState()  -- Pop the current control state
      return original_dispatcher
    elseif controlState.executing then
      return original_dispatcher(disp, word)
    else
      return disp  -- continue with the current dispatcher
    end
  end
end

function make_dispatch_skip_until(until_word, original_dispatcher)
  return function(disp, word)
    local controlState = currentControlState()
    if word == until_word then
      popControlState()  -- Pop the current control state
      return original_dispatcher
    else
      return disp  -- continue skipping words
    end
  end
end

--[[

backup

function make_dispatch_skip_until(until_word, after_dispatcher)
  return function(disp, word)
    if word == until_word then
      return after_dispatcher
    end
  end
end

]]--

function restart_dispatch(original_dispatcher)
  return function(disp, word)
    disp = res
  end
end

function make_dispatch_print_until(until_word, after_dispatcher)
	local num_printed = 0
  return function(disp, word)
		num_printed = num_printed + 1
    if word == until_word then
			if num_printed > 1 then
			io.write("\27[1D") --backspace over final space
			end
      return after_dispatcher
		else
			io.write(word," ")
    end
  end
end

--  main loop

function main_loop()
  os.execute('cls')
	local input = true
  local disp = dispatch
  if startup == true then
    list_words()
    io.write('\n')
  end

  if #arg == 0 then
    argstring = "no args"
  elseif #arg == 1 then
  -- file reading
    if interpmsg == true then
      print("interpreter:" .. " " .. argstring)
      argstring = arg[1] .. " interpreted"
    end
    local f, err = io.open(arg[1], "r")
    if err then
		errorlevel=1
  end
  local src = f:read("*all")
  f:close()
  file_input = src
  if file_input then
      local res, msg = pcall(function()
        for word in string.gmatch(file_input, "%s*(%S+)%s*") do
          local res = disp(disp, word)
          --tryword = res
          if res ~= nil then
            disp = res
          end
        end
		  if errorlevel ~= 1 then
			print(" ok")
	      end
      end)
      if not res then
        -- io.write(msg, "\n")
      end
    end
  ------
  end
  
  while input ~= 'EXIT' do
    io.write(prompt)
    io.flush()
			errorlevel=0
    --input = string.upper(io.read())
		input = io.read()
    if input then
      local res, msg = pcall(function()
        for word in string.gmatch(input, "%s*(%S+)%s*") do
          local res = disp(disp, word)
          --tryword = word
          if res ~= nil then
            disp = res
          end
        end
		  if errorlevel ~= 1 then
			print(" ok")
	      end
      end)
      if not res then
        --io.write(msg, "\n") -- this prints Lua error msgs
      end
    end
  end
end

-- Stack Operations

function pop(n)
  if #stack > 0 then
        if n == nil or n == 1 then
            return table.remove(stack)
        else
            res = {}
            max = #stack
            for i = 1, n do
                res[i] = stack[max - n + i]
                stack[max - n + i] = nil
            end
            return table.unpack(res)
        end
	else
		print('\27[31mstack underflow\27[0m')
        errorlevel=1
	end
end

function push(...)
  for i = 1, select("#", ...) do
    stack[#stack+1] = select(i, ...)
  end
end

function rpush()
	rstack[#rstack + 1] = pop()
end

function rpop()
	push(rstack[#rstack])
	rstack[#rstack]=nil
end

-- Execution

-- Lua 5.1 / 5.2 compatibility
if unpack and not table.unpack then
  table.unpack = unpack
end

main_loop()

