using JuliaSAILGUI
using Dates
using JuliaSAILGUI: DataFrames, Gtk4, Observables, LibSerialPort, CSV, GLMakie, GtkValueEntry

using JuliaSAILGUI: Gtk4.GObject, Gtk4.G_, Gtk4.GLib
using JuliaSAILGUI: Gtk4.GLib.GListStore, Gtk4.libgio, Gtk4.libgtk4

on_update_signal_name(::GtkButton) = "clicked"
on_update_signal_name(::GtkComboBoxText) = "changed"
on_update_signal_name(::GtkAdjustment) = "value-changed"
on_update_signal_name(::GtkEntry) = "activate"

Observables.on(@nospecialize(cb::Function), w::GtkWidget) = signal_connect(cb, w, on_update_signal_name(w))
Observables.connect!(w::GtkWidget, o::AbstractObservable) = on(v -> w[] = v, o)

Base.getindex(g::GtkEntry, ::Type{String}) = g.text
Base.getindex(g::GtkLabel, ::Type{String}) = g.label
Base.getindex(g::GtkComboBoxText, ::Type{String}) = Gtk4.active_text(g)
Base.getindex(g::GtkAdjustment, ::Type{Number}) = Gtk4.value(g)

Base.getindex(g::Union{GtkEntry, GtkLabel, GtkComboBoxText}, t::Type = String) = parse(g, t)

Base.setindex!(g::GtkLabel, v) = g.label = string(v)
Base.setindex!(g::GtkEntry, v) = g.text = string(v)
Base.setindex!(g::GtkAdjustment, v) = Gtk4.value(g, v)

function Gtk4.set_gtk_property!(o::GObject, name::String, value::AbstractObservable) 
    set_gtk_property!(o, name, value[])
    on(v -> set_gtk_property!(o, name, v), value)
end

function Observables.ObservablePair(w::GtkWidget, o::AbstractObservable{T}) where T
    w[] = o[]
    done = Ref(false)
    on(w) do w
        if !done[]
            done[] = true
            o[] = w[T]
            done[] = false
        end
    end
    on(o) do val
        if !done[]
            done[] = true
            w[] = val
            done[] = false
        end
    end
end

Base.append!(cv::GtkColumnView, cvc::GtkColumnViewColumn) = G_.append_column(cv, cvc)

GtkNoSelection(model) = G_.NoSelection_new(model)

mutable struct GtkJuliaStore
    items::Dict{Ptr{GObject}, Any}
    store::GListStore
    freeNames::Array{Ptr{GObject}}

    GtkJuliaStore() = new(Dict{Ptr{GObject}, Any}(), GLib.GListStore(:GObject), Ptr{GObject}[])
    GtkJuliaStore(items::AbstractArray) = (g = GtkJuliaStore(); append!(g, items))
    GtkJuliaStore(items...) = GtkJuliaStore(collect(items))

    Gtk4.GListModel(g::GtkJuliaStore) = Gtk4.GListModel(g.store)
    Base.getindex(g::GtkJuliaStore, i::Integer) = g.items[unsafegetname(g.store, i)]
    Base.setindex!(g::GtkJuliaStore, v, i::Integer) = g.items[unsafegetname(g.store, i)] = v
    Base.keys(lm::GtkJuliaStore) = keys(g.store)
    Base.eltype(::Type{GtkJuliaStore}) = Any
    Base.iterate(g::GtkJuliaStore, i=0) = (i == length(g) ? nothing : (getindex(g, i + 1), i + 1))
    Base.length(g::GtkJuliaStore) = length(g.store)
    Base.empty!(g::GtkJuliaStore) = (empty!(g.items); empty!(g.store); empty!(freeNames))
    Base.pushfirst!(g::GtkJuliaStore, item) = insert!(g, 1, item)
    Base.append!(g::GtkJuliaStore, items) = foreach(x -> push!(g, x), items)
    Base.getindex(g::GtkJuliaStore, i::GtkListItem) = g.items[ccall(("gtk_list_item_get_item", libgtk4), Ptr{GObject}, (Ptr{GObject},), i)]
    Base.setindex!(g::GtkJuliaStore, v, i::GtkListItem) = g.items[ccall(("gtk_list_item_get_item", libgtk4), Ptr{GObject}, (Ptr{GObject},), i)] = v
    unsafegetname(ls::GListStore, i) = ccall(("g_list_model_get_object", libgio), Ptr{GObject}, (Ptr{GObject}, UInt32), ls, i-1)

    function nextname(g::GtkJuliaStore)
        name = length(g.freeNames) == 0 ? Symbol("$(length(g))") : pop!(g.freeNames)
        return ccall(("gtk_string_object_new", libgtk4), Ptr{GObject}, (Cstring,), name)
    end

    function Base.push!(g::GtkJuliaStore, item)
        name = nextname(g)
        ccall(("g_list_store_append", libgio), Nothing, (Ptr{GObject}, Ptr{GObject}), g.store, name)
        g.items[name] = item
        return nothing
    end

    function Base.insert!(g::GtkJuliaStore, i::Integer, item)
        name = nextname(g)
        ccall(("g_list_store_insert", libgio), Nothing, (Ptr{GObject}, UInt32, Ptr{GObject}), g.store, i-1, name)
        g.items[name] = item
        return nothing
    end

    function Base.deleteat!(g::GtkJuliaStore, i::Integer)
        name = unsafegetname(g.store, i)
        push!(freeNames, name)
        delete!(g.items, name)
        ccall(("g_list_store_remove", libgio), Nothing, (Ptr{GObject}, UInt32), g.store, i-1)
        return nothing
    end   
end

function GtkJuliaColumnViewColumn(store::GtkJuliaStore, name::String, @nospecialize(init_child::Function), @nospecialize(update_child::Function))
    factory = GtkSignalListItemFactory()
    signal_connect((f, li) -> set_child(li, init_child()), factory, "setup")
    signal_connect((f, li) -> update_child(get_child(li), store[li]), factory, "bind")
    return GtkColumnViewColumn(name, factory)
end


const DeviceBaudRate = 115200
const GyroBaudRate = 9600
const InitMotorSpeed = 85
const TimeDisplayWindow = 10
const SampleRate = .25
const MaxMotorCurrent = 5.0 #A
const InitMotorVoltage = 20 #V

comp_println(x...) = println("[Comp]:", x...)

function create_plot(df, plot, running_time_in_seconds, gui)
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

    gui[:Update] = function()
        time = running_time_in_seconds()
        autolimits!(rpm_ax)
        autolimits!(power_ax)
        xlims!(rpm_ax, (time - TimeDisplayWindow, time))
        xlims!(power_ax, (time - TimeDisplayWindow, time))
        notify(time_data) #Changes all plots
    end
end

function create_gui(df, running_time, motorVoltage, motorControl)
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

    create_plot(df, plot, running_time, gui)

    append!(gui, :Window => win, :Freq => motor_freq_label)

    return gui
end

function gui_main()
    motorFreqLabel, portTimer, motorSampleTimer = fill(nothing, 3)
    df = DataFrame(Time=Float32[], Gyro=Float32[], IR=Float32[], Desired=Float32[], InputMotorPower=Float32[])
    measurements = zeros(size(df, 2))
    Time, Gyro, IR, Desired, InputMotorPower = 1:size(df, 2)
    runningTime = now()

    motorVoltage = Observable(Float64(InitMotorVoltage))
    motorControl = Observable(0)

    running_time_in_seconds() = Dates.value(now() - runningTime) * 1E-3
    measure!(name, v) = measurements[name] = v
    measure(name) = measurements[name]
    gui = create_gui(df, running_time_in_seconds, motorVoltage, motorControl)

    deviceSerial = MicroControllerPort(:Device, DeviceBaudRate, DelimitedReader("\r\n"), on_disconnect = () -> gui[:DevicePort].active = -1)
    gyroSerial = MicroControllerPort(:Gyro, GyroBaudRate, DelimitedReader("\r\n"), on_disconnect = () -> gui[:GyroPort].active = -1)
    
    portSelectors = [gui[:DevicePort], gui[:GyroPort]]
    ports = [deviceSerial, gyroSerial]    

    getinputmotorpower() = motorControl[] / 127 * motorVoltage[] * MaxMotorCurrent

    function set_motor_native_speed(v, set_text=true)
        isopen(deviceSerial) || (println("Motor Port Not Open!"); return)
        v = clamp(v, 0, 126)
        measure!(InputMotorPower, getinputmotorpower())
        comp_println("Set Motor Speed $v")
        set_text && (motorControl[] = v)
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
            v = motorControl[]
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
    on(w -> set_motor_native_speed(w[], false), motorControl)
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