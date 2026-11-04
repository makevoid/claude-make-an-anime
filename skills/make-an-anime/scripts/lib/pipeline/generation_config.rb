module Pipeline
  # The project's generations: config/generations.rb plus every config/generations/*.rb, each evaluated inside Pipeline
  # (so Steps::Shots, scene(480) … resolve) and returning a Hash of run name => generation. One file per scene or per cast
  # group lets several people or agents add runs at the same time without editing a shared file. A run defined in two
  # files is an error, never a silent override.
  class GenerationConfig
    def initialize(root)
      @root = root
    end

    def files
      main = File.join(@root, "config", "generations.rb")
      [main, *Dir[File.join(@root, "config", "generations", "*.rb")].sort].select { |f| File.file?(f) }
    end

    def load
      seen = {}
      files.each_with_object({}) do |file, all|
        runs = Pipeline.module_eval(File.read(file), file)
        raise ArgumentError, "#{file} must return a Hash of run => generation" unless runs.is_a?(Hash)
        runs.each do |name, generation|
          raise ArgumentError, "run #{name} is defined in both #{seen[name]} and #{file}" if seen[name]
          seen[name] = file
          all[name] = generation
        end
      end
    end
  end
end
