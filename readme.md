# lua-rmva

适用于RPG Maker VX Ace的LuaJIT 2.1.x支持。

## 安装

1. 准备一个*32位*的LuaJIT运行时DLL文件放置在项目目录中，路径为`<项目根目录>/System/lua51.dll`。
  - 推荐自行编译DLL以保证文件安全性
  - 注意，放置位置的文件名是`lua51.dll`，不是`lua5.1.dll`；编译或下载DLL后，可能需要重命名文件
  - 无法使用64位的LuaJIT运行时DLL
2. 在Script Editor中，新建一栏，并将`lua-rmva.rb`的内容粘贴进去。
3. 在Event Editor中，使用`lua = Lua.new`创建实例，即可使用`lua.eval(code, *args)`等函数运行Lua代码。

## 范例

在Event Editor中：
```ruby
begin
  ## 创建Lua实例
  $lua = Lua.new if $lua == nil
  lua = $lua
  p "Lua: #{lua}"
  ## 从Lua传递数据到Ruby
  p lua.eval("return 'Hello World!', 123, 4.56, true, nil")
  p lua.eval("return {'A', 'B', 'C'}, function() return 'DEF' end")
  ## 从Ruby传递数据到Lua再返回
  p lua.eval("return ...", "Hello World!", 123, 4.56, true, nil)
  p lua.eval("local num1,num2,str = ...; return num1==2, num2==3.14, 
str=='Hello'", 2, 3.14, 'Hello')
  ## 获得LuaJIT的版本信息
  p lua.eval("if type(jit) == 'table' then return jit.version end")
  ## 故意在Lua中引发错误，由Ruby接收
  # p lua.eval("error('This is an error'))",
rescue
  p($!.message, $!.backtrace)
end
```

## 数据类型的转换

### Ruby -> Lua

Ruby | Lua
--- | ---
`nil` | `nil`
`true`, `false` | `true`, `false`
`Integer`, `Float` | `number`
`String` | `string`
`Array`, `Hash` | **`table(+metatable)`**
`Method`, `Proc` | **`table(+metatable)`**
`Lua_WrappedObject` | 原本的`table`，`function`，`userdata`或`lightuserdata`
`Object` | **`table(+metatable)`**

### Lua -> Ruby

Lua | Ruby
--- | ---
`nil` | `nil`
`true`, `false` | `true`, `false`
`number` | **`Float`**
`string` | `String`
`table` | **`Lua_WrappedObject`**
`function` | **`Lua_WrappedObject`**
`userdata`, `lightuserdata` | **`Lua_WrappedObject`**
引用Ruby对象的 **`table(+metatable)`** | 原本的`Array`, `Hash`, `Method`, `Proc`或`Object`

### 注意

- 在Lua中，数字只有一种数据类型`number`；转换到Ruby时，所有的`number`都转换为`Float`类型成为浮点数小数，即使内容可能原本是整数
- Lua的`table`,`function`,`userdata`类型来到Ruby后，按引用传递，变成`Lua_WrappedObject`类型指向Ruby中原对象；其上的方法具体见下面API
- Ruby的`Array`,`Hash`,`Method`,`Proc`,`Object`类型来到Lua后，按引用传递，变成`table(+metatable)`形式指向Ruby中原对象；可以在其上调用方法，具体见下面API
- 原本来自Lua的对象来到Ruby后返回Lua，或者原本来自Ruby的对象来到Lua后返回Ruby，都能正确保持引用，可以用Lua中的`==`或Ruby中的`equals?`判断相等

## API

### Ruby中：`class Lua`

- `Lua#initialize(dll_path='System/lua51.dll')`：创建并初始化Lua虚拟机
- `Lua#eval_file(filename, *args)`：执行一个Lua文件，args传递给文件的`...`变量，返回一个包含有各返回值的Array
- `Lua#eval(code, *args)`：执行一段Lua代码，args传递给代码块的`...`变量，返回一个包含有各返回值的Array
- `Lua#eval_with_buffer(code, rets_buffer, *args)`：执行一段Lua代码，args传递给代码块的`...`变量，返回值使用rets_buffer接收，避免每次调用Lua的时候都重复为返回值创建Array，从而改善性能；rets_buffer的大小表示接受返回值的个数，个数超出容量时丢弃溢出部分，个数不足容量时用nil补足
- `Lua#close`, `Lua#dispose`：结束使用并销毁Lua虚拟机，清除并失去所有状态，例如在关闭游戏时可以使用

### Ruby中：`class Lua_WrappedObject`

- `Lua_WrappedObject#inspect`：显示关于对应Lua对象的粗略信息（只用于Debug）
- `Lua_WrappedObject#[](x)`：将对象视为table，访问其元素
- `Lua_WrappedObject#[]=(x, val)`：将对象视为table，设置键所对应的值
- `Lua_WrappedObject#to_s`：将对象转换为字符串，使用Lua中的tostring
- `Lua_WrappedObject#call(*args)`：将对象视为callable table / callable userdata / function，调用之；形式与`Lua#eval(code, *args)`相仿
- `Lua_WrappedObject#call_with_buffer(rets_buffer, *args)`：将对象视为callable table / callable userdata / function，调用之；使用现有Array存储返回值；形式与`Lua#eval_with_buffer(code, rets_buffer, *args)`相仿

### Lua中：`local rgss = require "rgss"`

- `rgss.eval(code)`：执行一段Ruby代码，无参数，取得返回值
- `rgss.call(ruby_obj, signal_name, ...)`：对来自Ruby的对象使用，调用其方法，并取得返回值
  - 也可以直接用`ruby_obj(signal_name, ...)` 
- `rgss.is_ruby_object(x)`：判断对象是否是Ruby对象

### Lua中：来自Ruby的引用对象所转换成的table中，metatable提供的方法

- 任何对象
  - `__eq`：使用方式如`ruby_obj1 == ruby_obj2`，检查引用到的Ruby对象是否一致
  - `__tostring`：使用方式如`tostring(ruby_obj)`，显示关于对应Ruby对象的粗略信息（只用于Debug）
  - `__call`：使用方式如`ruby_obj(signal_name, ...)`，调用Ruby对象的方法，并取得返回值

> 下方的方法实际上都与`ruby_obj(signal_name, ...)`等效，会调用Ruby中实际存在的方法；如果没能在API中找到自己需要的方法，可以直接使用`ruby_obj(signal_name, ...)`调用任意方法

- `Array`
  - `ruby_array:length()`, `ruby_array:size()`：取得元素数（Ruby中的`length`,`size`）
  - `ruby_array:get(k)`, `ruby_array:bracket_get(k)`：根据键取得对应值（Ruby中的`[]`）
  - `ruby_array:set(k, v)`, `ruby_array:bracket_set(k, v)`：设置键对应的值（Ruby中的`[]=`）
- `Hash`
  - `ruby_hash:length()`, `ruby_hash:size()`：取得元素数（Ruby中的`length`,`size`）
  - `ruby_hash:get(k)`, `ruby_hash:bracket_get(k)`：根据键取得对应值（Ruby中的`[]`）
  - `ruby_hash:set(k, v)`, `ruby_hash:bracket_set(k, v)`：设置键对应的值（Ruby中的`[]=`）
  - `ruby_hash:has_key(k)`, `ruby_hash:include(k)`：是否包含键（Ruby中的`has_key?`,`include?`）
  - `ruby_hash:has_value(v)`：是否包含值（Ruby中的`has_value?`）
  - `ruby_hash:index(v)`：寻找能对应值的一个键，未找到则返回nil（Ruby中的`index`）
  - `ruby_hash:keys()`：返回包含的各键（Ruby中的`keys`）
  - `ruby_hash:values()`：返回包含的各值（Ruby中的`values`）
- `Method`
  - `ruby_method:call(...)`：调用方法（Ruby中的`call`）
- `Proc`
  - `ruby_proc:call(...)`：调用过程（Ruby中的`call`）

## 限制

- 由于在初始化中使用了ffi库来包装RGSS的DLL中的`RGSSEval`，这个项目只支持LuaJIT，很可能无法支持原生Lua 5.1。
- 在Lua中，数字只有一种数据类型`number`，因此当从Lua来的数字要变成Ruby的`Hash`的键时，也只能当作`Float`浮点数处理，访问不到`Integer`类型的键。
  - 但是，Lua来的数字要变成Ruby的`Array`的键时，数字到整数的转换能隐式自动完成。
- 跨语言调用通常有一定性能损失。想要发挥充分的性能，最好减少跨越语言边界的次数。
  - 例如，相比一次次在Lua中调用Ruby的方法，可能的话最好精简成在Lua中整理好指令，一次性交给Ruby后再将必要的信息一同返回。
  - 在Lua中调用Ruby的方法的性能损失大于在Ruby中调用Lua的函数的性能损失。

## 贡献者

- 域外创音`<https://github.com/rinkaa, kaitensekai@qq.com>` (c) 2024
- 岚风雷`<https://github.com/gqxastg>` (c) 2024

## 许可证

（暂未确定）

