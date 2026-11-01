--[[
  MIT License

  Copyright (c) 2026 palepine

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in all
  copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  SOFTWARE.
]]

local FRAMEWORK_KEY = 'PPLuaFramework.instance'
local previous = package.loaded[ FRAMEWORK_KEY ]

-- clean previous resources
if previous then
  assert( previous.CEHelper.teardown(), 'cleanup failed' )
  package.loaded[ FRAMEWORK_KEY ] = nil
end

local Framework =
{
  CEHelper = {},
  Timer = {},
  Thread = {},
  MemRecs = {},
  Handles = {},
  Debug = {},
  Alloc = {},

  UnityHelper = {},


  API = {}
}

Framework.Alloc.Allocations = {}
Framework.Alloc.AllocationsBySymbol = {}
Framework.Timer.TimerItems = {}
Framework.Thread.ThreadItems = {}

function Framework.Alloc.AllocateSymbol(symbolName, size)
  assert( type(symbolName) == 'string', 'symbol name must be a string' )
  assert( type(size) == 'number', 'size must be provided as a number' )

  Framework.Alloc.DeallocateSymbol(symbolName)

  local addr = allocateMemory( size )
  assert(addr and addr ~= 0, 'failure to allocate')

  Framework.Alloc.Allocations[ addr ] = symbolName
  Framework.Alloc.AllocationsBySymbol[ symbolName ] = addr

  registerSymbol( symbolName, addr, true )

  return addr
end

function Framework.Alloc.DeallocateSymbol(symbolName)
  local addr = Framework.Alloc.AllocationsBySymbol[ symbolName ]
  if not addr then return end

  unregisterSymbol( symbolName )
  deAlloc( addr )
  
  Framework.Alloc.AllocationsBySymbol[symbolName] = nil
  Framework.Alloc.Allocations[addr] = nil
end

function Framework.Alloc.DeallocateAll()
  for addr, symbol in pairs(Framework.Alloc.Allocations or {}) do
    deAlloc( addr )
    unregisterSymbol( symbol )
  end
  Framework.Alloc.Allocations = {}
  Framework.Alloc.AllocationsBySymbol = {}
end

function Framework.Timer.create(name, interval, callback)
  assert( type(name) == 'string', 'timer name must be a string' )
  assert( type(interval) == 'number', 'interval must be provided as a number' )

  Framework.Timer.destroy( name )
  
  local timer = createTimer(nil, false)
  timer.Interval = interval
  timer.OnTimer = callback
  Framework.Timer.TimerItems[name] = timer
  return timer
end

function Framework.Timer.get(name)
  return Framework.Timer.TimerItems[name]
end

function Framework.Timer.enable(name)
  local timer = Framework.Timer.get(name)
  if timer then
    timer.Enabled = true
  end
end

function Framework.Timer.disable(name)
  local timer = Framework.Timer.get(name)
  if timer then
    timer.Enabled = false
  end
end

function Framework.Timer.destroy(name)
  local timer = Framework.Timer.get(name)
  if timer then
    timer.destroy()
    Framework.Timer.TimerItems[name] = nil
  end
end

function Framework.Timer.destroyAll()
  for name in pairs(Framework.Timer.TimerItems or {}) do
    Framework.Timer.destroy(name)
  end
end

function Framework.Thread.create(name, interval, callback)
  assert( type(name) == 'string', 'thread name must be a string' )
  assert( type(interval) == 'number' and interval > 0, 'interval must be positive' )
  assert( type(callback) == 'function', 'callback must be a function' )

  Framework.Thread.destroy( name )
  
  local thread = createThread(
    function(thr)
      thr.Name = name

      while not thr.Terminated do
        pcall( callback, thr )

        -- sleep
        local remaining = interval
        while remaining > 0 do
          if thr.Terminated then return end
          local chunk = math.min( remaining, 100 ) 
          sleep(chunk)
          remaining = remaining - chunk
        end

      end

    end
  )

  Framework.Thread.ThreadItems[name] = thread
  return thread
end

function Framework.Thread.get(name)
  return Framework.Thread.ThreadItems[name]
end

function Framework.Thread.enable(name)
  local thread = Framework.Thread.get(name)
  if thread then
    thread.resume()
  end
end

function Framework.Thread.disable(name)
  local thread = Framework.Thread.get(name)
  if thread then
    thread.suspend()
  end
end

function Framework.Thread.destroy(name)
  local thread = Framework.Thread.get(name)
  if not thread then return end

  thread.terminate()
  thread.waitfor()
  thread.destroy()
  Framework.Thread.ThreadItems[name] = nil
end

function Framework.Thread.destroyAll()
  for name in pairs(Framework.Thread.ThreadItems or {}) do
    Framework.Thread.destroy(name)
  end
end

function Framework.MemRecs.disable(memrec)
  createTimer( 200, function() memrec.Enabled = false end )
end

function Framework.MemRecs.toggleFlag(memrec, flag, description, onValue, offValue)
  assert( memrec ~= nil, 'memrec must be valid' )
  assert( memrec.getClassName and memrec.getClassName() == 'TMemoryRecord', 'not a memrec' )
  assert( type(flag) == 'string', 'flag symbol must be a string' )
  assert( type(description) == 'string', 'description must be a string' )

  onValue = onValue or 1
  offValue = offValue or 0

  local status = readByte(flag)
  if not status then error('invalid flag') end

  -- get opposite
  local newValue = (status == onValue) and offValue or onValue
  local newDescription = (status == onValue) and ' OFF' or ' ON'
  
  if not writeByte(flag, newValue) then error( 'failed toggle' ) end

  memrec.Description = description .. newDescription

  memrec.Enabled = false
end

function Framework.CEHelper.iterateOpenProcess(procNameArray)

  local ok = false

  for _, name in ipairs(procNameArray) do
    if openProcess( name ) then
      ok = true
      break
    end
  end

  if not ok then
    ShowMessage( 'Failed to attach. App isnt run? Process names tried: ' .. (table.concat( procNameArray , ', ' ) or '') )
    error( 'Cant attach. App isnt run or name mismatch.' )
  end 
end

function Framework.CEHelper.toggleFullView(sender, force)
  local state = not( sender.Caption == 'Compact View' )
  
  if force ~= nil then
    state = not force
  end
  sender.Caption = state and 'Compact View' or 'Full View'
  getMainForm().Splitter1.Visible = state;
  getMainForm().Panel4.Visible = state
  getMainForm().Panel5.Visible = state
end

function Framework.CEHelper.addCompactMenu()
  if Framework.CEHelper.compactMenuItem then return end
  
  local parent = getMainForm().Menu.Items
  local compactMenuItem = createMenuItem(parent)
  parent.add(compactMenuItem)
  compactMenuItem.Caption = 'Full View'
  compactMenuItem.OnClick = Framework.CEHelper.toggleFullView
  Framework.CEHelper.compactMenuItem = compactMenuItem

  Framework.CEHelper.toggleFullView( compactMenuItem, true )
end

function Framework.CEHelper.teardown()
  Framework.Timer.destroyAll()
  Framework.Thread.destroyAll()
  Framework.Alloc.DeallocateAll() -- last

  local menuItem = Framework.CEHelper.compactMenuItem
  if menuItem then
    menuItem.destroy()
    Framework.CEHelper.compactMenuItem = nil
  end

  return true
end

function Framework.CEHelper.cleanMenuItems()
  local mainForm = getMainForm()
  local menuItems = mainForm and mainForm.Menu and mainForm.Menu.Items
  if not menuItems then return end
  
  for i = menuItems.Count-1,0,-1 do
    local item = menuItems[i]
    if not item then goto continue end
    if item.Name == 'miCeUEDumper' or item.Name == 'miGMDumper' or item.Name == 'miPGMDumper' then synchronize(function() item.destroy() end) end
    ::continue::
  end
end

function Framework.CEHelper.loadScriptFromTable(fileName)
  if not fileName then error('Filename invalid') end
  local tableFile = findTableFile( fileName )
  if tableFile == nil then error('No script file found') end
  local fileStream = tableFile.getData()
  local scriptString = readStringLocal(fileStream.Memory, fileStream.Size)
  if scriptString == nil then error('Script not loaded from file') end
  local doScript = loadstring(scriptString)
  if type(doScript) == 'function' then return doScript() end
  error('Script not parsed')
end

function Framework.UnityHelper.init()
  assert( process ~= nil and process ~= 0, 'process not attached' )
  if not LaunchMonoDataCollector() then error('monocollector failed') end
  
  _G[ 'mono_getStaticField' ] = Framework.UnityHelper.mono_getStaticField
  _G[ 'mono_invokeMethodFromClass' ] = Framework.UnityHelper.mono_invokeMethodFromClass
  _G[ 'registerClassSymbol' ] = Framework.UnityHelper.registerClassSymbol
  _G[ 'getMonoStructsFor' ] = Framework.UnityHelper.getMonoStructsFor
  _G[ 'tryDisassembleDetour' ] = Framework.UnityHelper.tryDisassembleDetour
  _G[ 'tryCompileDetour' ] = Framework.UnityHelper.tryCompileDetour
  _G[ 'tryCompileScript' ] = Framework.UnityHelper.tryCompileScript
end

function Framework.UnityHelper.mono_getStaticField(className, fieldName, namespace)
  assert( className ~= nil and className ~= '', 'class name invalid' )
  assert( fieldName ~= nil and fieldName ~= '', 'field name invalid' )
  namespace = namespace or ''
  
  local classID = mono_findClass( namespace, className )
  if classID == nil or classID == 0 then error('class not found') end
  
  local fields = mono_class_enumFields(classID, true)
  if fields == nil then error('could not enumerate class fields') end
  
  local field = nil

  for i = 1, #fields do
    local field = fields[i]

    if field.name == fieldName or field.altname == fieldName then

      if not field.isStatic then error('field is not static') end
      if field.isConst then error('field is a constant, no normal static storage') end
      if field.staticAddress == nil or field.staticAddress == 0 then error('static field address unavailable') end

      return field.staticAddress
    end
  end
  
  error('field not found.')
end

function Framework.UnityHelper.mono_invokeMethodFromClass( className, methodName, addrSymbolName, args, domainName )
  assert( className ~= nil and className ~= '', 'class name invalid' )
  assert( methodName ~= nil and methodName ~= '', 'method name invalid' )
  local domainName = domainName or ''

  args = args or {}
  
  local classID = mono_findClass( domainName, className )
  if classID == 0 or classID == nil then error('class not found') end
  
  local methodID = mono_class_findMethod( classID, methodName )
  if methodID == 0 or methodID == nil then error('method not found') end
  
  local flags = mono_method_getFlags(methodID) or 0
  local isStatic = ( flags & METHOD_ATTRIBUTE_STATIC ) == METHOD_ATTRIBUTE_STATIC
  
  local addr = 0
  
  if not isStatic then
    if addrSymbolName == nil or addrSymbolName == 0 or addrSymbolName == '' then error('instance address required for non-static method') end
    
    addr = getAddress( addrSymbolName )
    if addr == 0 or addr == nil then showMessage('Address not found/resolved!') error('address not found') end
  end
  
  local params = mono_method_get_parameters( methodID )
  if #args ~= #params.parameters then error(( 'expected number of args: %d, got: %d' ):format( (#args or 0) , (#params.parameters or 0) ) ); end

  local args_t = {}

  for i=1, #params.parameters do
    args_t[i] = {}
    local monoType = params.parameters[i].type
    args_t[i].type = monoType == MONO_TYPE_STRING and vtString or monoTypeToVartypeLookup[monoType]
    args_t[i].value = args[i]
  end
  
  return mono_invoke_method( domainName, methodID, addr, args_t )
end

function Framework.UnityHelper.registerClassSymbol(className, namespace)
  className = string.gsub( className, '[%+%-]', '' )
  namespace = (namespace and namespace ~= '' and namespace .. '.') or ''
  
  local fClass = mono_class_enumFields( mono_findClass( namespace, className ) )
  if not fClass or fClass == 0 then return end
  
  namespace = string.gsub( namespace, '[%+%-]', '' )
  
  for _ , field in ipairs(fClass) do
    registerSymbol( namespace..className..'.'..field.name , field.offset , true )
  end
end

function Framework.UnityHelper.getMonoStructsFor(...)
  local tableOfNames = table.pack(...)
  assert( type(tableOfNames) =='table', 'Pass a valid table of class names.' )
  
  local outStructs = ''

  for i = 1, tableOfNames.n do
    local ok, result, err = pcall( monoAA_GETMONOSTRUCT, tableOfNames[i] , false )
    if ok and result then
      outStructs = outStructs .. result .. '\n\n'
    else
      print( err or '' )
    end
  end
  
  return outStructs
end

function Framework.UnityHelper.tryDisassembleDetour(detourName)
  if dotnetdetours == nil then dotnetdetours = {} end

  local detourInfo = dotnetdetours[ detourName ]
  if detourInfo and detourInfo.processid == getOpenedProcessID() then
    local result, err = autoAssemble( detourInfo.disablescript, detourInfo.disableinfo )
    if not result then error(err) end
    dotnetdetours[detourName] = nil
  end
end

function Framework.UnityHelper.filterAssemblyRefs(assemblyRefs, sysfile)
  local result = {}
  local seenNames = {}
  local sysfileName =  extractFileName(sysfile)

  for _, path in pairs( assemblyRefs ) do
    local fileName = extractFileName(path)
    local skip = false

    if fileName == "mscorlib.dll" then skip = true end
    
    if sysfile and fileName == sysfile then skip = true end

    if sysfileName and fileName == sysfileName then skip = true end

    if seenNames[ fileName ] then skip = true end
    
    if not skip then
      seenNames[ fileName ] = true
      table.insert( result, path )
    end

  end

  return result
end

function Framework.UnityHelper.tryCompileDetour(csharpScript, className, methodDetour)
  assert( type(csharpScript) == 'string', 'script must be a string' )
  assert( type(className) == 'string', 'class name must be a string' )
  assert( type(methodDetour) == 'string', 'method name must be a string' )
  
  if dotnetdetours == nil then dotnetdetours = {} end

  local detourName = className .. '.' .. methodDetour

  local detourinfo = {}
  
  local assemblyRefs, sysfile = dotnetpatch_getAllReferences()
  assemblyRefs = filterAssemblyRefs( assemblyRefs, sysfile )
  
  local csfile, err = compileCS( csharpScript, assemblyRefs, sysfile )
  
  if not csfile then

    csfile, err = compileCS( csharpScript, assemblyRefs )

    if not csfile then
      
      if not err then err = ' (?Unknown error?)' end
      
      messageDialog( 'Compilation error:' .. err, mtError, mbOK )
      error(err)
    end

  end
  
  local oldMethodName = className..'::'..methodDetour
  
  local newMethodName = 'patched'..className..'::'..'new'..methodDetour
  local oldMethodCaller = 'patched'..className..'::'..'old'..methodDetour
  
  local result, disableinfo, disablescript = InjectDotNetDetour( csfile, oldMethodName, newMethodName, oldMethodCaller )
  
  if result then
    detourinfo.disableinfo = disableinfo
    detourinfo.disablescript = disablescript
    detourinfo.processid = getOpenedProcessID()
    dotnetdetours[detourName] = detourinfo
  else
    if disableinfo == nil then disableinfo = 'no reason' end
    error( 'InjectDotNetDetour failed: '..disableinfo)
  end
end

function Framework.UnityHelper.tryCompileScript(csharpScript)
  assert( type(csharpScript) == 'string', 'script must be a string' )
  
  local assemblyRefs, sysfile = dotnetpatch_getAllReferences()
  assemblyRefs = Framework.UnityHelper.filterAssemblyRefs( assemblyRefs, sysfile )
  
  local csfile, err = compileCS( csharpScript, assemblyRefs, sysfile )
  if not csfile then
    csfile, err = compileCS( csharpScript, assemblyRefs )
  end
  
  if not csfile then error( 'Compilation failed: ' .. tostring(err) ) end
  
  local assembly = mono_loadAssemblyFromFile( csfile )
  assert( assembly and assembly ~= 0, 'Failed to load assembly' )

  return assembly
end


Framework.API =
{
  pp_teardown = Framework.CEHelper.teardown,
  pp_symAlloc = Framework.Alloc.AllocateSymbol,
  pp_symDealloc = Framework.Alloc.DeallocateSymbol,
  pp_symDeallocAll = Framework.Alloc.DeallocateAll,

  pp_timerCreate = Framework.Timer.create,
  pp_timerGet = Framework.Timer.get,
  pp_timerEnable = Framework.Timer.enable,
  pp_timerDisable = Framework.Timer.disable,
  pp_timerDestroy = Framework.Timer.destroy,
  pp_timerDestroyAll = Framework.Timer.destroyAll,

  pp_threadCreate = Framework.Thread.create,
  pp_threadGet = Framework.Thread.get,
  pp_threadEnable = Framework.Thread.enable,
  pp_threadDisable = Framework.Thread.disable,
  pp_threadDestroy = Framework.Thread.destroy,
  pp_threadDestroyAll = Framework.Thread.destroyAll,

  pp_mrTimeout = Framework.MemRecs.disable,
  pp_mrToggle = Framework.MemRecs.toggleFlag,
  
  pp_procOpen = Framework.CEHelper.iterateOpenProcess,
  pp_clean = Framework.CEHelper.cleanMenuItems,
  pp_monoInit = Framework.UnityHelper.init,

}

for functionName, implementation in pairs(Framework.API) do

  if type( implementation ) == 'function' then
    _G[ functionName ] = implementation 
  end

end

Framework.CEHelper.addCompactMenu()
package.loaded[ FRAMEWORK_KEY ] = Framework
