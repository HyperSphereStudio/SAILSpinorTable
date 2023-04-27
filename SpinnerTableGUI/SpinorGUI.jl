using JuliaSAILGUI, Dates, DataFrames, Gtk, CairoMakie, Observables, LibSerialPort, CSV

const DeviceBaudRate = 115200
const GyroBaudRate = 9600
const InitMotorSpeed = 75
const TimeDisplayWindow = 10
const SampleRate = .25

comp_println(x...) = println("[Comp]:", x...)

function launch_gui()
    motorFreqLabel, portTimer, update_plot = (nothing, nothing, nothing)
    currentMotorValue = 0
    file = ""
    df = DataFrame(Time=Float32[], IR=Float32[], Gyro=Float32[], Desired=Float32[])

    builder = GtkBuilder(filename="gui.glade")
    win, devicePortSelect, gyroPortSelect, motorFreqLabel, plotBox, motorFreq = 
        map(v->builder[v], ["window", "devicePorts", "gyroPorts", "realMotorFreq", "plotBox", "motorFreq"])
    
    deviceSerial = MicroControllerPort(:device, DeviceBaudRate, on_disconnect=()->set_gtk_property!(devicePortSelect, "active", -1))
    gyroSerial = MicroControllerPort(:gyro, GyroBaudRate, on_disconnect=()->set_gtk_property!(serialPortSelect, "active", -1))
    
    runningTime = now()
    cols = 4
    portSelectors = [devicePortSelect, gyroPortSelect]
    ports = [deviceSerial, gyroSerial]
    controlFreq = 0.0
    measurements = [0.0 for i in 1:cols]

    time = 1; ir = 2; gyro = 3; desired = 4
    running_time_in_seconds() = Dates.value(now() - runningTime) * 1E-3
    measure!(name, v) = measurements[name] = v
    measure(name) = measurements[name]

    motorSampleTimer = Timer(function(_)
                                currentMotorValue > 0 || return
                                measure!(time, running_time_in_seconds())
                                push!(df, measurements)
                                update_plot()
                                GAccessor.markup(motorFreqLabel, "<b>Measured: $v Hz</b>")
                             end, 5; interval=SampleRate)

    function set_motor_speed(v)
        check(deviceSerial) || (println("Motor Port Not Open!"); return)
        currentMotorValue = clamp(v, 0, 127)
        comp_println("Set Motor Speed $v")
        write(deviceSerial, UInt8(currentMotorValue)) 
    end

    function update_speed(v)
        measure!(desired, v)
        v == 0 && set_motor_speed(0) 
        @sigatom @async GAccessor.value(motorFreq) != v && GAccessor.value(motorFreq, v)
    end

    function reset()
        update_speed(0)
        empty!(df)
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
                foreach(p -> push!(ps, p), portList) 
            end, eachindex(ports))
    end

    set_port(port, selector) = setport(port, gtk_to_string(GAccessor.active_text(selector))) && reset()

    function update_motor(measuredFreq)
        desFreq = measure(desired)
        currentMotorValue += cmp(desFreq, controlFreq)
        comp_println("Measured: $controlFreq Hz. Desired: $desFreq Hz")
        set_motor_speed(currentMotorValue)
    end

    function save_to_file()
        println("Saving Run To File to $file")
        isfile(file) && CSV.write(file, df)
    end

    begin #Setup GUI window
        signal_connect(_-> exit(), win, :destroy)
        signal_connect(_-> set_port(deviceSerial, devicePortSelect), devicePortSelect, "changed")
        signal_connect(_-> set_port(gyroSerial, gyroPortSelect), gyroPortSelect, "changed")
        signal_connect(wid->file = gtk_to_string(GAccessor.filename(GtkFileChooser(wid))), builder["fileSelect"], "file-set")
        signal_connect(_-> save_to_file(file), builder["save"], "clicked")               
        signal_connect(_-> update_speed(GAccessor.value(motorFreq)), motorFreq, "value-changed")
        signal_connect(_-> start(), builder["start"], "clicked")
        signal_connect(_-> update_speed(0), builder["reset"], "clicked")
        signal_connect(function fire_item_release(_)
                           comp_println("Releasing!")
                           comp_println("Stopping Release")
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
        
        notification_hook = Observable(df.IR)   
        lines!(ax, notification_hook, color=:blue, label="IR Measured")
        lines!(ax, Observable(df.Gyro), color=:red, label="Gyro Measured")
        lines!(ax, Observable(df.Desired), color=:green, label="Desired")
        fig[1, 2] = Legend(fig, ax, "Freq", framevisible = false)
        makie_draw(plotCanvasObject, fig)
    
        update_plot = function()
            time = running_time_in_seconds()
            xlims!(ax, (time - TimeDisplayWindow, time))
            notify(notification_hook)
            draw(plotCanvasObject)
        end
    end
    
    showall(win)
    @async Gtk.gtk_main()

    atexit(() -> set_motor_speed(0)) #Turn the Table off if julia exits
    
    while true
        isopen(deviceSerial) && JuliaSAILGUI.readlines(deviceSerial) do str
            if startswith(str, "Freq")
                irFreq = parse(Float64, str[5:end])
                measure!(ir, irFreq)
                update_motor(irFreq) #Have IR Control Motor Speed
            else
                println("[Device]:$str")
            end
        end
        
        isopen(gyroSerial) && JuliaSAILGUI.readlines(gyroSerial) do str
            data = split(str, ",")
            if length(data) > 2
                packet_num, Gx_DPS, Gy_DPS, Gz_DPS, Ax_g, Ay_g, Az_g, Mx_Gauss, My_Gauss, Mz_Gauss = parse.(Float64, data)
                Gx_Hz, Gy_Hz, Gz_Hz = (Gx_DPS, Gy_DPS, Gz_DPS) ./ 360
                
                measure!(gyro, Gz_Hz)
                #update_motor(Gz_Hz) #Controlled via Gyro
            else 
                println("[Gyro]:$str")
            end
        end

        sleep(1E-2)
        yield()
    end
end

launch_gui()