# encoding: utf-8
#==============================================================================
# ** Lua-rmva
#------------------------------------------------------------------------------
#  This module enables usage of Lua script language (LuaJIT 2.1.x).
#  Authors:
#    - 域外创音`<https://github.com/rinkaa, kaitensekai@qq.com>` (c) 2024
#    - 岚风雷`<https://github.com/gqxastg>` (c) 2024
#==============================================================================

module Lua_Config
  #--------------------------------------------------------------------------
  # ■ 以下为设定部分
  #--------------------------------------------------------------------------
  DEFAULT_DLL_PATH = 'System/luajit2.1.1720049189_win32_04dca791.dll'
  RGSS_DLL_FILENAME = 'RGSS301.dll'
  #--------------------------------------------------------------------------
  # ■ 设定部分到此结束，使用者无须修改以下内容
  #--------------------------------------------------------------------------
end

# Lua C API
class Lua_C
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
    # add_method.(:pushnumber, 'lua_pushnumber', 'ill', '') # 特殊，见下面
    add_method.(:pushstring, 'lua_pushstring', 'ip', '')
    add_method.(:type, 'lua_type', 'ii', 'i')
    add_method.(:toboolean, 'lua_toboolean', 'ii', 'i')
    # add_method.(:tonumber, 'lua_tonumber', 'ii', 'l') # 特殊，见下面
    add_method.(:tolstring, 'lua_tolstring', 'iii', 'p')

    add_method.(:createtable, 'lua_createtable', 'iii', '')
    add_method.(:pushvalue, 'lua_pushvalue', 'ii', '')
    add_method.(:getfield, 'lua_getfield', 'iip', '')
    add_method.(:gettable, 'lua_gettable', 'ii', '')
    add_method.(:setfield, 'lua_setfield', 'iip', '')
    add_method.(:settable, 'lua_settable', 'ii', '')
    add_method.(:insert, 'lua_insert', 'ii', '')

    # lua_pushnumber发送2字长的double的对策
    # 把8字节的double拆成两个4字节的'l'传递
    _lua_pushnumber_inner = Win32API.new(dll_path, 'lua_pushnumber', 'ill', '')
    define_singleton_method(:pushnumber, lambda { |lua_state, num|
      built_buffer = [num.to_f].pack('D').unpack('L2')
      _lua_pushnumber_inner.(lua_state, built_buffer[0], built_buffer[1])
    })

    # lua_tonumber返回2字长的double的对策
    _GetProcAddress = Win32API.new('kernel32', 'GetProcAddress', 'lp', 'l')
    _GetModuleHandle = Win32API.new('kernel32', 'GetModuleHandle', 'p', 'l')
    _VirtualAlloc = Win32API.new('kernel32', 'VirtualAlloc', 'llll', 'l')
    _VirtualFree = Win32API.new('kernel32', 'VirtualFree', 'lll', 'l')
    #~ VirtualProtect = Win32API.new('kernel32', 'VirtualProtect', 'llll', 'l')
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

    if class_variable_defined?(:@@custom_tonumber_caller_addr) &&
      @@custom_tonumber_caller_addr && @@custom_tonumber_caller_addr != 0
      _VirtualFree.call(
        @@custom_tonumber_caller_addr,
        0,
        0x00008000) # MEM_RELEASE
    end
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

  # 由于Lua到Ruby类型转换错误而抛出异常
  def self.raise_unsupported_lua_type_error(lua_state, value, extra_msg=nil)
    type_enum_name = BASIC_TYPES.find {
      |s| const_get(s) == value
    } || "Unknown Type #{value}"
    msg = "Error: Lua type not supported for Ruby, type enum is #{type_enum_name}."
    msg += (extra_msg==nil ? '' : ("\n" + extra_msg))
    raise msg
  end
  # 由于编译或运行错误而抛出异常
  # 会把栈顶对象当作错误信息，并将其从栈中弹出
  def self.raise_thread_status_error(lua_state, value, extra_msg=nil)
    err_enum_name = THREAD_STATUSES.find {
      |s| const_get(s) == value
    } || "Unknown Error #{value}"
    err_msg = tolstring(lua_state, -1, 0).force_encoding(__ENCODING__)
    settop(lua_state, -2)
    msg = "Error: Lua code failed to compile or run, error enum is #{err_enum_name}.\n"
    msg += "Message: #{err_msg}."
    msg += (extra_msg==nil ? '' : ("\n" + extra_msg))
    raise msg
  end
end

# 为跨语言界面的对象提供引用管理
# 跨语言时，为对象分配引用键，引用键相同的对象为同一对象
# 引用键对应的对象在两语言环境中可以有不同表示，但在一侧的修改会跨语言界面传到另一侧
class Lua_CrossBoundaryManager

  include Lua_Config
  def initialize(lua_state, lua_object_wrapper, ruby_object_wrap_and_pusher)
    # 指定所用的Lua状态机
    @s = lua_state
    # 初始化跨语言界面引用的存储容器
    _init_ref_holders
    # 初始化跨语言界面调用的设施
    _init_cross_call_utils
    # 发生lua->ruby跨界面对象传递时，如何包装lua对象
    @lua_object_wrapper = lua_object_wrapper
    # 发生ruby->lua跨界面对象传递时，如何包装ruby对象
    @ruby_object_wrap_and_pusher = ruby_object_wrap_and_pusher
  end

  # 初始化引用保留设施
  def _init_ref_holders
    # Lua侧的引用保留表示形式：
    #   `LUA_REGISTRY`["lua-rmva"]["mapping"] = {}  -- 正查（[key] = obj）
    #   `LUA_REGISTRY`["lua-rmva"]["reverse"] = {}  -- 反查（[obj] = key）
    Lua_C.createtable(@s, 0, 4)
    Lua_C.pushvalue(@s, -1)
    Lua_C.setfield(@s, Lua_C::LUA_REGISTRYINDEX, 'lua-rmva')
    Lua_C.createtable(@s, 0, 0)
    Lua_C.setfield(@s, -2, 'mapping')
    Lua_C.createtable(@s, 0, 0)
    Lua_C.setfield(@s, -2, 'reverse')
    Lua_C.settop(@s, -2)
    # Ruby侧的引用保留表示形式：
    @mapping = Hash.new  # 正查（key => obj）
    @reverse = Hash.new  # 反查（obj => key）
    # 引用键顺序
    @next_key = 1
    @next_key_max = 1000000000 # 需要在double转换到int时能良好转换，所以需要设最大值
  end

  def get_mapping(key)
    @mapping[key]
  end
  def get_reverse(obj)
    @reverse[obj]
  end

  # 初始化跨界面调用设施
  def _init_cross_call_utils
    # Lua侧的调用Ruby设施形式：（通过require("rgss")访问）
    #   `LUA_REGISTRY`["lua-rmva"]["rgss"]  -- 从Registry快速访问这个模块的方式
    #                                    -- （注意，这个模块没有反过来指向Registry的引用）
    #   `rgss`.___post  -- Lua通知Ruby从Lua获取对象时，作为中转的存放位置
    #   `rgss`.___get   -- Lua通知Ruby向Lua发送对象时，作为中转的存放位置
    #   `rgss`.dll.RGSSEval  -- 执行一段Ruby代码，无参数，无返回值
    #   `rgss`.eval          -- 执行一段Ruby代码，无参数，取得返回值
    #   `rgss`.call          -- 对来自Ruby的对象使用，调用其方法，并取得返回值
    #   `rgss`.class.Object -- 来自Ruby的对象的通用包装
    #   `rgss`.class.Array  -- 来自Ruby的Array对象的便捷包装
    #   `rgss`.class.Hash   -- 来自Ruby的Hash对象的便捷包装
    #   `rgss`.class.Method -- 来自Ruby的Method对象的便捷包装
    #   `rgss`.class.Proc   -- 来自Ruby的Proc对象的便捷包装
    #   `rgss`.is_ruby_object   -- 对象是否是来自Ruby的对象
    #   `rgss`.error_handler    -- 错误发生时对错误信息的包装（例如加入调用栈信息）
    # 建立Lua侧的rgss模块，用Lua写成`rgss`.call`, rgss`.eval, `rgss`.class
    lua_rgss_module_code = <<-EOF
-- lua_rgss_module
local rgss = {}

-- 加载RGSS3中的函数
local ffi = require "ffi"
  -- 在Ruby中替换此@@@模板参数为当时的addr
rgss.dll = {}
rgss.dll.RGSSEval = ffi.cast("int(*)(const char*)", @@@RGSSEval_addr@@@)

-- 实用函数
local function common_eval(code)
  -- TODO: RGSSEval异常处理
  local request = {
    code = code,
  }
  rgss.___post = request
  local eval_return_code = rgss.dll.RGSSEval([[
    # ruby
      # 在Ruby中替换此@@@模板参数为当时的id
    cross = ObjectSpace._id2ref(@@@CrossManager_object_id@@@)
    cross.handle_eval_request
  ]])
  rgss.___post = nil
  local result = rgss.___get
  rgss.___get = nil
  return result
end
local function common_call(receiver_object_key, signal_name, ...)
  -- TODO: RGSSEval异常处理
  local request = {
    key = receiver_object_key,
    name = signal_name,
    argc = select("#", ...),
    argv = {...},
  }
  rgss.___post = request
  local eval_return_code = rgss.dll.RGSSEval([[
    # ruby
    # 在Ruby控制Lua运行此lua_rgss_module代码前替换此@@@模板参数为当时的id
    cross = ObjectSpace._id2ref(@@@CrossManager_object_id@@@)
    cross.handle_call_request
  ]])
  rgss.___post = nil
  local result = rgss.___get
  rgss.___get = nil
  return result
end

-- 包装Ruby对象的函数
rgss.class = {}
local _RUBY_OBJ_KEY = {}
function rgss.class.write_to_ruby_obj(ruby_obj, k, v)
  msg = "This operation is not permitted!\\n"
  msg = msg .. "If you want to write to a hash, use `hash:set(key, value)` instead."
  error(msg)
end
function rgss.class.call_on_ruby_obj(ruby_obj, signal_name, ...)
  local data = getmetatable(ruby_obj)[_RUBY_OBJ_KEY]
  return common_call(data.key, signal_name, ...)
end
function rgss.class.test_eq_on_ruby_obj(ruby_obj1, ruby_obj2)
  local data1 = getmetatable(ruby_obj1)[_RUBY_OBJ_KEY]
  local data2 = getmetatable(ruby_obj2)[_RUBY_OBJ_KEY]
  return data1.id == data2.id
end
function rgss.class.tostring_on_ruby_obj(ruby_obj)
  local data = getmetatable(ruby_obj)[_RUBY_OBJ_KEY]
  return string.format(
    "<RubyObject, key=%s, id=%s, type_hint=%s>",
      tostring(data.key),
      tostring(data.id),
      tostring(data.type_hint)
    )
end
function rgss.class.Object(key, object_id, methods, type_hint)
  return setmetatable({}, {
    [_RUBY_OBJ_KEY] = { -- metatable中有这个键值对说明是跨语言界面对象
      key = key,        -- 引用键
      id = object_id,   -- Ruby中对象的id，通过Object#object_id得到
      type_hint = type_hint or "Object", -- 在Ruby中的大致类型（需要包装方法支持）
    },
    __eq = rgss.class.test_eq_on_ruby_obj,
    __tostring = rgss.class.tostring_on_ruby_obj,
    __call = rgss.class.call_on_ruby_obj,
    __index = methods or {},
    __newindex = rgss.class.write_to_ruby_obj,
  })
end
local common_functions = {
  length = function(self) return rgss.class.call_on_ruby_obj(self, "length") end,
  bracket_get = function(self, k) return rgss.class.call_on_ruby_obj(self, "[]", k) end,
  bracket_set = function(self, k, v) return rgss.class.call_on_ruby_obj(self, "[]=", k, v) end,
  clear = function(self) return rgss.class.call_on_ruby_obj(self, "clear") end,
  has_key = function(self, k) return rgss.class.call_on_ruby_obj(self, "has_key?", k) end,
  has_value = function(self, v) return rgss.class.call_on_ruby_obj(self, "has_value?", v) end,
  call = function(self, ...) return rgss.class.call_on_ruby_obj(self, "call", ...) end,
}
local array_functions = {
  length = common_functions.length,
  size = common_functions.length,
  get = common_functions.bracket_get,
  set = common_functions.bracket_set,
  bracket_get = common_functions.bracket_get,
  bracket_set = common_functions.bracket_set,
}
local hash_functions = {
  length = common_functions.length,
  size = common_functions.size,
  get = common_functions.bracket_get,
  set = common_functions.bracket_set,
  bracket_get = common_functions.bracket_get,
  bracket_set = common_functions.bracket_set,
  has_key = common_functions.has_key,
  has_value = common_functions.has_value,
  include = common_functions.has_key,
  index = function(self, v) return rgss.class.call_on_ruby_obj(self, "index", v) end,
  keys = function(self) return rgss.class.call_on_ruby_obj(self, "keys") end,
  values = function(self) return rgss.class.call_on_ruby_obj(self, "values") end,
}
local method_functions = {
  call = common_functions.call,
}
local proc_functions = {
  call = common_functions.call,
}
function rgss.class.Array(key, object_id)
  return rgss.class.Object(key, object_id, array_functions, "Array")
end
function rgss.class.Hash(key, object_id)
  return rgss.class.Object(key, object_id, hash_functions, "Hash")
end
function rgss.class.Method(key, object_id)
  return rgss.class.Object(key, object_id, method_functions, "Method")
end
function rgss.class.Proc(key, object_id)
  return rgss.class.Object(key, object_id, proc_functions, "Proc")
end

-- 执行一段Ruby代码，无参数，取得返回值
rgss.eval = common_eval
-- 对来自Ruby的对象使用，调用其方法，并取得返回值
rgss.call = rgss.class.call_on_ruby_obj
-- 判断对象是否是Ruby对象
function rgss.is_ruby_object(x)
  return not not (type(x)=="table" and getmetatable(x)[_RUBY_OBJ_KEY])
end
-- 发生错误时包装错误
-- TODO: 把error_handler放在Lua_CrossBoundaryManager有点不妥当，之后需要移动到Lua_VM类下
function rgss.error_handler(err)
  return debug.traceback(tostring(err), 1)
end

package.loaded["rgss"] = rgss
return rgss
EOF
    # 替换模板参数
    _GetProcAddress = Win32API.new('kernel32', 'GetProcAddress', 'lp', 'l')
    _GetModuleHandle = Win32API.new('kernel32', 'GetModuleHandle', 'p', 'l')
    _RGSSEval_addr = _GetProcAddress.(_GetModuleHandle.(RGSS_DLL_FILENAME), 'RGSSEval')
    lua_rgss_module_code.sub!('@@@RGSSEval_addr@@@', _RGSSEval_addr.to_s)
    lua_rgss_module_code.sub!('@@@CrossManager_object_id@@@', object_id.to_s) 
    lua_rgss_module_code.sub!('@@@CrossManager_object_id@@@', object_id.to_s)
    # 估值Lua代码并将其挂载到Registry
    load_result = Lua_C.loadstring(@s, lua_rgss_module_code)
    if load_result != Lua_C::LUA_OK || Lua_C.type(@s, -1) != Lua_C::LUA_TFUNCTION
      # 编译出错
      Lua_C.raise_thread_status_error(@s, load_result, "Code is: |\n#{lua_rgss_module_code}") 
    end
    run_result = Lua_C.pcall(@s, 0, 1, 0) # <1>=`rgss`
    if run_result != Lua_C::LUA_OK
      # 模块定义代码运行出错
      Lua_C.raise_thread_status_error(@s, run_result, "Code is: |\n#{lua_rgss_module_code}") 
    end
    Lua_C.getfield(@s, Lua_C::LUA_REGISTRYINDEX, 'lua-rmva') # <2>=`LUA_REGISTRY`["lua-rmva"]
    Lua_C.pushvalue(@s, -2)        # <3>=<1>`rgss`
    Lua_C.setfield(@s, -2, 'rgss') # <2>`LUA_REGISTRY`["lua-rmva"].["rgss"]=<3>`rgss`
    Lua_C.settop(@s, -3)
  end

  def _generate_new_key
    raise 'Ran out of cross-boundary reference keys!' if @mapping.length == @next_key_max
    key = @next_key
    while @mapping.has_key?(key)
      key += 1
      key = 1 if key > @next_key_max
    end
    @next_key = key + 1
    @next_key = 1 if @next_key > @next_key_max
    return key
  end
  private :_generate_new_key

  # 取得lua栈中idx处对象的引用键，不存在时为其分配新引用键；返回引用键
  def get_or_appoint_key_of_lua_obj(idx, type_enum)
    len = Lua_C.gettop(@s)
    idx = len + 1 + idx if idx < 0
    # TODO: 异常处理
    # 查看是否存在引用键
    Lua_C.getfield(@s, Lua_C::LUA_REGISTRYINDEX, 'lua-rmva') # <1>=`LUA_REGISTRY`["lua-rmva"]
    Lua_C.getfield(@s, -1, 'reverse')  # <2>=`reverse`
    Lua_C.pushvalue(@s, idx)           # <3>=<idx>obj
    Lua_C.gettable(@s, -2)             # <3>=<2>`reverse`.[<3>obj] 即key
    if Lua_C.type(@s, -1) != Lua_C::LUA_TNIL
      # 已经有分配好的引用键：返回已经分配好的引用键
      key = Lua_C.tonumber(@s, -1).to_i
      Lua_C.settop(@s, -4)
      return key
    else
      # 没有分配好的引用键，所以创建新的引用键
      key = _generate_new_key
      # 在Lua侧注册引用键并保持引用
      Lua_C.settop(@s, -2)
      Lua_C.pushnumber(@s, key)  # <3>=key
      Lua_C.insert(@s, -2)       # <3>=<2>`reverse`, <2>=<3>key
      Lua_C.pushvalue(@s, idx)   # <4>=<idx>obj
      Lua_C.pushvalue(@s, -3)    # <5>=<2>key
      Lua_C.settable(@s, -3)     # <3>`reverse`.[<4>obj] = <5>key
      Lua_C.settop(@s, -2)
      Lua_C.getfield(@s, -2, 'mapping') # <3>=`mapping`
      Lua_C.pushvalue(@s, -2)           # <4>=<2>key
      Lua_C.pushvalue(@s, idx)          # <5>=<idx>obj
      Lua_C.settable(@s, -3)            # <3>`mapping`.[<4>key] = <5>obj
      Lua_C.settop(@s, -4)
      # 在Ruby侧创建包装对象
      wrapped_lua_obj = @lua_object_wrapper.(key, type_enum)
      # 在Ruby侧注册引用键并保持引用
      @reverse[wrapped_lua_obj] = key
      @mapping[key] = wrapped_lua_obj
      # 返回新创建的引用键
      return key
    end
  end
  def get_or_appoint_key_of_ruby_obj(obj, type_str)
    if @reverse.has_key?(obj)
      # 已经有分配好的引用键：返回已经分配好的引用键
      return @reverse[obj]
    else
      # 没有分配好的引用键，所以创建新的引用键
      key = _generate_new_key
      # 在Ruby侧注册引用键并保持引用
      @reverse[obj] = key
      @mapping[key] = obj
      # 在Lua侧创建包装对象
      @ruby_object_wrap_and_pusher.(key, obj.object_id, type_str) # <1>=obj
      # 在Lua侧注册引用键并保持引用
      # TODO: 异常处理
      Lua_C.pushnumber(@s, key)               # <2>=key
      Lua_C.getfield(@s, Lua_C::LUA_REGISTRYINDEX, 'lua-rmva') # <3>=`LUA_REGISTRY`["lua-rmva"]
      Lua_C.getfield(@s, -1, 'reverse') # <4>=`reverse`
      Lua_C.pushvalue(@s, -4)           # <5>=<1>obj
      Lua_C.pushvalue(@s, -4)           # <6>=<2>key
      Lua_C.settable(@s, -3)            # <4>`reverse`.[<5>obj] = <6>key
      Lua_C.settop(@s, -2)
      Lua_C.getfield(@s, -1, 'mapping') # <4>=`mapping`
      Lua_C.pushvalue(@s, -3)           # <5>=<2>key
      Lua_C.pushvalue(@s, -5)           # <6>=<1>obj
      Lua_C.settable(@s, -3)            # <4>`mapping`.[<5>key] = <6>obj
      Lua_C.settop(@s, -5)
      # 返回新创建的引用键
      return key
    end
  end
  # 对来自Lua或Ruby的对象，找到其引用键并取消对应的引用，以便于两语言各自回收对应的引用
  # 取消引用键后，对象不能再跨语言调用方法
  # 如果还想重新跨语言调用方法的话，需要重新从对方语言传递过来对象，以重新分配引用键和生成新的包装对象
  def release_obj(obj)
    # 不存在引用键：返回false
    return false if @reverse[obj] == nil
    # 存在引用键
    key = @reverse[obj]
    # 在Lua中取消引用
    Lua_C.pushnumber(@s, key)         # <1>=key
    Lua_C.getfield(@s, Lua_C::LUA_REGISTRYINDEX, 'lua-rmva') # <2>=`LUA_REGISTRY`["lua-rmva"]
    Lua_C.getfield(@s, -1, 'mapping') # <3>=`mapping`
    Lua_C.pushvalue(@s, -3)           # <4>=<1>key
    Lua_C.gettable(@s, -2)            # <4>=<3>`mapping`.[<4>key] 即obj
    Lua_C.insert(@s, -3)              # <4>=`mapping`, <3>=`LUA_REGISTRY`["lua-rmva"], <2>=obj
    Lua_C.pushvalue(@s, -4)           # <5>=<1>key
    Lua_C.pushnil(@s)                 # <6>=nil
    Lua_C.settable(@s, -3)            # <4>`mapping`.[<5>key] = <6>nil
    Lua_C.settop(@s, -2)
    Lua_C.getfield(@s, -1, 'reverse') # <4>=`reverse`
    Lua_C.pushvalue(@s, -3)           # <5>=<2>obj
    Lua_C.pushnil(@s)                 # <6>=nil
    Lua_C.settable(@s, -3)            # <4>`reverse`.[<5>obj] = <6>nil
    Lua_C.settop(@s, -5)
    # 在Ruby中取消引用
    @reverse.delete(obj)
    @mapping.delete(key)
    return true
  end

  # 将Ruby值推上Lua栈
  # 出现不支持的类型时，抛出异常
  def push_ruby(x)
    if x == nil
      Lua_C.pushnil(@s)
    elsif x == false
      Lua_C.pushboolean(@s, 0)
    elsif x == true
      Lua_C.pushboolean(@s, 1)
    elsif x.is_a?(Numeric)
      Lua_C.pushnumber(@s, x)
    elsif x.is_a?(String)
      Lua_C.pushstring(@s, x)
    elsif x.is_a?(Array)
      key = get_or_appoint_key_of_ruby_obj(x, 'Array')
      push_key(key)
    elsif x.is_a?(Hash)
      key = get_or_appoint_key_of_ruby_obj(x, 'Hash')
      push_key(key)
    elsif x.is_a?(Method)
      key = get_or_appoint_key_of_ruby_obj(x, 'Method')
      push_key(key)
    elsif x.is_a?(Proc)
      key = get_or_appoint_key_of_ruby_obj(x, 'Proc')
      push_key(key)
    elsif x.is_a?(Lua_WrappedObject)
      # 从Lua来的对象就直接用引用键还原引用
      push_key(x.key)
    elsif x.is_a?(Object)
      key = get_or_appoint_key_of_ruby_obj(x, 'Object')
      push_key(key)
    else
      # 当前暂不支持的传入类型
      raise "Error: Ruby type not supported for Lua, val is #{x}, class is #{x.class}"
    end
  end
  # 将对应引用键的对象推上栈，适用于要对对象进行操作时
  # 不检查对应对象是否存在
  # 如果只是临时使用，操作结束后记得调用pop
  def push_key(key)
    Lua_C.getfield(@s, Lua_C::LUA_REGISTRYINDEX, 'lua-rmva') # <1>=`LUA_REGISTRY`["lua-rmva"]
    Lua_C.getfield(@s, -1, 'mapping') # <2>=`mapping`
    Lua_C.pushnumber(@s, key)         # <3>=key
    Lua_C.gettable(@s, -2)            # <3>=<2>`mapping`.[<3>key] 即obj
    Lua_C.insert(@s, -3)              # <1>=<3>obj
    Lua_C.settop(@s, -3)
  end
  # 将`rgss`定义中的`rgss`.error_handler推上栈
  # TODO: 把error_handler放在Lua_CrossBoundaryManager有点不妥当，之后需要移动到Lua_VM类下
  def push_error_handler
    Lua_C.getfield(@s, Lua_C::LUA_REGISTRYINDEX, 'lua-rmva')
    Lua_C.getfield(@s, -1, 'rgss')
    Lua_C.getfield(@s, -1, 'error_handler')
    Lua_C.insert(@s, -3)
    Lua_C.settop(@s, -3)
  end
  # 将位于idx的内容返回为Ruby对象（不从栈中弹出；不检查Lua栈是否空）
  def get_ruby(idx=-1)
    t = Lua_C.type(@s, idx)
    if t == Lua_C::LUA_TNIL
      return nil
    elsif t == Lua_C::LUA_TBOOLEAN
      return (Lua_C.toboolean(@s, idx) != 0)
    elsif t == Lua_C::LUA_TNUMBER
      return Lua_C.tonumber(@s, idx)
    elsif t == Lua_C::LUA_TSTRING
      return Lua_C.tolstring(@s, idx, 0).force_encoding(__ENCODING__)
    elsif
      t == Lua_C::LUA_TTABLE \
      || t == Lua_C::LUA_TFUNCTION \
      || t == Lua_C::LUA_TUSERDATA \
      || t == Lua_C::LUA_TLIGHTUSERDATA
      # 同时也考虑进去了发过去的对象正好是来自ruby的对象的可能性
      key = get_or_appoint_key_of_lua_obj(idx, t)
      return @mapping[key]
    else
      # 目前暂不支持的传出类型
      Lua_C.raise_unsupported_lua_type_error(@s, t, "At stack index \##{i}.")
    end
  end
  # 舍弃栈顶，适用于结束操作时
  def pop(n=1)
    Lua_C.settop(@s, -n-1)
  end

  # 处理Lua发起的Ruby调用，执行一段代码
  # 从`rgss`.___post读取调用信息，并把结果写到`rgss`.___get
  def handle_eval_request
    # TODO: 异常处理
    Lua_C.getfield(@s, Lua_C::LUA_REGISTRYINDEX, 'lua-rmva') # <1>=`LUA_REGISTRY`["lua-rmva"]
    Lua_C.getfield(@s, -1, 'rgss')    # <2>=`rgss`
    Lua_C.getfield(@s, -1, '___post') # <3>=`___post`
    request = get_ruby(-1)
    code = request.get('code')
    result = eval(code)
    push_ruby(result)                     # <4>=result
    Lua_C.setfield(@s, -3, '___get') # 赋值<2>`rgss`.["___get"]=<4>result, 弹出<4>
    Lua_C.settop(@s, -4)
    release_obj(request)
  end

  # 处理Lua发起的Ruby调用，对指定对象调用其方法
  # 从`rgss`.___post读取调用信息，并把结果写到`rgss`.___get
  def handle_call_request
    # TODO: 异常处理
    Lua_C.getfield(@s, Lua_C::LUA_REGISTRYINDEX, 'lua-rmva') # <1>=`LUA_REGISTRY`["lua-rmva"]
    Lua_C.getfield(@s, -1, 'rgss')    # <2>=`rgss`
    Lua_C.getfield(@s, -1, '___post') # <3>=`___post`
    request = get_ruby(-1)
    receiver_key = request.get('key').to_i
    signal_name = request.get('name')
    argc = request.get('argc').to_i
    argv = request.get('argv')
    receiver = @mapping[receiver_key]
    result = nil
    if argc == 0
      result = receiver.send(signal_name)
    elsif argc == 1
      arg1 = argv.get(1)
      result = receiver.send(signal_name, arg1)
    elsif argc == 2
      arg1 = argv.get(1)
      arg2 = argv.get(2)
      result = receiver.send(signal_name, arg1, arg2)
    elsif argc == 3
      arg1 = argv.get(1)
      arg2 = argv.get(2)
      arg3 = argv.get(3)
      result = receiver.send(signal_name, arg1. arg2, arg3)
    else
      args = Array.new
      for i in 1..argc
        args[i-1] = argv.get(i)
      end
      result = receiver.send(signal_name, *args)
    end
    push_ruby(result)                     # <4>=result
    Lua_C.setfield(@s, -3, '___get') # 赋值<2>`rgss`.["___get"]=<4>result，弹出<4>
    Lua_C.settop(@s, -4)
    release_obj(argv)
    release_obj(request)
  end

end

# 在Lua侧创建的对象来到Ruby时的包装类
class Lua_WrappedObject
  def initialize(lua_vm, key, type_enum)
    @lua = lua_vm
    @key = key
    @type = type_enum
  end
  # 在跨语言界面的引用管理中的引用键
  def key
    @key
  end
  # 这个对象在Lua侧的类型（使用Lua C API中的类型常量）
  def type
    @type
  end
  # 转换为Debug查看数据显示
  def inspect
    return '<Lua_WrappedObject:0x%x @key=%d, @type=%d, tostring=%s>' \
      % [object_id * 2, @key, @type, tostring]
  end

  # 视为table，访问其元素
  def [](x)
    # TODO: 异常处理
    @lua.cross.push_key(@key)
    @lua.cross.push_ruby(x)
    @lua.tget
    result = @lua.cross.get_ruby
    @lua.cross.pop(2)
    return result
  end
  alias :get :[]
  # 视为table，设置其元素
  def []=(x, val)
    # TODO: 异常处理
    @lua.cross.push_key(@key)
    @lua.cross.push_ruby(x)
    @lua.cross.push_ruby(val)
    @lua.tset
    @lua.cross.pop(1)
  end
  alias :set :[]=
  # 转换为字符串
  def to_s
    # TODO: 异常处理
    @lua.cross.push_key(@key)
    @lua.tostring(-1)
    result = @lua.cross.get_ruby
    @lua.cross.pop(2)
    return result
  end
  alias :tostring :to_s

  # 视为callable table / callable userdata / function，调用之
  # 返回一个包含有各返回值的Array
  def call(*args)
    @lua.call_full(:push_cross, @key, nil, args)
  end
  # 视为callable table / callable userdata / function，调用之
  # 返回值使用rets_buffer接收，
  # 避免每次调用Lua的时候都重复为返回值创建Array，从而改善性能
  # rets_buffer的大小表示接受返回值的个数，
  # 个数超出容量时丢弃溢出部分，个数不足容量时用nil补足
  def call_with_buffer(rets_buffer, *args)
    @lua.call_full(:push_cross, @key, rets_buffer, args)
  end
end

# Lua虚拟机对象，以及对Lua虚拟机栈的操作
class Lua_VM

  # 创建Lua虚拟机，并且初始化跨语言界面的管理
  def initialize
    raise 'Lua DLL is not yet loaded!' if not Lua_C.loaded?
    @s = Lua_C.newstate  # s = state
    Lua_C.openlibs(@s)
    @cross = Lua_CrossBoundaryManager.new(
      @s,
      lambda { |key, type_enum| return Lua_WrappedObject.new(self, key, type_enum)},
      lambda { |key, object_id, type_str|
        # TODO: 把error_handler放在Lua_CrossBoundaryManager有点不妥当，之后需要移动到Lua_VM类下
        Lua_C.getfield(@s, Lua_C::LUA_REGISTRYINDEX, 'lua-rmva') # <1>=`LUA_REGISTRY`["lua-rmva"]
        Lua_C.getfield(@s, -1, 'rgss')          # <2>`rgss`
        Lua_C.getfield(@s, -1, 'error_handler') # <3>`rgss`.error_handler
        Lua_C.getfield(@s, -2, 'class')         # <4>`rgss`.class
        Lua_C.getfield(@s, -1, type_str)        # <5>`rgss`.class.XXXType
        if Lua_C.type(@s, -1) == Lua_C::LUA_TNIL
          # Lua侧没有匹配的包装函数：默认使用Object
          Lua_C.settop(@s, -2)
          Lua_C.getfield(@s, -1, 'Object')      # <5>`rgss`.class.Object
        end
        Lua_C.pushnumber(@s, key)       # <6>key
        Lua_C.pushnumber(@s, object_id) # <7>object_id
        Lua_C.pcall(@s, 2, 1, -5)       # <5>obj=xpcall(<5>`rgss`.class.XXXType, <6>key, <7>object_id; err_handler=<3>`rgss`.error_handler)
        Lua_C.insert(@s, -5)      # <1>=<5>obj
        Lua_C.settop(@s, -5)
      })
  end

  # 跨语言界面
  def cross
    @cross
  end
  alias :cross_boundary :cross

  # 将Ruby对象推上Lua栈
  # 出现不支持的类型时，抛出异常
  def push(x)
    @cross.push_ruby(x)
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
    if result != Lua_C::LUA_OK || Lua_C.type(@s, -1) != Lua_C::LUA_TFUNCTION
      # 编译出错
      Lua_C.raise_thread_status_error(@s, result, "Code is: |\n#{str}") 
    end
    return nil
  end
  # 将Lua代码文件编译为执行函数并推上Lua栈
  def push_codefile(filename)
    result = Lua_C.loadfile(@s, filename)
    if result != Lua_C::LUA_OK || Lua_C.type(@s, -1) != Lua_C::LUA_TFUNCTION
      # 编译出错
      Lua_C.raise_thread_status_error(@s, result, "Code file is #{filename}.")
    end
  end
  # 将跨语言界面中指定引用键的对象推上栈
  def push_cross(key)
    @cross.push_key(key)
  end
  # 只处理Lua状态机的栈的函数调用
  # 上方n_args个现有对象依次视作参数，上方往下数n_args+1位置视为要调用的函数
  # 之后弹出参数和函数，并试图放入n_results个返回值
  # 可以指定所用的错误处理函数（在栈中所在的位置）；默认是0即不使用
  def call_instack(n_args, n_results, error_handler_idx=0)
    result = Lua_C.pcall(@s, n_args, n_results, error_handler_idx)
    if result != Lua_C::LUA_OK
      # 运行出错
      Lua_C.raise_thread_status_error(@s, result)
    end
  end
  # 将Lua栈第i位的内容返回为Ruby对象（不从栈中弹出；不检查Lua栈是否空）
  # i为1表示栈底；-1时表示栈顶，-2时表示从顶向底第二位，以此类推
  def get(i=-1)
    @cross.get_ruby(i)
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
    n = 0 if n < 0
    out_array = Array.new(n) if out_array == nil
    len = out_array.length
    val_len = (n < len) ? n : len
    for i in 0 .. val_len-1
      out_array[i] = (-n+i < 0) ? get(-n+i) : nil
    end
    for i in val_len .. len-1
      out_array[i] = nil
    end
    return out_array
  ensure
    Lua_C.settop(@s, -n-1)
  end
  # 清空Lua栈，舍弃栈中所有对象
  def reset
    Lua_C.settop(@s, 0)
  end

  # 包装得更完善的函数调用
  # code_pusher_sym表示要使用此Lua_VM的哪个push_xxx方法来把要调用的函数对象推上栈，push_xxx方法接受code_object作为参数
  # 函数使用args传递要交给Lua的参数，并且返回Lua所返回的值；都是Array类型，因此多参多返回值
  # 给定retsBuffer时使用此buffer存放返回值，或者设为nil表示新建Array存放返回值
  def call_full(code_pusher_sym, code_object, rets_buffer, args)
    # 考虑原本的栈长
    length_before = length
    # 放上用于错误处理的error_handler
    # TODO: 把error_handler放在Lua_CrossBoundaryManager有点不妥当，之后需要移动到Lua_VM类下
    @cross.push_error_handler
    # 放上Lua代码块，然后放上参数
    # code_object提供内容，code_pusher_sym决定内容是视作文件名还是视作字符串
    send(code_pusher_sym, code_object)
    push_n(args)
    # 执行
    n_ret = (rets_buffer == nil) ? -1 : rets_buffer.length
    call_instack(args.length, n_ret, length_before+1)
    # 承接返回值（多余舍弃，不足填nil）
    # Lua侧已返回值的实际数目应当是当前栈长减去原本栈长和错误处理
    n_ret = length - length_before - 1
    rets_buffer = pop_n(n_ret, rets_buffer)
    # 舍弃错误处理的error_handler
    Lua_C.settop(@s, -2)
    return rets_buffer
  end
  # 将Lua栈第i位的内容视作table，栈顶视作key，访问table[key]
  # key将被弹出，并将结果value替换到栈顶
  # i为1表示栈底；-1时表示栈顶，-2时表示从顶向底第二位，以此类推
  # 这个函数不直接将结果value返回，如果接下来需要立刻使用value可以用pop取出
  def tget(i=-2)
    Lua_C.gettable(@s, i)
  end
  # 将Lua栈第i位的内容视作table，栈顶视作value，从顶向底第二位视作key，设置table[key]=value
  # key和value将被弹出
  # i为1表示栈底；-1时表示栈顶，-2时表示从顶向底第二位，以此类推
  def tset(i=-3)
    Lua_C.settable(@s, i)
  end
  # 将Lua栈第i位内容的字符串表示推向栈顶
  # 相当于在Lua侧对内容使用tostring得到字符串表示
  def tostring(i=-1)
    len = Lua_C.gettop(@s)
    i = len + 1 + i if i < 0
    Lua_C.getfield(@s, Lua_C::LUA_GLOBALSINDEX, 'tostring')
    Lua_C.pushvalue(@s, i)
    call_instack(1, 1)
  end

  # 关闭Lua虚拟机，释放空间
  def close
    Lua_C.close(@s)
  end
  alias dispose close
end

# 作为非正规解决方案的Lua代码，常用于临时用途或者实现单靠Ruby侧难实现的方法
module Lua_Magics

  include Lua_Config
  # 重设输出到调试控制台
  _GetProcAddress = Win32API.new('kernel32', 'GetProcAddress', 'lp', 'l')
  _GetModuleHandle = Win32API.new('kernel32', 'GetModuleHandle', 'p', 'l')
  rgssdll_addr = _GetModuleHandle.(RGSS_DLL_FILENAME)
  # _RGSSEval_addr = _GetProcAddress.(rgssdll_addr, 'RGSSEval')
  _RGSSSetStringUTF8_addr = _GetProcAddress.(rgssdll_addr, 'RGSSSetStringUTF8')
  PRINT = <<-EOF
local varname = '$LUA_PRINTED'

local ffi = require 'ffi'
local rgss = require 'rgss'
rgss.dll.RGSSSetStringUTF8 = ffi.cast('void(*)(const char*, const char*)', #{_RGSSSetStringUTF8_addr})
_G.print = function(...)
  local n = select(\'\#\', ...)
  local str = ''
  for i = 1, n do
    local argi = select(i, ...)
    str = str .. tostring(argi) .. ((i~=n) and \'\\t\' or \'\\n\')
  end
  rgss.dll.RGSSSetStringUTF8(varname, str)
  rgss.dll.RGSSEval('print '.. varname)
  return nil
end
EOF
end

# 用户可使用的各方法
class Lua

  include Lua_Config
  # 初始化
  # 创建Lua虚拟机，并且初始化必要的库和临时方案
  def initialize(dll_path=DEFAULT_DLL_PATH)
    # 第一次还没加载DLL的话，先加载DLL
    Lua_C.load(dll_path) if not Lua_C.loaded?
    # 创建Lua虚拟机
    @lua = Lua_VM.new
    # 加载各个临时方案
    eval(Lua_Magics::PRINT)
    return nil
  end

  # 执行一个Lua文件，args传递给文件的`...`变量
  # 返回一个包含有各返回值的Array
  def eval_file(filename, *args)
    @lua.call_full(:push_codefile, filename, nil, args)
  end

  # 执行一段Lua代码，args传递给代码块的`...`变量
  # 返回一个包含有各返回值的Array
  def eval(code, *args)
    @lua.call_full(:push_code, code, nil, args)
  end

  # 执行一段Lua代码，args传递给代码块的`...`变量，返回值使用rets_buffer接收
  # 避免每次调用Lua的时候都重复为返回值创建Array，从而改善性能
  # rets_buffer的大小表示接受返回值的个数，
  # 个数超出容量时丢弃溢出部分，个数不足容量时用nil补足
  def eval_with_buffer(code, rets_buffer, *args)
    @lua.call_full(:push_code, code, rets_buffer, args)
  end

  # 取消跨语言对象的引用；重新允许垃圾回收机制回收这个对象
  def release(obj)
    @lua.cross.release_obj(obj)
  end

  # 结束使用并销毁Lua虚拟机，清除并失去所有状态，例如在关闭游戏时可以使用
  def close
    @lua.close
  end
  alias :dispose :close

end
