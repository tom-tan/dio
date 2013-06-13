module dio.file;

import dio.core;
import std.utf;
version(Windows)
{
    import dio.sys.windows;
}
else version(Posix)
{
    import dio.sys.posix;
}

debug
{
    import std.stdio : writeln, writefln;
}

/**
File is seekable device.
*/
struct File
{
private:
    version(Posix)
    {
        alias int HANDLE;
    }
    HANDLE hFile;
    size_t* pRefCounter;

public:
    /**
    */
    this(string fname, in char[] mode = "r")
    {
        version(Windows)
        {
            int share = FILE_SHARE_READ | FILE_SHARE_WRITE;
            int access = void;
            int createMode = void;

            switch (mode)
            {
                case "r":
                    access = GENERIC_READ;
                    createMode = OPEN_EXISTING;
                    break;
                case "w":
                    access = GENERIC_WRITE;
                    createMode = CREATE_ALWAYS;
                    break;
                case "a":
                    assert(0);

                case "r+":
                    access = GENERIC_READ | GENERIC_WRITE;
                    createMode = OPEN_EXISTING;
                    break;
                case "w+":
                    access = GENERIC_READ | GENERIC_WRITE;
                    createMode = CREATE_ALWAYS;
                    break;
                case "a+":
                    assert(0);

                // do not have binary mode(binary access only)
                //  case "rb":
                //  case "wb":
                //  case "ab":
                //  case "rb+": case "r+b":
                //  case "wb+": case "w+b":
                //  case "ab+": case "a+b":
                default:
                    break;
            }

            attach(CreateFileW(std.utf.toUTFz!(const(wchar)*)(fname),
                               access, share, null, createMode, 0, null));
        }
        else version(Posix)
        {
            int access = void;
            // openにはOPEN_ALWAYSに相当するModeはない？
            switch (mode)
            {
                case "r":
                    access = O_RDONLY;
                    break;
                case "w":
                    // version(Windows) と違い，属性はそのまま
                    access = O_WRONLY;
                    break;
                case "a":
                    assert(0);
                case "r+":
                    access = O_RDWR;
                    break;
                case "w+":
                    access = O_RDWR | O_CREAT;
                    break;
            case "a+":
                assert(0);

                // do not have binary mode(binary access only)
            //  case "rb":
            //  case "wb":
            //  case "ab":
            //  case "rb+": case "r+b":
            //  case "wb+": case "w+b":
            //  case "ab+": case "a+b":
            default:
                break;
            }
            attach(open(std.utf.toUTFz!(const(char)*)(fname), access));
        }
    }
    package this(HANDLE h)
    {
        attach(h);
    }
    this(this)
    {
        if (pRefCounter)
            ++(*pRefCounter);
    }
    ~this()
    {
        detach();
    }

    @property HANDLE handle() { return hFile; }

    //
    //@property inout(HANDLE) handle() inout { return hFile; }
    //alias handle this;

    bool opEquals(ref const File rhs) const
    {
        return hFile == rhs.hFile;
    }
    bool opEquals(HANDLE h) const
    {
        return hFile == h;
    }


    /**
    */
    void attach(HANDLE h)
    {
        if (hFile)
            detach();
        hFile = h;
        pRefCounter = new size_t;
        *pRefCounter = 1;
    }
    /// ditto
    void detach()
    {
        if (pRefCounter && *pRefCounter > 0)
        {
            if (--(*pRefCounter) == 0)
            {
                //delete pRefCounter;   // trivial: delegate management to GC.
                version(Windows)
                {
                    CloseHandle(cast(HANDLE)hFile);
                }
                else version(Posix)
                {
                    close(hFile);
                }
            }
            //pRefCounter = null;       // trivial: do not need
        }
    }

    //typeof(this) dup() { return this; }
    //typeof(this) dup() shared {}

    /**
    Request n number of elements.
    $(D buf) is treated as an output range.
    Returns:
        $(UL
            $(LI $(D true ) : You can request next pull.)
            $(LI $(D false) : No element exists.))
    */
    bool pull(ref ubyte[] buf)
    {
        static import std.stdio;
        debug(File)
            std.stdio.writefln("ReadFile : buf.ptr=%08X, len=%s", cast(uint)buf.ptr, buf.length);

        version(Windows)
        {
            DWORD size = void;

            if (ReadFile(hFile, buf.ptr, buf.length, &size, null))
            {
                debug(File)
                    std.stdio.writefln("pull ok : hFile=%08X, buf.length=%s, size=%s, GetLastError()=%s",
                                       cast(uint)hFile, buf.length, size, GetLastError());
                debug(File)
                    std.stdio.writefln("F buf[0 .. %d] = [%(%02X %)]", size, buf[0 .. size]);
                buf = buf[size.. $];
                return (size > 0);  // valid on only blocking read
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
        else version(Posix)
        {
            ssize_t size = void;
            if ((size = read(hFile, buf.ptr, buf.length)) > 0)
            {
                debug(File)
                    std.stdio.writefln("pull ok : hFile=%s, buf.length=%s, size=%s, errno=%s",
                                       hFile, buf.length, size, errno);
                debug(File)
                    std.stdio.writefln("F buf[0 .. %d] = [%(%02X %)]", size, buf[0 .. size]);
                buf = buf[size.. $];
                return (size > 0);
            }
            {
                debug(File)
                    std.stdio.writefln("pull ng : hFile=%s, size=%s, errno=%s",
                                       hFile, size, errno);
                throw new Exception("pull(ref buf[]) error");
            }
        }
    }

    /**
    */
    bool push(ref const(ubyte)[] buf)
    {
        version(Windows)
        {
            DWORD size = void;
            if (WriteFile(hFile, buf.ptr, buf.length, &size, null))
            {
                buf = buf[size .. $];
                return true;    // (size == buf.length);
            }

            {
                throw new Exception("push error");  //?
            }
        }
        else version(Posix)
        {
            ssize_t size = void;
            if ((size = write(hFile, buf.ptr, buf.length)) != -1)
            {
                buf = buf[size .. $];
                return true;
            }

            {
                throw new Exception("push error");
            }
        }
    }

    bool flush()
    {
        version(WriteFile)
        {
            return FlushFileBuffers(hFile) != FALSE;
        }
        else version(Posix)
        {
            return fsync(hFile) != -1;
        }
    }

    /**
    */
    @property bool seekable()
    {
        version(WriteFile)
        {
            return GetFileType(hFile) != FILE_TYPE_CHAR;
        }
        else version(Posix)
        {
            stat_t s = void;
            if (fstat(hFile, &s) != -1)
            {
                return !S_ISCHR(s.st_mode);
            }
            // Windows と仕様が違うので注意!
            throw new Exception("seekable error");
        }
    }

    /**
    */
    ulong seek(long offset, SeekPos whence)
    {
      version(Windows)
      {
        int hi = cast(int)(offset>>32);
        uint low = SetFilePointer(hFile, cast(int)offset, &hi, whence);
        if ((low == INVALID_SET_FILE_POINTER) && (GetLastError() != 0))
            throw new /*Seek*/Exception("unable to seek file pointer");
        ulong result = (cast(ulong)hi << 32) + low;
      }
      else version (Posix)
      {
        auto result = lseek(hFile, cast(int)offset, whence);
        if (result == cast(typeof(result))-1)
            throw new /*Seek*/Exception("unable to seek file pointer");
      }
      else
      {
        static assert(false, "not yet supported platform");
      }

        return cast(ulong)result;
    }
}
static assert(isSource!File);
static assert(isSink!File);

version(unittest)
{
    import std.algorithm;
}
unittest
{
    auto file = File(__FILE__);
    ubyte[] buf = new ubyte[64];
    ubyte[] b = buf;
    while (file.pull(b)) {}
    buf = buf[0 .. $-b.length];

    assert(buf.length == 64);
    debug std.stdio.writefln("buf = [%(%02x %)]\n", buf);
    assert(startsWith(buf, "module dio.file;\n"));
}


/**
Wrapping array with $(I source) interface.
*/
struct ArraySource(E)
{
    const(E)[] array;

    @property auto handle() { return array; }

    bool pull(ref E[] buf)
    {
        if (array.length == 0)
            return false;
        if (buf.length <= array.length)
        {
            buf[] = array[0 .. buf.length];
            array = array[buf.length .. $];
            buf = buf[$ .. $];
        }
        else
        {
            buf[0 .. array.length] = array[];
            buf = buf[array.length .. $];
            array = array[$ .. $];
        }
        return true;
    }
}

unittest
{
    import dio.port;

    auto r = ArraySource!char("10\r\ntest\r\n").buffered.ranged;
    long num;
    string str;
    readf(r, "%s\r\n", &num);
    readf(r, "%s\r\n", &str);
    assert(num == 10);
    assert(str == "test");
}
