module ApplicationHelper
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
