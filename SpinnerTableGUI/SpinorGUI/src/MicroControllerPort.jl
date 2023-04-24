using LibSerialPort

pass() = ()

mutable struct MicroControllerPort
    name
    sp
    baud
    line_buffer::String
    on_disconnect

    MicroControllerPort(name, baud; on_disconnect=pass) = new(name, nothing, baud, "", on_disconnect)
end

close(p::MicroControllerPort) = isopen(p) && (LibSerialPort.close(p.sp); p.sp=nothing; p.on_disconnect(); println("$p Disconnected!"))
isopen(p::MicroControllerPort) = p.sp !== nothing && LibSerialPort.isopen(p.sp)
function check(p::MicroControllerPort)
    isopen(p) && return true
    p.sp === nothing || close(p)
    return false
end
write(p::MicroControllerPort, v::UInt8) = LibSerialPort.write(p.sp, v)
Base.print(io::IO, p::MicroControllerPort) = print(io, "Port[$(p.name), baud=$(p.baud), open=$(isopen(p))]")
function setport(p::MicroControllerPort, name)
    close(p)
    (name == "" || name === nothing) && return false
    p.sp = LibSerialPort.open(name, p.baud)
    println("$p Connected!")
    return true
end

function readlines(f::Function, p::MicroControllerPort)
    msg = p.line_buffer * String(nonblocking_read(p.sp))
    arr = split(msg, r"[\n\r]+")
    if length(arr) > 0
        for i in 1:length(arr)-1
            arr[i] != "" && f(arr[i])
        end
        p.line_buffer = arr[end]
    end
end