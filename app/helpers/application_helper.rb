module ApplicationHelper
  # Sortable column header link.
  # Toggles direction when already sorting by this column; defaults to asc on first click.
  def sort_link(label, column, current_sort:, current_dir:)
    active    = current_sort == column
    next_dir  = active && current_dir == "asc" ? "desc" : "asc"
    icon_name = active ? (current_dir == "asc" ? "arrow_upward" : "arrow_downward") : "unfold_more"
    icon_cls  = active ? "opacity-80" : "opacity-30"

    link_to(request.query_parameters.merge(sort: column, direction: next_dir),
            class: "flex items-center gap-0.5 hover:text-base-content") do
      safe_join([
        content_tag(:span, label),
        content_tag(:span, icon_name,
                    class: "material-symbols-outlined #{icon_cls}",
                    style: "font-size:14px;line-height:1")
      ])
    end
  end
  # Returns a styled paragraph tag with the error message(s) if a field has errors
  def field_errors(object, field)
    return if object.nil? || !object.respond_to?(:errors) || object.errors[field].empty?

    content_tag(:p, class: "text-error text-xs mt-1 font-medium") do
      object.errors[field].to_sentence.capitalize
    end
  end

  # Returns the dynamic classes for input fields when they have validation errors
  def error_class_for(object, field, base_class = "")
    return base_class if object.nil? || !object.respond_to?(:errors) || object.errors[field].empty?
    "#{base_class} input-error"
  end
end
