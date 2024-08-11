# encoding: utf-8
#==============================================================================
# ** Lua-rmva
#------------------------------------------------------------------------------
#  This module enables usage of Lua script language (LuaJIT 2.1.x).
#  Authors:
#    - 域外创音`<https://github.com/rinkaa, kaitensekai@qq.com>` (c) 2024
#    - 岚风雷`<https://github.com/gqxastg>` (c) 2024
#==============================================================================

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
end

# 为跨语言界面的对象提供引用管理
# 跨语言时，为对象分配引用键，引用键相同的对象为同一对象
# 引用键对应的对象在两语言环境中可以有不同表示，但在一侧的修改会跨语言界面传到另一侧
class Lua_CrossBoundaryReferenceManager

  def initialize(lua_state)
    @s = lua_state
    # Lua侧的引用保留表示形式：
    #   `LUA_REGISTRY`["lua-rmva"]["mapping"] = {}  -- 正查（[key] = obj）
    #   `LUA_REGISTRY`["lua-rmva"]["reverse"] = {}  -- 反查（[obj] = key）
    #   `LUA_REGISTRY`["lua-rmva"]["source"] = {}   -- 记录对象最初由哪侧创建（[obj] = "lua"|"ruby"）
    Lua_C.createtable(@s, 0, 4)
    Lua_C.pushvalue(@s, -1)
    Lua_C.setfield(@s, Lua_C::LUA_REGISTRYINDEX, 'lua-rmva')
    for word in ['mapping', 'reverse', 'source']
      Lua_C.createtable(@s, 0, 0)
      Lua_C.setfield(@s, -2, word)
    end
    Lua_C.settop(@s, -2)
    # Ruby侧的引用保留表示形式：
    @mapping = Hash.new  # 正查（key => obj）
    @reverse = Hash.new  # 反查（obj => key）
    @source = Hash.new   # 记录对象最初由哪侧创建（obj => :lua|:ruby）
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
  def get_source(key)
    @source[key]
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

  # 取得lua栈中idx处对象的引用键，不存在时返回nil
  def get_key_of_lua_obj(idx)
    len = Lua_C.gettop(@s)
    idx = len + 1 + idx if idx < 0
    # TODO: 异常处理
    Lua_C.getfield(@s, Lua_C::LUA_REGISTRYINDEX, 'lua-rmva') # <1>=`LUA_REGISTRY`["lua-rmva"]
    Lua_C.getfield(@s, -1, 'reverse')  # <2>=`reverse`
    Lua_C.pushvalue(@s, idx)           # <3>=<idx>obj
    Lua_C.gettable(@s, -2)             # <3>=<2>`reverse`.[<3>obj] 即key
    if Lua_C.type(@s, -1) != Lua_C::LUA_TNIL
      key = Lua_C.tonumber(@s, -1).to_i
      Lua_C.settop(@s, -4)
      return key
    else
      Lua_C.settop(@s, -4)
      return nil
    end
  end
  # 为lua栈中idx处对象设置新引用键
  # 注意：不检查对象的引用键是否已经存在，而对已经存在引用键的对象再指定新引用键会导致内存泄露
  # 请务必先用get_key_of_lua_obj获得现有的引用键并查看是否为nil！
  def appoint_key_of_lua_obj(idx, lua_obj_type, lua_obj_wrapper)
    key = _generate_new_key
    len = Lua_C.gettop(@s)
    idx = len + 1 + idx if idx < 0
    # TODO: 异常处理
    # 在Lua侧注册引用键并保持引用
    Lua_C.getfield(@s, Lua_C::LUA_REGISTRYINDEX, 'lua-rmva') # <1>=`LUA_REGISTRY`["lua-rmva"]
    Lua_C.getfield(@s, -1, 'reverse')  # <2>=`reverse`
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
    Lua_C.settop(@s, -2)
    Lua_C.getfield(@s, -2, 'source') # <3>=`source`
    Lua_C.pushvalue(@s, idx)         # <4>=<idx>obj
    Lua_C.pushstring(@s, 'lua')      # <5>="lua"
    Lua_C.settable(@s, -3)           # <3>`source`.[<4>obj] = <5>"lua"
    Lua_C.settop(@s, -4)
    # 在Ruby侧创建包装对象
    wrapped_lua_obj = lua_obj_wrapper.(key, lua_obj_type)
    # 在Ruby侧注册引用键并保持引用
    @reverse[wrapped_lua_obj] = key
    @mapping[key] = wrapped_lua_obj
    @source[wrapped_lua_obj] = :lua
    # 返回新创建的引用键
    return key
  end
  def release_lua_obj(stack, idx)
    # TODO
  end
  def get_or_appoint_key_of_ruby_obj(obj, type_sym, ruby_obj_wrap_and_pusher)
    if reverse.has_key?(obj)
      # 已经有分配好的引用键：返回已经分配好的引用键
      return reverse[obj]
    else
      # 没有分配好的引用键，所以创建新的引用键
      key = _generate_new_key
      # 在Ruby侧注册引用键并保持引用
      @reverse[obj] = key
      @mapping[key] = obj
      @source[obj] = :ruby
      # 在Lua侧创建包装对象
      ruby_obj_wrap_and_pusher.(obj, type_sym) # <1>=obj
      # 在Lua侧注册引用键并保持引用
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
      Lua_C.settop(@s, -2)
      Lua_C.getfield(@s, -1, 'source') # <4>=`source`
      Lua_C.pushvalue(@s, -4)          # <5>=<1>obj
      Lua_C.pushstring(@s, 'ruby')     # <6>="ruby"
      Lua_C.settable(@s, -3)           # <4>`source`.[<5>obj] = <6>"ruby"
      Lua_C.settop(@s, -5)
      # 返回新创建的引用键
      return key
    end
  end
  def release_ruby_obj(obj) 
    # TODO
  end

  # 将对应引用键的对象推上栈，适用于要对对象进行操作时
  # 不检查对应对象是否存在
  def push(key)
    Lua_C.getfield(@s, Lua_C::LUA_REGISTRYINDEX, 'lua-rmva') # <1>=`LUA_REGISTRY`["lua-rmva"]
    Lua_C.getfield(@s, -1, 'mapping') # <2>=`mapping`
    Lua_C.pushnumber(@s, key)         # <3>=key
    Lua_C.gettable(@s, -2)            # <3>=<2>`mapping`.[<3>key] 即obj
    Lua_C.insert(@s, -3)              # <1>=<3>obj
    Lua_C.settop(@s, -3)
  end
  # 将位于idx的对象的来源标识推上栈
  # 适用于要对来源进行操作（比如检查其是"lua"还是"ruby"，还是nil）时
  def push_source(idx)
    len = Lua_C.gettop(@s)
    idx = len + 1 + idx if idx < 0
    Lua_C.getfield(@s, Lua_C::LUA_REGISTRYINDEX, 'lua-rmva') # <1>=`LUA_REGISTRY`["lua-rmva"]
    Lua_C.getfield(@s, -1, 'source') # <2>=`source`
    Lua_C.pushvalue(@s, idx)         # <3>=<idx>obj
    Lua_C.gettable(@s, -2)           # <3>=<2>`source`.[<3>obj] 即"lua"|"ruby"|nil
    Lua_C.insert(@s, -3)             # <1>=<3>"lua"|"ruby"|nil
    Lua_C.settop(@s, -3)
  end
  # 舍弃栈顶，适用于结束操作时
  def pop(n=1)
    Lua_C.settop(@s, -n-1)
  end

  def push_array(stack, array)
  end
  def push_hash(stack, hash)
  end
  def push_callable(stack, callable)
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
    return "<Lua_WrappedObject:0x%x @key=%d, @type=%d>" % [object_id * 2, @key, @type]
  end

  # 视为table，访问其元素
  def [](x)
    # TODO: 异常处理
    @lua.cross_boundary.push(@key)
    @lua.push(x)
    @lua.tget
    result = @lua.pop
    @lua.cross_boundary.pop
    return result
  end
  alias :get :[]
  # 视为table，设置其元素
  def []=(x, val)
    # TODO: 异常处理
    @lua.cross_boundary.push(@key)
    @lua.push(x)
    @lua.push(val)
    @lua.tset
    @lua.cross_boundary.pop
  end
  alias :set :[]=
  # 转换为字符串
  def to_s
    # TODO: 异常处理
    @lua.cross_boundary.push(@key)
    @lua.tostring(-1)
    result = @lua.pop
    @lua.cross_boundary.pop
    return result
  end
  alias :tostring :to_s

  # 视为callable table / callable userdata / function，调用之
  # Ruby调用Lua过程，可以传参和取返回值，支持多参多返回值
  # 给定retsBuffer时使用此buffer存放返回值，或者设为nil表示新建Array存放返回值
  def _call(rets_buffer, args)
    # 考虑原本的栈长
    length_before = @lua.length
    # 放上自身作为要执行的过程，然后放上参数
    @lua.cross_boundary.push(@key)
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
  private :_call
  # 视为callable table / callable userdata / function，调用之
  # 返回一个包含有各返回值的Array
  def call(*args)
    return _call(nil, args)
  end
  # 视为callable table / callable userdata / function，调用之
  # 返回值使用rets_buffer接收，
  # 避免每次调用Lua的时候都重复为返回值创建Array，从而改善性能
  # rets_buffer的大小表示接受返回值的个数，
  # 个数超出容量时丢弃溢出部分，个数不足容量时用nil补足
  def call_with_buffer(rets_buffer, *args)
    return _call(rets_buffer, args)
  end
end

# Lua虚拟机对象，以及对Lua虚拟机栈的操作
class Lua_VM

  # 创建Lua虚拟机，并且初始化跨语言界面的管理
  def initialize
    raise 'Lua DLL is not yet loaded!' if not Lua_C.loaded?
    @s = Lua_C.newstate  # s = state
    @cross = Lua_CrossBoundaryReferenceManager.new(@s)
  end

  # 跨语言界面
  def cross_boundary
    @cross
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
      Lua_C.pushnumber(@s, x)
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
    if result != Lua_C::LUA_OK
      # 编译出错
      raise_thread_status_error(result, "Code is: |\n#{str}") 
    end
    return nil
  end
  # 将Lua代码文件编译为执行函数并推上Lua栈
  def push_codefile(filename)
    result = Lua_C.loadfile(@s, filename)
    if result != Lua_C::LUA_OK
      # 编译出错
      raise_thread_status_error(result, "Code file is #{filename}.")
    end
  end
  # 函数调用
  # 上方n_args个对象依次视作参数，上方往下数n_args+1位置视为要调用的函数
  # 之后弹出参数和函数，并试图放入n_results个返回值
  def call(n_args, n_results)
    result = Lua_C.pcall(@s, n_args, n_results, 0)
    if result != Lua_C::LUA_OK
      # 运行出错
      raise_thread_status_error(result)
    end
  end
  # 将Lua栈第i位的内容返回为Ruby对象（不从栈中弹出；不检查Lua栈是否空）
  # i为1表示栈底；-1时表示栈顶，-2时表示从顶向底第二位，以此类推
  def get(i=-1)
    t = Lua_C.type(@s, i)
    if t == Lua_C::LUA_TNIL
      return nil
    elsif t == Lua_C::LUA_TBOOLEAN
      return (Lua_C.toboolean(@s, i) != 0)
    elsif t == Lua_C::LUA_TNUMBER
      return Lua_C.tonumber(@s, i)
    elsif t == Lua_C::LUA_TSTRING
      return Lua_C.tolstring(@s, i, 0).force_encoding(__ENCODING__)
    elsif
      t == Lua_C::LUA_TTABLE \
      || t == Lua_C::LUA_TFUNCTION \
      || t == Lua_C::LUA_TUSERDATA \
      || t == Lua_C::LUA_TLIGHTUSERDATA
      key = @cross.get_key_of_lua_obj(i)
      if key==nil
        key = @cross.appoint_key_of_lua_obj(
          i, t,
          lambda {|key, type| return Lua_WrappedObject.new(self, key, type)}
        )
      end
      return @cross.get_mapping(key)
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
    call(1, 1)
  end

  # 由于Lua到Ruby类型转换错误而抛出异常
  def raise_unsupported_lua_type_error(value, extra_msg=nil)
    type_enum_name = Lua_C::BASIC_TYPES.find {
      |s| Lua_C.const_get(s) == value
    } || "Unknown Type #{value}"
    msg = "Error: Lua type not supported for Ruby, type enum is #{type_enum_name}."
    msg += (extra_msg==nil ? '' : ("\n" + extra_msg))
    raise msg
  end
  # 由于编译或运行错误而抛出异常
  # 会把栈顶对象当作错误信息，并将其从栈中弹出
  def raise_thread_status_error(value, extra_msg=nil)
    err_enum_name = Lua_C::THREAD_STATUSES.find {
      |s| Lua_C.const_get(s) == value
    } || "Unknown Error #{value}"
    msg = "Error: Lua code failed to compile or run, error enum is #{err_enum_name},\n"
    msg += "message is #{pop}."
    msg += (extra_msg==nil ? '' : ("\n" + extra_msg))
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
