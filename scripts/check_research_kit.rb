#!/usr/bin/env ruby
# frozen_string_literal: true

require "csv"
require "pathname"
require "yaml"

require_relative "research_evidence"

ROOT = Pathname.new(__dir__).join("..").cleanpath

EXPECTED_HEADERS = {
  "stage-1-participants.csv" => %w[
    participant_alias recruitment_context context_alias role_band platform
    consented completed_diary qualifying_failures reusable_failures
    recurrent_failures repository_specific_failures previously_saved_failures
  ],
  "stage-2-observations.csv" => %w[
    participant_alias card_alias creation_seconds controlled_variants
    correct_rank_one fixcard_lookup_seconds_samples normal_search_seconds_samples
    metadata_confusion_observed privacy_edits scanner_false_positives
    trust_preferred maintainer_decision
  ],
  "stage-3-repository-weeks.csv" => %w[
    repository_alias week fixcard_version pilot_users weekly_active_users
    active_users_with_three_cards lookup_attempts strong_matches
    relevant_strong_matches correct_abstentions incorrect_abstentions
    search_p95_ms end_to_end_lookup_seconds_samples
    full_lookups_under_ten_seconds fixcard_used_first other_tool_used_first
    authored_cards capture_seconds_samples cumulative_unique_active_reusers
    author_reuses teammate_reuses
    shared_submitted shared_accepted shared_changed shared_rejected retired_cards
    scanner_catches scanner_false_positives missed_real_secrets
    serious_trust_incidents differentiation_yes differentiation_responses
    maintenance_burden
  ]
}.freeze

FORBIDDEN_HEADERS = %w[
  raw_error error_text command path repository_name hostname token secret
].freeze

errors = []
templates = ROOT.join("research", "templates")
tables = {}

EXPECTED_HEADERS.each do |name, expected|
  path = templates.join(name)
  unless path.file?
    errors << "missing research template: #{path.relative_path_from(ROOT)}"
    next
  end

  table = CSV.read(path, headers: true)
  tables[name] = table
  headers = table.headers
  errors << "#{name}: headers differ from the registered schema" unless headers == expected
  errors << "#{name}: distributed template must not contain participant data" unless table.empty?

  forbidden = headers & FORBIDDEN_HEADERS
  errors << "#{name}: privacy-sensitive headers: #{forbidden.join(', ')}" unless forbidden.empty?
rescue CSV::MalformedCSVError => e
  errors << "#{name}: malformed CSV: #{e.message}"
end

report = templates.join("aggregate-report.md")
required_sections = [
  "## Registration and methods",
  "## Milestone 0 evidence corpus",
  "## Stage 1 results",
  "## Stage 2 results",
  "## Stage 3 results",
  "## Kill-criteria review",
  "## Limitations and missing data",
  "## Decision"
]

if report.file?
  source = report.read
  required_sections.each do |section|
    errors << "aggregate-report.md: missing #{section}" unless source.include?(section)
  end
else
  errors << "missing research template: research/templates/aggregate-report.md"
end

begin
  registration = ResearchEvidence.load_registration
  errors.concat(ResearchEvidence.validate_registration(registration))
  exact_version = registration.dig("pilot", "version")

  stage_3 = tables["stage-3-repository-weeks.csv"]
  if stage_3
    unless EXPECTED_HEADERS.fetch("stage-3-repository-weeks.csv") == ResearchEvidence::STAGE_3_HEADERS
      errors << "Stage 3 schema differs between the template checker and evidence validator"
    end

    errors.concat(
      ResearchEvidence.validate_stage3_table(stage_3, exact_version: exact_version)
    )

    headers = EXPECTED_HEADERS.fetch("stage-3-repository-weeks.csv")
    build_row = lambda do |version, overrides = {}|
      values = headers.map do |header|
        defaults = {
          "repository_alias" => "R001",
          "week" => "1",
          "fixcard_version" => version
        }
        overrides.fetch(header, defaults.fetch(header, ""))
      end
      CSV::Table.new([CSV::Row.new(headers, values)])
    end

    exact_errors = ResearchEvidence.validate_stage3_table(
      build_row.call(exact_version),
      exact_version: exact_version
    )
    errors << "Stage 3 exact-build control rejected #{exact_version}: #{exact_errors.join('; ')}" unless exact_errors.empty?

    previous_version = registration.dig("amendment", "supersedes_version")
    mixed_errors = ResearchEvidence.validate_stage3_table(
      build_row.call(previous_version),
      exact_version: exact_version
    )
    errors << "Stage 3 mixed-build mutation was accepted" if mixed_errors.empty?

    blank_errors = ResearchEvidence.validate_stage3_table(
      build_row.call(""),
      exact_version: exact_version
    )
    errors << "Stage 3 blank-build mutation was accepted" if blank_errors.empty?

    impossible_errors = ResearchEvidence.validate_stage3_table(
      build_row.call(exact_version, "lookup_attempts" => "1", "strong_matches" => "2"),
      exact_version: exact_version
    )
    errors << "Stage 3 impossible-count mutation was accepted" if impossible_errors.empty?

    complete_rows = (1..5).flat_map do |repository_number|
      (1..4).map do |week|
        build_row.call(
          exact_version,
          "repository_alias" => format("R%03d", repository_number),
          "week" => week.to_s
        ).first
      end
    end
    complete_table = CSV::Table.new(complete_rows)
    complete_errors = ResearchEvidence.validate_stage3_table(
      complete_table,
      exact_version: exact_version,
      complete_pilot: true
    )
    errors << "Stage 3 complete-pilot control failed: #{complete_errors.join('; ')}" unless complete_errors.empty?

    incomplete_errors = ResearchEvidence.validate_stage3_table(
      CSV::Table.new(complete_rows[0...-1]),
      exact_version: exact_version,
      complete_pilot: true
    )
    errors << "Stage 3 incomplete-week mutation was accepted" if incomplete_errors.empty?

    too_few_errors = ResearchEvidence.validate_stage3_table(
      CSV::Table.new(complete_rows.select { |row| row["repository_alias"] != "R005" }),
      exact_version: exact_version,
      complete_pilot: true
    )
    errors << "Stage 3 four-repository mutation was accepted" if too_few_errors.empty?
  end

  dogfood = File.read(ROOT.join("docs", "dogfood.md"), encoding: "UTF-8")
  errors << "dogfood.md: must name exact pilot build #{exact_version}" unless dogfood.include?("`#{exact_version}`")
  errors << "dogfood.md: must not direct pilots to the newest candidate" if dogfood.match?(/newest release candidate/i)

  results = File.read(ROOT.join("docs", "validation-results.md"), encoding: "UTF-8")
  errors << "validation-results.md: must name exact pilot build #{exact_version}" unless results.include?("`#{exact_version}`")

  form_path = ROOT.join(".github", "ISSUE_TEMPLATE", "validation-report.yml")
  form = YAML.safe_load(File.read(form_path, encoding: "UTF-8"), aliases: false, filename: form_path.to_s)
  build_field = form.fetch("body").find { |element| element["id"] == "exact_pilot_build" }
  unless build_field&.dig("type") == "dropdown" && build_field.dig("attributes", "options") == [exact_version]
    errors << "validation-report.yml: exact_pilot_build must offer only #{exact_version}"
  end

  confirmations = form.fetch("body").find { |element| element["id"] == "build_confirmation" }
  confirmation_labels = confirmations&.dig("attributes", "options")&.map { |option| option["label"] } || []
  errors << "validation-report.yml: must confirm fixcard --version" unless confirmation_labels.any? { |label| label.include?("fixcard --version") && label.include?(exact_version) }
  errors << "validation-report.yml: must confirm fix --version" unless confirmation_labels.any? { |label| label.include?("fix --version") && label.include?(exact_version) }
rescue ArgumentError, KeyError, Psych::Exception => e
  errors << "research registration controls: #{e.message}"
end

unless errors.empty?
  warn errors.join("\n")
  exit 1
end

puts "Validated #{EXPECTED_HEADERS.length} blank research templates, exact-build controls, and the aggregate report"
