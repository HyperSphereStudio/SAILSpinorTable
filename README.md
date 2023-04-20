# SAILSpinorTable

MicroController Framework Outline

* MicroController
  * Bizzano MicroFramework - MicroController side interface of the microcontroller framework. Composed of various libraries to assist in programming microcontrollers
    * LightWeight IO Library - Provide basic IO capabilities with custom printf functions designed to run with a uart
    * Bit Abstraction - Increase abstraction from working on the register level
    * FUTURE TD: Packet & Data Serialization Library - Provide a reliable data protocol to enable sending/recieving complex data structures to the server
    * [MSP430 Driver Library](https://www.ti.com/tool/MSPDRIVERLIB) - Creates an abstraction on the bits and registers of the MSP430 device
    
* Server (PC) Controller

  The GUI is built on the julia programming language. This enables powerful data pre/post processing. This framework is very large and complex and slow to initialize, to combat this a package compiler is built in to allow you to save the julia image to the device for signficantly faster startup.

  * Bizzano MicroFramework
    * [Gtk.jl](https://github.com/JuliaGraphics/Gtk.jl) - Julia bindings into the powerful Gtk GUI library
    * [Glade](https://en.wikipedia.org/wiki/Glade_Interface_Designer) - Used to design the Gtk GUI
    * [CairoMakie.jl](https://github.com/JuliaPlots/CairoMakie.jl) - Used to display Makie plots onto Gtk canvas
    * [Makie.jl](https://github.com/MakieOrg/Makie.jl) - Complex Data Visualization library accelerated via GPU
    * [LibSerialPort.jl](https://github.com/JuliaIO/LibSerialPort.jl) - IO from COM ports with UART protocol
    * BizzanoMFGUI.jl - Weave together gui libraries to design a simple framework
    * Parse COM input stream 
    * [PackageCompiler](https://github.com/JuliaLang/PackageCompiler.jl) - Compile julia package to native for fast startup
    * FUTURE TD: Packet & Data Serialization Library - Provide a reliable data protocol to enable sending/recieving complex data structures to the client
