using JuliaSAILGUI
using Dates
using JuliaSAILGUI: DataFrames, Gtk4, Observables, LibSerialPort, CSV, GLMakie

const DeviceBaudRate = 115200
const GyroBaudRate = 9600
const InitMotorSpeed = 85
const TimeDisplayWindow = 10
const SampleRate = .25
const MaxMotorCurrent = 5.0 #A
const InitMotorVoltage = 20 #V

comp_println(x...) = println("[Comp]:", x...)

RunningTime = now()
runningtime() = Dates.value(now() - RunningTime) * 1E-3

function create_plot(df, plot, gui)
    set_theme!(theme_hypersphere())
    fig = Figure()

    rpm_ax = Axis(fig[1:2, 1], xlabel="Time [s]", ylabel="Freq [Hz]", title="Spinner Rate")  
    power_ax = Axis(fig[3, 1], xlabel="Time [s]", ylabel="Power [W]", title="Power") 
    
    time_data = Observable(df.Time) 
    on(time_data) do v
        time = runningtime()
        autolimits!(rpm_ax)
        autolimits!(power_ax)
        xlims!(rpm_ax, (time - TimeDisplayWindow, time))
        xlims!(power_ax, (time - TimeDisplayWindow, time))
    end
    gui[:TimeData] = time_data
    
    lines!(rpm_ax, time_data, df.IR, color=:blue, label="IR Measured")
    lines!(rpm_ax, time_data, df.Gyro, color=:red, label="Gyro Measured")
    lines!(rpm_ax, time_data, df.Desired, color=:green, label="Desired")
    fig[1:2, 2] = Legend(fig, rpm_ax, "Freq", framevisible = false)

    lines!(power_ax, time_data, df.InputMotorPower, color=:yellow, label="Input Motor Power")
    fig[3, 2] = Legend(fig, power_ax, "Power", framevisible = false)
    
    screen = GtkGLScreen(plot)
    display(screen, fig)
end

function create_gui(df, motorVoltage, motorControl, motorSpeed)
    gui = Dict{Symbol, Any}()
    back_box = GtkBox(:v, 50)

    select_box = GtkBox(:v)
    device_port_select = GtkComboBoxText()
    gyro_port_select = GtkComboBoxText()
    motor_voltage_entry = GtkEntry(input_purpose = Gtk4.InputPurpose_NUMBER)
    motor_control_entry = GtkEntry(input_purpose = Gtk4.InputPurpose_NUMBER)

    Observables.ObservablePair(motor_voltage_entry, motorVoltage)
    Observables.ObservablePair(motor_control_entry, motorControl)

    instrument_control_select = GtkComboBoxText()
    append!(instrument_control_select, "Gyro-Controlled", "IR-Controlled", "Manual-Controlled")
    instrument_control_select.active = 0
    append!(select_box, makewidgetswithtitle([device_port_select, gyro_port_select, instrument_control_select, motor_voltage_entry], ["Device Port", "Gyro Port", "Mode", "Motor Voltage [V]"]))
    append!(gui, :DevicePort => device_port_select, :GyroPort => gyro_port_select, :Instrument => instrument_control_select)

    control_box = GtkBox(:v)
    play_button = buttonwithimage("Play", GtkImage(icon_name = "media-playback-start"))
    stop_button = buttonwithimage("Stop", GtkImage(icon_name = "process-stop"))
    save_button = buttonwithimage("Save", GtkImage(icon_name = "document-save-as"))
    append!(gui, :Play => play_button, :Stop => stop_button, :Save => save_button)
    append!(control_box, play_button, stop_button, save_button, motor_control_entry)

    motor_speed_adjuster = GtkAdjustment(0, 0, 11, .25, 1, 0)
    motor_speed_spin_button = GtkSpinButton(motor_speed_adjuster, .1, 3; update_policy = Gtk4.SpinButtonUpdatePolicy_IF_VALID, orientation = Gtk4.Orientation_VERTICAL)
    Observables.ObservablePair(motor_speed_adjuster, motorSpeed)

    release_button = GtkButton("Release")

    append!(back_box, select_box, makewidgetswithtitle([control_box, motor_speed_spin_button], ["Control", "Motor Frequency"])..., release_button)
    append!(gui, :Release => release_button, :MotorControl => motor_speed_adjuster)

    plot = GtkGLArea(hexpand=true, vexpand=true)

    motor_freq_label = GtkLabel(""; hexpand=true)
    Gtk4.markup(motor_freq_label, "<b>Motor Frequency:0 Hz</b>")

    win = GtkWindow("Spinner Table")
    grid = GtkGrid(column_homogeneous=true)
    win[] = grid
    grid[1, 1:6] = back_box
    grid[2:7, 1:6] = plot
    grid[2:7, 7] = motor_freq_label
    display_gui(win; blocking=false)

    create_plot(df, plot, gui)

    append!(gui, :Window => win, :Freq => motor_freq_label)

    return gui
end

function gui_main()
    motorFreqLabel, portTimer, motorSampleTimer = fill(nothing, 3)
    df = DataFrame(Time=Float32[], Gyro=Float32[], IR=Float32[], Desired=Float32[], InputMotorPower=Float32[])
    measurements = zeros(size(df, 2))
    Time, Gyro, IR, Desired, InputMotorPower = 1:size(df, 2)

    motorVoltage = Observable(Float64(InitMotorVoltage))
    motorControl = Observable(0)
    motorSpeed = Observable(0.0)

    measure!(name, v) = measurements[name] = v
    measure(name) = measurements[name]
    gui = create_gui(df, motorVoltage, motorControl, motorSpeed)

    deviceSerial = MicroControllerPort(:Device, DeviceBaudRate, DelimitedReader("\r\n"), on_disconnect = () -> gui[:DevicePort].active = -1)
    gyroSerial = MicroControllerPort(:Gyro, GyroBaudRate, DelimitedReader("\r\n"), on_disconnect = () -> gui[:GyroPort].active = -1)
    
    portSelectors = [gui[:DevicePort], gui[:GyroPort]]
    ports = [deviceSerial, gyroSerial]    

    getinputmotorpower() = motorControl[] / 127 * motorVoltage[] * MaxMotorCurrent

    function reset()
        global RunningTime
        motorSpeed[] = 0
        empty!(df)
        RunningTime = now()
        notify(gui[:TimeData])
    end

    function start()
        isopen(deviceSerial) || (println("Motor Port Not Open!"); return)
        reset()
        motorSampleTimer = Timer(0; interval=SampleRate) do t
                                    measure!(Time, runningtime())
                                    push!(df, measurements)
                                    notify(gui[:TimeData])
                                    Gtk4.markup(gui[:Freq], "<b>Measured: $(measure(Desired)) Hz</b>")
                                end
        motorControl[] = InitMotorSpeed                    
        motorSpeed[] = 1.5
    end

    function update_com_ports()
        portList = get_port_list()
        foreach(eachindex(ports)) do i
                    isopen(ports[i]) && return
                    ps = portSelectors[i] 
                    empty!(ps)
                    append!(ps, portList)
                end
    end

    set_port(port, selector) = setport(port, selector[]) && reset()

    Timer(0; interval=1) do t 
            v = motorControl[]
            measurement_mode = gui[:Instrument].active
            (v == 0 || measurement_mode == 2) && return #Skip on manual mode or not moving
            m = measure(measurement_mode + 2)
            v += cmp(measure(Desired), m)
            comp_println("Measured: $m Hz. Desired: $(measure(Desired)) Hz")
            motorControl[] = v
        end

    function save_to_file(file)
        endswith(file, ".csv") || (file *= ".csv")
        println("Saving Run To File to $file")
        CSV.write(file, df)
    end

    signal_connect(_-> (motorControl[] = 0; exit(0)), gui[:Window], :close_request)
    on(motorControl) do v
        isopen(deviceSerial) || (println("Motor Port Not Open!"); return)
        v = clamp(v, 0, 126)
        measure!(InputMotorPower, getinputmotorpower())
        comp_println("Set Motor Speed $v")
        write(deviceSerial, UInt8(v)) 
        motorControl.val = v                                            #Set without notification
        v == 0 && isopen(motorSampleTimer) && close(motorSampleTimer)   #Stop Sampling
    end
    on(motorSpeed) do v
        measure!(Desired, v)
        v == 0 && (motorControl[] = 0)
    end
    on(w -> @async(set_port(deviceSerial, w)), gui[:DevicePort])
    on(w -> @async(set_port(gyroSerial, w)), gui[:GyroPort]) #Async to put task at end of main
    on(_ -> save_dialog(save_to_file, "Save data file as...", nothing, ["*.csv"]), gui[:Save])
    on(_ -> @async(start()), gui[:Play])
    on(_ -> @async(motorSpeed[] = 0), gui[:Stop])
    on(gui[:Release]) do w
        comp_println("Releasing!")
        comp_println("Stopping Release")
    end
          
    portTimer = Timer(_ -> update_com_ports(), 0; interval=2)
    atexit(() -> motorControl[] = 0)     #Turn the Table off if julia exits
    
    while true #GUI Loop
        try

            isopen(deviceSerial) && readport(deviceSerial) do str
                if startswith(str, "Freq")
                    (measure(Desired) != 0) || return
                    irFreq = parse(Float64, str[5:end])
                    measure!(IR, irFreq)
                else
                    println("[Device]:$str")
                end
            end
        
            isopen(gyroSerial) && readport(gyroSerial) do str
                data = split(str, ",")
                if length(data) > 2
                    (measure(Desired) != 0) || return
                    packet_num, Gx_DPS, Gy_DPS, Gz_DPS, Ax_g, Ay_g, Az_g, Mx_Gauss, My_Gauss, Mz_Gauss = parse.(Float64, data)
                    Gx_Hz, Gy_Hz, Gz_Hz = (Gx_DPS, Gy_DPS, Gz_DPS) ./ 360
                    measure!(Gyro, Gz_Hz)
                else
                    println("[Gyro]:$str")
                end
            end

        catch e
            showerror(stdout, e)
            close(deviceSerial)
            close(gyroSerial)
        end
        sleep(1E-2)
    end
end

gui_main()