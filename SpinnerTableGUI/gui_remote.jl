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

println("Pulling from git...")
Pkg.add(url="https://github.com/HyperSphereStudio/JuliaSAILGUI.jl")

dllname = joinpath(Sys.BINDIR, ARGS[1])
scriptname = ARGS[2]

println("Compile System Image [true/false]?")

if parse(Bool, readline())
   println("Warming environment...")
   modules = eval(
        quote 
            using JuliaSAILGUI 
            println("Initializing Create Image!")
            JuliaSAILGUI.run_test() 
            return JuliaSAILGUI.public_packages()
        end) 
   println("Compiling Image containing $modules to $dllname")   
   create_sysimage(nameof.(modules); sysimage_path=dllname)
end 
    
println("Creating System Image Executable File \"gui.bat\"")
open("gui.bat", "w") do f
    write(f, "julia --sysimage $dllname $scriptname")
end