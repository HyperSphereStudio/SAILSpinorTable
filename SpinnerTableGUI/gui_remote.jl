using Pkg

function prompt(label)
	println(label * " [true/false]?")
	if parse(Bool, readline())
		return true
	end
	return false
end

update_core = prompt("Update Core")
compile_img = prompt("Compile System Image")

Pkg.activate("juliasailenv"; shared=true)
update_core && Pkg.add(url="https://github.com/HyperSphereStudio/JuliaSAILGUI.jl")

dllname = joinpath(Sys.BINDIR, ARGS[1])
scriptname = ARGS[2]

println("To use in vscode add addt. arg: --sysimage=$(abspath(dllname))")

if compile_img
   try
        @eval(using PackageCompiler)
   catch 
        Pkg.add("PackageCompiler")
        @eval(using PackageCompiler)
   end
   
   println("Compiling Image to $dllname")   
   ENV["SYS_COMPILING"] = true
   PackageCompiler.create_sysimage(["JuliaSAILGUI"]; sysimage_path=dllname)
end
    
println("Creating System Image Executable File \"gui.bat\"")
open("gui.bat", "w") do f
	try run(`juliaup remove juliasailgui`) catch _ end
	success(Cmd(`juliaup link juliasailgui julia -- --sysimage $dllname`, dir=Sys.BINDIR))
    write(f, "julia +juliasailgui $scriptname")
end