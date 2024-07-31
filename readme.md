# lua-rmva

适用于RPG Maker VX Ace的Lua 5.1(包括LuaJIT）支持。

## 安装

1. 准备一个32位的Lua5.1运行时DLL文件放置在项目目录中，路径为`<项目根目录>/System/lua51.dll`。
    - 推荐自行编译DLL以保证文件安全性。没有条件的话，可以在sourceforge上的[这里](https://sourceforge.net/projects/luabinaries/files/5.1.5/Windows%20Libraries/Dynamic)，寻找类似`lua-5.1.5_Win32_dll17_lib.zip`的文件。
    - 注意，放置位置的文件名是`lua51.dll`，不是`lua5.1.dll`.编译或下载DLL后，可能需要重命名文件。
    - LuaJIT 2.1.0也已测试发现可用。
2. 在Script Editor中，新建一栏，并将`lua-rmva.rb`的内容粘贴进去。
3. 在Event Editor中，使用`lua=Lua.new`创建实例，即可使用`lua.eval()`等函数运行Lua代码。

## 范例

在Event Editor中：
```ruby
begin
  ## 创建Lua实例
  if $lua == nil
    $lua = Lua.new
  end
  lua = $lua
  p "Lua: #{lua}"
  ## 从Lua传递数据到Ruby
  p lua.eval("return 'Hello World!', 123, 4.56, true, nil")
  ## 从Ruby传递数据到Lua再返回
  p lua.eval("return ...", "Hello World!", 123, 4.56, true, nil)
  p lua.eval("local num1,num2,str = ...; return num1==2, num2==3.14,
str=='Hello'", 2, 3.14, "Hello")
  ## 故意在Lua中引发错误，由Ruby接收
#   p lua.eval("error(string.format('num1=%s,num2=%s,str=%s',...))",
# 2, 3.14, "Hello")
rescue
  p $!
end
```

## 限制

- 当前仅支持传入和返回基本数据类型。正在努力适配更多数据类型。
  - 传入
    - nil(Ruby)变为nil(Lua)
    - true/false(Ruby)变为boolean(Lua)
    - Numeric(Ruby)变为number(Lua)
    - String(Ruby)变为string(Lua)
  - 返回
    - nil(Lua)变为nil(Ruby)
    - boolean(Lua)变为true/false(Ruby)
    - number(Lua)视情况：
      - 在Lua的C API中lua_tointeger表示区间内的整数变为Fixnum(Ruby)
      - 浮点数和超出lua_tointeger表示区间的整数变为Float(Ruby)
    - string(Lua)变为String(Ruby)
- 跨语言调用通常有一定性能损失。想要发挥充分的性能，最好减少跨越语言边界的次数。
  - 例如，相比一次次在Ruby中调用Lua的函数，可能的话最好精简成在Ruby中整理好指令，按一批次交付给Lua后再将必要的信息一同返回。
- 在RPGMaker中测试场景时，由Lua侧`print`的内容不会输出在测试控制台中。

## 贡献者

- 域外创音`<https://github.com/rinkaa, kaitensekai@qq.com>` (c) 2024
- 岚风雷`<https://github.com/gqxastg>` (c) 2024

## 许可证

（暂未确定）

