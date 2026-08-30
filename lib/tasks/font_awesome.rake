namespace :font_awesome do
  SOURCE = Rails.root.join("node_modules/@fortawesome/fontawesome-free/webfonts")
  DESTINATION = Rails.root.join("public/webfonts")

  desc "Copy Font Awesome webfonts into public/webfonts"
  task :copy do
    # $fa-font-path points at /webfonts, served straight from public/. It cannot point
    # into the asset pipeline: Dart Sass compiles outside Sprockets, so it has no way to
    # write the digested filenames Sprockets produces.
    unless Dir.exist?(SOURCE)
      warn "Font Awesome webfonts not found at #{SOURCE}. Run `npm install` first."
      next
    end

    FileUtils.mkdir_p(DESTINATION)
    # Only the styles application.scss imports, plus the v4 compatibility face the
    # core stylesheet declares.
    %w[fa-solid-900 fa-regular-400 fa-brands-400 fa-v4compatibility].each do |face|
      Dir.glob("#{SOURCE}/#{face}.*").each { |file| FileUtils.cp(file, DESTINATION) }
    end

    puts "Copied #{Dir.glob("#{DESTINATION}/*").size} font files to public/webfonts"
  end
end

# The fonts have to exist wherever the CSS is served from, so tie this to the same hook
# that builds the CSS.
Rake::Task["assets:precompile"].enhance(["font_awesome:copy"]) if Rake::Task.task_defined?("assets:precompile")
