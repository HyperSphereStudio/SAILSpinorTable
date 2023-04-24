module SpinorGUI

using Dates
include("MicroControllerPort.jl")
include("JuliaGUI.jl")

const DeviceBaudRate = 115200
const InitMotorSpeed = 75
const TimeDisplayWindow = 10

deviceSerialPort = nothing
desiredMotorFreq = 0
currentMotorValue = 0
motorFreqLabel = nothing
saveFile = ""
measuredMotorValues = Observable(Point2f[])
desiredMotorValues = Observable(Point2f[])
update_plot = nothing
runningTime = now()

comp_println(x...) = println("[Comp]:", x...)
isactiveserial() = isopen(deviceSerialPort)
running_time_in_seconds() = Dates.value(now() - runningTime) * 1E-3

function close_port()
    global deviceSerialPort
    if isopen(deviceSerialPort)
        comp_println("Closing Port!")
        close(deviceSerialPort)
    end
end

function set_motor_speed(v)
    isactiveserial() || (println("Motor Port Not Open!"); return)
    global currentMotorValue = clamp(v, 0, 127)
    comp_println("Set Motor Speed $v")
    write(deviceSerialPort, UInt8(currentMotorValue)) 
end

function watch_uart()
    global deviceSerialPort, motorFreqLabel, currentMotorValue

    readlines(deviceSerialPort) do str 
        if startswith(str, "Freq")
            measuredMotorFreq = parse(Float64, str[5:end])
            currentMotorValue += cmp(desiredMotorFreq, measuredMotorFreq)
            comp_println("Measured: $measuredMotorFreq Freq. Desire: $desiredMotorFreq Freq")
            set_motor_speed(currentMotorValue)
            time = running_time_in_seconds()
            push!(measuredMotorValues[], (time, measuredMotorFreq))
            push!(desiredMotorValues[], (time, desiredMotorFreq))
            update_plot()
            GAccessor.markup(motorFreqLabel, "<b>Measured: $measuredMotorFreq Hz</b>")
        else
            println("[Device]:$str")
        end
    end
end

function launch_gui()
    global desiredMotorFreq, plotCanvasObject, desiredMotorFreq, currentMotorValue, desiredMotorValues, saveFile, runningTime

    builder = GtkBuilder(filename="gui.glade")
    win = builder["window"]
    devicePortSelect = builder["portComboBox"]
    global motorFreqLabel = builder["realMotorFreq"]
    plotBox = builder["plotBox"]
    motorFreq = builder["motorFreq"]
    portTimer = nothing

    function update_speed(v)
        desiredMotorFreq = v
        desiredMotorFreq == 0 && set_motor_speed(0)
        @sigatom @async GAccessor.value(motorFreq) != v && GAccessor.value(motorFreq, v)
    end

    function reset()
        update_speed(0)
        empty!(measuredMotorValues[])
        empty!(desiredMotorValues[])
        runningTime = now()
        update_plot()
    end

    function start()
        reset()
        set_motor_speed(InitMotorSpeed)
        update_speed(1.5)
    end

    function update_com_ports()
        isactiveserial() && return
        empty!(devicePortSelect)
        foreach(p -> push!(devicePortSelect, p), get_port_list())     
    end

    function set_port(name)
        global deviceSerialPort
        isactiveserial() && close(deviceSerialPort)
        name != "" && (deviceSerialPort = MicroControllerPort(name, DeviceBaudRate))
        comp_println("Reading Port $name [open = $(isopen(deviceSerialPort))]")
        reset()
    end

    begin #Setup GUI window
        signal_connect(_-> exit(), win, :destroy)
        signal_connect(_-> set_port(gtk_to_string(GAccessor.active_text(devicePortSelect))), devicePortSelect, "changed")
        signal_connect(wid -> saveFile = gtk_to_string(GAccessor.filename(GtkFileChooser(wid))), builder["fileSelect"], "file-set")
        signal_connect(function save_to_file(_)
                            println("Saving Run To File to $saveFile")
                            if isfile(saveFile)
                                open(saveFile, "w") do f 
                                    mV = measuredMotorValues[]
                                    dV = desiredMotorValues[]
                                    Base.write(f, "Time[S] Measured[Hz] Desired[Hz]")
                                    foreach(i -> Base.write(f, "$(mV[i][1]) $(mV[i][2]) $(dV[i][2])\r\n"), eachindex(mV))
                                end
                            end 
                        end, builder["save"], "clicked")               
        signal_connect(_-> update_speed(GAccessor.value(motorFreq)), motorFreq, "value-changed")
        signal_connect(_-> start(), builder["start"], "clicked")
        signal_connect(_-> update_speed(0), builder["reset"], "clicked")
        signal_connect(function fire_item_release(_)
                           comp_println("Releasing!")
                           write(deviceSerialPort, UInt8(128))
                           sleep(.5)
                           comp_println("Stopping Release")
                           write(deviceSerialPort, UInt8(129))
                       end, builder["release"], "clicked")
        update_com_ports()               
        portTimer = Timer(_->update_com_ports(), 1; interval=2)
    end

    begin  #Create Plot
        set_theme!(theme_dark())
        fig = Figure()
        plotCanvasObject = GtkCanvas(get_gtk_property(plotBox, "width-request", Int), get_gtk_property(plotBox, "height-request", Int))
        push!(plotBox, plotCanvasObject)
        ax = Axis(fig[1, 1], 
            backgroundcolor=:grey, xlabel="Time [s]", ylabel="Freq [Hz]", title="Spinner Rate", 
            titlecolor=:white, xgridcolor = :white, ygridcolor = :white, xlabelcolor = :white, 
            ylabelcolor = :white, xticklabelcolor = :white, yticklabelcolor = :white)
        lines!(ax, measuredMotorValues, color=:blue, label="Measured")
        lines!(ax, desiredMotorValues, color=:green, label="Desired")
        fig[1, 2] = Legend(fig, ax, "Freq", framevisible = false)
        makie_draw(plotCanvasObject, fig)
    
        global update_plot = function()
            time = running_time_in_seconds()
            xlims!(ax, (time - TimeDisplayWindow, time))
            notify(desiredMotorValues)
            draw(plotCanvasObject)
        end
    end
    
    @async showall(win)
    @async Gtk.gtk_main()
    
    while true
        if isactiveserial() watch_uart()
        else
            close_port()
            set_gtk_property!(devicePortSelect, "active", -1)
        end
        yield()
        sleep(1E-2)
    end
end

end

using .SpinorGUI

#SpinorGUI.compile_sysimage()
SpinorGUI.launch_gui()