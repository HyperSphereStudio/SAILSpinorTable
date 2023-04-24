module SpinorGUI

using Dates
include("MicroControllerPort.jl")
include("JuliaGUI.jl")

const DeviceBaudRate = 115200
const SensorBaudRate = 9600
const InitMotorSpeed = 75
const TimeDisplayWindow = 10

comp_println(x...) = println("[Comp]:", x...)

function launch_gui()
    desiredMotorFreq = 0.0
    sensorMotorFreq = 0.0
    currentMotorValue = 0
    motorFreqLabel = nothing
    saveFile = ""
    IRmeasuredMotorValues = Observable(Point2f[])
    SensormeasuredMotorValues = Observable(Point2f[])
    desiredMotorValues = Observable(Point2f[])
    update_plot = nothing
    runningTime = now()
    builder = GtkBuilder(filename="gui.glade")
    win = builder["window"]
    devicePortSelect = builder["devicePorts"]
    sensorPortSelect = builder["sensorPorts"]
    motorFreqLabel = builder["realMotorFreq"]
    plotBox = builder["plotBox"]
    motorFreq = builder["motorFreq"]
    portTimer = nothing

    deviceSerial = MicroControllerPort(:device, DeviceBaudRate, on_disconnect=()->set_gtk_property!(devicePortSelect, "active", -1))
    sensorSerial = MicroControllerPort(:sensor, SensorBaudRate, on_disconnect=()->set_gtk_property!(serialPortSelect, "active", -1))
    portSelectors = [devicePortSelect, sensorPortSelect]
    ports = [deviceSerial, sensorSerial]

    running_time_in_seconds() = Dates.value(now() - runningTime) * 1E-3

    function set_motor_speed(v)
        check(deviceSerial) || (println("Motor Port Not Open!"); return)
        currentMotorValue = clamp(v, 0, 127)
        comp_println("Set Motor Speed $v")
        write(deviceSerial, UInt8(currentMotorValue)) 
    end

    function update_speed(v)
        desiredMotorFreq = v
        desiredMotorFreq == 0 && set_motor_speed(0)
        @sigatom @async GAccessor.value(motorFreq) != v && GAccessor.value(motorFreq, v)
    end

    function reset()
        update_speed(0)
        empty!(IRmeasuredMotorValues[])
        empty!(desiredMotorValues[])
        empty!(SensormeasuredMotorValues[])
        runningTime = now()
        update_plot()
    end

    function start()
        reset()
        set_motor_speed(InitMotorSpeed)
        update_speed(1.5)
    end

    function update_com_ports()
        portList = get_port_list()
        foreach(i -> check(ports[i]) || 
            begin 
                ps = portSelectors[i] 
                empty!(ps)
                foreach(p->push!(ps, p), portList) 
            end, eachindex(ports))
    end

    function set_port(port, selector)
        name = gtk_to_string(GAccessor.active_text(selector))
        setport(port, name) && reset()
    end

    begin #Setup GUI window
        signal_connect(_-> exit(), win, :destroy)
        signal_connect(_-> set_port(deviceSerial, devicePortSelect), devicePortSelect, "changed")
        signal_connect(_-> set_port(sensorSerial, sensorPortSelect), sensorPortSelect, "changed")
        signal_connect(wid -> saveFile = gtk_to_string(GAccessor.filename(GtkFileChooser(wid))), builder["fileSelect"], "file-set")
        signal_connect(function save_to_file(_)
                            println("Saving Run To File to $saveFile")
                            if isfile(saveFile)
                                open(saveFile, "w") do f 
                                    mV = IRmeasuredMotorValues[]
                                    dV = desiredMotorValues[]
                                    sV = SensormeasuredMotorValues[]
                                    Base.write(f, "Time[S] IRMeasured[Hz] Desired[Hz] Sensor[Hz]\r\n")
                                    foreach(i -> Base.write(f, "$(mV[i][1]) $(mV[i][2]) $(dV[i][2]) $(sV[i][2])\r\n"), eachindex(mV))
                                end
                            end 
                        end, builder["save"], "clicked")               
        signal_connect(_-> update_speed(GAccessor.value(motorFreq)), motorFreq, "value-changed")
        signal_connect(_-> start(), builder["start"], "clicked")
        signal_connect(_-> update_speed(0), builder["reset"], "clicked")
        signal_connect(function fire_item_release(_)
                           comp_println("Releasing!")
                           write(deviceSerial, UInt8(128))
                           sleep(.5)
                           comp_println("Stopping Release")
                           write(deviceSerial, UInt8(129))
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
        lines!(ax, IRmeasuredMotorValues, color=:blue, label="IR Measured")
        lines!(ax, SensormeasuredMotorValues, color=:red, label="Sensor Measured")
        lines!(ax, desiredMotorValues, color=:green, label="Desired")
        fig[1, 2] = Legend(fig, ax, "Freq", framevisible = false)
        makie_draw(plotCanvasObject, fig)
    
        update_plot = function()
            time = running_time_in_seconds()
            xlims!(ax, (time - TimeDisplayWindow, time))
            notify(desiredMotorValues)
            draw(plotCanvasObject)
        end
    end
    
    @async showall(win)
    @async Gtk.gtk_main()
    
    while true
        isopen(deviceSerial) && readlines(deviceSerial) do str
            if startswith(str, "Freq")
                IRmeasuredMotorFreq = parse(Float64, str[5:end])
                currentMotorValue += cmp(desiredMotorFreq, IRmeasuredMotorFreq)
                comp_println("Measured: $IRmeasuredMotorFreq Freq. Desire: $desiredMotorFreq Freq")
                set_motor_speed(currentMotorValue)
                time = running_time_in_seconds()
                push!(SensormeasuredMotorValues[], (time, sensorMotorFreq))
                push!(IRmeasuredMotorValues[], (time, IRmeasuredMotorFreq))
                push!(desiredMotorValues[], (time, desiredMotorFreq))
                update_plot()
                GAccessor.markup(motorFreqLabel, "<b>Measured: $IRmeasuredMotorFreq Hz</b>")
            else
                println("[Device]:$str")
            end
        end
        
        isopen(sensorSerial) && readlines(sensorSerial) do str
            data = split(str, ",")
            if length(data) > 2
                packet_num, Gx_DPS, Gy_DPS, Gz_DPS, Ax_g, Ay_g, Az_g, Mx_Gauss, My_Gauss, Mz_Gauss = parse.(Float64, data)
                to_hz(x) = x / 360
                Gx_Hz, Gy_Hz, Gz_Hz = to_hz.((Gx_DPS, Gy_DPS, Gz_DPS))
                
                sensorMotorFreq = Gz_Hz
                println(sensorMotorFreq)
            else 
                println("[Sensor]:$str")
            end
        end

        yield()
        sleep(1E-2)
    end
end
end

using .SpinorGUI

if length(ARGS) > 0
    (ARGS[1] == "sys_image") && SpinorGUI.compile_sysimage()
else
    SpinorGUI.launch_gui()
end
