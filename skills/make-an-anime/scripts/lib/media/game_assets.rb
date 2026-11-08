require_relative "python"
module Media
  # JSON recipes avoid comma-separated task arguments for names, crops and paths.
  class GameAssets
    def cut(recipe)
      r = JSON.parse(File.read(recipe))
      mode = r.fetch("mode")
      options = case mode
                when "sprites", "grid" then %w[names key min_px min_len gap margin size inset]
                when "frame" then %w[key dark scale min_area]
                when "fit" then %w[width crop]
                else raise ArgumentError, "mode must be sprites, grid, frame or fit"
                end
      args = [mode, r.fetch("source"), r.fetch("out")]
      args << r.fetch("slots") if mode == "frame"
      Python.new.call("cut_sheets.py", *args, *flags(r, options))
    end

    def faces(recipe)
      r = JSON.parse(File.read(recipe))
      args = case r.fetch("mode")
             when "build" then ["build", r.fetch("spec"), r.fetch("out"), *flags(r, %w[preview])]
             when "cut" then ["cut", r.fetch("source"), r.fetch("spec"), r.fetch("out"), *flags(r, %w[size tol])]
             else raise ArgumentError, "mode must be build or cut"
             end
      args << "--grid-fallback" if r["mode"] == "cut" && r["grid_fallback"] == true
      Python.new.call("face_collage.py", *args)
    end

    private

    def flags(recipe, keys)
      keys.select { recipe.key?(_1) }.flat_map do |key|
        value = recipe[key]
        ["--#{key.tr('_', '-')}", value.is_a?(Array) ? value.join(",") : value.to_s]
      end
    end
  end
end
