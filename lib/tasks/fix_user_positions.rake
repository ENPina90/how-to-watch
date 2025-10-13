namespace :positions do
  desc "Fix UserListPositions that point to non-existent entries"
  task fix_invalid: :environment do
    puts "Finding invalid UserListPositions..."

    fixed_count = 0
    UserListPosition.includes(list: :entries).find_each do |position|
      list = position.list
      current_entry = list.entries.find_by(position: position.current_position)

      # If current position doesn't have an entry, fix it
      if current_entry.nil? && list.entries.exists?
        # Find first valid entry
        first_entry = list.entries.order(:position).first

        if first_entry
          puts "Fixing position for User #{position.user_id}, List #{list.name}: #{position.current_position} -> #{first_entry.position}"
          position.update!(current_position: first_entry.position)
          fixed_count += 1
        end
      end
    end

    puts "Fixed #{fixed_count} invalid positions"
  end
end
