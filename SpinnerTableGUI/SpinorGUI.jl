using Dates

using JuliaSAILGUI
using JuliaSAILGUI: DataFrames, Gtk4, Observables, LibSerialPort, CSV, GLMakie, IOReader

#using .JuliaSAILGUI, .DataFrames, .Gtk4, .Observables, .LibSerialPort, .CSV, .GLMakie, .IOReader


#Adjustable Constants
const BaudRate = 115200
const InitMotorSpeed = 30
const TimeDisplayWindow = 10
const SampleRate = .5
const MaxMotorCurrent = 5.0 #A
const InitMotorVoltage = 20 #V
const AverageMeasurementLength = 3

#Packet Types
const AccelerationPacket::UInt8 = 1
const ComputerPrint::UInt8 = 2
const SetMotorSpeed::UInt8 = 3
const Cut::UInt8 = 4

RunningTime = now()
runningtime() = Dates.value(now() - RunningTime) * 1E-3
comp_println(x...) = println("[Comp]:", x...)

const MAGIC_NUMBER::UInt32 = 0xDEADBEEF
const TAIL_MAGIC_NUMBER::UInt8 = 0xEE

mutable struct SimpleConnection2 <: IOReader
    port::MicroControllerPort
    write_buffer::IOBuffer

    function SimpleConnection2(port::MicroControllerPort)
        c = new(port, IOBuffer())
        port.reader = c
        c
    end

    Base.close(c::SimpleConnection2) = close(c.port)
    Base.isopen(c::SimpleConnection2) = isopen(c.port)
    Base.print(io::IO, c::SimpleConnection2) = print(io, "Connection[Name=$(c.port.name), Open=$(isopen(c))]")
    Observables.on(cb::Function, p::SimpleConnection2; update=false) = on(cb, p.port; update=update)
    Base.setindex!(p::SimpleConnection2, port) = setport(p, port)
end
JuliaSAILGUI.setport(s::SimpleConnection2, name) = setport(s.port, name)
JuliaSAILGUI.readport(f::Function, s::SimpleConnection2) = readport(f, s.port)

function JuliaSAILGUI.send(s::SimpleConnection2, args...)
    s.write_buffer.ptr = 1
    s.write_buffer.size = 0
    writestd(x::T) where T <: Number = write(s.write_buffer, hton(x)) 
    writestd(x) = write(s.write_buffer, x) 
    writestd(MAGIC_NUMBER)
    writestd(UInt8(sum(sizeof, args)))
    foreach(writestd, args)
    writestd(TAIL_MAGIC_NUMBER)
    LibSerialPort.sp_nonblocking_write(s.port.sp.ref, pointer(s.write_buffer.data), s.write_buffer.ptr - 1)
end

function Base.take!(r::SimpleConnection2, io::IOBuffer)
    head::UInt32 = 0
    canread(s::Integer) = bytesavailable(io) >= s
    canread(::Type{T}) where T = canread(sizeof(T))
    canread(x) = canread(sizeof(typeof(x)))

    while canread(UInt32) && (head = peekn(io, UInt32)) != MAGIC_NUMBER
        io.ptr += 1                             
    end

    mark(io)                                                      #Mark after discardable data
    if canread(sizeof(MAGIC_NUMBER) + 1) && (readn(io, UInt32) == MAGIC_NUMBER)
        size = read(io, UInt8)
        if canread(size + 1)
            base_pos = io.ptr
            io.ptr += size
	   
            if read(io, UInt8) == TAIL_MAGIC_NUMBER               #Peek ahead to make sure tail is okay
                return IOBuffer(@view(io.data[base_pos:(base_pos + size - 1)]))
            else
                return nothing
            end
        end
    end

    io.ptr = io.mark
    return nothing
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
    master = SimpleConnection2(MicroControllerPort(:Reciever, BaudRate, nothing))
    gui = create_gui(df, motorVoltage, motorControl, motorSpeed)
   
    measure(name) = measurements[name]
    measure!(name, v) = measurements[name] = v
    getinputmotorpower() = motorControl[] / 127 * motorVoltage[] * MaxMotorCurrent
    
    motorSampleTimer = HTimer(0, SampleRate; start=false) do t
        measure!(Time, runningtime())
        push!(df, measurements)
        notify(gui[:TimeData])
    end

    measureTimer = HTimer(1, .75; start=false) do t 
        s = measure(measurementMode[] + 2)
        d = measure(Desired)
        v = motorControl[]
        Gtk4.markup(gui[:Freq], "<b>Measured:$(round(s, digits=3)) Hz</b>")
        measurementMode[] == 1 && return                        #Skip on manual mode
        comp_println("Measured: $s Hz. Desired: $d Hz")
        motorControl[] += cmp(d, s)
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
        isopen(master) || return
        resume(motorSampleTimer)
        resume(measureTimer)
        lastDirection = 1
        lastSpeed = 0
        motorControl[] = InitMotorSpeed                    
        motorSpeed[] = 1.5
    end

    function stop()
		println("Stopping...")
        pause(motorSampleTimer)
        pause(measureTimer)
        if isopen(master)
			for i in 1:3
				send(master, SetMotorSpeed, UInt8(0))
				sleep(.01)
			end
		end
    end

    function save_to_file(file)
        endswith(file, ".csv") || (file *= ".csv")
        comp_println("Saving Run To File to $file")
        CSV.write(file, df)
    end

    atexit(() -> motorControl[] = 0)                                               #Silently turn off table if its still on 
    signal_connect(_ -> exit(0), gui[:Window], :close_request)                     #Kill Program on GUI close
    Observables.ObservablePair(gui[:Instrument], measurementMode)
    on(master) do c
        c || (gui[:Port].active = -1)
        comp_println("Master Connected: $c")
    end
    on(motorControl; priority=1) do v
        isopen(master) || (comp_println("Master Not Connected!"); return)
        v = round(clamp(v, 0, 126))
        measure!(InputMotorPower, getinputmotorpower())
        comp_println("Set Motor Value $v")
		
		send(master, SetMotorSpeed, UInt8(v))
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
            setport(master, w[]) && reset()
        end
    end
    on(_ -> save_dialog(save_to_file, "Save data file as...", nothing, ["*.csv"]), gui[:Save])
    on(_ -> @async(start()), gui[:Play])
    on(_ -> @async(motorSpeed[] = 0), gui[:Stop])
    on(_ -> @async(close(master)), gui[:Disconnect])
    on(gui[:Release]) do w
        comp_println("Releasing!")
        @async(send(master, Cut))
    end
    on(PortsObservable; update=true) do pl
        isopen(master) && return
        empty!(gui[:Port])
        append!(gui[:Port], pl)
    end                                                   
    while true #GUI Loop
        try
            isopen(master) && readport(master) do io
				id = read(io, UInt8)
                if id == AccelerationPacket
                    Gz = readn(io, Float32)
                    Gz_Hz = Gz ./ 360
                    measure!(Gyro, Gz_Hz)
                elseif id == ComputerPrint
                    print(read(io, String))
                else
                    println("Invalid Packet!")
                end
            end
        catch e
            showerror(stdout, e)
        end    
        sleep(1E-3)
    end
end

gui_main()