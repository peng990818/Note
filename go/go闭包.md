# 闭包

<span style='color:red'>闭包捕获的是当前变量的引用。</span>

```
package main

import (
    "fmt"
    "time"
)

var values = [5]int{10, 11, 12, 13, 14}

func main() {
    // 版本A:
    for ix := range values { // ix是索引值
        func() {
            fmt.Print(ix, " ")
        }() // 调用闭包打印每个索引值
    }
    fmt.Println()
    // 版本B: 和A版本类似，但是通过调用闭包作为一个协程
    for ix := range values {
        go func() {
            fmt.Print(ix, " ")
        }()
    }
    fmt.Println()
    time.Sleep(5e9)
    // 版本C: 正确的处理方式
    for ix := range values {
        go func(ix interface{}) {
            fmt.Print(ix, " ")
        }(ix)
    }
    fmt.Println()
    time.Sleep(5e9)
    // 版本D: 输出值:
    for ix := range values {
        val := values[ix]
        go func() {
            fmt.Print(val, " ")
        }()
    }
    time.Sleep(1e9)
}
```

## 版本A

使用闭包打印每个索引值。0 1 2 3 4

## 版本B

B的循环中，ix实际上是一个单变量，表示每个数组元素的索引值，因为这些闭包只绑定到一个变量,当运行代码时，不会看到每个元素的索引值，协程可能在循环结束时还没开始执行。

## 版本C

调用每个闭包是将ix作为参数传递给闭包，ix在每次循环的时都会被重新赋值，并将每个协程的ix放置在栈中，所以当协程最终被执行时，每个索引值对协程都是可用的，但顺序可能不同，取决于哪个协程开始执行。

## 版本D

D中的变量声明在循环内部，在每次循环时，这些变量相互之间不共享，所以这些变量可以单独被每个闭包使用。

