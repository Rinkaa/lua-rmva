# encoding: utf-8
#==============================================================================
# ** Lua-rmva
#------------------------------------------------------------------------------
#  This module enables usage of Lua script language (LuaJIT 2.1.x).
#  Authors:
#    - 域外创音`<https://github.com/rinkaa, kaitensekai@qq.com>` (c) 2024
#    - 岚风雷`<https://github.com/gqxastg>` (c) 2024
#==============================================================================

# Lua C API中的各常量
module Lua_Constants
  LUA_REGISTRYINDEX = -10000
  LUA_ENVIRONINDEX = -10001
  LUA_GLOBALSINDEX = -10002
  PSEUDO_INDICES = %w{LUA_REGISTRYINDEX LUA_ENVIRONINDEX LUA_GLOBALSINDEX}
  LUA_OK = 0
  LUA_YIELD = 1
  LUA_ERRRUN = 2
  LUA_ERRSYNTAX = 3
  LUA_ERRMEM = 4
  LUA_ERRERR = 5
  THREAD_STATUSES = %w{LUA_OK LUA_YIELD LUA_ERRRUN LUA_ERRSYNTAX LUA_ERRMEM LUA_ERRERR}
  LUA_TNIL = 0
  LUA_TBOOLEAN = 1
  LUA_TLIGHTUSERDATA = 2
  LUA_TNUMBER = 3
  LUA_TSTRING = 4
  LUA_TTABLE = 5
  LUA_TFUNCTION = 6
  LUA_TUSERDATA = 7
  LUA_TTHREAD = 8
  BASIC_TYPES = %w{LUA_TNIL LUA_TBOOLEAN LUA_TLIGHTUSERDATA LUA_TNUMBER LUA_TSTRING
                  LUA_TTABLE LUA_TFUNCTION LUA_TUSERDATA LUA_TTHREAD}
end

# Lua C API
class Lua_C
  @@loaded = false
  @@dll_path = ''
  def self.loaded?
    @@loaded
  end
  def self.dll_path
    raise 'Lua DLL is not yet loaded!' if not @@loaded
    @@dll_path
  end
  def self.load(dll_path)
    raise 'Lua DLL is already loaded!' if @@loaded
    add_method = lambda { |sym, src_name, type_in, type_out| 
      c_api = Win32API.new(dll_path, src_name, type_in, type_out)
      define_singleton_method(sym, lambda { |*args|
        c_api.(*args)
      })
    }
    add_method.(:newstate, 'luaL_newstate', '', 'i')
    add_method.(:openlibs, 'luaL_openlibs', 'i', '')
    add_method.(:gettop, 'lua_gettop', 'i', 'i')
    add_method.(:settop, 'lua_settop', 'ii', '')
    add_method.(:loadfile, 'luaL_loadfile', 'ip', '')
    add_method.(:loadstring, 'luaL_loadstring', 'ip', '')
    add_method.(:close, 'lua_close', 'i', '')
    add_method.(:pcall, 'lua_pcall', 'iiii', 'i')
    add_method.(:pushnil, 'lua_pushnil', 'i', '')
    add_method.(:pushboolean, 'lua_pushboolean', 'ii', '')
    add_method.(:pushnumber, 'lua_pushnumber', 'ill', '')
    add_method.(:pushstring, 'lua_pushstring', 'ip', '')
    add_method.(:type, 'lua_type', 'ii', 'i')
    add_method.(:toboolean, 'lua_toboolean', 'ii', 'i')
    # add_method.(:tonumber, 'lua_tonumber', 'ii', 'l') # 特殊，见下面
    add_method.(:tolstring, 'lua_tolstring', 'iii', 'p')

    # lua_tonumber返回2字长的double的对策
    _GetProcAddress = Win32API.new('kernel32', 'GetProcAddress', 'lp', 'l')
    _GetModuleHandle = Win32API.new('kernel32', 'GetModuleHandle', 'p', 'l')
    _VirtualAlloc = Win32API.new('kernel32', 'VirtualAlloc', 'llll', 'l')
    _RtlMoveMemory_lp = Win32API.new('kernel32', 'RtlMoveMemory', 'lpi', '')
    _CallWindowProc_ippii = Win32API.new('user32', 'CallWindowProc', 'ippii', 'i')
    @@lua_tonumber_addr = _GetProcAddress.(
      _GetModuleHandle.(File.basename(dll_path)), 'lua_tonumber')
    @@lua_tonumber_addr_p = [@@lua_tonumber_addr].pack('L')
    @@custom_tonumber_caller = [
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
    @@custom_tonumber_caller_addr = _VirtualAlloc.(
      0,
      @@custom_tonumber_caller.bytesize,
      0x00001000, # MEM_COMMIT
      0x40)       # PAGE_EXECUTE_READWRITE
    raise 'VirtualAlloc failed' if @@custom_tonumber_caller_addr == 0
    _RtlMoveMemory_lp.(
      @@custom_tonumber_caller_addr,
      @@custom_tonumber_caller,
      @@custom_tonumber_caller.bytesize)
    @@float_buffer = "\0" * 8
    define_singleton_method(:tonumber, lambda { |lua_state, idx|
      _CallWindowProc_ippii.(
        @@custom_tonumber_caller_addr,
        @@lua_tonumber_addr_p,
        @@float_buffer,
        lua_state,
        idx)
      return @@float_buffer.unpack('D').first
    })

    @@dll_path = dll_path
    @@loaded = true
  end
  def self.unload
    raise 'Lua DLL is not yet loaded!' if not @@loaded
    _VirtualFree = Win32API.new('kernel32', 'VirtualFree', 'lll', 'l')
    _VirtualFree.(
      @@custom_tonumber_caller_addr,
      0,
      0x00008000) # MEM_RELEASE

    @@dll_path = ''
    @@loaded = false
  end
end

# Lua虚拟机对象，以及对Lua虚拟机栈的操作
class Lua_VM
  # 创建Lua虚拟机
  def initialize
    raise 'Lua DLL is not yet loaded!' if not Lua_C.loaded?
    @s = Lua_C.newstate  # s = stack
  end
  # 打开基础库（math, string, table之类）
  def open_libs
    Lua_C.openlibs(@s)
  end
  # 将Ruby对象推上Lua栈
  # 出现不支持的类型时，抛出异常
  def push(x)
    if x == nil
      Lua_C.pushnil(@s)
    elsif x == false
      Lua_C.pushboolean(@s, 0)
    elsif x == true
      Lua_C.pushboolean(@s, 1)
    elsif x.is_a?(Numeric)
      # 把8字节的double拆成两个4字节的'l'传递
      built_buffer = [x.to_f].pack('D').unpack('L2')
      Lua_C.pushnumber(@s, built_buffer[0], built_buffer[1])
    elsif x.is_a?(String)
      Lua_C.pushstring(@s, x)
    else
      # 当前暂不支持的传入类型
      raise "Error: Ruby type not supported for Lua, val is #{x}, class is #{x.class}"
    end
  end
  # 将多个Ruby对象推上Lua栈
  # 出现不支持的类型时，抛出异常，并弹出先前所推上的对象以保证退回原来的状态
  def push_n(array)
    current_top = Lua_C.gettop(@s)
    for x in array
      push(x)
    end
  rescue
    Lua_C.settop(@s, current_top)
    raise $!
  end
  # 将Lua代码字符串编译为执行函数并推上Lua栈
  def push_code(str)
    result = Lua_C.loadstring(@s, str)
    if result != Lua_Constants::LUA_OK
      # 编译出错
      raise_thread_status_error(result, "Code is: |\n#{str}") 
    end
    return nil
  end
  # 将Lua代码文件编译为执行函数并推上Lua栈
  def push_codefile(filename)
    result = Lua_C.loadfile(@s, filename)
    if result != Lua_Constants::LUA_OK
      # 编译出错
      raise_thread_status_error(result, "Code file is #{filename}.")
    end
  end
  def call(n_args, n_results)
    result = Lua_C.pcall(@s, n_args, n_results, 0)
    if result != Lua_Constants::LUA_OK
      # 运行出错
      raise_thread_status_error(result)
    end
  end
  # 将Lua栈第i位的内容返回为Ruby对象（不从栈中弹出；不检查Lua栈是否空）
  # i为1表示栈底；-1时表示栈顶，-2时表示从顶向底第二位，以此类推
  def get(i=-1)
    t = Lua_C.type(@s, i)
    if t == Lua_Constants::LUA_TNIL
      return nil
    elsif t == Lua_Constants::LUA_TBOOLEAN
      return (Lua_C.toboolean(@s, i) != 0)
    elsif t == Lua_Constants::LUA_TNUMBER
      return Lua_C.tonumber(@s, i)
    elsif t == Lua_Constants::LUA_TSTRING
      return Lua_C.tolstring(@s, i, 0).force_encoding(__ENCODING__)
    else
      # 目前暂不支持的传出类型
      raise_unsupported_lua_type_error(t, "At stack index \##{i}.")
    end
  end
  # 当前栈内对象数量
  def length
    Lua_C.gettop(@s)
  end
  # 将Lua栈顶转化为Ruby对象，并将其从栈中弹出
  # 即使对象转化失败并抛出异常，Lua栈顶也会弹出这个对象
  def pop
    result = get(-1)
  ensure
    Lua_C.settop(@s, -2)
    return ($! == nil) ? result : nil
  end
  # 将Lua栈从栈顶起的n项内容转化为Ruby对象，并将其从栈中弹出
  # 可以指定将结果写到一个现有的数组，
  # 这时数组的长度不会变化，多余的对象舍弃，不足的对象用nil补足
  # 即使对象转化失败并抛出异常，Lua栈顶也会弹出这些对象
  def pop_n(n, out_array=nil)
    out_array = Array.new(n) if out_array == nil
    len = out_array.length
    val_len = (n < len) ? n : len
    for i in 0 .. val_len-1
      out_array[i] = (-n+i < 0) ? get(-n+i) : nil
    end
    for i in val_len .. len-1
      out_array[i] = nil
    end
  rescue
    raise $!
  ensure
    out_array.fill(nil) if $! != nil
    Lua_C.settop(@s, -n-1)
    return out_array
  end
  # 清空Lua栈，舍弃栈中所有对象
  def reset
    Lua_C.settop(@s, 0)
  end
  # 由于Lua到Ruby类型转换错误而抛出异常
  def raise_unsupported_lua_type_error(value, extra_msg=nil)
    type_enum_name = Lua_Constants::BASIC_TYPES.find {
      |s| Lua_Constants.const_get(s) == value
    } || "Unknown Type #{value}"
    msg = "Error: Lua type not supported for Ruby, type enum is #{type_enum_name}."
    msg += (extra_msg==nil ? '' : ('\n' + extra_msg))
    raise msg
  end
  # 由于编译或运行错误而抛出异常
  # 会把栈顶对象当作错误信息，并将其从栈中弹出
  def raise_thread_status_error(value, extra_msg=nil)
    err_enum_name = Lua_Constants::THREAD_STATUSES.find {
      |s| Lua_Constants.const_get(s) == value
    } || "Unknown Error #{value}"
    msg = "Error: Lua code failed to compile or run, error enum is #{err_enum_name},\n"
    msg += "message is #{pop}."
    msg += (extra_msg==nil ? '' : ('\n' + extra_msg))
    raise msg
  end
  # 关闭Lua虚拟机，释放空间
  def close
    Lua_C.close(@s)
  end
  alias dispose close
end

# 作为非正规解决方案的Lua代码，常用于临时用途或者实现单靠Ruby侧难实现的方法
module Lua_Magics
  # 重设输出到调试控制台
  PRINT = <<-EOF
-- lua
local ffi = require 'ffi'
ffi.cdef[[
typedef void *HANDLE;
typedef unsigned long DWORD;
typedef DWORD *LPDWORD;
typedef int BOOL;
typedef void VOID;
typedef void *LPVOID;
HANDLE GetStdHandle(
  long in_nStdHandle
);
BOOL WriteConsoleA(
  HANDLE in_hConsoleOutput, 
  const VOID *in_lpBuffer, 
  DWORD in_nNumberOfCharsToWrite,
  LPDWORD out_opt_lpNumberOfCharsWritten,
  LPVOID lpReserved
);
]]
local out_charsWritten = ffi.new('long[1]')
local console = ffi.C.GetStdHandle(-11) -- stdout=-11
local function write(str) ffi.C.WriteConsoleA(console, str, #str, out_charsWritten, nil) end
_G.print = function(...)
  local n = select(\'\#\', ...)
  for i = 1, n do
    write(tostring(select(i, ...)))
    write((i~=n) and \'\\t\' or \'\\n\')
  end
  return nil
end
EOF
end

# 用户可使用的各方法
class Lua

  # 初始化
  # 创建Lua虚拟机，并且初始化必要的库和临时方案
  def initialize(dll_path='System/lua51.dll')
    # 第一次还没加载DLL的话，先加载DLL
    Lua_C.load(dll_path) if not Lua_C.loaded?
    # 创建Lua虚拟机
    @lua = Lua_VM.new
    # 加载库和临时方案
    @lua.open_libs
    eval(Lua_Magics::PRINT)
    return nil
  end

  # Ruby调用Lua过程，可以传参和取返回值，支持多参多返回值
  # 给定retsBuffer时使用此buffer存放返回值，或者设为nil表示新建Array存放返回值
  def _eval_target(code_pusher_sym, code_object, rets_buffer, args)
    # 考虑原本的栈长
    length_before = @lua.length
    # 放上Lua代码块，然后放上参数
    # code_object提供内容，code_pusher_sym决定内容是视作文件名还是视作字符串
    @lua.send(code_pusher_sym, code_object)
    @lua.push_n(args)
    # 执行
    n_ret = (rets_buffer == nil) ? -1 : rets_buffer.length
    @lua.call(args.length, n_ret)
    # 承接返回值（多余舍弃，不足填nil）
    # Lua侧已返回值的实际数目应当是当前栈长减去原本栈长
    n_ret = @lua.length - length_before
    rets_buffer = @lua.pop_n(n_ret, rets_buffer)
    return rets_buffer
  end
  protected :_eval_target

  # 执行一个Lua文件，args传递给文件的`...`变量
  # 返回一个包含有各返回值的Array
  def eval_file(filename, *args)
    _eval_target(:push_codefile, filename, nil, args)
  end

  # 执行一段Lua代码，args传递给代码块的`...`变量
  # 返回一个包含有各返回值的Array
  def eval(code, *args)
    _eval_target(:push_code, code, nil, args)
  end

  # 执行一段Lua代码，args传递给代码块的`...`变量，返回值使用rets_buffer接收
  # 避免每次调用Lua的时候都重复为返回值创建Array，从而改善性能
  # rets_buffer的大小表示接受返回值的个数，
  # 个数超出容量时丢弃溢出部分，个数不足容量时用nil补足
  def eval_with_buffer(func, rets_buffer, *args)
    _eval_target(:push_code, code, rets_buffer, args)
  end

  # 结束使用并销毁Lua虚拟机，清除并失去所有状态，例如在关闭游戏时可以使用
  def close
    @lua.close
  end
  alias dispose close

end
