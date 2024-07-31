#==============================================================================
# ** Lua(5.1/LuaJIT2.1.0)
#------------------------------------------------------------------------------
#  This module enables usage of Lua script language.
#==============================================================================

class Lua
  @@dll = 'System/lua51.dll'

  LuaInit = Win32API.new(@@dll, 'luaL_newstate', '', 'i')
  LuaOpenLibs = Win32API.new(@@dll, 'luaL_openlibs', 'i', '')
  LuaGetTop = Win32API.new(@@dll, 'lua_gettop', 'i', 'i')
  LuaSetTop = Win32API.new(@@dll, 'lua_settop', 'ii', '')
  LuaLoadFile = Win32API.new(@@dll, 'luaL_loadfile', 'ip', '')
  LuaLoadString = Win32API.new(@@dll, 'luaL_loadstring', 'ip', '')
  LuaDeinit = Win32API.new(@@dll, 'lua_close', 'i', '')

  LuaPCall = Win32API.new(@@dll, 'lua_pcall', 'iiii', 'i')
  LUA_YIELD = 1
  LUA_ERRRUN = 2
  LUA_ERRSYNTAX = 3
  LUA_ERRMEM = 4
  LUA_ERRERR = 5
  @@error_codes = %w{LUA_YIELD LUA_ERRRUN LUA_ERRSYNTAX LUA_ERRMEM LUA_ERRERR}

  LuaPushNil = Win32API.new(@@dll, 'lua_pushnil', 'i', '')
  LuaPushBoolean = Win32API.new(@@dll, 'lua_pushboolean', 'ii', '')
  LuaPushNumber = Win32API.new(@@dll, 'lua_pushnumber', 'ill', '')
  LuaPushString = Win32API.new(@@dll, 'lua_pushstring', 'ip', '')

  LuaType = Win32API.new(@@dll, 'lua_type', 'ii', 'i')
  LUA_TYPE_NIL = 0
  LUA_TYPE_BOOLEAN = 1
  LUA_TYPE_NUMBER = 3
  LUA_TYPE_STRING = 4
  LUA_TYPE_FUNCTION = 6

  LuaToBoolean = Win32API.new(@@dll, 'lua_toboolean', 'ii', 'i')
  LuaToNumber = Win32API.new(@@dll, 'lua_tonumber', 'ii', 'l')
  LuaToString = Win32API.new(@@dll, 'lua_tolstring', 'iii', 'p')

  # 用来转换双浮点数的buffer（Ruby的Float和Lua的Number都使用C的8字节double的布局）
  @@float_buffer = "\0" * 8
#~   MemCpy = Win32API.new('msvcrt', 'memcpy', 'ppl', 'i')
#~   MemFree = Win32API.new('msvcrt', 'free', 'i', '')
  RtlMoveMemory_lp = Win32API.new('kernel32', 'RtlMoveMemory', 'lpi', '')

  GetProcAddress = Win32API.new('kernel32', 'GetProcAddress', 'lp', 'l')
  GetModuleHandle = Win32API.new('kernel32', 'GetModuleHandle', 'p', 'l')
  CallWindowProc_ippii = Win32API.new('user32', 'CallWindowProc', 'ippii', 'i')

  @@lua_tonumber_adr = GetProcAddress.call(
  GetModuleHandle.call(File.basename(@@dll)), 'lua_tonumber')
  @@lua_tonumber_adr_p = [@@lua_tonumber_adr].pack('L')
  @@lua_tonumber_code = [
  0x55,               # push  ebp
  0x89, 0xE5,         # mov   ebp, esp
  0x83, 0xEC, 0x08,   # sub   esp, 8
  0x8B, 0x45, 0x14,   # mov   eax, DWORD PTR [ebp+20]
  0x50,               # push  eax
  0x8B, 0x4D, 0x10,   # mov   ecx, DWORD PTR [ebp+16]
  0x51,               # push  ecx
  0x8B, 0x55, 0x08,   # mov   edx, DWORD PTR [ebp+8]
  0xFF, 0x12,         # call  DWORD PTR [edx]
  0x83, 0xC4, 0x08,   # add   esp, 8
  0xDD, 0x5D, 0xF8,   # fstp  QWORD PTR [ebp-8]
  0xF2, 0x0F, 0x10, 0x45, 0xF8,  # movsd xmm0, QWORD PTR [ebp-8]
  0x8B, 0x55, 0x0C,              # mov   edx, DWORD PTR [ebp+12]
  0xF2, 0x0F, 0x11, 0x02,        # movsd QWORD PTR [edx], xmm0
  0x89, 0xEC,         # mov  esp, ebp
  0x5D,               # pop  ebp
  0xC3,               # ret
  ].pack('C*')

  MEM_COMMIT  = 0x00001000
  MEM_RESERVE = 0x00002000
  MEM_RELEASE = 0x00008000
  PAGE_EXECUTE_READWRITE = 0x40

  VirtualAlloc = Win32API.new('kernel32', 'VirtualAlloc', 'llll', 'l')
  VirtualFree = Win32API.new('kernel32', 'VirtualFree', 'lll', 'l')
#~   VirtualProtect = Win32API.new('kernel32', 'VirtualProtect', 'llll', 'l')

  if class_variable_defined?(:@@lua_tonumber_code_adr) &&
    @@lua_tonumber_code_adr && @@lua_tonumber_code_adr != 0
    VirtualFree.call(@@lua_tonumber_code_adr, 0, MEM_RELEASE)
  end
  @@lua_tonumber_code_adr = VirtualAlloc.call(0,
  @@lua_tonumber_code.bytesize, MEM_COMMIT, PAGE_EXECUTE_READWRITE)
  raise 'VirtualAlloc failed' if @@lua_tonumber_code_adr == 0
  RtlMoveMemory_lp.call(
  @@lua_tonumber_code_adr, @@lua_tonumber_code, @@lua_tonumber_code.bytesize)

  # 创建新实例时，创建其Lua虚拟机，并且初始化必要的库
  def initialize
    # 新建Lua实例
    @lua = LuaInit.call

    # 打开基础库（math, string, table之类）
    LuaOpenLibs.call(@lua)
#    # 重设输出到调试控制台
#    rm_print_lua = <<-EOF
#    _G.print = function(...)
#      local n = select(\'\#\', ...)
#      local c = require(\'winapi\').get_console()
#      for i = 1, n do
#        c:write(tostring(select(i, ...)))
#        c:write((i~=n) and \'\\t\' or \'\\n\')
#      end
#    end
#    return nil
#EOF
#    LuaLoadString.call(@lua, rm_print_lua)
#    LuaPCall.call(@lua, 0, 0, 0)
  end

  # Ruby调用Lua过程，可以传参和取返回值，支持多参多返回值；给定retsBuffer时使用此buffer存放返回值，否则新建Array存放返回值
  def _evalTarget(evalPusher, content, retsBuffer, *args)
    # 放上Lua代码块（content提供内容，evalPusher提供内容是视作文件名还是视作字符串）
    evalPusher.call(@lua, content)
    # 放上参数
    args.each do |arg|
      if arg == nil
        LuaPushNil.call(@lua)
      elsif arg == false
        LuaPushBoolean.call(@lua, 0)
      elsif arg == true
        LuaPushBoolean.call(@lua, 1)
      elsif arg.is_a?(Numeric)
        # 把8字节的double拆成两个4字节的'l'传递
        built_buffer = [arg.to_f].pack('D').unpack('L2')
        LuaPushNumber.call(@lua, built_buffer[0], built_buffer[1])
      elsif arg.is_a?(String)
        LuaPushString.call(@lua, arg)
      else
        # 当前暂不支持的参数类型
        LuaSetTop.call(@lua, 0)
        raise "Error: Param val type not supported for Lua, param is #{arg}, class is #{arg.class}"
      end
    end
    # 执行
    n_ret = (retsBuffer == nil)? -1 : retsBuffer.length
    pcall_result = LuaPCall.call(@lua, args.length, n_ret, 0)
    if pcall_result != 0
      # 执行出错
      error = @@error_codes.find {|s|
      self.class.const_get(s) == pcall_result } || "Error #{pcall_result}"
      err_lua = LuaToString.call(@lua, -1, 0)
      LuaSetTop.call(@lua, 0)
      raise "#{error}: Lua code error thrown:\n#{err_lua}"
    end
    # 处理Lua返回值
    n_ret = LuaGetTop.call(@lua)
    if retsBuffer != nil
      rets = retsBuffer
      rets.fill(nil)
      if rets.length < n_ret
        n_ret = rets.length
      end
    else
      rets = Array.new(n_ret)
    end
    for i in 0 ... n_ret
      ret_luaidx = i + 1
      ret_type = LuaType.call(@lua, ret_luaidx)
      if ret_type == LUA_TYPE_NIL
        rets[i] = nil
      elsif ret_type == LUA_TYPE_BOOLEAN
        rets[i] = (LuaToBoolean.call(@lua, ret_luaidx)!=0)
      elsif ret_type == LUA_TYPE_NUMBER
        CallWindowProc_ippii.call(@@lua_tonumber_code_adr,
        @@lua_tonumber_adr_p, @@float_buffer, @lua, ret_luaidx)
        rets[i] = @@float_buffer.unpack('D').first
      elsif ret_type == LUA_TYPE_STRING
        rets[i] = LuaToString.call(@lua, ret_luaidx, 0).force_encoding(__ENCODING__)
      else
        # 目前暂不支持的返回值类型
        rets[i] = nil
        raise "Error: Lua return val type not supported, at return val \##{ret_luaidx} and type enum is \##{ret_type}"
      end
    end
    LuaSetTop.call(@lua, 0)
    return rets
  end
  protected :_evalTarget

  # 执行一个Lua文件，args传递给文件的`...`变量
  # 创建新的Array接受返回值
  def evalFile(filename, *args)
    self._evalTarget(LuaLoadFile, filename, nil, *args)
  end
  # 执行一段Lua代码，args传递给代码块的`...`变量
  # 创建新的Array接受返回值
  def eval(code, *args)
    self._evalTarget(LuaLoadString, code, nil, *args)
  end
  # 执行一段Lua代码，args传递给代码块的`...`变量，返回值使用retsBuffer接收
  # retsBuffer可以用现有的Array，来避免每次调用Lua的时候都重复申请空间，从而改善性能
  # retsBuffer的大小表示接受返回值的个数，个数超出容量时丢弃溢出部分，个数不足容量时用nil补足，因此retsBuffer的大小不会有变化
  def evalWithBuffer(func, retsBuffer, *args)
    self._evalTarget(LuaLoadString, code, retsBuffer, *args)
  end
  # 结束使用并销毁Lua虚拟机，清除并失去所有状态。例如在关闭游戏时可以使用
  def deinitialize
    LuaDeinit.call(@lua)
  end
  alias dispose deinitialize
end

