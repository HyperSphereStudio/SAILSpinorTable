using JuliaSAILGUI, Dates, DataFrames, Gtk4, Observables, LibSerialPort, CSV, GLMakie

const DeviceBaudRate = 115200
const GyroBaudRate = 9600
const InitMotorSpeed = 75
const TimeDisplayWindow = 10
const SampleRate = .25
const MaxMotorCurrent = 2.5 #A
const InitMotorVoltage = 21 #V

comp_println(x...) = println("[Comp]:", x...)

function launch_gui()
    motorFreqLabel, portTimer, update_plot, motorSampleTimer = (nothing, nothing, nothing, nothing)
    currentMotorValue = 0
    df = DataFrame(Time=Float32[], IR=Float32[], Gyro=Float32[], Desired=Float32[], InputMotorPower=Float32[])
    cols = size(df, 2)
    measurements = zeros(cols)
    Time, IR, Gyro, Desired, InputMotorPower = 1:cols
    runningTime = now()
    motorVoltage = InitMotorVoltage

    running_time_in_seconds() = Dates.value(now() - runningTime) * 1E-3
    measure!(name, v) = measurements[name] = v
    measure(name) = measurements[name]

    back_box = GtkBox(:v, 50)

    select_box = GtkBox(:v)
    devicePortSelect = GtkComboBoxText()
    gyroPortSelect = GtkComboBoxText()
    motor_voltage_entry = GtkEntry(input_purpose = Gtk4.InputPurpose_NUMBER)
    motor_voltage_entry[] = motorVoltage
    append!(select_box, makewidgetwithtitle(devicePortSelect, "Device Port"), makewidgetwithtitle(gyroPortSelect, "Gyro Port"), makewidgetwithtitle(motor_voltage_entry, "Motor Voltage [V]"))

    control_box = GtkBox(:v)
    play_button = buttonwithimage("Play", GtkImage(icon_name = "media-playback-start"))
    stop_button = buttonwithimage("Stop", GtkImage(icon_name = "process-stop"))
    save_button = buttonwithimage("Save", GtkImage(icon_name = "document-save-as"))

    append!(control_box, play_button, stop_button, save_button)

    motor_control_adjuster = GtkAdjustment(0, 0, 11, .25, 1, 0)
    motor_control = GtkSpinButton(motor_control_adjuster, .1, 3)
    motor_control.update_policy = Gtk4.SpinButtonUpdatePolicy_IF_VALID
    motor_control.orientation = Gtk4.Orientation_VERTICAL
   
    release_button = GtkButton("Release")

    append!(back_box, select_box, makewidgetwithtitle(control_box, "Control"), makewidgetwithtitle(motor_control, "Motor Frequency"), release_button)    

    plot = GtkGLArea(hexpand=true, vexpand=true)

    motor_freq_label = GtkLabel("")
    motor_freq_label.hexpand = true
    Gtk4.markup(motor_freq_label, "<b>Motor Frequency:0 Hz</b>")

    win = GtkWindow("Spinner Table")
    grid = GtkGrid(column_homogeneous=true)
    win[] = grid
    grid[1, 1:6] = back_box
    grid[2:7, 1:6] = plot
    grid[2:7, 7] = motor_freq_label

    deviceSerial = MicroControllerPort(:device, DeviceBaudRate, DelimitedReader("\r\n"), on_disconnect = () -> devicePortSelect.active = -1)
    gyroSerial = MicroControllerPort(:gyro, GyroBaudRate, DelimitedReader("\r\n"), on_disconnect = () -> gyroPortSelect.active = -1)
    
    portSelectors = [devicePortSelect, gyroPortSelect]
    ports = [deviceSerial, gyroSerial]

    function motor_timer_callback(_)
        measure!(Time, running_time_in_seconds())
        push!(df, measurements)
        update_plot()
        Gtk4.markup(motor_freq_label, "<b>Measured: $(measure(Desired)) Hz</b>")
    end

    getinputmotorpower() = currentMotorValue / 127 * motorVoltage * MaxMotorCurrent

    function set_motor_native_speed(v)
        isopen(deviceSerial) || (println("Motor Port Not Open!"); return)
        currentMotorValue = clamp(v, 0, 127)
        measure!(InputMotorPower, getinputmotorpower())
        comp_println("Set Motor Speed $v")
        write(deviceSerial, UInt8(currentMotorValue)) 
    end

    is_active() = measure(Desired) != 0

    function update_speed(v)
        measure!(Desired, v)
        if v == 0
            set_motor_native_speed(0)
            isopen(motorSampleTimer) && close(motorSampleTimer)
        end
        @async motor_control_adjuster[] != v && (motor_control_adjuster[] = v)
    end

    function reset()
        update_speed(0)
        empty!(df)
        runningTime = now()
        update_plot()
    end

    function start()
        isopen(deviceSerial) || (println("Motor Port Not Open!"); return)
        reset()
        motorSampleTimer = Timer(motor_timer_callback, 0; interval=SampleRate)
        set_motor_native_speed(InitMotorSpeed)
        update_speed(1.5)
    end

    function update_com_ports()
        portList = get_port_list()
        foreach(function (i) 
                    isopen(ports[i]) && return
                    ps = portSelectors[i] 
                    empty!(ps)
                    foreach(p -> push!(ps, p), portList) 
                end, eachindex(ports))
    end

    set_port(port, selector) = setport(port, selector[]) && reset()

    function update_motor(measuredFreq)
        currentMotorValue += cmp(measure(Desired), measuredFreq)
        comp_println("Measured: $measuredFreq Hz. Desired: $(measure(Desired)) Hz")
        set_motor_native_speed(currentMotorValue)
    end

    function save_to_file(file)
        if isfile(file)
            println("Saving Run To File to $file")
            CSV.write(file, df)
        end
    end

    begin #Setup GUI window
        signal_connect(_-> exit(), win, :close_request)
        on(w -> set_port(deviceSerial, w), devicePortSelect)
        on(w -> set_port(gyroSerial, w), gyroPortSelect)
        on(_-> save_dialog(save_to_file, "Save data file as...", nothing, ["*.csv"]), save_button)
        on(w -> update_speed(w[]), motor_control_adjuster)
        on(_ -> start(), play_button)
        on(w -> motorVoltage = w[Float64], motor_voltage_entry)
        on(_ -> update_speed(0), stop_button)
        on(function fire_item_release(_)
            comp_println("Releasing!")
            comp_println("Stopping Release")
           end, release_button)
        update_com_ports()               
        portTimer = Timer(_->update_com_ports(), 1; interval=2)
    end

   begin  #Create Plot
        set_theme!(theme_hypersphere())
        fig = Figure()

        rpm_ax = Axis(fig[1:2, 1], xlabel="Time [s]", ylabel="Freq [Hz]", title="Spinner Rate")  
        
        notification_hook = Observable(df.Time)   
        lines!(rpm_ax, notification_hook, Observable(df.IR), color=:blue, label="IR Measured")
        lines!(rpm_ax, notification_hook, Observable(df.Gyro), color=:red, label="Gyro Measured")
        lines!(rpm_ax, notification_hook, Observable(df.Desired), color=:green, label="Desired")
        fig[1:2, 2] = Legend(fig, rpm_ax, "Freq", framevisible = false)

        power_ax = Axis(fig[3, 1], xlabel="Time [s]", ylabel="Power [W]", title="Power") 
        lines!(power_ax, notification_hook, Observable(df.InputMotorPower), color=:yellow, label="Input Motor Power")
        fig[3, 2] = Legend(fig, power_ax, "Power", framevisible = false)
        
        screen = GtkGLScreen(plot)
        display(screen, fig)
    
        update_plot = function()
            time = running_time_in_seconds()
            autolimits!(rpm_ax)
            autolimits!(power_ax)
            xlims!(rpm_ax, (time - TimeDisplayWindow, time))
            xlims!(power_ax, (time - TimeDisplayWindow, time))
            notify(notification_hook)
        end
    end

    display_gui(win; blocking=false)

    atexit(() -> set_motor_native_speed(0)) #Turn the Table off if julia exits
    
    while true
        isopen(deviceSerial) && readport(deviceSerial) do str
            if startswith(str, "Freq")
                is_active() || return
                irFreq = parse(Float64, str[5:end])
                measure!(IR, irFreq)
                update_motor(irFreq) #Have IR Control Motor Speed
            else
                println("[Device]:$str")
            end
        end
        
        isopen(gyroSerial) && readport(gyroSerial) do str
            data = split(str, ",")
            if length(data) > 2
                is_active() || return
                packet_num, Gx_DPS, Gy_DPS, Gz_DPS, Ax_g, Ay_g, Az_g, Mx_Gauss, My_Gauss, Mz_Gauss = parse.(Float64, data)
                Gx_Hz, Gy_Hz, Gz_Hz = (Gx_DPS, Gy_DPS, Gz_DPS) ./ 360
                
                measure!(Gyro, Gz_Hz)
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