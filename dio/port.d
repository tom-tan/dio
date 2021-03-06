/**
*/
module dio.port;

import dio.core, dio.file;
import std.range, std.traits, std.typecons;

//import core.stdc.stdio : printf;

version(Windows)
{
    import dio.sys.windows;
}

debug
{
    static import std.stdio;
}

private template isNarrowChar(T)
{
    enum isNarrowChar = is(Unqual!T == char) || is(Unqual!T == wchar);
}

/**
*/
File stdin;
File stdout;    /// ditto
File stderr;    /// ditto


private struct StdIo
{
    File _io;
    this(File host)
    {
        _io = host;
    }
    bool pull(ref ubyte[] buf)
    {
        // Reading console input always returns UTF-16
        if (GetFileType(_io.handle) == FILE_TYPE_CHAR)
        {
            DWORD size = void;
            if (ReadConsoleW(_io.handle, buf.ptr, buf.length/2, &size, null))
            {
                debug(File)
                    std.stdio.writefln("pull ok : hFile=%08X, buf.length=%s, size=%s, GetLastError()=%s",
                        cast(uint)_io.handle, buf.length, size, GetLastError());
                debug(File)
                    std.stdio.writefln("C buf[0 .. %d] = [%(%02X %)]", size, buf[0 .. size*2]);
                buf = buf[size * 2 .. $];
                return (size > 0);  // valid on only blocking read
            }
        }
        else
        {
            return _io.pull(buf);
        }
        {
            switch (GetLastError())
            {
                case ERROR_BROKEN_PIPE:
                    return false;
                default:
                    break;
            }

            debug(File)
                std.stdio.writefln("pull ng : hFile=%08X, size=%s, GetLastError()=%s",
                    cast(uint)hFile, size, GetLastError());
            throw new Exception("pull(ref buf[]) error");

        //  // for overlapped I/O
        //  eof = (GetLastError() == ERROR_HANDLE_EOF);
        }
    }
    
    bool push(ref const(ubyte)[] buf)
    {
        if (GetFileType(_io.handle) == FILE_TYPE_CHAR)
        {
            DWORD size = void;
            if (WriteConsoleW(_io.handle, buf.ptr, buf.length/2, &size, null))
            {
                debug(File)
                    std.stdio.writefln("pull ok : hFile=%08X, buf.length=%s, size=%s, GetLastError()=%s",
                        cast(uint)_io.handle, buf.length, size, GetLastError());
                debug(File)
                    std.stdio.writefln("C buf[0 .. %d] = [%(%02X %)]", size, buf[0 .. size]);
                buf = buf[size * 2 .. $];
                return (size > 0);  // valid on only blocking read
            }
        }
        else
        {
            return _io.push(buf);
        }
        {
            throw new Exception("push error");  //?
        }
    }
    bool opEquals(ref const StdIo rhs) const { return _io.opEquals(rhs._io); }
    bool opEquals(HANDLE h) const { return _io.opEquals(h); }
    bool flush() { return _io.flush(); }
    HANDLE handle() @property { return _io.handle; }
    ulong seek(long offset, SeekPos whence) { return _io.seek(offset, whence); }
    bool seekable() @property { return _io.seekable; }
    //mixin Proxy!_io;
}

alias typeof({ return StdIo(stdin).textPort(); }()) StdInTextPort;
alias typeof({ return StdIo(stdout).textPort(); }()) StdOutTextPort;
alias typeof({ return StdIo(stderr).textPort(); }()) StdErrTextPort;

/**
*/
StdInTextPort din;
StdOutTextPort dout;   /// ditto
StdErrTextPort derr;   /// ditto

shared static this()
{
    version(Windows)
    {
        stdin  = File(GetStdHandle(STD_INPUT_HANDLE));
        stdout = File(GetStdHandle(STD_OUTPUT_HANDLE));
        stderr = File(GetStdHandle(STD_ERROR_HANDLE));
    }

    din  = StdIo(stdin).textPort();
    dout = StdIo(stdout).textPort();
    derr = StdIo(stderr).textPort();
}

shared static ~this()
{
    dout.flush();
    derr.flush();
}

/**
Output $(D args) to $(D writer).
*/
void write(Writer, T...)(auto ref Writer writer, T args)
    if (is(typeof({ put(writer, ""); })) && T.length > 0)
{
    static if (isPointer!Writer)
        alias writer w;
    else
        auto w = &writer;

    import std.conv;
    foreach (i, ref arg; args)
    {
        static if (isSomeString!(typeof(arg)))
            put(w, arg);
        else
            put(w, to!string(arg));
    }
}
/// ditto
void writef(Writer, T...)(auto ref Writer writer, T args)
    if (is(typeof({ put(writer, ""); })) && T.length > 0)
{
    static if (isPointer!Writer)
        alias writer w;
    else
        auto w = &writer;

    import std.format;
    formattedWrite(w, args);
}
/// ditto
void writeln(Writer, T...)(auto ref Writer writer, T args)
    if (is(typeof({ put(writer, ""); })))
{
    static if (isPointer!Writer)
        alias writer w;
    else
        auto w = &writer;

    write(w, args, "\n");
}
/// ditto
void writefln(Writer, T...)(auto ref Writer writer, T args)
    if (is(typeof({ put(writer, ""); })) && T.length > 0)
{
    static if (isPointer!Writer)
        alias writer w;
    else
        auto w = &writer;

    writef(w, args);
    put(w, "\n");
}

/**
Output $(D args) to $(D io.port.dout).
*/
void write(T...)(T args)
    if (T.length > 0 && !is(typeof({ put(args[0], ""); })))
{
    auto w = &dout;
    write(w, args);
}
/// ditto
void writef(T...)(T args)
    if (T.length > 0 && !is(typeof({ put(args[0], ""); })))
{
    auto w = &dout;
    writef(w, args);
}

/// ditto
void writeln(T...)(T args)
    if (T.length == 0 || !is(typeof({ put(args[0], ""); })))
{
    auto w = &dout;
    writeln(w, args);
}
/// ditto
void writefln(T...)(T args)
    if (T.length > 0 && !is(typeof({ put(args[0], ""); })))
{
    auto w = &dout;
    writefln(w, args);
}

/**
Input $(D data)s from $(D reader) with specified $(D format).
*/
uint readf(Reader, Data...)(auto ref Reader reader, in char[] format, Data data) if (isInputRange!Reader)
{
    import std.format;
    return formattedRead(reader, format, data);
}

/**
Input $(D data)s from $(D io.port.din).
*/
uint readf(Data...)(in char[] format, Data data)
{
    return readf(din, format, data);
}


/**
Configure text I/O port with following translations:
$(UL
$(LI Unicode transcoding. If original device element is ubyte, treats as UTF-8 device.)
$(LI New-line conversion, replace $(D '\r'), $(D '\n'), $(D '\r\n') to $(D '\n') for input, and vice versa.)
$(LI Buffering. For output, line buffering is done.)
)
*/
auto textPort(Dev)(Dev device)
if (isSomeChar!(DeviceElementType!Dev) ||
    is(DeviceElementType!Dev == ubyte))
{
    version(Windows) enum isWindows = true;
    else             enum isWindows = false;
    static if (isWindows && is(typeof(device.handle) : HANDLE))
    {
        return WindowsTextPort!Dev(device);
    }
    else
    {
        alias typeof({ return Dev.init.coerced!char.buffered; }()) LowDev;
        return TextPort!LowDev(device.coerced!char.buffered, false);
    }
}

/**
Implementation of text port.
 */
struct TextPort(Dev)
{
private:
    import std.utf : stride, encode, decode;

    alias Unqual!(DeviceElementType!Dev) B;
    alias Select!(isNarrowChar!B, dchar, B) E;
    static assert(isBufferedSource!Dev || isBufferedSink!Dev);
    static assert(isSomeChar!B);

    Dev device;
    bool lineflush;
    bool eof;
    dchar front_val; bool front_ok;
    size_t dlen = 0;

public:
    this(Dev dev, bool lineOut)
    {
        device = dev;
        lineflush = lineOut;
    }

  static if (isSource!Dev)
  {
    /**
    Provides character input range if original device is $(I source).
    */
    @property bool empty()
    {
        while (device.available.length == 0 && !eof)
            eof = !device.fetch();
        assert(eof || device.available.length > 0);
        return eof;
    }

    /// ditto
    @property dchar front()
    {
        if (front_ok)
            return front_val;

        static if (isNarrowChar!B)
        {
        Lagain:
            B c = device.available[0];
            auto n = stride((&c)[0..1], 0);
            if (n == 1)
            {
                device.consume(1);
                if (dlen && (dlen = 0, c == '\n'))
                {
                    while (device.available.length == 0 && device.fetch()) {}
                    if (device.available.length == 0)
                        goto err;
                    goto Lagain;
                }
                else if (c == '\r')
                {
                    dlen = 1;
                    c = '\n';
                }
                front_ok = true;
                front_val = c;
                return c;
            }

            B[B.sizeof == 1 ? 6 : 2] ubuf;
            B[] buf = ubuf[0 .. n];
            while (buf.length > 0 && device.pull(buf)) {}
            if (buf.length)
                goto err;
            size_t i = 0;
            front_val = decode(ubuf[0 .. n], i);
        }
        else
        {
            front_val = device.available[0];
            device.consume(1);
        }
        front_ok = true;
        return front_val;

    err:
        throw new Exception("Unexpected failure of fetching value form underlying device");
    }

    /// ditto
    void popFront()
    {
        //device.consume(1);
        front_ok = false;
    }

    /// for efficient character input range iteration.
    int opApply(scope int delegate(dchar) dg)
    {
        for(; !empty; popFront())
        {
            if (auto r = dg(front))
                return r;
        }
        return 0;
    }

    /** returns line range.
    Example:
    ---
    foreach (ln; stdin.textPort().lines) {}
    ---
    */
    @property auto lines(String = const(B)[])()
    {
        return LinePort!(Dev, String)(device);
    }
  }

  static if (isSink!Dev)
  {
    enum const(B)[] NativeNewline = "\r\n";

    /**
    Provides character output range if original device is $(I sink).
    */
    void put()(dchar data)
    {
        put((&data)[0 .. 1]);
    }

    /// ditto
    void put()(const(B)[] data)
    {
        // direct output
        immutable last = data.length - 1;
    retry:
        foreach (i, e; data)
        {
            if (e == '\n')
            {
                auto buf = data[0 .. i];
                while (device.push(buf) && buf.length) {}
                if (buf.length)
                    throw new Exception("");

                buf = NativeNewline;
                while (device.push(buf) && buf.length) {}
                if (buf.length)
                    throw new Exception("");
                if (lineflush) device.flush();

                data = data[i+1 .. $];
                goto retry;
            }
        }
        if (data.length)
        {
            while (device.push(data) && data.length) {}
            if (data.length)
                throw new Exception("");
            if (lineflush) device.flush();
        }
    }

    /// ditto
    void put()(const(dchar)[] data) if (isNarrowChar!B)
    {
        // encode to narrow
        foreach (c; data)
        {
            if (c == '\n')
            {
                auto buf = NativeNewline;
                while (device.push(buf) && buf.length) {}
                if (buf.length)
                    throw new Exception("");
                if (lineflush) device.flush();
                continue;
            }

            B[B.sizeof == 1 ? 4 : 2] ubuf;
            const(B)[] buf = ubuf[0 .. encode(ubuf, c)];
            while (device.push(buf) && buf.length) {}
            if (buf.length)
                throw new Exception("");
        }
    }

    /// ditto
    void put(C)(const(C)[] data) if (isNarrowChar!C && !is(B == C))
    {
        // transcode between narrows
        size_t i = 0;
        while (i < data.length)
        {
            dchar c = decode(data, i);
            if (c == '\n')
            {
                auto buf = NativeNewline;
                while (device.push(buf) && buf.length) {}
                if (buf.length)
                    throw new Exception("");
                if (lineflush) device.flush();
                continue;
            }

            B[B.sizeof == 1 ? 4 : 2] ubuf;
            const(B)[] buf = ubuf[0 .. encode(ubuf, c)];
            while (device.push(buf) && buf.length) {}
            if (buf.length)
                throw new Exception("");
        }
    }

    void flush()
    {
        device.flush();
    }
  }
}

/**
Generates line range over text port.
*/
struct LinePort(Dev, String : Char[], Char)
{
private:
    static assert(isBufferedSource!Dev && isSomeChar!Char);
    alias Unqual!(DeviceElementType!Dev) B;
    alias Unqual!Char C;

    import std.utf : encode, decode;
    import std.array : Appender;

    Dev device;
    Appender!(C[]) buffer;
    String line;
    bool eof;
    size_t dlen = 0;

public:
    this(Dev dev)
    {
        this.device = dev;
        popFront();
    }

    /**
    Provides line input range.
    */
    @property bool empty() const
    {
        return eof;
    }

    /// ditto
    @property String front() const
    {
        return line;
    }

    /// ditto
    void popFront()
    in { assert(!empty); }
    body
    {
        const(B)[] view;
        const(C)[] nextline;

        bool fetchExact()   // fillAvailable?
        {
            view = device.available;
            while (!view.length && device.fetch())
            {
                view = device.available;
            }
            return view.length != 0;
        }
        if (!fetchExact())
        {
            eof = true;
            return;
        }

        if (dlen && view[0] == '\n')
        {
            dlen = 0;
            device.consume(1);
            view = view[1..$];
            if (!view.length && !fetchExact())
            {
                eof = true;
                return;
            }
        }

        line = null;
        buffer.clear();

        C[] putBuffer(const(B)[] data)
        {
            static if (is(B == C))
            {
                // direct output
                buffer.put(data);
            }
            else if (is(B == dchar))
            {
                // encode to narrow
                C[C.sizeof == 1 ? 4 : 2] ubuf;
                foreach (c; data)
                    buffer.put(ubuf[0 .. encode(ubuf, c)]);
            }
            else
            {
                // transcoding between narrows
                size_t i = 0;
                C[C.sizeof == 1 ? 4 : 2] ubuf;
                while (i < data.length)
                    buffer.put(ubuf[0 .. encode(ubuf, decode(data, i))]);
            }
            return buffer.data;
        }

        for (size_t vlen=0; ; )
        {
            if (vlen == view.length)
            {
                putBuffer(view);
                device.consume(vlen);
                if (!fetchExact())
                    break;

                vlen = 0;
                continue;
            }

            auto e = view[vlen++];
            if (e == '\r')
            {
                ++dlen;
            Lnewline:
                // can slice underlying buffer directly
                static if (is(B == C))
                if (!buffer.data.length)
                {
                    static if (is(Char == const))
                        line = view[0 .. vlen-1];
                    static if (is(Char == immutable))
                        line = view[0 .. vlen-1].idup;
                    goto Ldone;
                }

                // general case: copy to buffer
                putBuffer(view[0 .. vlen-1]);

            Ldone:
                device.consume(vlen);
                break;
            }
            else if (e == '\n')
            {
                assert(dlen == 0);
                goto Lnewline;
            }
            else
                dlen = 0;
        }

        if (buffer.data.length)
        {
            static if (is(Char == immutable))
                line = buffer.data.idup;
            else    // mutable or const
                line = buffer.data;
        }
    }
}

unittest
{
    const(char)[] line;
    foreach (ln; File(__FILE__).textPort().lines)
    {
        line = ln;
        break;
    }
    assert(line == "/**");

    foreach (ln; File(__FILE__).textPort().lines!string){}
}


// Type erasure for console device
version(Windows)
{
    struct WindowsTextPort(Dev)
    {
    private:
        import std.conv : emplace;

        alias typeof({ return Dev.init.coerced!wchar.buffered; }()) ConDev;
        alias typeof({ return Dev.init.coerced!char.buffered; }()) LowDev;

        bool con;
        union X
        {
            TextPort!ConDev cport;
            TextPort!LowDev fport;
        }
        ubyte[X.sizeof]* payload;
        @property ref X store() { return *cast(X*)payload.ptr; }
        size_t* pRefCounter;
        import core.stdc.stdlib;

    public:
        this(ref Dev dev)
        {
            payload = cast(typeof(payload))malloc(typeof(*payload).sizeof);
            // If original device is character file, I/O UTF-16 encodings.
            if (GetFileType(dev.handle) == FILE_TYPE_CHAR)
            {
                con = true;
                emplace(&store.cport, dev.coerced!wchar.buffered, true);
            }
            else
            {
                con = false;
                emplace(&store.fport, dev.coerced!char.buffered, false);
            }
            pRefCounter = new size_t;
            *pRefCounter = 1;
        }
        this(this)
        {
            if (pRefCounter)
                ++(*pRefCounter);
            //con ? typeid(store().cport).postblit(&store.cport)
            //    : typeid(store().fport).postblit(&store.fport);
        }
        ~this()
        {
            if (pRefCounter && *pRefCounter > 0)
            {
                if (--(*pRefCounter) == 0)
                {
                    con ? clear(store.cport) : clear(store.fport);
                    free(payload);
                }
            }
        }

      static if (isSource!Dev)
      {
        @property bool empty()
        {
            return con ? store.cport.empty : store.fport.empty;
        }
        @property dchar front()
        {
            return con ? store.cport.front : store.fport.front;
        }
        void popFront()
        {
            return con ? store.cport.popFront() : store.fport.popFront();
        }
        int opApply(scope int delegate(dchar) dg)
        {
            return con ? store.cport.opApply(dg) : store.fport.opApply(dg);
        }

        @property auto lines(String = const(char)[])()
        {
            return WindowsLinePort!(typeof(this), String)(this);
        }
      }

      static if (isSink!Dev)
      {
        void put(dchar data) { return con ? store.cport.put(data) : store.fport.put(data); }
        void put(const( char)[] data) { return con ? store.cport.put(data) : store.fport.put(data); }
        void put(const(wchar)[] data) { return con ? store.cport.put(data) : store.fport.put(data); }
        void put(const(dchar)[] data) { return con ? store.cport.put(data) : store.fport.put(data); }

        void flush() { con ? store.cport.flush() : store.fport.flush(); }
      }
    }

    unittest
    {
        HANDLE hStdIn = GetStdHandle(STD_INPUT_HANDLE);
        assert(GetFileType(hStdIn) == FILE_TYPE_CHAR);
        auto str = "Ma Chérieあいうえお";

        // console input emulation
        DWORD nwritten;
        foreach (wchar wc; str~"\r\n")
        {
            INPUT_RECORD irec;
            irec.EventType = KEY_EVENT;
            irec.KeyEvent.wRepeatCount = 1;
            irec.KeyEvent.wVirtualKeyCode = 0;   // todo
            irec.KeyEvent.wVirtualScanCode = 0;  // todo
            irec.KeyEvent.UnicodeChar = wc;
            irec.KeyEvent.dwControlKeyState = 0; // todo

            irec.KeyEvent.bKeyDown = TRUE;
            WriteConsoleInputW(hStdIn, &irec, 1, &nwritten);

            irec.KeyEvent.bKeyDown = FALSE;
            WriteConsoleInputW(hStdIn, &irec, 1, &nwritten);
        }

        string s;
        readf(din, "%s\n", &s);

        //std.stdio.writefln("s   = [%(%02X %)]", s);   // as Unicode code points
        //std.stdio.writefln("s   = [%(%02X %)]", cast(ubyte[])s);    // as UTF-8
        //std.stdio.writefln("str = [%(%02X %)]", cast(ubyte[])str);  // as UTF-8
        assert(s == str);
    }
    unittest
    {
        import std.algorithm, std.range, std.typetuple, std.conv;

        HANDLE hStdOut = GetStdHandle(STD_OUTPUT_HANDLE);
        assert(GetFileType(hStdOut) == FILE_TYPE_CHAR);
        enum orgstr = "Ma Chérieあいうえお"w;
        enum orglen = orgstr.length;    // UTF-16 code unit count

        foreach (Str; TypeTuple!(string, wstring, dstring))
        {
            // get cursor positioin
            CONSOLE_SCREEN_BUFFER_INFO csbinfo;
            GetConsoleScreenBufferInfo(hStdOut, &csbinfo);
            COORD curpos = csbinfo.dwCursorPosition;

            Str str = to!Str(orgstr);

            // output to console
            writeln(dout, str);
            
            GetConsoleScreenBufferInfo(hStdOut, &csbinfo);
            if (curpos == csbinfo.dwCursorPosition)
            {
                curpos.Y--;
            }

            wchar[orglen*2] buf = void;    // prited columns may longer than code-unit count.
            DWORD cnt;
            ReadConsoleOutputCharacterW(hStdOut, buf.ptr, buf.length, curpos, &cnt);

            //static if (is(Str ==  string)) alias ubyte EB;
            //static if (is(Str == wstring)) alias ushort EB;
            //static if (is(Str == dstring)) alias uint EB;
            //std.stdio.writefln("str = [%(%02X %)]", cast(EB[])str);
            //std.stdio.writefln("buf = [%(%02X %)]", buf[0 .. orglen]);
            assert(equal(str, buf[0 .. orglen]));
        }
    }

    // Type erasure for console device
    struct WindowsLinePort(Dev, String)
    {
    private:
        import std.conv : emplace;

        alias typeof({ return Dev.init.store.cport.lines!String; }()) ConDev;
        alias typeof({ return Dev.init.store.fport.lines!String; }()) LowDev;

        bool con;
        union
        {
            ConDev clines;
            LowDev flines;
        }

    public:
        this(ref Dev dev)
        {
            if (dev.con)
            {
                con = true;
                emplace(&clines, dev.store.cport.lines!String);
            }
            else
            {
                con = false;
                emplace(&flines, dev.store.fport.lines!String);
            }
        }
        this(this)
        {
            con ? typeid(clines).postblit(&clines)
                : typeid(flines).postblit(&flines);
        }
        ~this()
        {
            con ? clear(clines) : clear(flines);
        }

        @property bool empty()
        {
            return con ? clines.empty : flines.empty;
        }
        @property String front()
        {
            return con ? clines.front : flines.front;
        }
        void popFront()
        {
            return con ? clines.popFront() : flines.popFront();
        }
    }
}
