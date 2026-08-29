namespace :entries do
  desc "Renumber entry positions 1..N on channels whose positions have drifted"
  task normalize_positions: :environment do
    drifted = List.all.reject(&:positions_normalized?)

    drifted.each do |list|
      before = "#{list.entries.count} entries over #{list.entries.distinct.count(:position)} positions"
      list.normalize_entry_positions!
      puts "  ##{list.id} #{list.name}: #{before} -> 1..#{list.entries.count}"
    end

    puts "Renumbered #{drifted.count} #{'channel'.pluralize(drifted.count)}."
  end
end
