require "fileutils"
require "json"
module Toolkit
  class Initializer
    EXCLUDED = %w[node_modules .venv .bundle output tmp specs .build prompts config docs audio .skill __pycache__].freeze
    def initialize(runtime) = @runtime = runtime
    def examples_root
      [File.expand_path("../examples", @runtime), File.join(@runtime, ".skill", "examples")].find { File.directory?(_1) } || File.expand_path("../examples", @runtime)
    end
    def example_dir(name)
      raise ArgumentError, "Example names are plain words" unless name.match?(/\A[a-z0-9-]+\z/)
      dir = File.join(examples_root, name)
      raise ArgumentError, "No example #{name} in #{examples_root}" unless File.file?(File.join(dir, "story.md"))
      dir
    end
    def copy_tree(source, destination)
      FileUtils.mkdir_p(destination)
      Dir.children(source).each do |entry|
        next if EXCLUDED.include?(entry)
        src, dst = File.join(source, entry), File.join(destination, entry)
        File.directory?(src) ? copy_tree(src, dst) : FileUtils.cp(src, dst)
      end
    end
    # An anime project: the story/brief (--prompt-file or --story) is required; a soundtrack (--song) and a folder of character
    # reference photos (--references, copied to references/) are optional. Scores are usually generated per scene.
    # --example <name> starts from the skill's examples/<name>: its story, config, prompts and plan.
    def create(project:, prompt: nil, song: nil, references: nil, example: nil)
      bundled = example && example_dir(example)
      prompt ||= bundled && File.join(bundled, "story.md")
      raise ArgumentError, "init requires --project and --story (or --prompt-file)" unless project && prompt
      raise ArgumentError, "Story/prompt file missing" unless File.file?(prompt)
      raise ArgumentError, "Song file missing" if song && !File.file?(song)
      raise ArgumentError, "References directory missing" if references && !File.directory?(references)
      raise ArgumentError, "Project must be a new or empty directory" if File.exist?(project) && (!File.directory?(project) || !Dir.children(project).empty?)
      copy_tree(@runtime, project)
      origin = File.file?(File.expand_path("../SKILL.md", @runtime)) ? File.expand_path("..", @runtime) : File.join(@runtime, ".skill")
      if File.file?(File.join(origin, "SKILL.md"))
        target = File.join(project, ".skill")
        FileUtils.mkdir_p(target)
        %w[SKILL.md references assets examples].each { |entry| FileUtils.cp_r(File.join(origin, entry), target) if File.exist?(File.join(origin, entry)) }
      end
      %w[audio config docs prompts output].each { |d| FileUtils.mkdir_p(File.join(project, d)) }
      source = nil
      if song
        source = "audio/source#{File.extname(song)}"
        FileUtils.cp(song, File.join(project, source))
      end
      FileUtils.cp_r(File.join(references, "."), File.join(project, "references")) if references
      FileUtils.cp(prompt, File.join(project, "docs", "BRIEF.md"))
      File.write(File.join(project, "config/generations.rb"), "# Evaluated inside Pipeline; see the skill task reference.\n{}\n")
      File.write(File.join(project, "config/production.json"), JSON.pretty_generate(wave: 0, jobs: []))
      File.write(File.join(project, "config/project.json"), JSON.pretty_generate(song_source: source, fps: 24, references: references && "references"))
      %w[config prompts docs].each { |d| FileUtils.cp_r(File.join(bundled, d, "."), File.join(project, d)) if File.directory?(File.join(bundled, d)) } if bundled
      { project: project, references: references && "references", example: example,
        next: "setup; write config/style.md, config/cast.yml and docs/PLAN.md (episode storyboard) before approval#{"; audio:analyze[#{source},audio]" if source}" }
    end
  end
end
