# unsafe

### 1、unsafe.Sizeof

返回操作数在内存中的大小，参数可以是任意类型的表达式，但是它不会对表达式进行求值。

一个Sizeof函数调用是一个对应uintptr类型的常量表达式，因此返回的结果可以用作数组类型的长度大小，或者用做计量其他大小的常量。

Sizeof函数返回的大小只包括数据结构中固定的部分。

```go
// 返回string对应结构体中的指针和字符串长度部分，但是并不包含指针指向的内容。
fmt.Println(unsafe.Sizeof("a")) // 16
```

Go语言中非聚合类型通常有一个固定的大小，尽管在不同工具链下生成的实际大小可能会有所不同。考虑到可移植性，引用类型或者包含引用类型的大小在32位平台上是4个字节，在64位平台上是8个字节。

<span style='color:red'>计算机在加载和保存数据时，如果内存地址合理的对齐将会更加有效率。</span>

2字节大小的int16类型的变量地址应该是偶数，一个4字节大小的rune变量的地址应该是4的倍数，一个8字节大小的float64、uint64或64-bit指针类型变量地址应该是8字节对齐的。但是对于再大的地址对齐倍数则是不需要的，即使是complex128等较大的数据类型最多也只是8字节对齐。

由于地址对齐这个因素，一个聚合类型（结构体或数组）的大小至少是所有字段或元素大小的总和，或者更大因为可能存在内存空洞。

内存空洞是编译器自动添加的没有被使用的内存空间。用于保证后面每个字段或元素的地址相对于结构或数组的开始地址能够合理的对齐。（内存空洞可能会存在一些随机数据，可能会对用unsafe包直接操作内存的处理产生影响）。

<span style='color:red'>位、字节与字</span>

8位为一个字节，字由若干个字节构成，字的位数叫做字长，也就是字所对应的二进制数的长度，不同的机器有不同的字长。<span style='color:red'>字节的位数是固定的，为8位</span>

8位的机器，一个字对应一个字节，字长为8位。

16位的机器，一个字对应两个字节，字长为16位。

32位的机器，一个字对应四个字节，字长为32位。

64位的机器，一个字对应八个字节，字长为64位。

通常计算机所说的32位机器是指计算机的总线宽度为32位，所谓的32位处理器就是一次只能处理32位，也就是4字节的数据，32位处理器的寻址空间最大为4GB。64位的处理器理论上可以达到1800万个TB，但是由于处理器，主板，操作系统的限制，往往达不到。

| 类型                            | 大小                              |
| ------------------------------- | --------------------------------- |
| `bool`                          | 1个字节                           |
| `intN, uintN, floatN, complexN` | N/8个字节（例如float64是8个字节） |
| `int, uint, uintptr`            | 1个机器字                         |
| `*T`                            | 1个机器字                         |
| `string`                        | 2个机器字（data、len）            |
| `[]T`                           | 3个机器字（data、len、cap）       |
| `map`                           | 1个机器字                         |
| `func`                          | 1个机器字                         |
| `chan`                          | 1个机器字                         |
| `interface`                     | 2个机器字（type、value）          |



### 2、unsafe.Alignof

返回对应参数的类型需要对齐的倍数，也是一个常量表达式。

### 3、unsafe.Offsetof

这个函数的参数必须是一个字段，返回这个字段相当于起始地址的偏移量，包括可能的空洞。

例子：

![内存布局](../image/内存布局.png)

```Go
var x struct {
    a bool
    b int16
    c []int
}

// 32位
Sizeof(x)   = 16  Alignof(x)   = 4
Sizeof(x.a) = 1   Alignof(x.a) = 1 Offsetof(x.a) = 0
Sizeof(x.b) = 2   Alignof(x.b) = 2 Offsetof(x.b) = 2
Sizeof(x.c) = 12  Alignof(x.c) = 4 Offsetof(x.c) = 4

// 64位
Sizeof(x)   = 32  Alignof(x)   = 8
Sizeof(x.a) = 1   Alignof(x.a) = 1 Offsetof(x.a) = 0
Sizeof(x.b) = 2   Alignof(x.b) = 2 Offsetof(x.b) = 2
Sizeof(x.c) = 24  Alignof(x.c) = 8 Offsetof(x.c) = 8
```



### 4、unsafe.Pointer

是go特别定义的一种指针类型，可以包含任意类型变量的地址，和普通指针一样，该类型的指针也是可以比较的，并且可以支持和nil常量进行比较，判断是否位空指针。

一个普通的*T类型指针可以被转化为unsafe.Pointer类型的指针，并且一个unsafe.Pointer类型的指针也可以被转回普通指针，被转回的普通指针不需要和原始的类型相同。

通过转换新类型的指针，可以更新位模式。指针转换语法可以在不破坏类型系统的前提下向内存写入任意的值。

```Go
package math

// float64类型的指针转成uint64类型的指针。
func Float64bits(f float64) uint64 { return *(*uint64)(unsafe.Pointer(&f)) }

fmt.Printf("%#016x\n", Float64bits(1.0)) // "0x3ff0000000000000"
```

一个unsafe.Pointer指针也可以转换为uintptr类型，然后保存到指针型数值变量中（仅仅是一个和指针相同的一个数值，并不是一个指针），然后可以做必要的指针运算。这种转换虽然是可逆的，但是将uintptr转换成unsafe.Pointer指针可能会破坏类型系统，因为并不是所有的数字都是有效的内存地址。

许多讲uintptr转换成unsafe.Pointer类型的指针也是不安全的。

```Go
var x struct {
    a bool
    b int16
    c []int
}

// 和 pb := &x.b 等价
pb := (*int16)(unsafe.Pointer(
    uintptr(unsafe.Pointer(&x)) + unsafe.Offsetof(x.b)))
*pb = 42
fmt.Println(x.b) // "42"
```

上面这种写法虽然繁琐，但是更加安全。这些功能应该谨慎的使用。

<span style='color:red'>不要试图引入一个uintptr类型的临时变量，因为可能会破坏代码的安全性</span>

```Go
// NOTE: subtly incorrect!
tmp := uintptr(unsafe.Pointer(&x)) + unsafe.Offsetof(x.b)
pb := (*int16)(unsafe.Pointer(tmp))
*pb = 42
```

为什么会产生错误？因为有时候垃圾回收会移动一些变量以降低内存碎片等问题。当一个变量被移动，所有保存该变量旧地址的指针必须同时被更新为变量移动后的新地址。从垃圾回收器的角度来看，一个unsafe.Pointer是一个指向变量的指针，因此当变量被移动时，对应的指针也必须被更新，但uintptr类型的临时变量只是一个普通数字，所以他的值不应该被改变。所以当引入一个非指针的临时变量tmp时，导致垃圾收集器无法正确识别这是一个指向x变量的指针，当第二个语句执行的时候，变量x可能已经被转移，这个时候临时变量tmp就不是x.b的地址了，接下来的赋值语句会摧毁整个程序。

```Go
pT := uintptr(unsafe.Pointer(new(T))) // 提示: 错误!
```

这里并没有引用new新创建的变量，该语句执行完之后，垃圾收集器有权马上回收其内存空间，返回的pT将是无效地址。

<span style='color:red'>goroutine的栈是动态增长的，当发生栈动态增长时，原来栈中的所有变量可能需要被移动到更大的栈中，并不能确保变量的地址在整个的使用周期内是不变的</span>
