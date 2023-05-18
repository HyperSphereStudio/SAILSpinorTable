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

function create_plot(df, plot, running_time_in_seconds)
    set_theme!(theme_hypersphere())
    fig = Figure()

    rpm_ax = Axis(fig[1:2, 1], xlabel="Time [s]", ylabel="Freq [Hz]", title="Spinner Rate")  
    
    time_data = Observable(df.Time)   
    lines!(rpm_ax, time_data, Observable(df.IR), color=:blue, label="IR Measured")
    lines!(rpm_ax, time_data, Observable(df.Gyro), color=:red, label="Gyro Measured")
    lines!(rpm_ax, time_data, Observable(df.Desired), color=:green, label="Desired")
    fig[1:2, 2] = Legend(fig, rpm_ax, "Freq", framevisible = false)

    power_ax = Axis(fig[3, 1], xlabel="Time [s]", ylabel="Power [W]", title="Power") 
    lines!(power_ax, time_data, Observable(df.InputMotorPower), color=:yellow, label="Input Motor Power")
    fig[3, 2] = Legend(fig, power_ax, "Power", framevisible = false)
    
    screen = GtkGLScreen(plot)
    display(screen, fig)

    return function() #Update Callback
        time = running_time_in_seconds()
        autolimits!(rpm_ax)
        autolimits!(power_ax)
        xlims!(rpm_ax, (time - TimeDisplayWindow, time))
        xlims!(power_ax, (time - TimeDisplayWindow, time))
        notify(time_data) #Changes all plots
    end
end

function create_gui(df, running_time, motor_voltage, motor_control_value)
    gui = Dict{Symbol, Any}()
    back_box = GtkBox(:v, 50)

    select_box = GtkBox(:v)
    devicePortSelect = GtkComboBoxText()
    gyroPortSelect = GtkComboBoxText()

    instrument_control_select = GtkComboBoxText()
    append!(instrument_control_select, "Gyro-Controlled", "IR-Controlled", "Manual-Controlled")
    instrument_control_select.active = 0
    append!(select_box, makewidgetswithtitle([devicePortSelect, gyroPortSelect, instrument_control_select, motor_voltage], ["Device Port", "Gyro Port", "Mode", "Motor Voltage [V]"]))
    append!(gui, :DevicePort => devicePortSelect, :GyroPort => gyroPortSelect, :Instrument => instrument_control_select)

    control_box = GtkBox(:v)
    play_button = buttonwithimage("Play", GtkImage(icon_name = "media-playback-start"))
    stop_button = buttonwithimage("Stop", GtkImage(icon_name = "process-stop"))
    save_button = buttonwithimage("Save", GtkImage(icon_name = "document-save-as"))
    append!(gui, :Play => play_button, :Stop => stop_button, :Save => save_button)
    append!(control_box, play_button, stop_button, save_button, motor_control_value)

    motor_control_adjuster = GtkAdjustment(0, 0, 11, .25, 1, 0)
    motor_control = GtkSpinButton(motor_control_adjuster, .1, 3; update_policy = Gtk4.SpinButtonUpdatePolicy_IF_VALID, orientation = Gtk4.Orientation_VERTICAL)
   
    release_button = GtkButton("Release")

    append!(back_box, select_box, makewidgetswithtitle([control_box, motor_control], ["Control", "Motor Frequency"])..., release_button)
    append!(gui, :Release => release_button, :MotorControl => motor_control_adjuster)

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

    append!(gui, :Window => win, :Update => create_plot(df, plot, running_time), :Freq => motor_freq_label)

    return gui
end

function gui_main()
    motorFreqLabel, portTimer, motorSampleTimer = fill(nothing, 3)
    df = DataFrame(Time=Float32[], Gyro=Float32[], IR=Float32[], Desired=Float32[], InputMotorPower=Float32[])
    measurements = zeros(size(df, 2))
    Time, Gyro, IR, Desired, InputMotorPower = 1:size(df, 2)
    runningTime = now()

    motor_voltage = GtkValueEntry{Float64}(InitMotorVoltage; input_purpose = Gtk4.InputPurpose_NUMBER)
    motor_control_value = GtkValueEntry{Int}(0; input_purpose = Gtk4.InputPurpose_NUMBER)

    running_time_in_seconds() = Dates.value(now() - runningTime) * 1E-3
    measure!(name, v) = measurements[name] = v
    measure(name) = measurements[name]
    gui = create_gui(df, running_time_in_seconds, motor_voltage, motor_control_value)

    deviceSerial = MicroControllerPort(:Device, DeviceBaudRate, DelimitedReader("\r\n"), on_disconnect = () -> gui[:DevicePort].active = -1)
    gyroSerial = MicroControllerPort(:Gyro, GyroBaudRate, DelimitedReader("\r\n"), on_disconnect = () -> gui[:GyroPort].active = -1)
    
    portSelectors = [gui[:DevicePort], gui[:GyroPort]]
    ports = [deviceSerial, gyroSerial]    

    getinputmotorpower() = motor_control_value[] / 127 * motor_voltage[] * MaxMotorCurrent

    function set_motor_native_speed(v, set_text=true)
        isopen(deviceSerial) || (println("Motor Port Not Open!"); return)
        v = clamp(v, 0, 126)
        measure!(InputMotorPower, getinputmotorpower())
        comp_println("Set Motor Speed $v")
        set_text && (motor_control_value[] = v)
        write(deviceSerial, UInt8(v)) 
    end

    function update_speed(v, set_text=true)
        measure!(Desired, v)
        if v == 0
            set_motor_native_speed(0)
            isopen(motorSampleTimer) && close(motorSampleTimer)
        end
        set_text && @async(gui[:MotorControl][] = v)
    end

    function reset()
        update_speed(0)
        empty!(df)
        runningTime = now()
        gui[:Update]()
    end

    function start()
        isopen(deviceSerial) || (println("Motor Port Not Open!"); return)
        reset()
        motorSampleTimer = Timer(function motor_timer(_)
                                    measure!(Time, running_time_in_seconds())
                                    push!(df, measurements)
                                    gui[:Update]()
                                    Gtk4.markup(gui[:Freq], "<b>Measured: $(measure(Desired)) Hz</b>")
                                end, 0; interval=SampleRate)
        set_motor_native_speed(InitMotorSpeed)
        update_speed(1.5)
    end

    function update_com_ports()
        portList = get_port_list()
        foreach(function (i) 
                    isopen(ports[i]) && return
                    ps = portSelectors[i] 
                    empty!(ps)
                    append!(ps, portList)
                end, eachindex(ports))
    end

    set_port(port, selector) = setport(port, selector[]) && reset()

    Timer(function motor_update(_)
            v = motor_control_value[]
            measurement_mode = gui[:Instrument].active
            (v == 0 || measurement_mode == 2) && return #Skip on manual mode or not moving
            m = measure(measurement_mode + 2)
            v += cmp(measure(Desired), m)
            comp_println("Measured: $m Hz. Desired: $(measure(Desired)) Hz")
            set_motor_native_speed(v)
        end, 0; interval=1)

    function save_to_file(file)
        endswith(file, ".csv") || (file *= ".csv")
        println("Saving Run To File to $file")
        CSV.write(file, df)
    end

    signal_connect(_-> (set_motor_native_speed(0); exit(0)), gui[:Window], :close_request)
    on(w -> @async(set_port(deviceSerial, w)), gui[:DevicePort])
    on(w -> @async(set_port(gyroSerial, w)), gui[:GyroPort]) #Async to put task at end of main
    on(w -> set_motor_native_speed(w[], false), motor_control_value)
    on(_ -> save_dialog(save_to_file, "Save data file as...", nothing, ["*.csv"]), gui[:Save])
    on(w -> update_speed(w[], false), gui[:MotorControl])
    on(_ -> start(), gui[:Play])
    on(_ -> update_speed(0), gui[:Stop])
    on(function fire_item_release(_)
            comp_println("Releasing!")
            comp_println("Stopping Release")
        end, gui[:Release])
    update_com_ports()               
    portTimer = Timer(_->update_com_ports(), 1; interval=2)
    atexit(() -> set_motor_native_speed(0))     #Turn the Table off if julia exits
    
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