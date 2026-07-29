-- ---------------------------------------------------------------------------
-- uci_process.lua — minimal POSIX subprocess (fork/exec/pipe) via LuaJIT FFI,
-- used to talk to a UCI chess engine binary (e.g. Stockfish) over its
-- stdin/stdout.
--
-- POSIX-only by construction: fork()/execvp()/pipe()/poll() have no Windows
-- equivalent, and Android's /data partition is typically mounted `noexec` so
-- an external binary cannot run there regardless of this code. Every public
-- entry point is wrapped in pcall so a failure returns nil/false instead of
-- raising — callers must treat that as "engine unavailable", never crash.
-- ---------------------------------------------------------------------------

local M = {}

local ok_ffi, ffi = pcall(require, "ffi")
if not ok_ffi then
    function M.spawn() return nil, "ffi not available" end
    function M.pollLines() end
    function M.writeLine() end
    function M.closeFd() end
    return M
end

local C = ffi.C

-- `pollfd_t` (not `struct pollfd`) so this never collides with a same-named
-- cdef already declared elsewhere in the shared LuaJIT FFI namespace.
local ok_cdef = pcall(ffi.cdef, [[
    typedef long ssize_t;
    typedef struct { int fd; short events; short revents; } pollfd_t;
    typedef void (*sighandler_t)(int);
    int pipe(int[2]);
    int fork(void);
    int execvp(const char *, char *const argv[]);
    void _exit(int);
    int waitpid(int, int *, int);
    int dup2(int, int);
    int close(int);
    ssize_t read(int, void *, size_t);
    ssize_t write(int, const void *, size_t);
    int poll(pollfd_t *fds, unsigned long nfds, int timeout);
    char *strerror(int);
    sighandler_t signal(int signum, sighandler_t handler);
]])

if not ok_cdef then
    function M.spawn() return nil, "ffi.cdef failed (not a POSIX platform?)" end
    function M.pollLines() end
    function M.writeLine() end
    function M.closeFd() end
    return M
end

-- Writing to a pipe whose reader has already exited raises SIGPIPE, which by
-- default *terminates this whole process* (not a catchable Lua error, so
-- pcall alone cannot protect writeLine() below) — e.g. if the spawned engine
-- crashes and we still try to send it a command. Ignore it process-wide so a
-- dead engine just yields EPIPE from write() instead of killing KOReader.
local SIGPIPE = 13
pcall(function() C.signal(SIGPIPE, ffi.cast("sighandler_t", 1)) end)  -- 1 == SIG_IGN

local POLLIN = 0x0001
local BUF_SZ = 4096

local function errnoString()
    return ffi.string(C.strerror(ffi.errno()))
end

-- Spawns `cmd` with argv `args` (args[1] should be `cmd` itself), wiring its
-- stdin/stdout to two pipes. Returns pid, read_fd, write_fd on success, or
-- nil, error-message on failure. Never raises.
function M.spawn(cmd, args)
    local ok, a, b, c = pcall(function()
        local p2c = ffi.new("int[2]")
        if C.pipe(p2c) ~= 0 then error("pipe (stdin): " .. errnoString()) end
        local c2p = ffi.new("int[2]")
        if C.pipe(c2p) ~= 0 then
            C.close(p2c[0]); C.close(p2c[1])
            error("pipe (stdout): " .. errnoString())
        end

        local child_pid = C.fork()
        if child_pid < 0 then
            C.close(p2c[0]); C.close(p2c[1]); C.close(c2p[0]); C.close(c2p[1])
            error("fork: " .. errnoString())
        end

        if child_pid == 0 then
            -- Child: wire pipes to stdio, then exec. Never returns on success.
            C.close(p2c[1])
            C.dup2(p2c[0], 0); C.close(p2c[0])
            C.close(c2p[0])
            C.dup2(c2p[1], 1); C.dup2(c2p[1], 2); C.close(c2p[1])

            local argc = #args
            local argv = ffi.new("char*[?]", argc + 1)
            for i = 1, argc do argv[i - 1] = ffi.cast("char*", args[i]) end
            argv[argc] = nil
            C.execvp(cmd, argv)
            C._exit(127)  -- only reached if execvp itself failed
        end

        -- Parent: close the ends we don't use.
        C.close(p2c[0])
        C.close(c2p[1])
        return child_pid, c2p[0], p2c[1]
    end)
    if not ok then return nil, tostring(a) end
    return a, b, c
end

-- Non-blocking: call periodically (e.g. via UIManager:scheduleIn). Invokes
-- on_line(line) for every complete line currently buffered, and returns
-- immediately (0ms poll timeout) if nothing is available yet.
function M.pollLines(fd, on_line)
    pcall(function()
        local pollfds = ffi.new("pollfd_t[1]")
        pollfds[0].fd = fd
        pollfds[0].events = POLLIN
        if C.poll(pollfds, 1, 0) <= 0 or pollfds[0].revents == 0 then return end

        local buf = ffi.new("char[?]", BUF_SZ)
        local n = C.read(fd, buf, BUF_SZ - 1)
        if n <= 0 then return end
        local chunk = ffi.string(buf, n)
        for line in chunk:gmatch("([^\n]*)\n") do
            on_line(line)
        end
    end)
end

function M.writeLine(fd, line)
    pcall(function()
        local data = line .. "\n"
        C.write(fd, data, #data)
    end)
end

function M.closeFd(fd)
    if fd then pcall(function() C.close(fd) end) end
end

return M
