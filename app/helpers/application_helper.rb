module ApplicationHelper
  def dom_id_for_partial(entry)
    "entry_#{entry.id}_partial"
  end
end
