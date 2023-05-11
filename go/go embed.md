# embed

## 1、嵌入

- 对于单个文件，支持嵌入为字符串和byte slice
- 对于多个文件和文件夹，支持嵌入为新的文件系统Fs
- 导入embed包，即使无显式使用
- go:embed指令用来嵌入，必须紧跟着嵌入后的变量名
- 只支持嵌入为string，byte slice和embed.FS三种类型，这三种的别名和命名类型都不可以

### 示例

#### 1）嵌入为字符串

```go
package main

import (
	_ "embed"
	"fmt"
)

//go:embed hello.txt
var s string

func main() {
	fmt.Println(s)
}
```

#### 2）嵌入为slice

```go
package main

import (
	_ "embed"
	"fmt"
)

//go:embed hello.txt
var b []byte

func main() {
	fmt.Println(b)
}
```

#### 3）嵌入为fs.FS

嵌入为一个文件

```go
package main

import (
	"embed"
	"fmt"
)

//go:embed hello.txt
var f embed.FS

func main() {
	data, _ := f.ReadFile("hello.txt")
	fmt.Println(string(data))
}
```

嵌入多个文件

```go
package main

import (
	"embed"
	"fmt"
)

//go:embed hello.txt
//go:embed hello2.txt
var f embed.FS

func main() {
	data, _ := f.ReadFile("hello.txt")
	fmt.Println(string(data))
	data, _ = f.ReadFile("hello2.txt")
    fmt.Println(string(data))
}
```

嵌入子文件夹下的文件

```go
package main

import (
	"embed"
	"fmt"
)

//go:embed p/hello.txt
//go:embed p/hello2.txt
var f embed.FS

func main() {
	data, _ := f.ReadFile("p/hello.txt")
	fmt.Println(string(data))
	data, _ = f.ReadFile("p/hello2.txt")
	fmt.Println(string(data))
}
```

#### 4）同一个文件嵌入为多个变量

```go
package main

import (
	_ "embed"
	"fmt"
)

//go:embed hello.txt
var s string

//go:embed hello.txt
var s2 string

func main() {
	fmt.Println(s)

	fmt.Println(s2)
}
```

#### 5）exported 和 unexported

```go
package main

import (
	_ "embed"
	"fmt"
)

//go:embed hello.txt
var s string

//go:embed hello2.txt
var S string

func main() {
	fmt.Println(s)

	fmt.Println(S)
}
```

#### 6）package级别的变量和局部变量都支持

```go
package main

import (
	_ "embed"
	"fmt"
)

func main() {
	//go:embed hello.txt
	var s string

	//go:embed hello.txt
	var s2 string

	fmt.Println(s, s2)
}
```

注意：s和s2的值编译期就已经确定了，即使运行时更改了文件，也不会改变和影响s和s2的值。

## 2、只读

嵌入的内容是只读的。在编译期嵌入文件的内容是什么，那么运行时内容也就是什么。

FS文件系统只提供了打开和读取的方法，并没有写入的方法，FS的实例是线程安全的，多个goroutine可以并发使用

## 3、go:embed指令

go:embed指令支持嵌入多个文件

```go
package main

import (
	"embed"
	"fmt"
)

//go:embed hello.txt hello2.txt
var f embed.FS

func main() {
	data, _ := f.ReadFile("hello.txt")
	fmt.Println(string(data))

	data, _ = f.ReadFile("hello2.txt")
	fmt.Println(string(data))
}
```

支持文件夹

```go
package main

import (
	"embed"
	"fmt"
)

//go:embed p
var f embed.FS

func main() {
	data, _ := f.ReadFile("p/hello.txt")
	fmt.Println(string(data))

	data, _ = f.ReadFile("p/hello2.txt")
	fmt.Println(string(data))
}
```

使用的是相对路径

```go
package main

import (
	"embed"
	"fmt"
)

//go:embed "he llo.txt" `hello-2.txt`
var f embed.FS

func main() {
	data, _ := f.ReadFile("he llo.txt")
	fmt.Println(string(data))
}
```

匹配模式

```go
package main

import (
	"embed"
	"fmt"
)

//go:embed p/*
var f embed.FS

func main() {
	data, _ := f.ReadFile("p/.hello.txt")
	fmt.Println(string(data))

	data, _ = f.ReadFile("p/q/.hi.txt") // 没有嵌入 p/q/.hi.txt
	fmt.Println(string(data))
}
```

嵌入和嵌入模式不支持绝对路径，不支持路径中包含.和..，如果想嵌入go源文件所在的路径，使用*

```go
package main

import (
	"embed"
	"fmt"
)

//go:embed *
var f embed.FS

func main() {
	data, _ := f.ReadFile("hello.txt")
	fmt.Println(string(data))

	data, _ = f.ReadFile(".hello.txt")
	fmt.Println(string(data))
}
```

## 4、文件系统

打开文件

```go
package main

import (
	"embed"
	"fmt"
)

//go:embed *
var f embed.FS

func main() {
	helloFile, _ := f.Open("hello.txt")
	stat, _ := helloFile.Stat()
	fmt.Println(stat.Name(), stat.Size())
}
```

遍历一个文件下的文件和文件夹信息：

```go
package main

import (
	"embed"
	"fmt"
)

//go:embed *
var f embed.FS

func main() {
	dirEntries, _ := f.ReadDir("p")
	for _, de := range dirEntries {
		fmt.Println(de.Name(), de.IsDir())
	}
}
```

可以返回子文件夹作为新的文件系统

```go
package main

import (
	"embed"
	"fmt"
	"io/fs"
	"io/ioutil"
)

//go:embed *
var f embed.FS

func main() {
	ps, _ := fs.Sub(f, "p")
	hi, _ := ps.Open("q/hi.txt")
	data, _ := ioutil.ReadAll(hi)
	fmt.Println(string(data))
}
```

