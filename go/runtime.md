# 运行时



## 一、程序启动引导

```
// 真正的程序入口
// src/runtime/rt0_linux_amd64.s 
TEXT _rt0_amd64_linux(SB),NOSPLIT,$-8
	JMP	_rt0_amd64(SB)
```

在程序编译为机器码之后，依赖特定CPU架构的指令集，而操作系统的差异则是直接反应在运行时进行不同的系统级操作上，比如系统调用。

<span style='color:red'>rt0是runtime0的缩写，意为运行时的创生。</span>

### 1、入口参数

#### 1）操作系统和入口参数的约定

操作系统和入口参数的约定通常是通过编译器和链接器生成的启动代码来实现，不同的操作系统和CPU架构有不同的约定，但是基本思路类似。

Unix-like系统

在大多数Unix-like系统中，包括Linux，当一个程序启动时，操作系统会将命令行参数和环境变量传递给程序

栈布局

- 栈顶（高地址）存储命令行参数和环境变量。

- 参数个数argc是一个整数表示命令行传参的数量。

- 参数值argv是一个指针数组，每个指针指向一个命令行参数的字符串。

- argv数组的最后一个元素是NULL。

- 环境变量envp是一个指针数组，每个指针指向一个环境变量字符串，数组的最后一个元素也是NULL。

  ```
  +---------------------+
  | envp[0]             |
  | envp[1]             |
  | ...                 |
  | envp[n]             |
  | NULL                |
  | argv[0]             |
  | argv[1]             |
  | ...                 |
  | argv[argc-1]        |
  | NULL                |
  | argc                |
  +---------------------+
  
  ```

Windows系统

对于GUI应用程序，WinMain是入口点

```c
int WINAPI WinMain(
    HINSTANCE hInstance,
    HINSTANCE hPrevInstance,
    LPSTR     lpCmdLine, // 包含命令行参数的字符串
    int       nCmdShow
);
```

对于控制台应用程序，入口点是main或者wmain(宽字符版本)

```c
int main(int argc, char *argv[]);
int wmain(int argc, wchar_t *argv[]);
```

#### 2）Go运行时处理

为了支持从系统给运行时传递参数，Go程序在进行引导时将对这部分参数进行处理。程序刚刚启动时，栈指针SP的前两个值分别对应argc和argv，分别存储参数的数量和具体的参数的值。

```
// src/runtime/asm_amd64.s
TEXT _rt0_amd64(SB),NOSPLIT,$-8
	MOVQ	0(SP), DI	// argc
	LEAQ	8(SP), SI	// argv
	JMP	runtime·rt0_go(SB)

TEXT runtime·rt0_go(SB),NOSPLIT,$0
	// 将参数向前复制到一个偶数栈上
	MOVQ	DI, AX			// argc
	MOVQ	SI, BX			// argv
	SUBQ	$(4*8+7), SP	// 2args 2auto
	ANDQ	$~15, SP
	MOVQ	AX, 16(SP)
	MOVQ	BX, 24(SP)

	// 初始化 g0 执行栈
	MOVQ	$runtime·g0(SB), DI			// DI = g0
	LEAQ	(-64*1024+104)(SP), BX
	MOVQ	BX, g_stackguard0(DI)		// g0.stackguard0 = SP + (-64*1024+104)
	MOVQ	BX, g_stackguard1(DI)		// g0.stackguard1 = SP + (-64*1024+104)
	MOVQ	BX, (g_stack+stack_lo)(DI)	// g0.stack.lo    = SP + (-64*1024+104)
	MOVQ	SP, (g_stack+stack_hi)(DI)	// g0.stack.hi    = SP

	// 确定 CPU 处理器的信息
	MOVL	$0, AX
	CPUID			// CPUID 会设置 AX 的值
	MOVL	AX, SI
```

### 2、线程本地存储TLS

之后会初始化并运行本地线程存储。

```
TEXT runtime·rt0_go(SB),NOSPLIT,$0
	(...)
#ifdef GOOS_darwin
	JMP ok // 在 Darwin 系统上跳过 TLS 设置
#endif

	LEAQ	runtime·m0+m_tls(SB), DI	// DI = m0.tls
	CALL	runtime·settls(SB)			// 将 TLS 地址设置到 DI

	// 使用它进行存储，确保能正常运行
	MOVQ	TLS, BX
	MOVQ	$0x123, g(BX)
	MOVQ	runtime·m0+m_tls(SB), AX
	CMPQ	AX, $0x123			// 判断 TLS 是否设置成功
	JEQ 2(PC)		 			// 如果相等则向后跳转两条指令
	CALL	runtime·abort(SB)	// 使用 INT 指令执行中断
ok:
	// 程序刚刚启动，此时位于主线程
	// 当前栈与资源保存在 g0
	// 该线程保存在 m0
	MOVQ	TLS, BX
	LEAQ	runtime·g0(SB), CX
	MOVQ	CX, g(BX)
	LEAQ	runtime·m0(SB), AX

	MOVQ	CX, m_g0(AX) // m->g0 = g0
	MOVQ	AX, g_m(CX)  // g0->m = m0
	(...)
```

其中g0和m0是一组全局变量，在程序运行之初就已经存在了，除了程序参数外，会首先将m0与g0通过指针互相关联。

```
// set tls base to DI
TEXT runtime·settls(SB),NOSPLIT,$32
#ifdef GOOS_android
	// Android stores the TLS offset in runtime·tls_g.
	SUBQ	runtime·tls_g(SB), DI
#else
	ADDQ	$8, DI	// ELF wants to use -8(FS)
#endif
	MOVQ	DI, SI
	MOVQ	$0x1002, DI	// ARCH_SET_FS
	// SYS_arch_prctl 系统调用用来在x86_64上设置和获取架构相关特性
	// 它通过设置FS和GS寄存器来支持线程局部存储
	// FS寄存器：通常用于指向线程局部存储区的指针
	// GS寄存器：在windows中和FS差不多，在linux中主要用于存储指向进程控制块或其他内核数据的指针
	MOVQ	$SYS_arch_prctl, AX
	SYSCALL
	CMPQ	AX, $0xfffffffffffff001  // 验证是否成功
	JLS	2(PC)
	MOVL	$0xf1, 0xf1  // crash 崩溃
	RET
```



### 3、早期校验和系统级初始化

在正式初始化运行时组件之前，还需要做一些校验和系统级的初始化工作，包括运行时类型检查，系统参数的获取以及影响内存管理和程序调度的相关常量的初始化。

<span style='color:red'>注意：Linux的可执行文件大多数是ELF格式，macOS的可执行文件大多数是mach-o格式，两者存在很大区别，windows系统区别更大。</span>

#### 1）运行时类型检查

本质上属于对编译器翻译工作的一个校验。

```go
// runtime/runtime1.go
// 程序启动时的类型检查函数
func check() {
    var (
        a     int8
        b     uint8
        c     int16
        d     uint16
        e     int32
        f     uint32
        g     int64
        h     uint64
        i, i1 float32
        j, j1 float64
        k     unsafe.Pointer
        l     *uint16
        m     [4]byte
    )
    type x1t struct {
        x uint8
    }
    type y1t struct {
        x1 x1t
        y  uint8
    }
    var x1 x1t
    var y1 y1t

    // 校验各个类型的大小是否符合预期
    if unsafe.Sizeof(a) != 1 {
        throw("bad a")
    }
    if unsafe.Sizeof(b) != 1 {
        throw("bad b")
    }
    if unsafe.Sizeof(c) != 2 {
        throw("bad c")
    }
    if unsafe.Sizeof(d) != 2 {
        throw("bad d")
    }
    if unsafe.Sizeof(e) != 4 {
        throw("bad e")
    }
    if unsafe.Sizeof(f) != 4 {
        throw("bad f")
    }
    if unsafe.Sizeof(g) != 8 {
        throw("bad g")
    }
    if unsafe.Sizeof(h) != 8 {
        throw("bad h")
    }
    if unsafe.Sizeof(i) != 4 {
        throw("bad i")
    }
    if unsafe.Sizeof(j) != 8 {
        throw("bad j")
    }
    if unsafe.Sizeof(k) != goarch.PtrSize {
        throw("bad k")
    }
    if unsafe.Sizeof(l) != goarch.PtrSize {
        throw("bad l")
    }
    if unsafe.Sizeof(x1) != 1 {
        throw("bad unsafe.Sizeof x1")
    }
    if unsafe.Offsetof(y1.y) != 1 {
        throw("bad offsetof y1.y")
    }
    if unsafe.Sizeof(y1) != 2 {
        throw("bad unsafe.Sizeof y1")
    }

    // timediv函数测试
    // 假设timediv函数用于计算秒和纳秒部分，并返回秒部分，同时通过指针参数返回纳秒部分
    if timediv(12345*1000000000+54321, 1000000000, &e) != 12345 || e != 54321 {
        throw("bad timediv")
    }

    // 测试原子操作
    var z uint32
    z = 1
    if !atomic.Cas(&z, 1, 2) {
        throw("cas1")
    }
    if z != 2 {
        throw("cas2")
    }

    z = 4
    if atomic.Cas(&z, 5, 6) {
        throw("cas3")
    }
    if z != 4 {
        throw("cas4")
    }

    z = 0xffffffff
    if !atomic.Cas(&z, 0xffffffff, 0xfffffffe) {
        throw("cas5")
    }
    if z != 0xfffffffe {
        throw("cas6")
    }

    m = [4]byte{1, 1, 1, 1}
    atomic.Or8(&m[1], 0xf0)
    if m[0] != 1 || m[1] != 0xf1 || m[2] != 1 || m[3] != 1 {
        throw("atomicor8")
    }

    m = [4]byte{0xff, 0xff, 0xff, 0xff}
    atomic.And8(&m[1], 0x1)
    if m[0] != 0xff || m[1] != 0x1 || m[2] != 0xff || m[3] != 0xff {
        throw("atomicand8")
    }

    // 浮点数NaN检查
    // NaN表示未定义或不可表示的值，用于处理无效的浮点运算结果
    *(*uint64)(unsafe.Pointer(&j)) = ^uint64(0)
    if j == j {
        throw("float64nan")
    }
    if !(j != j) {
        throw("float64nan1")
    }

    *(*uint64)(unsafe.Pointer(&j1)) = ^uint64(1)
    if j == j1 {
        throw("float64nan2")
    }
    if !(j != j1) {
        throw("float64nan3")
    }

    *(*uint32)(unsafe.Pointer(&i)) = ^uint32(0)
    if i == i {
        throw("float32nan")
    }
    if i == i {
        throw("float32nan1")
    }

    *(*uint32)(unsafe.Pointer(&i1)) = ^uint32(1)
    if i == i1 {
        throw("float32nan2")
    }
    if i == i1 {
        throw("float32nan3")
    }

    // 其他检查
    testAtomic64()

    if _FixedStack != round2(_FixedStack) {
        throw("FixedStack is not power-of-2")
    }

    if !checkASM() {
        throw("assembly checks failed")
    }
}
```

#### 2）系统参数、处理器与内存常量

argc，argv作为来自操作系统的参数传递给args处理程序参数的相关事宜。

```go
// 程序启动时的对来自操作系统的参数进行处理
// runtime/runtime1.go
func args(c int32, v **byte) {
  	// args函数将参数指针保存到argc和argv这两个全局变量中，供其他初始化函数使用
    argc = c
    argv = v
  	// 调用平台特定的sysargs
    sysargs(c, v)
}
```

```go
// runtime/os_darwin.go
// Darwin系统，仅需要获取程序的可执行路径即可，大部分工作操作系统已经帮忙完成了
//go:linkname executablePath os.executablePath
var executablePath string

func sysargs(argc int32, argv **byte) {
    // 跳过前面的系统参数
    // skip over argv, envv and the first string will be the path
    n := argc + 1
    for argv_index(argv, n) != nil {
        n++
    }
    // 通过系统参数获取可执行文件路径字符串
    executablePath = gostringnocopy(argv_index(argv, n+1))

    // strip "executable_path=" prefix if available, it's added after OS X 10.11.
    const prefix = "executable_path="
    if len(executablePath) > len(prefix) && executablePath[:len(prefix)] == prefix {
        executablePath = executablePath[len(prefix):]
    }
}
```

```go
// runtime/os_linux.go
const (
    _AT_NULL   = 0  // End of vector Linux 辅助向量终止符
    _AT_PAGESZ = 6  // System physical page size 物理页大小,通常4KB
    _AT_HWCAP  = 16 // hardware capability bit vector 硬件能力位向量。用于描述处理器支持的硬件特性
    _AT_SECURE = 23 // secure mode boolean 安全模式布尔值。指示进程是否在安全模式下运行。
    _AT_RANDOM = 25 // introduced in 2.6.29 一个随机值的地址，内核在启动时生成，用于增强安全性，常用于堆栈保护。
    _AT_HWCAP2 = 26 // hardware capability bit vector 2 硬件能力位向量2.扩展的硬件能力描述，补充上一个
)

// linux的ELF格式，除了传递必要参数argc，argv，envp外还会携带辅助向量auxv
// 将某些内核级的用户信息传递给用户进程，例如内存物理页大小
func sysargs(argc int32, argv **byte) {
    n := argc + 1

    // skip over argv, envp to get to auxv
    for argv_index(argv, n) != nil {
        n++
    }

    // skip NULL separator
    n++

    // now argv+n is auxv
    // 读取辅助向量
    auxv := (*[1 << 28]uintptr)(add(unsafe.Pointer(argv), uintptr(n)*goarch.PtrSize))
    if sysauxv(auxv[:]) != 0 {
        return
    }
    // In some situations we don't get a loader-provided
    // auxv, such as when loaded as a library on Android.
    // Fall back to /proc/self/auxv.
    // 无法直接读取时，取文件中获取
    fd := open(&procAuxv[0], 0 /* O_RDONLY */, 0)
    if fd < 0 {
        // On Android, /proc/self/auxv might be unreadable (issue 9229), so we fallback to
        // try using mincore to detect the physical page size.
        // mincore should return EINVAL when address is not a multiple of system page size.
        // 文件也读不了，就尝试调用mmap等内存分配系统直接测试物理页大小
        const size = 256 << 10 // size of memory region to allocate
        p, err := mmap(nil, size, _PROT_READ|_PROT_WRITE, _MAP_ANON|_MAP_PRIVATE, -1, 0)
        if err != 0 {
            return
        }
        var n uintptr
        for n = 4 << 10; n < size; n <<= 1 {
            err := mincore(unsafe.Pointer(uintptr(p)+n), 1, &addrspace_vec[0])
            if err == 0 {
                physPageSize = n
                break
            }
        }
        if physPageSize == 0 {
            physPageSize = size
        }
        munmap(p, size)
        return
    }
    // 读文件获取
    var buf [128]uintptr
    n = read(fd, noescape(unsafe.Pointer(&buf[0])), int32(unsafe.Sizeof(buf)))
    closefd(fd)
    if n < 0 {
        return
    }
    // Make sure buf is terminated, even if we didn't read
    // the whole file.
    buf[len(buf)-2] = _AT_NULL
    sysauxv(buf[:])
}

func sysauxv(auxv []uintptr) int {
    var i int
    for ; auxv[i] != _AT_NULL; i += 2 {
        tag, val := auxv[i], auxv[i+1]
        switch tag {
        case _AT_RANDOM:
            // The kernel provides a pointer to 16-bytes
            // worth of random data.
            startupRandomData = (*[16]byte)(unsafe.Pointer(val))[:]

        case _AT_PAGESZ:
            // 读取内存页大小
            physPageSize = val

        case _AT_SECURE:
            secureMode = val == 1
        }

        archauxv(tag, val)
        vdsoauxv(tag, val)
    }
    return i / 2
}

```

处理器相关

```go
// runtime/os_darwin.go
// BSD interface for threading.
func osinit() {
    // pthread_create delayed until end of goenvs so that we
    // can look at the environment first.

    ncpu = getncpu()             // 获取CPU核数
    physPageSize = getPageSize() // 获取物理页大小

    osinit_hack() // 执行操作系统特定的初始化操作
    // 例如设置线程堆栈大小、初始化系统线程、处理特殊的系统调用
}
```

```go
// runtime/os_Linux.go
func osinit() {
    // 获取处理器数量
    ncpu = getproccount()
    // 获取物理大页面大小
    physHugePageSize = getHugePageSize()
    // cgo启用后对信号的一些特殊处理
    if iscgo {
        // #42494 glibc and musl reserve some signals for
        // internal use and require they not be blocked by
        // the rest of a normal C runtime. When the go runtime
        // blocks...unblocks signals, temporarily, the blocked
        // interval of time is generally very short. As such,
        // these expectations of *libc code are mostly met by
        // the combined go+cgo system of threads. However,
        // when go causes a thread to exit, via a return from
        // mstart(), the combined runtime can deadlock if
        // these signals are blocked. Thus, don't block these
        // signals when exiting threads.
        // - glibc: SIGCANCEL (32), SIGSETXID (33)
        // - musl: SIGTIMER (32), SIGCANCEL (33), SIGSYNCCALL (34)
        // 如果启用了CGO，进行信号处理的特殊设置

        // #42494 glibc 和 musl 保留了一些信号用于内部使用，
        // 并要求这些信号在正常的 C 运行时不能被阻塞。
        // 当 Go 运行时暂时阻塞和解除阻塞信号时，
        // 这种阻塞的时间间隔通常很短。因此，libc 代码的这些预期
        // 在 Go + CGO 系统的线程中基本上都能得到满足。
        // 但是，当 Go 导致线程退出时，通过从 mstart() 返回，
        // 如果这些信号被阻塞，组合运行时可能会死锁。
        // 因此，不要在退出线程时阻塞这些信号。
        // - glibc: SIGCANCEL (32), SIGSETXID (33)
        // - musl: SIGTIMER (32), SIGCANCEL (33), SIGSYNCCALL (34)
        sigdelset(&sigsetAllExiting, 32)
        sigdelset(&sigsetAllExiting, 33)
        sigdelset(&sigsetAllExiting, 34)
    }
    // 架构相关初始化
    osArchInit()
}
```

macOS系统调用的特殊之处在于它提供了两套调用接口，一个是Mach调用，另一个则是POSIX调用。Mach是NeXTSTEP遗留下来的产物，其BSD层本质上是对Mach内核的一层封装。尽管用户态进程可以直接访问Mach调用，但出于通用性的考虑，物理页大小获取的方式是通过POSIX sysctl这个系统调用进行获取。

物理大页面（HugePages）

一种内存管理技术，允许操作系统使用比标准页面（通常是4KB或者8KB）更大的内存页面，大页面的大小通常是2MB或者1GB，具体取决于系统和硬件架构。

优势：

- 减少页表开销：使用大页面可以显著减少页表项的数量，因为每个页表项映射的内存范围更大，这可以降低页表开销，提高内存管理的效率。
- 提高TLB命中率：转换后备缓冲器是一种用于缓存虚拟地址到物理地址映射硬件缓存。大页面可以减少TLB的压力，提高TLB的命中率，从而减少地址转换的开销，提高性能。
- 减少内存碎片：使用大页面可以减少内存碎片，因为系统分配的大页面块较少，分配和管理内存块的操作更高效。
- 提高I/O性能：在某些情况下，使用大页面可以提高I/O性能，特别是对于大规模的数据处理和传输，因为大页面可以减少内存访问的次数和开销。

应用场景

数据库管理系统（DBMS）：数据库通常需要处理大量的数据，使用大页面可以提高缓存效率和查询性能。例如，Oracle 和 PostgreSQL 数据库都支持使用大页面来提升性能。

虚拟化技术：虚拟机监控程序（Hypervisor）如 KVM 和 VMware 使用大页面来优化虚拟机的内存管理，提高整体性能。

高性能计算（HPC）：科学计算和模拟通常需要大量的内存和高效的内存管理。使用大页面可以显著提高计算性能。

大数据处理：Hadoop 和 Spark 等大数据处理框架可以利用大页面来提高内存访问效率和数据处理速度。

使用大页面的注意事项

内存消耗：大页面可能导致内存消耗增加，因为每个大页面必须全部使用，即使只需要其中的一部分。这可能导致浪费内存资源。

配置复杂性：配置和管理大页面可能比标准页面更复杂，尤其是在需要手动调整内核参数和应用程序设置的情况下。

兼容性：并不是所有应用程序和工作负载都适合使用大页面，某些情况下可能需要进行性能测试和优化。

### 4、运行时组件核心

```
	// 系统初始化
	CALL	runtime·osinit(SB)
	// 调度器初始化
	CALL	runtime·schedinit(SB)
	
	// create a new goroutine to start program
	// runtime.main函数值传给newproc函数，创建一个新的goroutine来启动程序
	MOVQ	$runtime·mainPC(SB), AX		// entry
	PUSHQ	AX
	CALL	runtime·newproc(SB)
	POPQ	AX

    // 启动这个M，mstart应该永不返回
	// start this M
	CALL	runtime·mstart(SB)

	CALL	runtime·abort(SB)	// mstart should never return
	RET
	
// mainPC is a function value for runtime.main, to be passed to newproc.
// The reference to runtime.main is made via ABIInternal, since the
// actual function (not the ABI0 wrapper) is needed by newproc.
// mainPC是一个表示runtime.main函数值的变量，它将被传递给newproc函数。
// runtime.main的引用通过ABIInternal进行，因为newproc需要的是实际的函数，而不是ABI0包装器。
// DATA 定义了runtime.mainPC符号，起始位置为0，大小为8字节
// runtime·main<ABIInternal>(SB)这个值是runtime.main函数的地址，使用ABIInternal调用约定
DATA	runtime·mainPC+0(SB)/8,$runtime·main<ABIInternal>(SB)
// 定义全局符号runtime·mainPC，这个全局符号位于只读数据段，大小为8个字节
GLOBL	runtime·mainPC(SB),RODATA,$8
```

- schedinit：进行各种运行时组件初始化工作，包括调度器，内存分配器，回收器等。
- newproc：负责根据主协程（即main）入口地址创建可被运行时调度的执行单元。
- mstart：开始启动调度器的调度循环。

```go
// The bootstrap sequence is:
//
//	call osinit
//	call schedinit
//	make & queue new G
//	call runtime·mstart
//
// The new G calls runtime·main.
// todo 待研究
func schedinit() {
    lockInit(&sched.lock, lockRankSched)
    lockInit(&sched.sysmonlock, lockRankSysmon)
    lockInit(&sched.deferlock, lockRankDefer)
    lockInit(&sched.sudoglock, lockRankSudog)
    lockInit(&deadlock, lockRankDeadlock)
    lockInit(&paniclk, lockRankPanic)
    lockInit(&allglock, lockRankAllg)
    lockInit(&allpLock, lockRankAllp)
    lockInit(&reflectOffs.lock, lockRankReflectOffs)
    lockInit(&finlock, lockRankFin)
    lockInit(&trace.bufLock, lockRankTraceBuf)
    lockInit(&trace.stringsLock, lockRankTraceStrings)
    lockInit(&trace.lock, lockRankTrace)
    lockInit(&cpuprof.lock, lockRankCpuprof)
    lockInit(&trace.stackTab.lock, lockRankTraceStackTab)
    allocmLock.init(lockRankAllocmR, lockRankAllocmRInternal, lockRankAllocmW)
    execLock.init(lockRankExecR, lockRankExecRInternal, lockRankExecW)
    // Enforce that this lock is always a leaf lock.
    // All of this lock's critical sections should be
    // extremely short.
    lockInit(&memstats.heapStats.noPLock, lockRankLeafRank)

    // raceinit must be the first call to race detector.
    // In particular, it must be done before mallocinit below calls racemapshadow.
    gp := getg()
    if raceenabled {
        gp.racectx, raceprocctx0 = raceinit()
    }

    // 最大系统线程数量限制
    sched.maxmcount = 10000

    // The world starts stopped.
    // go运行时是否处于停止状态
    worldStopped()

    moduledataverify()
    stackinit()  // 初始化执行栈
    mallocinit() // 初始化内存分配器
    godebug := getGodebugEarly()
    initPageTrace(godebug) // must run after mallocinit but before anything allocates
    cpuinit(godebug)       // must run before alginit
    alginit()              // maps, hash, fastrand must not be used before this call
    fastrandinit()         // must run before mcommoninit
    mcommoninit(gp.m, -1)  // 初始化当前系统线程
    modulesinit()          // provides activeModules
    typelinksinit()        // uses maps, activeModules
    // 接口相关初始化
    itabsinit()  // uses activeModules
    stkobjinit() // must run before GC starts

    sigsave(&gp.m.sigmask)
    initSigmask = gp.m.sigmask

    goargs()
    goenvs()
    secure()
    parsedebugvars()
    gcinit() // 垃圾回收器初始化

    // if disableMemoryProfiling is set, update MemProfileRate to 0 to turn off memprofile.
    // Note: parsedebugvars may update MemProfileRate, but when disableMemoryProfiling is
    // set to true by the linker, it means that nothing is consuming the profile, it is
    // safe to set MemProfileRate to 0.
    if disableMemoryProfiling {
        MemProfileRate = 0
    }

    lock(&sched.lock)
    sched.lastpoll.Store(nanotime())
    // 创建P
    // 确定P的数量
    procs := ncpu
    if n, ok := atoi32(gogetenv("GOMAXPROCS")); ok && n > 0 {
        procs = n
    }
    if procresize(procs) != nil {
        throw("unknown runnable goroutine during bootstrap")
    }
    unlock(&sched.lock)

    // World is effectively started now, as P's can run.
    worldStarted()

    // For cgocheck > 1, we turn on the write barrier at all times
    // and check all pointer writes. We can't do this until after
    // procresize because the write barrier needs a P.
    if debug.cgocheck > 1 {
        writeBarrier.cgo = true
        writeBarrier.enabled = true
        for _, pp := range allp {
            pp.wbBuf.reset()
        }
    }

    if buildVersion == "" {
        // Condition should never trigger. This code just serves
        // to ensure runtime·buildVersion is kept in the resulting binary.
        buildVersion = "unknown"
    }
    if len(modinfo) == 1 {
        // Condition should never trigger. This code just serves
        // to ensure runtime·modinfo is kept in the resulting binary.
        modinfo = ""
    }
}
```

