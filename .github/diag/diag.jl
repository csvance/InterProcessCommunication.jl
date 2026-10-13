# Temporary macOS diagnostics (not for upstream).
using InterProcessCommunication
const I = InterProcessCommunication
using Printf

hdr(s) = println("\n==== ", s)
errstr() = (e = Libc.errno(); "errno=$e ($(Libc.strerror(e)))")
function showmode(fd)
    try
        st = stat(RawFD(fd))
        @printf("  stat(RawFD): mode=%o size=%d\n", st.mode, st.size)
    catch err
        println("  stat(RawFD) threw: ", sprint(showerror, err))
    end
end

hdr("platform")
println("  ", Sys.MACHINE, "  Julia ", VERSION)
println("  sizeof(mode_t)=", sizeof(I.mode_t), "  O_CREAT=", I.O_CREAT, " O_EXCL=", I.O_EXCL,
        " O_RDWR=", I.O_RDWR, " O_RDONLY=", I.O_RDONLY, " S_IRUSR=", string(I.S_IRUSR, base=8),
        " S_IWUSR=", string(I.S_IWUSR, base=8))

vtuple(n, f, m) = ccall(:shm_open, Cint, (Cstring, Cint, Cuint...), n, f, m)
vmacro(n, f, m) = @ccall shm_open(n::Cstring, f::Cint; m::Cuint)::Cint

for (label, opener) in (("IPC fixed-arity _shm_open", (n, f, m) -> I._shm_open(n, f, m)),
                        ("tuple vararg (Cuint...)", vtuple),
                        ("@ccall vararg", vmacro))
    hdr("shm create via $label")
    name = "/ipcd-$(getpid())-$(length(label))"
    ccall(:shm_unlink, Cint, (Cstring,), name)
    fd = opener(name, I.O_CREAT | I.O_EXCL | I.O_RDWR, 0o600)
    println("  create fd=$fd ", fd < 0 ? errstr() : "")
    fd >= 0 && (I._ftruncate(fd, 100); showmode(fd))
    fd2 = vtuple(name, I.O_RDONLY, 0)
    println("  reopen O_RDONLY fd=$fd2 ", fd2 < 0 ? errstr() : "ok")
    fd2 >= 0 && showmode(fd2)
    ccall(:shm_unlink, Cint, (Cstring,), name)
end

hdr("IPC.SharedMemory create + reopen")
name = "/ipcd-sm-$(getpid())"
try
    A = SharedMemory(name, 100)
    println("  created sizeof=", sizeof(A))
    for ro in (false, true)
        try
            B = SharedMemory(name; readonly=ro)
            println("  reopen readonly=$ro ok sizeof=", sizeof(B))
        catch err
            println("  reopen readonly=$ro failed: ", sprint(showerror, err))
        end
    end
catch err
    println("  failed: ", sprint(showerror, err))
end
ccall(:shm_unlink, Cint, (Cstring,), name)

hdr("System V shm")
try
    A = SharedMemory(I.PRIVATE, 1000)
    id = shmid(A)
    println("  created id=", id)
    println("  sizeof=", sizeof(A))
    println("  ShmInfo=", ShmInfo(id))
catch err
    println("  failed: ", sprint(showerror, err))
    Base.show_backtrace(stdout, catch_backtrace()); println()
end
println("  _sizeof_struct_shmid_ds=", I._sizeof_struct_shmid_ds, " segsz off=", I._offsetof_shm_segsz,
        " typeof segsz=", I._typeof_shm_segsz)

hdr("System V shm, volatile=false (no early IPC_RMID)")
try
    A = SharedMemory(I.PRIVATE, 1000; volatile=false)
    id = shmid(A)
    println("  created id=", id, " sizeof(id)=", sizeof(id))
    println("  ShmInfo segsz=", ShmInfo(id).segsz)
    B = SharedMemory(id; readonly=true)
    println("  reopen by id ok sizeof=", sizeof(B))
    ccall(:shmctl, Cint, (Cint, Cint, Ptr{Cvoid}), id.value, I.IPC_RMID, C_NULL)
catch err
    println("  failed: ", sprint(showerror, err))
end
