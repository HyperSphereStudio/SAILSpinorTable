module SpinorGUI

using Dates
include("MicroControllerPort.jl")
include("JuliaGUI.jl")

const DeviceBaudRate = 115200
const InitMotorSpeed = 75

window = nothing
deviceSerialPort = nothing
desiredMotorRPM = 0
currentMotorValue = 0
motorRPMLabel = nothing
devicePortSelect = nothing
plotCanvasObject = nothing
measuredMotorValues = Observable(Point2f[])
runningTime = now()

comp_println(x...) = println("[Comp]:", x...)
function close_port()
    global deviceSerialPort
    if isopen(deviceSerialPort)
        comp_println("Closing Port!")
        close(deviceSerialPort)
    end
end

function set_motor_speed(v)
    global motorValue = clamp(v, 0, 127)
    comp_println("Set Motor Speed $v")
    write(deviceSerialPort, UInt8(motorValue)) 
end

function watch_uart()
    global deviceSerialPort, motorRPMLabel, currentMotorValue

    isopen(deviceSerialPort) || (close_port(); set_gtk_property!(devicePortSelect, "active", -1); return)

    readlines(deviceSerialPort) do str 
        if startswith(str, "RPM")
            measuredMotorRPM = parse(Float64, str[4:end])
            currentMotorValue += cmp(desiredMotorRPM, measuredMotorRPM)
            comp_println("Set Motor Speed To $currentMotorValue. Measured: $measuredMotorRPM RPM. Desire: $desiredMotorRPM RPM")
            set_motor_speed(currentMotorValue)
            x = Dates.value(now()-runningTime)*1E-3 #Seconds
            y = measuredMotorRPM
            push!(measuredMotorValues[], (x, y))
            notify(measuredMotorValues)
            draw(plotCanvasObject)
            GAccessor.text(motorRPMLabel, "<b>Measured RPM:$measuredMotorRPM</b>")
        else
            println("[Device]:$str")
        end
    end
end

function set_port(name)
    global deviceSerialPort

    name === nothing && return
    deviceSerialPort === nothing || close(deviceSerialPort)
    deviceSerialPort = MicroControllerPort(name, DeviceBaudRate)
    comp_println("Reading Port $name [open = $(isopen(deviceSerialPort))]")
end

function launch_gui()
    global desiredMotorRPM, plotCanvasObject, desiredMotorRPM

    builder = GtkBuilder(filename="gui.glade")
    frame = builder["frame"]
    win = builder["window"]
    global devicePortSelect = builder["portComboBox"]
    global motorRPMLabel = builder["realMotorRPM"]
    plotBox = builder["plotBox"]
    motorFreq = builder["motorFreq"]

    function update_speed(s, shouldUpdate)
        desiredMotorRPM = s isa String ? s == "" ? 0 : parse(Float64, s) : s
        shouldUpdate && @sigatom @async GAccessor.text(motorFreq, string(s))
        desiredMotorRPM == 0 && set_motor_speed(0)
    end

    foreach(p -> push!(devicePortSelect, p), get_port_list())
    
    signal_connect(_-> exit(0), win, :destroy)
    signal_connect(_-> set_port(Gtk.bytestring(GAccessor.active_text(devicePortSelect))), devicePortSelect, "changed")
    signal_connect(_-> update_speed(get_gtk_property(motorFreq, :text, String), false), motorFreq, "changed")
    signal_connect(_-> update_speed(desiredMotorRPM * 2, true), builder["addFreq"], "clicked")
    signal_connect(_-> update_speed(desiredMotorRPM /= 2, true), builder["decFreq"], "clicked")
    signal_connect(_-> (set_motor_speed(InitMotorSpeed); update_speed(6, true)), builder["start"], "clicked")
    signal_connect(function(_)
                       update_speed(0, true)
                       empty!(measuredMotorValues[])
                   end, builder["reset"], "clicked")
    signal_connect(function(_)
                       comp_println("Releasing!")
                       write(deviceSerialPort, UInt8(128))
                       sleep(1)
                       comp_println("Stopping Release")
                       write(deviceSerialPort, UInt8(129))
                   end, builder["release"], "clicked")

    fig = Figure()
    plotCanvasObject = GtkCanvas(get_gtk_property(plotBox, "width-request", Int), get_gtk_property(plotBox, "height-request", Int))
    push!(plotBox, plotCanvasObject)
    ax = Axis(fig[1, 1], backgroundcolor="white", xlabel="Time [s]", ylabel="Freq [RPM]", title="Spinner RPM")
    lines!(ax, measuredMotorValues, color="green")
    makie_draw(plotCanvasObject, fig)

    @async showall(win)
    @async Gtk.gtk_main()

    while true
        watch_uart()
        yield()
        sleep(1E-2)
    end
end

end

using .SpinorGUI

#SpinorGUI.compile_sysimage()
SpinorGUI.launch_gui()