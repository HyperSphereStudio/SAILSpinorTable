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

            return [ccall(:jl_module_usings, Any, (Any,), @__MODULE__)..., @__MODULE__]
        end) 
   invalid_modules = [Base, Main, Core]  
   compiling_modules = map(nameof, filter(m -> !(m in invalid_modules), modules))
   println("Compiling Image containing $compiling_modules to $dllname")   
   create_sysimage(compiling_modules; sysimage_path=dllname)
end 
    
println("Creating System Image Executable File \"gui.bat\"")
open("gui.bat", "w") do f
    write(f, "julia --sysimage $dllname $scriptname")
end