using Pkg

macro install(x)
    try
        @eval(using $x)
    catch 
        Pkg.add(string(x))
        @eval(using $x)
    end
end

@install(PackageCompiler)
@install(Reexport)

println("Pulling from git...")
Pkg.add(url="https://github.com/HyperSphereStudio/JuliaSAILGUI.jl")

dllname = joinpath(Sys.BINDIR, ARGS[1])
scriptname = ARGS[2]

println("Compile System Image [true/false]?")
if parse(Bool, readline())
   eval(:(using JuliaSAILGUI)) 
   println("Warming environment...")
   println("Initializing Create Image!")
   JuliaSAILGUI.run_test()   
   println("Compiling Image to $dllname")   
   create_sysimage(; sysimage_path=dllname)
end 
    
println("Creating System Image Executable File \"gui.bat\"")
open("gui.bat", "w") do f
    write(f, "julia --sysimage $dllname $scriptname")
end