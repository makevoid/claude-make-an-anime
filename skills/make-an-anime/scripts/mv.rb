#!/usr/bin/env ruby
require "optparse"
require "fileutils"
require "rbconfig"
require "open3"
runtime = __dir__
options = {}
parser = OptionParser.new do |o|
  o.banner = "make-an-anime toolkit\nUsage: ruby scripts/mv.rb [--project DIR] TASK [task arguments]\n       ruby scripts/mv.rb init --project DIR --story STORY.md [--references DIR] [--song FILE]\n       ruby scripts/mv.rb init --project DIR --example 01-sample-seven\nRuby is the only execution entry. Tasks use ENV RUN/ONLY/FORCE/VFX/SFX."
  o.on("--project DIR", "Project workspace (defaults to bundled runtime)") { |v| options[:project] = File.expand_path(v) }
  o.on("--song FILE", "Local soundtrack for init") { |v| options[:song] = File.expand_path(v) }
  o.on("--prompt-file FILE", "--story FILE", "Story bible / creative brief for init") { |v| options[:prompt] = File.expand_path(v) }
  o.on("--example NAME", "Start init from a bundled example, e.g. 01-sample-seven") { |v| options[:example] = v }
  o.on("--references DIR", "Character reference photos for init (copied to references/)") { |v| options[:references] = File.expand_path(v) }
  o.on("-T", "List all rake tasks") { options[:list] = true }
  o.on("--help", "Show tasks and exit") { puts o; puts "Tasks: init, setup, doctor, test, plan:approve, work:next, work:accept, audio:analyze, audio:transcribe, media:stems, gen:<step>, review:<step>, gen:dialogue, gen:music, gen:mix, gen:keyframes, gen:shots, pipeline:all, anim:preview, anim:overlay, media:preview, sfx:gen, sfx:mix, vfx:render. Use -T for the complete rake task list.\nExit: 0 success; 1 task/runtime failure; 2 invalid CLI or missing input. No interactive shell prompts."; exit }
end
begin
  parser.parse!(ARGV)
  command = options[:list] ? "-T" : (ARGV.shift || "pipeline:status")
  if command == "init"
    # json loads here, not at the top: activating the default json gem before bundler/setup makes Bundler refuse the
    # Gemfile's json on a first setup run ("You have already activated json ...").
    require "json"
    require_relative "lib/toolkit/initializer"
    puts JSON.pretty_generate(Toolkit::Initializer.new(runtime).create(project: options[:project], song: options[:song], prompt: options[:prompt], references: options[:references], example: options[:example]))
    exit
  end
  project = options[:project] || runtime
  raise ArgumentError, "No project Rakefile in #{project}; use init first" unless File.file?(File.join(project, "Rakefile"))
  Dir.chdir(project)
  if command == "setup"
    # Bootstrap gems before loading any runtime dependencies.
    ok = system(RbConfig.ruby, "-S", "bundle", "install")
    raise "bundle install failed" unless ok
  end
  ENV["BUNDLE_GEMFILE"] = File.join(project, "Gemfile")
  require "bundler/setup"
  require "rake"
  args = command == "-T" ? ["-T"] : [command, *ARGV]
  Rake.application.run(args)
rescue OptionParser::ParseError, ArgumentError => e
  warn "Error: #{e.message}\n#{parser}"
  exit 2
rescue StandardError => e
  warn "Error: #{e.message}"
  exit 1
end
