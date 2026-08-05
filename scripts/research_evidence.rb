#!/usr/bin/env ruby
# frozen_string_literal: true

require "csv"
require "date"
require "json"
require "pathname"

module ResearchEvidence
  ROOT = Pathname.new(__dir__).join("..").cleanpath
  REGISTRATION_PATH = ROOT.join("research", "pilot-registration.json")
  STAGE_3_TEMPLATE_PATH = ROOT.join("research", "templates", "stage-3-repository-weeks.csv")

  STAGE_3_HEADERS = %w[
    repository_alias week fixcard_version pilot_users weekly_active_users
    active_users_with_three_cards lookup_attempts strong_matches
    relevant_strong_matches correct_abstentions incorrect_abstentions
    search_p95_ms end_to_end_lookup_seconds_samples
    full_lookups_under_ten_seconds fixcard_used_first other_tool_used_first
    authored_cards capture_seconds_samples cumulative_unique_active_reusers
    author_reuses teammate_reuses shared_submitted shared_accepted
    shared_changed shared_rejected retired_cards scanner_catches
    scanner_false_positives missed_real_secrets serious_trust_incidents
    differentiation_yes differentiation_responses maintenance_burden
  ].freeze

  ELIGIBLE_EVIDENCE_KEYS = %w[
    permissioned_second_reviewed_real_pairs stage_1_recruited_participants
    stage_1_completed_two_week_diaries stage_2_real_card_observations
    stage_3_repositories stage_3_repository_weeks
  ].freeze

  EXPECTED_PROTOCOL_DOCUMENTS = %w[
    docs/research-study.md docs/research-operations.md docs/validation.md
    docs/dogfood.md
  ].freeze

  EXPECTED_FIXED_GATES = {
    "milestone_0" => {
      "real_pairs_minimum" => 100,
      "permission_required" => true,
      "second_person_review_required" => true
    },
    "stage_1" => {
      "recruited_participants_minimum" => 24,
      "recruited_participants_maximum" => 30,
      "working_weeks" => 2,
      "reusable_failure_participant_share_minimum" => 0.3333333333,
      "denominator" => "all_recruited_participants"
    },
    "stage_2" => {
      "real_cards_per_participant" => 3,
      "median_creation_seconds_maximum" => 30,
      "correct_rank_one_share_minimum" => 0.7,
      "trust_preference_share_minimum" => 0.6,
      "maintainer_accepted_cards_minimum" => 5
    },
    "stage_3" => {
      "strong_rank_one_relevance_share_minimum" => 0.75,
      "strong_rank_one_relevance_target" => 0.85,
      "search_p95_ms_maximum" => 100,
      "full_lookup_under_ten_seconds_requirement" => "usually",
      "median_capture_seconds_maximum" => 20,
      "active_users_with_three_cards_share_minimum" => 0.5,
      "active_user_reuse_share_minimum" => 0.3,
      "shared_cards_accepted_minimum" => 5,
      "serious_trust_incidents_maximum" => 0,
      "missed_real_secrets_maximum" => 0,
      "differentiation_share_requirement" => "strict_majority",
      "maintenance_burden_requirement" => "acceptable"
    },
    "stable_promotion" => "milestone_0_and_every_stage_and_every_kill_criterion_reviewed"
  }.freeze

  EXPECTED_KILL_CRITERIA = [
    "More than 80% of relevant developers create no card after onboarding.",
    "Median creation remains above 30 seconds.",
    "Strong-match false positives exceed 20%.",
    "Most users prefer ordinary history, Atuin, Recall, or equivalent search.",
    "Fewer than 10% of cards are reused by another person over eight weeks in active teams.",
    "Teams refuse committed cards as clutter or liability.",
    "Secret redaction is not reliable enough for shared cards.",
    "Cards become stale faster than they are used.",
    "The product needs automatic terminal capture to feel valuable.",
    "Adoption depends on AI generation, cloud sync, or workflow replay."
  ].freeze

  COUNT_FIELDS = %w[
    pilot_users weekly_active_users active_users_with_three_cards lookup_attempts
    strong_matches relevant_strong_matches correct_abstentions
    incorrect_abstentions full_lookups_under_ten_seconds fixcard_used_first
    other_tool_used_first authored_cards cumulative_unique_active_reusers
    author_reuses teammate_reuses shared_submitted shared_accepted
    shared_changed shared_rejected retired_cards scanner_catches
    scanner_false_positives missed_real_secrets serious_trust_incidents
    differentiation_yes differentiation_responses
  ].freeze

  TIMING_FIELDS = %w[
    end_to_end_lookup_seconds_samples capture_seconds_samples
  ].freeze

  MAINTENANCE_VALUES = ["acceptable", "unacceptable", "too_early_to_judge"].freeze

  module_function

  def load_registration(path = REGISTRATION_PATH)
    JSON.parse(File.read(path, encoding: "UTF-8"))
  rescue Errno::ENOENT => e
    raise ArgumentError, "missing registration: #{e.message}"
  rescue JSON::ParserError => e
    raise ArgumentError, "invalid registration JSON: #{e.message}"
  end

  def validate_registration(registration)
    errors = []
    expected_version = registration.dig("pilot", "version")
    expected_tag = registration.dig("pilot", "tag")
    expected_commit = registration.dig("pilot", "commit")

    errors << "registration: schema_version must be 1" unless registration["schema_version"] == 1
    errors << "registration: status must be pre_data_amendment" unless registration["status"] == "pre_data_amendment"
    registered_on = begin
      Date.iso8601(registration.fetch("registered_on"))
    rescue ArgumentError, KeyError, TypeError
      errors << "registration: registered_on must be a real YYYY-MM-DD date"
      nil
    end
    errors << "registration: exact pilot version is missing" unless expected_version.to_s.match?(/\A1\.0\.0-rc\.\d+\z/)
    errors << "registration: tag must equal v + version" unless expected_tag == "v#{expected_version}"
    errors << "registration: commit must be a full SHA-1" unless expected_commit.to_s.match?(/\A[0-9a-f]{40}\z/)
    errors << "registration: protocol commit must be a full SHA-1" unless registration.dig("protocol", "commit").to_s.match?(/\A[0-9a-f]{40}\z/)
    errors << "registration: evidence must not carry forward" unless registration.dig("amendment", "carry_forward_eligible_evidence") == false

    counts = registration.dig("amendment", "eligible_evidence_at_registration")
    unless counts.is_a?(Hash) && counts.keys.sort == ELIGIBLE_EVIDENCE_KEYS.sort && counts.values.all? { |value| value == 0 }
      errors << "registration: every required eligible-evidence count must be present and explicitly zero"
    end

    errors << "registration: pilot must cover exactly four working weeks" unless registration.dig("pilot", "working_weeks") == 4
    errors << "registration: repository minimum must be 5" unless registration.dig("pilot", "repositories", "minimum") == 5
    errors << "registration: repository maximum must be 8" unless registration.dig("pilot", "repositories", "maximum") == 8
    errors << "registration: build switching must be forbidden" unless registration.dig("pilot", "build_switching") == "forbidden"
    errors << "registration: security restart rule must be explicit" unless registration.dig("pilot", "security_fix_rule") == "stop_document_and_preregister_restart"

    eligible_on = begin
      Date.iso8601(registration.dig("pilot", "eligible_observations_on_or_after"))
    rescue ArgumentError, TypeError
      errors << "registration: eligible observation date must use YYYY-MM-DD"
      nil
    end
    errors << "registration: observations must begin after registration" if registered_on && eligible_on && eligible_on <= registered_on

    checksums = registration.dig("release", "archive_sha256")
    expected_assets = %w[
      aarch64-apple-darwin.tar.gz aarch64-unknown-linux-gnu.tar.gz
      x86_64-apple-darwin.tar.gz x86_64-pc-windows-msvc.zip
      x86_64-unknown-linux-gnu.tar.gz x86_64-unknown-linux-musl.tar.gz
    ].map { |suffix| "fixcard-#{expected_version}-#{suffix}" }
    unless checksums.is_a?(Hash) && checksums.keys.sort == expected_assets.sort && checksums.values.all? { |digest| digest.match?(/\A[0-9a-f]{64}\z/) }
      errors << "registration: exactly six archive SHA-256 digests are required"
    end

    errors << "registration: release URL must match the exact tag" unless registration.dig("release", "url") == "https://github.com/MarinJursic/fixcard/releases/tag/#{expected_tag}"
    errors << "registration: release must remain a prerelease" unless registration.dig("release", "prerelease") == true
    errors << "registration: release must contain eight assets" unless registration.dig("release", "asset_count") == 8
    errors << "registration: checksum asset must be SHA256SUMS" unless registration.dig("release", "checksum_asset") == "SHA256SUMS"
    errors << "registration: SBOM asset must be fixcard.cdx.json" unless registration.dig("release", "sbom_asset") == "fixcard.cdx.json"

    errors << "registration: fixed gates differ from the predeclared protocol" unless registration["fixed_gates"] == EXPECTED_FIXED_GATES

    criteria = registration["kill_criteria"]
    unless criteria.is_a?(Array) &&
           criteria.map { |item| item["id"] } == (1..10).to_a &&
           criteria.map { |item| item["criterion"] } == EXPECTED_KILL_CRITERIA
      errors << "registration: all ten kill criteria must be frozen in order"
    end

    documents = Array(registration.dig("protocol", "documents"))
    errors << "registration: protocol document set differs" unless documents == EXPECTED_PROTOCOL_DOCUMENTS
    documents.each do |document|
      errors << "registration: missing protocol document #{document}" unless ROOT.join(document).file?
    end

    errors
  end

  def validate_stage3_table(table, exact_version:, complete_pilot: false)
    errors = []
    errors << "Stage 3 CSV: headers differ from the registered schema" unless table.headers == STAGE_3_HEADERS
    seen_repository_weeks = {}
    pilot_users_by_repository = {}
    reusers_by_repository = Hash.new { |hash, key| hash[key] = [] }

    table.each_with_index do |row, index|
      line = index + 2
      repository = row["repository_alias"].to_s
      version = row["fixcard_version"].to_s
      week = integer(row["week"])

      errors << "line #{line}: repository_alias must look like R001" unless repository.match?(/\AR\d{3,}\z/)
      errors << "line #{line}: fixcard_version must be exactly #{exact_version.inspect}, got #{version.inspect}" unless version == exact_version
      errors << "line #{line}: week must be an integer from 1 through 4" unless week && (1..4).cover?(week)

      key = [repository, week]
      errors << "line #{line}: duplicate repository/week #{key.inspect}" if seen_repository_weeks.key?(key)
      seen_repository_weeks[key] = true

      counts = {}
      COUNT_FIELDS.each do |field|
        value = row[field]
        next if value.nil? || value.empty?

        parsed = integer(value)
        if parsed.nil? || parsed.negative?
          errors << "line #{line}: #{field} must be a non-negative integer or blank"
        else
          counts[field] = parsed
        end
      end

      validate_upper_bound(errors, line, counts, "weekly_active_users", "pilot_users")
      validate_upper_bound(errors, line, counts, "active_users_with_three_cards", "weekly_active_users")
      validate_upper_bound(errors, line, counts, "strong_matches", "lookup_attempts")
      validate_upper_bound(errors, line, counts, "relevant_strong_matches", "strong_matches")
      %w[full_lookups_under_ten_seconds fixcard_used_first other_tool_used_first].each do |field|
        validate_upper_bound(errors, line, counts, field, "lookup_attempts")
      end
      validate_upper_bound(errors, line, counts, "cumulative_unique_active_reusers", "pilot_users")
      %w[shared_accepted shared_changed shared_rejected].each do |field|
        validate_upper_bound(errors, line, counts, field, "shared_submitted")
      end
      validate_upper_bound(errors, line, counts, "differentiation_yes", "differentiation_responses")
      validate_upper_bound(errors, line, counts, "differentiation_responses", "pilot_users")

      if counts.values_at("strong_matches", "correct_abstentions", "incorrect_abstentions", "lookup_attempts").all?
        classified = counts["strong_matches"] + counts["correct_abstentions"] + counts["incorrect_abstentions"]
        errors << "line #{line}: strong matches plus abstentions must equal lookup_attempts" unless classified == counts["lookup_attempts"]
      end

      if counts.values_at("fixcard_used_first", "other_tool_used_first", "lookup_attempts").all?
        first_tool_total = counts["fixcard_used_first"] + counts["other_tool_used_first"]
        errors << "line #{line}: first-tool counts cannot exceed lookup_attempts" if first_tool_total > counts["lookup_attempts"]
      end

      if counts.values_at("shared_accepted", "shared_changed", "shared_rejected", "shared_submitted").all?
        reviewed = counts["shared_accepted"] + counts["shared_changed"] + counts["shared_rejected"]
        errors << "line #{line}: reviewed shared-card outcomes cannot exceed shared_submitted" if reviewed > counts["shared_submitted"]
      end

      TIMING_FIELDS.each do |field|
        next if row[field].nil? || row[field].empty?

        samples = row[field].split(";", -1)
        valid = samples.all? { |sample| numeric?(sample) && sample.to_f >= 0 }
        errors << "line #{line}: #{field} must be semicolon-separated non-negative numbers" unless valid
      end

      unless row["search_p95_ms"].nil? || row["search_p95_ms"].empty? || (numeric?(row["search_p95_ms"]) && row["search_p95_ms"].to_f >= 0)
        errors << "line #{line}: search_p95_ms must be a non-negative number or blank"
      end

      burden = row["maintenance_burden"].to_s
      unless burden.empty? || MAINTENANCE_VALUES.include?(burden)
        errors << "line #{line}: maintenance_burden must be blank or one of #{MAINTENANCE_VALUES.join(', ')}"
      end

      if counts["pilot_users"]
        previous = pilot_users_by_repository[repository]
        errors << "line #{line}: pilot_users changed within #{repository}" if previous && previous != counts["pilot_users"]
        pilot_users_by_repository[repository] = counts["pilot_users"]
      end
      reusers_by_repository[repository] << [week, counts["cumulative_unique_active_reusers"], line] if week && counts["cumulative_unique_active_reusers"]
    end

    reusers_by_repository.each_value do |observations|
      observations.sort_by!(&:first)
      observations.each_cons(2) do |previous, current|
        errors << "line #{current[2]}: cumulative_unique_active_reusers cannot decrease" if current[1] < previous[1]
      end
    end

    if complete_pilot
      repositories = seen_repository_weeks.keys.map(&:first).uniq
      errors << "complete pilot: expected 5 through 8 repositories, got #{repositories.length}" unless (5..8).cover?(repositories.length)
      repositories.each do |repository|
        weeks = seen_repository_weeks.keys.each_with_object([]) do |(name, week), selected|
          selected << week if name == repository
        end.sort
        errors << "complete pilot: #{repository} must contain weeks 1, 2, 3, and 4" unless weeks == [1, 2, 3, 4]
      end
    end

    errors
  end

  def integer(value)
    Integer(value, 10)
  rescue ArgumentError, TypeError
    nil
  end

  def numeric?(value)
    Float(value, exception: false) && value.to_s.match?(/\A(?:\d+(?:\.\d*)?|\.\d+)\z/)
  end

  def validate_upper_bound(errors, line, counts, numerator, denominator)
    return unless counts[numerator] && counts[denominator]
    return if counts[numerator] <= counts[denominator]

    errors << "line #{line}: #{numerator} cannot exceed #{denominator}"
  end
end

if $PROGRAM_NAME == __FILE__
  complete_pilot = ARGV.delete("--complete-pilot")
  path = ARGV.shift
  abort "usage: ruby scripts/research_evidence.rb [--complete-pilot] STAGE_3_CSV" unless path && ARGV.empty?

  registration = ResearchEvidence.load_registration
  errors = ResearchEvidence.validate_registration(registration)
  table = CSV.read(path, headers: true)
  errors.concat(
    ResearchEvidence.validate_stage3_table(
      table,
      exact_version: registration.dig("pilot", "version"),
      complete_pilot: complete_pilot
    )
  )

  abort errors.join("\n") unless errors.empty?

  puts "Validated #{table.length} Stage 3 rows against exact build #{registration.dig('pilot', 'version')}"
end
