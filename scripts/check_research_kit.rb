#!/usr/bin/env ruby
# frozen_string_literal: true

require "csv"
require "pathname"

ROOT = Pathname.new(__dir__).join("..").cleanpath
EXACT_STAGE_3_BUILD = "1.0.0-rc.4"

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

EXPECTED_HEADERS.each do |name, expected|
  path = templates.join(name)
  unless path.file?
    errors << "missing research template: #{path.relative_path_from(ROOT)}"
    next
  end

  table = CSV.read(path, headers: true)
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

pilot_build_references = {
  "docs/dogfood.md" => [
    "exact preregistered pilot build",
    "`v#{EXACT_STAGE_3_BUILD}`",
    "`#{EXACT_STAGE_3_BUILD}`",
    "Bare `fix` shows status in RC4",
    "RC4 observations cannot validate RC5-only behavior"
  ],
  "docs/validation-results.md" => [
    "exact preregistered Stage 3 build remains",
    "Exact pilot build `#{EXACT_STAGE_3_BUILD}`",
    "The exact Stage 3 build is `#{EXACT_STAGE_3_BUILD}`",
    "RC4 predates RC5's bare-`fix` paste workflow"
  ],
  ".github/ISSUE_TEMPLATE/validation-report.yml" => [
    "The exact Stage 3 build is `#{EXACT_STAGE_3_BUILD}`"
  ]
}

pilot_build_references.each do |name, required_text|
  path = ROOT.join(name)
  unless path.file?
    errors << "missing pilot-build reference: #{name}"
    next
  end

  source = path.read
  required_text.each do |text|
    errors << "#{name}: missing exact-build guard #{text.inspect}" unless source.include?(text)
  end
end

unless errors.empty?
  warn errors.join("\n")
  exit 1
end

puts "Validated #{EXPECTED_HEADERS.length} blank research data templates and the aggregate report"
