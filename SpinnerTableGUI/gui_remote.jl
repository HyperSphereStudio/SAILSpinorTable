using Pkg, PackageCompiler

Pkg.add(url="https://github.com/HyperSphereStudio/JuliaSAILGUI.jl")

dllname = joinpath(Sys.BINDIR, ARGS[1])
scriptname = ARGS[2]
make_sys_image = parse(Bool, ARGS[3])

if make_sys_image
   modules = eval(quote 
            using JuliaSAILGUI 
            JuliaSAILGUI.run_test() 
            return [ccall(:jl_module_usings, Any, (Any,), @__MODULE__)..., @__MODULE__]
        end) 
    invalid_modules = [Base, Main, Core]  
    create_sysimage(map(nameof, filter(m -> !(m in invalid_modules), modules)); sysimage_path=dllname)
end 
    
open("gui.bat", "w") do f
    write(f, "julia --sysimage $dllname $scriptname")
end