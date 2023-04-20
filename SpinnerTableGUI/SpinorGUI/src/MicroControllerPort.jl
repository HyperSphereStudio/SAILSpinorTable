using LibSerialPort

mutable struct MicroControllerPort
    sp::SerialPort
    line_buffer::String

    MicroControllerPort(port, baud) = new(LibSerialPort.open(port, baud), "")
end

close(p::MicroControllerPort) = LibSerialPort.close(p.sp)
isopen(p::MicroControllerPort) = LibSerialPort.isopen(p.sp)
isopen(::Nothing) = false
write(p::MicroControllerPort, v::UInt8) = LibSerialPort.write(p.sp, v)

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