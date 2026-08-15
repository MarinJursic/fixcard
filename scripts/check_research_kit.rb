#!/usr/bin/env ruby
# frozen_string_literal: true

require "csv"
require "pathname"
require "tempfile"

require_relative "research_evidence"

ROOT = Pathname.new(__dir__).join("..").cleanpath

EXPECTED_HEADERS = {
  "stage-1-participants.csv" => %w[
    participant_alias recruitment_context context_alias role_band platform
    consented completed_diary qualifying_failures reusable_failures
    recurrent_failures repository_specific_failures previously_saved_failures
  ],
  "stage-2-observations.csv" => %w[
    participant_alias card_alias maintainer_alias fixcard_version creation_seconds controlled_variants
    correct_rank_one fixcard_lookup_seconds_samples normal_search_seconds_samples
    metadata_confusion_observed privacy_edits scanner_false_positives
    trust_preferred maintainer_decision card_committed
  ],
  "stage-3-repository-weeks.csv" => %w[
    repository_alias week observation_start observation_end fixcard_version
    pilot_users weekly_active_users
    active_users_with_three_cards lookup_attempts strong_matches
    relevant_strong_matches correct_abstentions incorrect_abstentions
    search_p95_ms end_to_end_lookup_seconds_samples
    full_lookups_under_ten_seconds fixcard_used_first other_tool_used_first
    authored_cards capture_seconds_samples cumulative_unique_active_users
    cumulative_unique_active_reusers
    author_reuses teammate_reuses
    shared_submitted shared_accepted shared_changed shared_rejected retired_cards
    scanner_catches scanner_false_positives
    users_bypassing_scanner_due_false_positives missed_real_secrets
    serious_trust_incidents differentiation_yes differentiation_responses
    maintenance_burden
  ],
  "stage-3-active-user-reuse.csv" => %w[
    participant_alias repository_alias fixcard_version active_during_weeks_1_4
    reused_or_teammate_reused_during_weeks_1_4
  ],
  "stage-3-eight-week-card-reuse.csv" => %w[
    repository_alias card_alias fixcard_version authored_on follow_up_end
    available_to_teammates reused_by_other_person_by_week_8
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
  interruption = ResearchEvidence.load_interruption
  errors.concat(ResearchEvidence.validate_registration(registration, interruption: interruption))
  errors.concat(ResearchEvidence.validate_interruption(interruption))
  exact_version = registration.dig("pilot", "version")
  eligible_on = ResearchEvidence.iso_date(registration.dig("pilot", "eligible_observations_on_or_after"))

  version_mutation = JSON.parse(JSON.generate(registration))
  version_mutation["pilot"]["version"] = "1.0.0-rc.6"
  version_mutation_errors = ResearchEvidence.validate_registration(version_mutation)
  unless version_mutation_errors.any? { |error| error.include?("exact pilot version") }
    errors << "registration accepted a non-RC4 pilot version"
  end

  date_mutation = JSON.parse(JSON.generate(registration))
  date_mutation["pilot"]["eligible_observations_on_or_after"] = "2026-08-11"
  date_mutation_errors = ResearchEvidence.validate_registration(date_mutation)
  unless date_mutation_errors.any? { |error| error.include?("eligible date differs") }
    errors << "registration accepted a changed RC4 eligibility date"
  end

  checksum_mutation = JSON.parse(JSON.generate(registration))
  checksum_mutation["release"]["archive_sha256"].values[0].replace("0" * 64)
  checksum_mutation_errors = ResearchEvidence.validate_registration(checksum_mutation)
  unless checksum_mutation_errors.any? { |error| error.include?("archive SHA-256 set differs") }
    errors << "registration accepted changed RC4 archive digests"
  end

  supersedes_mutation = JSON.parse(JSON.generate(registration))
  supersedes_mutation["amendment"]["supersedes_version"] = "1.0.0-rc.2"
  supersedes_mutation_errors = ResearchEvidence.validate_registration(supersedes_mutation)
  unless supersedes_mutation_errors.any? { |error| error.include?("amendment superseded version differs") }
    errors << "registration accepted a changed amendment superseded version"
  end

  reason_mutation = JSON.parse(JSON.generate(registration))
  reason_mutation["amendment"]["reason"] = "rewritten after registration"
  reason_mutation_errors = ResearchEvidence.validate_registration(reason_mutation)
  unless reason_mutation_errors.any? { |error| error.include?("amendment reason differs") }
    errors << "registration accepted a changed amendment reason"
  end

  protocol_commit_mutation = JSON.parse(JSON.generate(registration))
  protocol_commit_mutation["protocol"]["commit"] = "0" * 40
  protocol_commit_mutation_errors = ResearchEvidence.validate_registration(protocol_commit_mutation)
  unless protocol_commit_mutation_errors.any? { |error| error.include?("protocol commit differs from the frozen") }
    errors << "registration accepted a changed protocol commit"
  end

  interruption_mutation = JSON.parse(JSON.generate(interruption))
  interruption_mutation["collection_open"] = true
  if ResearchEvidence.validate_interruption(interruption_mutation).empty?
    errors << "interruption record accepted an open collection"
  end
  if ResearchEvidence.validate_intake_authorization(registration, interruption).empty?
    errors << "evidence intake remained open during the registered pause"
  end
  if ResearchEvidence.validate_intake_authorization(registration, interruption_mutation).empty?
    errors << "evidence intake accepted an open flag without an exact eligible build"
  end
  interruption_mutation["eligible_build"] = registration.fetch("pilot").slice("version", "tag", "commit")
  if ResearchEvidence.validate_intake_authorization(registration, interruption_mutation).empty?
    errors << "evidence intake accepted an unfrozen open RC4 mutation"
  end

  stage_2 = tables["stage-2-observations.csv"]
  if stage_2
    errors << "Stage 2 schema differs between the template checker and evidence validator" unless EXPECTED_HEADERS.fetch("stage-2-observations.csv") == ResearchEvidence::STAGE_2_HEADERS
    errors.concat(ResearchEvidence.validate_stage2_table(stage_2, exact_version: exact_version))
    stage_2_headers = EXPECTED_HEADERS.fetch("stage-2-observations.csv")
    stage_2_row = lambda do |version|
      values = stage_2_headers.map do |header|
        {
          "participant_alias" => "P001",
          "card_alias" => "C001",
          "fixcard_version" => version,
          "controlled_variants" => "0",
          "correct_rank_one" => "0",
          "maintainer_decision" => "not_reviewed",
          "card_committed" => "false"
        }.fetch(header, "")
      end
      CSV::Table.new([CSV::Row.new(stage_2_headers, values)])
    end
    exact_stage_2_errors = ResearchEvidence.validate_stage2_table(stage_2_row.call(exact_version), exact_version: exact_version)
    errors << "Stage 2 exact-build control failed: #{exact_stage_2_errors.join('; ')}" unless exact_stage_2_errors.empty?
    previous_version = registration.dig("amendment", "supersedes_version")
    errors << "Stage 2 mixed-build mutation was accepted" if ResearchEvidence.validate_stage2_table(stage_2_row.call(previous_version), exact_version: exact_version).empty?
    errors << "Stage 2 blank-build mutation was accepted" if ResearchEvidence.validate_stage2_table(stage_2_row.call(""), exact_version: exact_version).empty?

    missing_variant_denominator = stage_2_row.call(exact_version)
    missing_variant_denominator.first["controlled_variants"] = ""
    missing_variant_denominator.first["correct_rank_one"] = "100"
    if ResearchEvidence.validate_stage2_table(missing_variant_denominator, exact_version: exact_version).empty?
      errors << "Stage 2 rank-one numerator without controlled-variant denominator was accepted"
    end

    missing_rank_one_numerator = stage_2_row.call(exact_version)
    missing_rank_one_numerator.first["controlled_variants"] = "100"
    missing_rank_one_numerator.first["correct_rank_one"] = ""
    if ResearchEvidence.validate_stage2_table(missing_rank_one_numerator, exact_version: exact_version).empty?
      errors << "Stage 2 controlled-variant denominator without rank-one numerator was accepted"
    end

    invalid_trust = stage_2_row.call(exact_version)
    invalid_trust.first["trust_preferred"] = "sometimes"
    errors << "Stage 2 invalid trust response was accepted" if ResearchEvidence.validate_stage2_table(invalid_trust, exact_version: exact_version).empty?

    invalid_metadata_confusion = stage_2_row.call(exact_version)
    invalid_metadata_confusion.first["metadata_confusion_observed"] = "maybe"
    errors << "Stage 2 invalid metadata-confusion value was accepted" if ResearchEvidence.validate_stage2_table(invalid_metadata_confusion, exact_version: exact_version).empty?

    conflicting_trust_rows = [stage_2_row.call(exact_version).first, stage_2_row.call(exact_version).first.dup]
    conflicting_trust_rows[0]["trust_preferred"] = "fixcard"
    conflicting_trust_rows[1]["card_alias"] = "C002"
    conflicting_trust_rows[1]["trust_preferred"] = "normal_search"
    conflicting_trust = CSV::Table.new(conflicting_trust_rows)
    errors << "Stage 2 conflicting participant trust responses were accepted" if ResearchEvidence.validate_stage2_table(conflicting_trust, exact_version: exact_version).empty?

    missing_reviewer = stage_2_row.call(exact_version)
    missing_reviewer.first["maintainer_decision"] = "accepted"
    errors << "Stage 2 reviewed card without maintainer alias was accepted" if ResearchEvidence.validate_stage2_table(missing_reviewer, exact_version: exact_version).empty?

    missing_committed_state = stage_2_row.call(exact_version)
    missing_committed_state.first["card_committed"] = ""
    errors << "Stage 2 row without committed state was accepted" if ResearchEvidence.validate_stage2_table(missing_committed_state, exact_version: exact_version).empty?

    unaccepted_committed_card = stage_2_row.call(exact_version)
    unaccepted_committed_card.first["card_committed"] = "true"
    errors << "Stage 2 unaccepted committed card was accepted" if ResearchEvidence.validate_stage2_table(unaccepted_committed_card, exact_version: exact_version).empty?

    invalid_decision = stage_2_row.call(exact_version)
    invalid_decision.first["maintainer_decision"] = "maybe"
    errors << "Stage 2 invalid maintainer decision was accepted" if ResearchEvidence.validate_stage2_table(invalid_decision, exact_version: exact_version).empty?

    unpaired_timings = stage_2_row.call(exact_version)
    unpaired_timings.first["fixcard_lookup_seconds_samples"] = "1;2"
    errors << "Stage 2 unpaired lookup timings were accepted" if ResearchEvidence.validate_stage2_table(unpaired_timings, exact_version: exact_version).empty?

    unequal_timings = stage_2_row.call(exact_version)
    unequal_timings.first["fixcard_lookup_seconds_samples"] = "1;2"
    unequal_timings.first["normal_search_seconds_samples"] = "3"
    errors << "Stage 2 unequal lookup timing counts were accepted" if ResearchEvidence.validate_stage2_table(unequal_timings, exact_version: exact_version).empty?

    complete_stage_2_control = stage_2_row.call(exact_version)
    complete_stage_2_control.first["maintainer_alias"] = "M001"
    complete_stage_2_control.first["maintainer_decision"] = "accepted"
    complete_stage_2_control.first["card_committed"] = "true"
    complete_stage_2_control.first["trust_preferred"] = "fixcard"
    complete_stage_2_control.first["fixcard_lookup_seconds_samples"] = "1;2"
    complete_stage_2_control.first["normal_search_seconds_samples"] = "3;4"
    complete_stage_2_errors = ResearchEvidence.validate_stage2_table(complete_stage_2_control, exact_version: exact_version)
    errors << "Stage 2 complete-row control failed: #{complete_stage_2_errors.join('; ')}" unless complete_stage_2_errors.empty?
  end

  active_user_reuse = tables["stage-3-active-user-reuse.csv"]
  if active_user_reuse
    errors << "Stage 3 active-user schema differs between checker and validator" unless EXPECTED_HEADERS.fetch("stage-3-active-user-reuse.csv") == ResearchEvidence::STAGE_3_USER_REUSE_HEADERS
    errors.concat(ResearchEvidence.validate_stage3_user_reuse_table(active_user_reuse, exact_version: exact_version))
    reuse_headers = EXPECTED_HEADERS.fetch("stage-3-active-user-reuse.csv")
    reuse_row = lambda do |version, active: "true", reused: "true", participant: "P001", repository: "R001"|
      CSV::Table.new([
        CSV::Row.new(reuse_headers, [participant, repository, version, active, reused])
      ])
    end
    valid_reuse_errors = ResearchEvidence.validate_stage3_user_reuse_table(reuse_row.call(exact_version), exact_version: exact_version)
    errors << "Stage 3 active-user control failed: #{valid_reuse_errors.join('; ')}" unless valid_reuse_errors.empty?
    errors << "Stage 3 active-user mixed-build mutation was accepted" if ResearchEvidence.validate_stage3_user_reuse_table(reuse_row.call(registration.dig("amendment", "supersedes_version")), exact_version: exact_version).empty?
    errors << "Stage 3 inactive-reuser mutation was accepted" if ResearchEvidence.validate_stage3_user_reuse_table(reuse_row.call(exact_version, active: "false", reused: "true"), exact_version: exact_version).empty?
  end

  card_reuse = tables["stage-3-eight-week-card-reuse.csv"]
  if card_reuse
    errors << "Stage 3 eight-week card schema differs between checker and validator" unless EXPECTED_HEADERS.fetch("stage-3-eight-week-card-reuse.csv") == ResearchEvidence::STAGE_3_CARD_REUSE_HEADERS
    errors.concat(ResearchEvidence.validate_stage3_card_reuse_table(card_reuse, exact_version: exact_version, eligible_on: eligible_on))
    card_headers = EXPECTED_HEADERS.fetch("stage-3-eight-week-card-reuse.csv")
    card_row = lambda do |version, available: "true", reused: "true", authored: eligible_on.iso8601|
      values = ["R001", "C001", version, authored, (eligible_on + 55).iso8601, available, reused]
      CSV::Table.new([CSV::Row.new(card_headers, values)])
    end
    valid_card_errors = ResearchEvidence.validate_stage3_card_reuse_table(card_row.call(exact_version), exact_version: exact_version, eligible_on: eligible_on)
    errors << "Stage 3 eight-week card control failed: #{valid_card_errors.join('; ')}" unless valid_card_errors.empty?
    errors << "Stage 3 eight-week mixed-build mutation was accepted" if ResearchEvidence.validate_stage3_card_reuse_table(card_row.call(registration.dig("amendment", "supersedes_version")), exact_version: exact_version, eligible_on: eligible_on).empty?
    errors << "Stage 3 unavailable-card reuse mutation was accepted" if ResearchEvidence.validate_stage3_card_reuse_table(card_row.call(exact_version, available: "false", reused: "true"), exact_version: exact_version, eligible_on: eligible_on).empty?
  end

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

    partial_abstention_errors = ResearchEvidence.validate_stage3_table(
      build_row.call(exact_version, "lookup_attempts" => "1", "correct_abstentions" => "2"),
      exact_version: exact_version
    )
    errors << "Stage 3 partial-abstention overcount mutation was accepted" if partial_abstention_errors.empty?

    partial_shared_errors = ResearchEvidence.validate_stage3_table(
      build_row.call(
        exact_version,
        "shared_submitted" => "5",
        "shared_accepted" => "5",
        "shared_changed" => "5"
      ),
      exact_version: exact_version
    )
    errors << "Stage 3 partial shared-outcome overcount mutation was accepted" if partial_shared_errors.empty?

    timing_errors = ResearchEvidence.validate_stage3_table(
      build_row.call(
        exact_version,
        "lookup_attempts" => "1",
        "end_to_end_lookup_seconds_samples" => "1.2;2.3"
      ),
      exact_version: exact_version
    )
    errors << "Stage 3 excess-timing-samples mutation was accepted" if timing_errors.empty?

    contradictory_timing_errors = ResearchEvidence.validate_stage3_table(
      build_row.call(
        exact_version,
        "lookup_attempts" => "2",
        "end_to_end_lookup_seconds_samples" => "12;13",
        "full_lookups_under_ten_seconds" => "2"
      ),
      exact_version: exact_version
    )
    errors << "Stage 3 contradictory under-ten timing mutation was accepted" if contradictory_timing_errors.empty?

    missing_timing_count_errors = ResearchEvidence.validate_stage3_table(
      build_row.call(
        exact_version,
        "lookup_attempts" => "2",
        "end_to_end_lookup_seconds_samples" => "8;12"
      ),
      exact_version: exact_version
    )
    errors << "Stage 3 missing derived timing count was accepted" if missing_timing_count_errors.empty?

    valid_timing_errors = ResearchEvidence.validate_stage3_table(
      build_row.call(
        exact_version,
        "lookup_attempts" => "3",
        "end_to_end_lookup_seconds_samples" => "9;10;2.5",
        "full_lookups_under_ten_seconds" => "2"
      ),
      exact_version: exact_version
    )
    errors << "Stage 3 derived under-ten timing control failed: #{valid_timing_errors.join('; ')}" unless valid_timing_errors.empty?

    scanner_errors = ResearchEvidence.validate_stage3_table(
      build_row.call(
        exact_version,
        "pilot_users" => "1",
        "users_bypassing_scanner_due_false_positives" => "2"
      ),
      exact_version: exact_version
    )
    errors << "Stage 3 scanner-bypass denominator mutation was accepted" if scanner_errors.empty?

    cumulative_active_errors = ResearchEvidence.validate_stage3_table(
      build_row.call(
        exact_version,
        "pilot_users" => "5",
        "weekly_active_users" => "5",
        "cumulative_unique_active_users" => "1"
      ),
      exact_version: exact_version
    )
    errors << "Stage 3 understated cumulative-active mutation was accepted" if cumulative_active_errors.empty?

    unbacked_three_card_users_errors = ResearchEvidence.validate_stage3_table(
      build_row.call(
        exact_version,
        "active_users_with_three_cards" => "1",
        "authored_cards" => "0"
      ),
      exact_version: exact_version
    )
    errors << "Stage 3 qualifying-user numerator without three authored cards was accepted" if unbacked_three_card_users_errors.empty?

    missing_authored_cards_errors = ResearchEvidence.validate_stage3_table(
      build_row.call(
        exact_version,
        "active_users_with_three_cards" => "1"
      ),
      exact_version: exact_version
    )
    errors << "Stage 3 qualifying-user numerator without an authored-card count was accepted" if missing_authored_cards_errors.empty?

    complete_rows = (1..5).flat_map do |repository_number|
      (1..4).map do |week|
        start_date = eligible_on + ((week - 1) * 7)
        required_counts = ResearchEvidence::COUNT_FIELDS.to_h { |field| [field, "0"] }
        required_counts.delete("differentiation_yes") unless week == 4
        required_counts.delete("differentiation_responses") unless week == 4
        build_row.call(
          exact_version,
          required_counts.merge(
            "repository_alias" => format("R%03d", repository_number),
            "week" => week.to_s,
            "observation_start" => start_date.iso8601,
            "observation_end" => (start_date + 6).iso8601,
            "pilot_users" => "1",
            "weekly_active_users" => week == 1 ? "1" : "0",
            "cumulative_unique_active_users" => "1",
            "maintenance_burden" => week == 4 ? "acceptable" : ""
          )
        ).first
      end
    end
    complete_table = CSV::Table.new(complete_rows)
    complete_errors = ResearchEvidence.validate_stage3_table(
      complete_table,
      exact_version: exact_version,
      eligible_on: eligible_on,
      complete_pilot: true
    )
    errors << "Stage 3 complete-pilot control failed: #{complete_errors.join('; ')}" unless complete_errors.empty?

    complete_reuse_rows = (1..5).map do |repository_number|
      reuse_row.call(
        exact_version,
        reused: "false",
        participant: format("P%03d", repository_number),
        repository: format("R%03d", repository_number)
      ).first
    end
    complete_reuse_table = CSV::Table.new(complete_reuse_rows)
    coverage_errors = ResearchEvidence.validate_stage3_cross_file_coverage(
      complete_table,
      complete_reuse_table,
      card_reuse
    )
    errors << "Stage 3 cross-file coverage control failed: #{coverage_errors.join('; ')}" unless coverage_errors.empty?

    omitted_users_errors = ResearchEvidence.validate_stage3_cross_file_coverage(
      complete_table,
      CSV::Table.new(complete_reuse_rows.first(1)),
      card_reuse
    )
    errors << "Stage 3 omitted active-user memberships were accepted" if omitted_users_errors.empty?

    authored_without_card_rows = complete_rows.map(&:dup)
    authored_without_card_rows.first["authored_cards"] = "1"
    missing_cards_errors = ResearchEvidence.validate_stage3_cross_file_coverage(
      CSV::Table.new(authored_without_card_rows),
      complete_reuse_table,
      card_reuse
    )
    errors << "Stage 3 omitted eight-week card rows were accepted" if missing_cards_errors.empty?

    incomplete_errors = ResearchEvidence.validate_stage3_table(
      CSV::Table.new(complete_rows[0...-1]),
      exact_version: exact_version,
      eligible_on: eligible_on,
      complete_pilot: true
    )
    errors << "Stage 3 incomplete-week mutation was accepted" if incomplete_errors.empty?

    too_few_errors = ResearchEvidence.validate_stage3_table(
      CSV::Table.new(complete_rows.select { |row| row["repository_alias"] != "R005" }),
      exact_version: exact_version,
      eligible_on: eligible_on,
      complete_pilot: true
    )
    errors << "Stage 3 four-repository mutation was accepted" if too_few_errors.empty?

    blank_complete_rows = complete_rows.map(&:dup)
    blank_complete_rows.each do |row|
      ResearchEvidence::COUNT_FIELDS.each { |field| row[field] = "" }
    end
    blank_complete_errors = ResearchEvidence.validate_stage3_table(
      CSV::Table.new(blank_complete_rows),
      exact_version: exact_version,
      eligible_on: eligible_on,
      complete_pilot: true
    )
    errors << "Stage 3 observation-free complete-pilot mutation was accepted" if blank_complete_errors.empty?

    selective_timing_rows = complete_rows.map(&:dup)
    selective_timing_rows.first["lookup_attempts"] = "100"
    selective_timing_rows.first["strong_matches"] = "100"
    selective_timing_rows.first["relevant_strong_matches"] = "100"
    selective_timing_rows.first["fixcard_used_first"] = "100"
    selective_timing_rows.first["end_to_end_lookup_seconds_samples"] = "1"
    selective_timing_rows.first["full_lookups_under_ten_seconds"] = "1"
    selective_timing_rows.first["search_p95_ms"] = "1"
    selective_timing_errors = ResearchEvidence.validate_stage3_table(
      CSV::Table.new(selective_timing_rows),
      exact_version: exact_version,
      eligible_on: eligible_on,
      complete_pilot: true
    )
    errors << "Stage 3 selective timing mutation was accepted" if selective_timing_errors.empty?

    early_rows = complete_rows.map(&:dup)
    early_rows.first["observation_start"] = (eligible_on - 7).iso8601
    early_rows.first["observation_end"] = (eligible_on - 1).iso8601
    early_errors = ResearchEvidence.validate_stage3_table(
      CSV::Table.new(early_rows),
      exact_version: exact_version,
      eligible_on: eligible_on,
      complete_pilot: true
    )
    errors << "Stage 3 pre-registration date mutation was accepted" if early_errors.empty?
  end

  dogfood = File.read(ROOT.join("docs", "dogfood.md"), encoding: "UTF-8")
  errors << "dogfood.md: must name exact pilot build #{exact_version}" unless dogfood.include?("`#{exact_version}`")
  errors << "dogfood.md: must not direct pilots to the newest candidate" if dogfood.match?(/newest release candidate/i)
  dogfood_pause_prefix = ResearchEvidence::PAUSE_HEADINGS.fetch("docs/dogfood.md") + ResearchEvidence::PAUSE_BANNERS.fetch("docs/dogfood.md")
  errors << "dogfood.md: must state that collection is paused" unless dogfood.start_with?(dogfood_pause_prefix)

  operations = File.read(ROOT.join("docs", "research-operations.md"), encoding: "UTF-8")
  operations_pause_prefix = ResearchEvidence::PAUSE_HEADINGS.fetch("docs/research-operations.md") + ResearchEvidence::PAUSE_BANNERS.fetch("docs/research-operations.md")
  errors << "research-operations.md: must state that collection is paused" unless operations.start_with?(operations_pause_prefix)

  validation = File.read(ROOT.join("docs", "validation.md"), encoding: "UTF-8")
  validation_pause_prefix = ResearchEvidence::PAUSE_HEADINGS.fetch("docs/validation.md") + ResearchEvidence::PAUSE_BANNERS.fetch("docs/validation.md")
  errors << "validation.md: must state that collection and intake are paused" unless validation.start_with?(validation_pause_prefix)

  results = File.read(ROOT.join("docs", "validation-results.md"), encoding: "UTF-8")
  errors << "validation-results.md: must name exact pilot build #{exact_version}" unless results.include?("`#{exact_version}`")
  errors << "validation-results.md: must state that public intake is disabled" unless results.include?("public validation intake form is disabled")

  research_readme = File.read(ROOT.join("research", "README.md"), encoding: "UTF-8")
  errors << "research/README.md: must state that collection is paused" unless research_readme.include?("No build is currently eligible")

  form_path = ROOT.join(".github", "ISSUE_TEMPLATE", "validation-report.yml")
  errors << "validation-report.yml: paused collection must not expose an active submission form" if form_path.exist?

  Tempfile.create(["malformed-stage-3", ".csv"]) do |file|
    file.write("repository_alias,week\n\"unterminated")
    file.flush
    begin
      ResearchEvidence.read_csv(file.path)
      errors << "malformed CSV mutation was accepted"
    rescue ArgumentError
      nil
    end
  end

  Tempfile.create(["non-object-registration", ".json"]) do |file|
    file.write("[]")
    file.flush
    begin
      ResearchEvidence.load_registration(file.path)
      errors << "non-object registration mutation was accepted"
    rescue ArgumentError
      nil
    end
  end
rescue ArgumentError, KeyError => e
  errors << "research registration controls: #{e.message}"
end

unless errors.empty?
  warn errors.join("\n")
  exit 1
end

puts "Validated #{EXPECTED_HEADERS.length} blank research templates, exact-build controls, and the aggregate report"
