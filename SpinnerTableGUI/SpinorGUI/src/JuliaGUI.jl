using Gtk, CairoMakie, Makie, Observables, PackageCompiler

CairoMakie.activate!()

function makie_draw(canvas, fig)
    @guarded draw(canvas) do _
       scene = fig.scene
       resize!(scene, Gtk.width(canvas), Gtk.height(canvas))
       config = CairoMakie.ScreenConfig(1.0, 1.0, :good, true, true)
       screen = CairoMakie.Screen(scene, config, Gtk.cairo_surface(canvas))
       CairoMakie.cairo_draw(screen, scene)
    end
    show(canvas)
end

fixed_move(fixed, widget, x, y) = ccall((:gtk_fixed_move, Gtk.libgtk), Nothing, (Ptr{GObject}, Ptr{GObject}, Cint, Cint), fixed, widget, x, y)

function compile_sysimage()
    precompile(SpinorGUI.launch_gui, ())
    create_sysimage(nothing; sysimage_path="juliagui.dll")
end

gtk_to_string(s) = s == C_NULL ? "" : Gtk.bytestring(s)