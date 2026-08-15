#!/usr/bin/env ruby
# frozen_string_literal: true

require "set"
require "yaml"

VALID_TYPES = Set.new(%w[checkboxes dropdown input markdown textarea upload]).freeze
FORM_PATHS = Dir[".github/ISSUE_TEMPLATE/*.{yml,yaml}"].reject do |path|
  File.basename(path) == "config.yml"
end.concat(["research/pilots/rc7/validation-report.yml"]).freeze

errors = []

FORM_PATHS.each do |path|
  begin
    form = YAML.safe_load(File.read(path), aliases: false, filename: path)
  rescue Psych::Exception => e
    errors << "#{path}: invalid YAML: #{e.message.lines.first.strip}"
    next
  end

  unless form.is_a?(Hash)
    errors << "#{path}: top level must be a mapping"
    next
  end

  %w[name description body].each do |key|
    errors << "#{path}: missing top-level #{key}" unless form.key?(key)
  end
  body = form["body"]
  unless body.is_a?(Array) && body.any?
    errors << "#{path}: body must be a non-empty array"
    next
  end

  ids = Set.new
  labels = Set.new

  body.each_with_index do |element, index|
    location = "#{path}: body[#{index}]"
    unless element.is_a?(Hash)
      errors << "#{location}: element must be a mapping"
      next
    end

    type = element["type"]
    errors << "#{location}: unsupported type #{type.inspect}" unless VALID_TYPES.include?(type)
    attributes = element["attributes"]
    unless attributes.is_a?(Hash)
      errors << "#{location}: attributes must be a mapping"
      next
    end

    if type == "markdown"
      errors << "#{location}: markdown requires a string value" unless attributes["value"].is_a?(String)
      next
    end

    id = element["id"]
    unless id.is_a?(String) && id.match?(/\A[a-zA-Z0-9_-]+\z/)
      errors << "#{location}: id must contain only letters, numbers, hyphens, or underscores"
    end
    errors << "#{location}: duplicate id #{id.inspect}" if ids.include?(id)
    ids << id

    label = attributes["label"]
    unless label.is_a?(String) && !label.strip.empty?
      errors << "#{location}: label must be a non-empty string"
    end
    normalized_label = label.to_s.strip.downcase
    errors << "#{location}: duplicate label #{label.inspect}" if labels.include?(normalized_label)
    labels << normalized_label

    options = attributes["options"]
    if type == "dropdown"
      unless options.is_a?(Array) && options.any? && options.all? { |option| option.is_a?(String) }
        errors << "#{location}: dropdown options must be a non-empty string array"
      end
    elsif type == "checkboxes"
      unless options.is_a?(Array) && options.any?
        errors << "#{location}: checkboxes require a non-empty options array"
        next
      end
      option_labels = Set.new
      options.each_with_index do |option, option_index|
        option_location = "#{location}.options[#{option_index}]"
        unless option.is_a?(Hash) && option["label"].is_a?(String)
          errors << "#{option_location}: checkbox option requires a string label"
          next
        end
        normalized_option = option["label"].strip.downcase
        if option_labels.include?(normalized_option)
          errors << "#{option_location}: duplicate checkbox label #{option['label'].inspect}"
        end
        option_labels << normalized_option
        required = option["required"]
        unless required.nil? || required == true || required == false
          errors << "#{option_location}: required must be boolean"
        end
      end
    end

    required = element.dig("validations", "required")
    unless required.nil? || required == true || required == false
      errors << "#{location}: validations.required must be boolean"
    end
  end
end

if errors.any?
  warn errors.join("\n")
  exit 1
end

puts "Validated #{FORM_PATHS.length} GitHub issue forms"
