using JuliaSAILGUI
using Dates
using JuliaSAILGUI: DataFrames, Gtk4, Observables, LibSerialPort, CSV, GLMakie

#Adjustable Constants
const BaudRate = 115200
const InitMotorSpeed = 75
const TimeDisplayWindow = 10
const SampleRate = .25
const MaxMotorCurrent = 5.0 #A
const InitMotorVoltage = 20 #V
const AverageMeasurementLength = 3

#Packet Types
const AccelerationPacket = 1
const ComputerPrint = 2
const SetTxState = 3
const ControllerWrite = 4
const ControllerRead = 5
const Cut = 6

#Tx States
const TxReadyIdle::UInt8 = 1
const TxGetData::UInt8 = 2

#Controller Commands
const ControllerSetSpeed::UInt8 = 0xC2

RunningTime = now()
runningtime() = Dates.value(now() - RunningTime) * 1E-3
comp_println(x...) = println("[Comp]:", x...)
JuliaSAILGUI.readport(f::Function, s::SimpleConnection) = readport(f, s.port)
function JuliaSAILGUI.send(s::SimpleConnection, type::Integer, args...)
    s.write_buffer.ptr = 1
    s.write_buffer.size = 0
    writestd(x::T) where T <: Number = write(s.write_buffer, hton(x)) 
    writestd(x) = write(s.write_buffer, x) 
    writestd(JuliaSAILGUI.MAGIC_NUMBER)
    writestd(UInt8(sum(sizeof, args)))
    writestd(UInt8(type))
    writestd(UInt8(s.packet_count))
    foreach(writestd, args)
    writestd(JuliaSAILGUI.TAIL_MAGIC_NUMBER)
    s.packet_count += 1
    LibSerialPort.sp_nonblocking_write(s.port.sp.ref, pointer(s.write_buffer.data), s.write_buffer.ptr - 1)
end

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
    receiver_port_select = GtkComboBoxText()

    motor_voltage_entry = GtkEntry(input_purpose = Gtk4.InputPurpose_NUMBER)
    motor_control_entry = GtkEntry(input_purpose = Gtk4.InputPurpose_NUMBER)
    Observables.ObservablePair(motor_voltage_entry, motorVoltage)
    Observables.ObservablePair(motor_control_entry, motorControl)

    instrument_control_select = GtkComboBoxText()
    append!(instrument_control_select, "Gyro-Controlled", "Manual-Controlled")
    instrument_control_select.active = 0
    append!(select_box, makewidgetswithtitle([receiver_port_select, instrument_control_select, motor_voltage_entry], ["Reciever Port", "Mode", "Motor Voltage [V]"]))
    append!(gui, :Port => receiver_port_select, :Instrument => instrument_control_select)

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
    disconnect_button = GtkButton("Disconnect")

    append!(back_box, select_box, makewidgetswithtitle([control_box, motor_speed_spin_button], ["Control", "Motor Frequency"])..., release_button, disconnect_button)
    append!(gui, :Release => release_button, :Disconnect => disconnect_button, :MotorControl => motor_speed_adjuster)

    plot = GtkGLArea(hexpand=true, vexpand=true)

    motor_freq_label = GtkLabel(""; hexpand=true)

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
    df = DataFrame(Time=Float32[], Gyro=Float32[], Desired=Float32[], InputMotorPower=Float32[])
    measurements = zeros(size(df, 2))
    Time, Gyro, Desired, InputMotorPower = 1:size(df, 2)

    motorVoltage = Observable(Float64(InitMotorVoltage))
    motorControl = Observable(0)
    motorSpeed = Observable(0.0)
    measurementMode = Observable(0)
    lastDirection = 1
    lastSpeed = 0
    rx = SimpleConnection(MicroControllerPort(:Reciever, BaudRate, nothing), (h) -> comp_println("Packet Corruption! $(h.Type)"))
    gui = create_gui(df, motorVoltage, motorControl, motorSpeed)
   
    measure(name) = measurements[name]
    measure!(name, v) = measurements[name] = v
    getinputmotorpower() = motorControl[] / 127 * motorVoltage[] * MaxMotorCurrent
    
    motorSampleTimer = HTimer(0, SampleRate; start=false) do t
        measure!(Time, runningtime())
        push!(df, measurements)
        notify(gui[:TimeData])
    end

    measureTimer = HTimer(4, .5; start=false) do t 
        s = measure(measurementMode[] + 2)
        d = measure(Desired)
        v = motorControl[]
        Gtk4.markup(gui[:Freq], "<b>Measured:$(round(s, digits=3)) Hz</b>")
        measurementMode[] == 1 && return                        #Skip on manual mode
        comp_println("Measured: $s Hz. Desired: $d Hz")
       
        current = abs(s - d)
        last = abs(lastSpeed - d)
        if current > .05
            if s > d
                direction = -1                  #Wont cause motor stalling
            else
                direction = lastDirection       #Go up to desired without stalling
                current > last && (direction *= -1)
                lastSpeed = s
            end
            motorControl[] += direction
            lastDirection = direction
        end
    end

    function reset()
        global RunningTime
        (motorSpeed[] != 0) && (motorSpeed[] = 0)
        empty!(df)
        RunningTime = now()
        notify(gui[:TimeData])
    end
    
    function start()
        reset()
        isopen(rx) || return
        resume(motorSampleTimer)
        resume(measureTimer)
        lastDirection = 1
        lastSpeed = 0
        motorControl[] = InitMotorSpeed                    
        motorSpeed[] = 1.5
        send(rx, SetTxState, TxGetData)                             #Send Packets
    end

    function stop()
        pause(motorSampleTimer)
        pause(measureTimer)
        isopen(rx) && send(rx, SetTxState, TxReadyIdle)             #Stop Sending Packets
    end

    function save_to_file(file)
        endswith(file, ".csv") || (file *= ".csv")
        comp_println("Saving Run To File to $file")
        CSV.write(file, df)
    end

    atexit(() -> motorControl[] = 0)                                               #Silently turn off table if its still on 
    signal_connect(_ -> exit(0), gui[:Window], :close_request)                     #Kill Program on GUI close
    Observables.ObservablePair(gui[:Instrument], measurementMode)
    on(rx) do c
        c || (gui[:Port].active = -1)
        comp_println("Rx Connected: $c")
    end
    on(motorControl; priority=1) do v
        isopen(rx) || (comp_println("Rx Not Connected!"); return)
        v = clamp(v, 0, 126)
        measure!(InputMotorPower, getinputmotorpower())
        comp_println("Set Motor Value $v")
        send(rx, ControllerWrite, ControllerSetSpeed, UInt8(v))                                         
        motorControl.val = v                                                                            #Set without notification
        v == 0 && stop()
    end
    on(motorSpeed) do v
        comp_println("Set Motor Speed:$v Hz")
        measure!(Desired, v)
        v == 0 && (motorControl[] = 0)
    end
    on(gui[:Port]) do w
        @async begin
            w[] === nothing && return
            comp_println("Rx Port = $(w[])")
            setport(rx, w[]) && reset()
        end
    end
    on(_ -> save_dialog(save_to_file, "Save data file as...", nothing, ["*.csv"]), gui[:Save])
    on(_ -> @async(start()), gui[:Play])
    on(_ -> @async(motorSpeed[] = 0), gui[:Stop])
    on(_ -> @async(close(rx)), gui[:Disconnect])
    on(gui[:Release]) do w
        comp_println("Releasing!")
        @async(send(rx, Cut))
    end
    on(PortsObservable; update=true) do pl
        isopen(rx) && return
        empty!(gui[:Port])
        append!(gui[:Port], pl)
    end                                                   
    while true #GUI Loop
        try
            isopen(rx) && readport(rx) do (h, io)
                if h.Type == AccelerationPacket
                    Gx, Gy, Gz, Ax, Ay, Az, Mx, My, Mz = readn(io, Float32, 9)
                    Gx_Hz, Gy_Hz, Gz_Hz = (Gx, Gy, Gz) ./ 360
                    measure!(Gyro, Gz_Hz)
                elseif h.Type == ComputerPrint
                    print(read(io, String))
                end
            end
        catch e
            showerror(stdout, e)
        end    
        sleep(1E-2)
    end
end

gui_main()