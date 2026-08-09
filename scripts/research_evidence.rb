#!/usr/bin/env ruby
# frozen_string_literal: true

require "csv"
require "date"
require "digest"
require "json"
require "open3"
require "pathname"

module ResearchEvidence
  ROOT = Pathname.new(__dir__).join("..").cleanpath
  REGISTRATION_PATH = ROOT.join("research", "pilot-registration.json")
  STAGE_2_TEMPLATE_PATH = ROOT.join("research", "templates", "stage-2-observations.csv")
  STAGE_3_TEMPLATE_PATH = ROOT.join("research", "templates", "stage-3-repository-weeks.csv")
  STAGE_3_USER_REUSE_TEMPLATE_PATH = ROOT.join("research", "templates", "stage-3-active-user-reuse.csv")
  STAGE_3_CARD_REUSE_TEMPLATE_PATH = ROOT.join("research", "templates", "stage-3-eight-week-card-reuse.csv")

  MAX_INPUT_BYTES = 10 * 1024 * 1024
  MAX_FIELD_BYTES = 100_000

  EXPECTED_PILOT = {
    "registered_on" => "2026-08-05",
    "protocol_commit" => "64dede128d7f7fa56379baa488f5ba542fac3328",
    "amendment_supersedes_version" => "1.0.0-rc.3",
    "amendment_reason" => "RC4 was frozen as the exact Stage 3 treatment before any eligible external observation. Later product and usability builds do not qualify for the security-fix restart exception and are excluded from this pilot.",
    "version" => "1.0.0-rc.4",
    "tag" => "v1.0.0-rc.4",
    "commit" => "acf0c07944700085d56f50a02b26bbdf2525272d",
    "eligible_on" => "2026-08-10",
    "release_url" => "https://github.com/MarinJursic/fixcard/releases/tag/v1.0.0-rc.4",
    "workflow_url" => "https://github.com/MarinJursic/fixcard/actions/runs/30926021852",
    "homebrew_formula_commit" => "c22efbe78064a8c78192b778e270bb936e2cdb4d",
    "homebrew_formula_url" => "https://raw.githubusercontent.com/MarinJursic/homebrew-tap/c22efbe78064a8c78192b778e270bb936e2cdb4d/Formula/fixcard.rb",
    "archive_sha256" => {
      "fixcard-1.0.0-rc.4-aarch64-apple-darwin.tar.gz" => "9b9d28e7bc637ac6beb7f5c86175888ecc826b64aac1cd4de9116ef98306f0a0",
      "fixcard-1.0.0-rc.4-aarch64-unknown-linux-gnu.tar.gz" => "fd1102510c4ec90753a3ae45bbc2bbda07ee666b11bfb5d78abd25403c082c90",
      "fixcard-1.0.0-rc.4-x86_64-apple-darwin.tar.gz" => "ec17d3d9cb856b9b6d2acd7ce866ffbaf4fbcfd4ee9ef9702d403b427cfc2780",
      "fixcard-1.0.0-rc.4-x86_64-pc-windows-msvc.zip" => "17d1c47875aaae8971a620608a5b236e5f79d4a1b8d697b893591b27f8e2b60d",
      "fixcard-1.0.0-rc.4-x86_64-unknown-linux-gnu.tar.gz" => "513b4e0d4ca03def2749c555c8d85e8bf3f3e7d00847f17f3a3c503583b3237f",
      "fixcard-1.0.0-rc.4-x86_64-unknown-linux-musl.tar.gz" => "49cfce7b2d20588694446f1f25a325bd296b525148fb246cd27c92a911bdd139"
    }.freeze
  }.freeze

  STAGE_2_HEADERS = %w[
    participant_alias card_alias maintainer_alias fixcard_version
    creation_seconds controlled_variants correct_rank_one
    fixcard_lookup_seconds_samples normal_search_seconds_samples
    metadata_confusion_observed privacy_edits scanner_false_positives
    trust_preferred maintainer_decision
  ].freeze

  STAGE_3_USER_REUSE_HEADERS = %w[
    participant_alias repository_alias fixcard_version active_during_weeks_1_4
    reused_or_teammate_reused_during_weeks_1_4
  ].freeze

  STAGE_3_CARD_REUSE_HEADERS = %w[
    repository_alias card_alias fixcard_version authored_on follow_up_end
    available_to_teammates reused_by_other_person_by_week_8
  ].freeze

  STAGE_3_HEADERS = %w[
    repository_alias week observation_start observation_end fixcard_version
    pilot_users weekly_active_users
    active_users_with_three_cards lookup_attempts strong_matches
    relevant_strong_matches correct_abstentions incorrect_abstentions
    search_p95_ms end_to_end_lookup_seconds_samples
    full_lookups_under_ten_seconds fixcard_used_first other_tool_used_first
    authored_cards capture_seconds_samples cumulative_unique_active_users
    cumulative_unique_active_reusers
    author_reuses teammate_reuses shared_submitted shared_accepted
    shared_changed shared_rejected retired_cards scanner_catches
    scanner_false_positives users_bypassing_scanner_due_false_positives
    missed_real_secrets serious_trust_incidents
    differentiation_yes differentiation_responses maintenance_burden
  ].freeze

  ELIGIBLE_EVIDENCE_KEYS = %w[
    permissioned_second_reviewed_real_pairs stage_1_recruited_participants
    stage_1_completed_two_week_diaries stage_2_real_card_observations
    stage_3_repositories stage_3_repository_weeks
  ].freeze

  # The study documents are bound to EXPECTED_PILOT["protocol_commit"]. The
  # verifier scripts are intentionally outside this set because an executable
  # cannot contain the hash of the commit that contains itself.
  EXPECTED_PROTOCOL_DOCUMENTS = %w[
    docs/research-study.md docs/research-operations.md docs/validation.md
    docs/dogfood.md research/templates/stage-1-participants.csv
    research/templates/stage-2-observations.csv
    research/templates/stage-3-repository-weeks.csv
    research/templates/stage-3-active-user-reuse.csv
    research/templates/stage-3-eight-week-card-reuse.csv
    research/templates/aggregate-report.md
    .github/ISSUE_TEMPLATE/validation-report.yml
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
      "denominator" => "all_recruited_participants",
      "coverage" => {
        "product_backend_context_aliases_minimum" => 5,
        "platform_infrastructure_context_aliases_minimum" => 3,
        "data_ml_context_aliases_minimum" => 3,
        "open_source_participants_minimum" => 3,
        "required_role_bands" => %w[junior mid senior staff],
        "required_platforms" => %w[macos linux windows]
      }
    },
    "stage_2" => {
      "real_cards_per_participant" => 3,
      "median_creation_seconds_maximum" => 30,
      "correct_rank_one_share_minimum" => 0.7,
      "trust_preference_share_minimum" => 0.6,
      "distinct_maintainers_accepting_committed_cards_minimum" => 5,
      "exact_registered_build_required" => true,
      "precision_denominator" => "all_observed_controlled_variants",
      "trust_denominator" => "participants_answering_once"
    },
    "stage_3" => {
      "strong_rank_one_relevance_share_minimum" => 0.8,
      "strong_rank_one_relevance_target" => 0.85,
      "search_p95_ms_maximum" => 100,
      "full_lookup_under_ten_seconds_share_minimum_exclusive" => 0.5,
      "full_lookup_denominator" => "observed_end_to_end_lookup_timings",
      "median_capture_seconds_maximum" => 20,
      "active_users_with_three_cards_share_minimum" => 0.5,
      "active_user_reuse_share_minimum" => 0.3,
      "active_user_reuse_denominator" => "globally_deduplicated_active_pilot_users_through_week_four",
      "shared_cards_accepted_minimum" => 5,
      "repositories_with_accepted_shared_cards_minimum" => 2,
      "serious_trust_incidents_maximum" => 0,
      "missed_real_secrets_maximum" => 0,
      "users_bypassing_scanner_due_false_positives_maximum" => 0,
      "differentiation_share_requirement" => "strict_majority",
      "maintenance_acceptable_share_minimum_exclusive" => 0.5,
      "maintenance_denominator" => "final_week_repository_responses",
      "every_triggered_kill_criterion_overrides_passing_metric_gates" => true
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
    other_tool_used_first authored_cards cumulative_unique_active_users
    cumulative_unique_active_reusers
    author_reuses teammate_reuses shared_submitted shared_accepted
    shared_changed shared_rejected retired_cards scanner_catches
    scanner_false_positives missed_real_secrets serious_trust_incidents
    users_bypassing_scanner_due_false_positives differentiation_yes
    differentiation_responses
  ].freeze

  TIMING_FIELDS = %w[
    end_to_end_lookup_seconds_samples capture_seconds_samples
  ].freeze

  MAINTENANCE_VALUES = ["acceptable", "unacceptable", "too_early_to_judge"].freeze

  module_function

  def load_registration(path = REGISTRATION_PATH)
    raise ArgumentError, "registration exceeds #{MAX_INPUT_BYTES} bytes" if File.size(path) > MAX_INPUT_BYTES

    registration = JSON.parse(File.read(path, encoding: "UTF-8"))
    raise ArgumentError, "registration top level must be an object" unless registration.is_a?(Hash)

    registration
  rescue Errno::ENOENT => e
    raise ArgumentError, "missing registration: #{e.message}"
  rescue EncodingError => e
    raise ArgumentError, "invalid registration encoding: #{e.message}"
  rescue JSON::ParserError => e
    raise ArgumentError, "invalid registration JSON: #{e.message}"
  end

  def validate_registration(registration)
    return ["registration: top level must be an object"] unless registration.is_a?(Hash)

    errors = []
    expected_version = EXPECTED_PILOT.fetch("version")
    expected_tag = EXPECTED_PILOT.fetch("tag")
    expected_commit = EXPECTED_PILOT.fetch("commit")

    errors << "registration: schema_version must be 1" unless registration["schema_version"] == 1
    errors << "registration: status must be pre_data_registration" unless registration["status"] == "pre_data_registration"
    errors << "registration: registered_on differs from the frozen RC4 registration" unless registration["registered_on"] == EXPECTED_PILOT.fetch("registered_on")
    registered_on = begin
      Date.iso8601(registration.fetch("registered_on"))
    rescue ArgumentError, KeyError, TypeError
      errors << "registration: registered_on must be a real YYYY-MM-DD date"
      nil
    end
    errors << "registration: exact pilot version must remain #{expected_version}" unless registration.dig("pilot", "version") == expected_version
    errors << "registration: exact pilot tag must remain #{expected_tag}" unless registration.dig("pilot", "tag") == expected_tag
    errors << "registration: exact pilot commit must remain #{expected_commit}" unless registration.dig("pilot", "commit") == expected_commit
    protocol_commit = registration.dig("protocol", "commit").to_s
    errors << "registration: protocol commit must be a full SHA-1" unless protocol_commit.match?(/\A[0-9a-f]{40}\z/)
    errors << "registration: protocol commit differs from the frozen RC4 protocol snapshot" unless protocol_commit == EXPECTED_PILOT.fetch("protocol_commit")
    errors << "registration: protocol commit must differ from the product build commit" if protocol_commit == expected_commit
    errors << "registration: raw data must remain access-controlled" unless registration.dig("protocol", "raw_data_location") == "access_controlled_outside_public_repository"
    errors << "registration: public data must be sanitized aggregates only" unless registration.dig("protocol", "public_data_policy") == "sanitized_cross_repository_aggregates_with_small_cell_suppression"
    errors << "registration: amendment superseded version differs from the frozen RC4 registration" unless registration.dig("amendment", "supersedes_version") == EXPECTED_PILOT.fetch("amendment_supersedes_version")
    errors << "registration: amendment reason differs from the frozen RC4 registration" unless registration.dig("amendment", "reason") == EXPECTED_PILOT.fetch("amendment_reason")
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
    errors << "registration: stable review must wait eight weeks" unless registration.dig("pilot", "stable_decision_after_weeks") == 8

    eligible_on = begin
      Date.iso8601(registration.dig("pilot", "eligible_observations_on_or_after"))
    rescue ArgumentError, TypeError
      errors << "registration: eligible observation date must use YYYY-MM-DD"
      nil
    end
    errors << "registration: eligible date differs from the frozen RC4 registration" unless registration.dig("pilot", "eligible_observations_on_or_after") == EXPECTED_PILOT.fetch("eligible_on")
    errors << "registration: observations must begin after registration" if registered_on && eligible_on && eligible_on <= registered_on

    checksums = registration.dig("release", "archive_sha256")
    errors << "registration: RC4 archive SHA-256 set differs" unless checksums == EXPECTED_PILOT.fetch("archive_sha256")

    errors << "registration: RC4 release URL differs" unless registration.dig("release", "url") == EXPECTED_PILOT.fetch("release_url")
    errors << "registration: RC4 release workflow differs" unless registration.dig("release", "workflow_url") == EXPECTED_PILOT.fetch("workflow_url")
    errors << "registration: release must remain a prerelease" unless registration.dig("release", "prerelease") == true
    errors << "registration: release must contain eight assets" unless registration.dig("release", "asset_count") == 8
    errors << "registration: checksum asset must be SHA256SUMS" unless registration.dig("release", "checksum_asset") == "SHA256SUMS"
    errors << "registration: SBOM asset must be fixcard.cdx.json" unless registration.dig("release", "sbom_asset") == "fixcard.cdx.json"
    errors << "registration: RC4 Homebrew formula commit differs" unless registration.dig("release", "homebrew_formula_commit") == EXPECTED_PILOT.fetch("homebrew_formula_commit")
    errors << "registration: RC4 Homebrew formula URL differs" unless registration.dig("release", "homebrew_formula_url") == EXPECTED_PILOT.fetch("homebrew_formula_url")

    errors << "registration: fixed gates differ from the predeclared protocol" unless registration["fixed_gates"] == EXPECTED_FIXED_GATES

    criteria = registration["kill_criteria"]
    unless criteria.is_a?(Array) && criteria.all? { |item| item.is_a?(Hash) } &&
           criteria.map { |item| item["id"] } == (1..10).to_a &&
           criteria.map { |item| item["criterion"] } == EXPECTED_KILL_CRITERIA
      errors << "registration: all ten kill criteria must be frozen in order"
    end

    documents = Array(registration.dig("protocol", "documents"))
    errors << "registration: protocol document set differs" unless documents == EXPECTED_PROTOCOL_DOCUMENTS
    documents.select { |document| document.is_a?(String) }.each do |document|
      errors << "registration: missing protocol document #{document}" unless ROOT.join(document).file?
    end

    errors.concat(validate_git_bindings(protocol_commit, expected_commit, expected_tag, expected_version, documents))

    errors
  rescue TypeError, NoMethodError
    ["registration: nested values have invalid types"]
  end

  def validate_git_bindings(protocol_commit, product_commit, tag, version, documents)
    return ["registration: validation must run from a full Git checkout"] unless ROOT.join(".git").exist?

    errors = []
    {
      "protocol commit" => protocol_commit,
      "product commit" => product_commit
    }.each do |label, commit|
      next unless commit.match?(/\A[0-9a-f]{40}\z/)

      _stdout, _stderr, status = Open3.capture3("git", "-C", ROOT.to_s, "cat-file", "-e", "#{commit}^{commit}")
      errors << "registration: #{label} does not exist in this checkout" unless status.success?
    end

    if protocol_commit.match?(/\A[0-9a-f]{40}\z/)
      documents.each do |document|
        current_path = ROOT.join(document)
        next unless current_path.file?

        frozen, _stderr, status = Open3.capture3("git", "-C", ROOT.to_s, "show", "#{protocol_commit}:#{document}")
        if !status.success?
          errors << "registration: #{document} is absent from the protocol commit"
        elsif frozen.b != current_path.binread
          errors << "registration: #{document} differs from the protocol commit"
        end
      end
    end

    if product_commit.match?(/\A[0-9a-f]{40}\z/) && tag.to_s.match?(/\Av1\.0\.0-rc\.\d+\z/)
      resolved, _stderr, status = Open3.capture3("git", "-C", ROOT.to_s, "rev-parse", "refs/tags/#{tag}^{commit}")
      errors << "registration: exact pilot tag is missing" unless status.success?
      errors << "registration: exact pilot tag does not resolve to the product commit" if status.success? && resolved.strip != product_commit
    end

    cargo_source, _stderr, cargo_status = Open3.capture3("git", "-C", ROOT.to_s, "show", "#{product_commit}:Cargo.toml")
    cargo_version = cargo_source[/^version\s*=\s*"([^"]+)"/, 1] if cargo_status.success?
    errors << "registration: product commit Cargo.toml version does not match the exact pilot build" unless cargo_version == version
    errors
  end

  def validate_stage2_table(table, exact_version:)
    errors = []
    errors << "Stage 2 CSV: headers differ from the registered schema" unless table.headers == STAGE_2_HEADERS
    seen_cards = {}

    table.each_with_index do |row, index|
      line = index + 2
      participant = row["participant_alias"].to_s
      card = row["card_alias"].to_s
      version = row["fixcard_version"].to_s
      errors << "line #{line}: participant_alias must look like P001" unless participant.match?(/\AP\d{3,}\z/)
      errors << "line #{line}: card_alias must look like C001" unless card.match?(/\AC\d{3,}\z/)
      errors << "line #{line}: duplicate card_alias #{card.inspect}" if seen_cards[card]
      seen_cards[card] = true
      errors << "line #{line}: fixcard_version must be exactly #{exact_version.inspect}, got #{version.inspect}" unless version == exact_version

      %w[controlled_variants correct_rank_one privacy_edits scanner_false_positives].each do |field|
        next if row[field].to_s.empty?

        value = integer(row[field])
        errors << "line #{line}: #{field} must be a non-negative integer or blank" unless value && value >= 0
      end
      variants = integer(row["controlled_variants"])
      correct = integer(row["correct_rank_one"])
      if row["correct_rank_one"].to_s.empty? != row["controlled_variants"].to_s.empty?
        errors << "line #{line}: controlled_variants and correct_rank_one must be reported together"
      end
      errors << "line #{line}: correct_rank_one cannot exceed controlled_variants" if variants && correct && correct > variants
      unless row["creation_seconds"].to_s.empty? || (numeric?(row["creation_seconds"]) && row["creation_seconds"].to_f >= 0)
        errors << "line #{line}: creation_seconds must be a non-negative number or blank"
      end
    end
    errors
  end

  def validate_stage3_user_reuse_table(table, exact_version:)
    errors = []
    errors << "Stage 3 active-user CSV: headers differ from the registered schema" unless table.headers == STAGE_3_USER_REUSE_HEADERS
    seen = {}
    table.each_with_index do |row, index|
      line = index + 2
      participant = row["participant_alias"].to_s
      repository = row["repository_alias"].to_s
      key = [participant, repository]
      errors << "line #{line}: participant_alias must look like P001" unless participant.match?(/\AP\d{3,}\z/)
      errors << "line #{line}: repository_alias must look like R001" unless repository.match?(/\AR\d{3,}\z/)
      errors << "line #{line}: duplicate participant/repository #{key.inspect}" if seen[key]
      seen[key] = true
      version = row["fixcard_version"].to_s
      errors << "line #{line}: fixcard_version must be exactly #{exact_version.inspect}, got #{version.inspect}" unless version == exact_version
      %w[active_during_weeks_1_4 reused_or_teammate_reused_during_weeks_1_4].each do |field|
        errors << "line #{line}: #{field} must be true or false" unless %w[true false].include?(row[field].to_s)
      end
      if row["reused_or_teammate_reused_during_weeks_1_4"] == "true" && row["active_during_weeks_1_4"] != "true"
        errors << "line #{line}: an inactive participant cannot count as an active reuser"
      end
    end
    errors
  end

  def validate_stage3_card_reuse_table(table, exact_version:, eligible_on:, pilot_periods: nil)
    errors = []
    errors << "Stage 3 eight-week card CSV: headers differ from the registered schema" unless table.headers == STAGE_3_CARD_REUSE_HEADERS
    seen = {}
    table.each_with_index do |row, index|
      line = index + 2
      repository = row["repository_alias"].to_s
      card = row["card_alias"].to_s
      key = [repository, card]
      errors << "line #{line}: repository_alias must look like R001" unless repository.match?(/\AR\d{3,}\z/)
      errors << "line #{line}: card_alias must look like C001" unless card.match?(/\AC\d{3,}\z/)
      errors << "line #{line}: duplicate repository/card #{key.inspect}" if seen[key]
      seen[key] = true
      version = row["fixcard_version"].to_s
      errors << "line #{line}: fixcard_version must be exactly #{exact_version.inspect}, got #{version.inspect}" unless version == exact_version
      authored_on = iso_date(row["authored_on"])
      follow_up_end = iso_date(row["follow_up_end"])
      errors << "line #{line}: authored_on must be a real YYYY-MM-DD date" unless authored_on
      errors << "line #{line}: follow_up_end must be a real YYYY-MM-DD date" unless follow_up_end
      errors << "line #{line}: authored_on predates the eligible window" if authored_on && eligible_on && authored_on < eligible_on
      if authored_on && follow_up_end
        errors << "line #{line}: follow_up_end must be after authored_on" unless follow_up_end > authored_on
      end
      if pilot_periods
        period = pilot_periods[repository]
        if period.nil?
          errors << "line #{line}: repository_alias is absent from the complete pilot"
        elsif !period.values_at(:start, :core_end, :follow_up_end).all?
          errors << "line #{line}: repository pilot periods are incomplete"
        elsif authored_on && follow_up_end
          errors << "line #{line}: authored_on must fall within that repository's weeks 1–4" unless (period[:start]..period[:core_end]).cover?(authored_on)
          errors << "line #{line}: follow_up_end must equal the end of that repository's week eight" unless follow_up_end == period[:follow_up_end]
        end
      end
      %w[available_to_teammates reused_by_other_person_by_week_8].each do |field|
        errors << "line #{line}: #{field} must be true or false" unless %w[true false].include?(row[field].to_s)
      end
      if row["reused_by_other_person_by_week_8"] == "true" && row["available_to_teammates"] != "true"
        errors << "line #{line}: a card unavailable to teammates cannot count as teammate-reused"
      end
    end
    errors
  end

  def validate_stage3_table(table, exact_version:, eligible_on: nil, complete_pilot: false)
    errors = []
    errors << "Stage 3 CSV: headers differ from the registered schema" unless table.headers == STAGE_3_HEADERS
    seen_repository_weeks = {}
    pilot_users_by_repository = {}
    periods_by_repository = Hash.new { |hash, key| hash[key] = [] }
    weekly_active_totals = Hash.new(0)
    active_users_by_repository = Hash.new { |hash, key| hash[key] = [] }
    reusers_by_repository = Hash.new { |hash, key| hash[key] = [] }

    table.each_with_index do |row, index|
      line = index + 2
      repository = row["repository_alias"].to_s
      version = row["fixcard_version"].to_s
      week = integer(row["week"])
      observation_start = iso_date(row["observation_start"])
      observation_end = iso_date(row["observation_end"])

      errors << "line #{line}: repository_alias must look like R001" unless repository.match?(/\AR\d{3,}\z/)
      errors << "line #{line}: fixcard_version must be exactly #{exact_version.inspect}, got #{version.inspect}" unless version == exact_version
      errors << "line #{line}: week must be an integer from 1 through 4" unless week && (1..4).cover?(week)
      if !row["observation_start"].to_s.empty? && observation_start.nil?
        errors << "line #{line}: observation_start must be a real YYYY-MM-DD date"
      end
      if !row["observation_end"].to_s.empty? && observation_end.nil?
        errors << "line #{line}: observation_end must be a real YYYY-MM-DD date"
      end
      if observation_start && observation_end
        errors << "line #{line}: each repository-week must span exactly seven calendar days" unless observation_end - observation_start == 6
        errors << "line #{line}: observation_start predates the eligible window" if eligible_on && observation_start < eligible_on
        periods_by_repository[repository] << [week, observation_start, observation_end, line] if week
      elsif complete_pilot
        errors << "line #{line}: observation_start and observation_end are required for a complete pilot"
      end

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

      if complete_pilot
        required_counts = COUNT_FIELDS - %w[differentiation_yes differentiation_responses]
        required_counts.each do |field|
          errors << "line #{line}: #{field} is required for a complete pilot; use 0 when observed zero" unless counts.key?(field)
        end
      end

      errors << "line #{line}: pilot_users must be at least 1 when reported" if counts["pilot_users"] == 0

      validate_upper_bound(errors, line, counts, "weekly_active_users", "pilot_users")
      validate_lower_bound(errors, line, counts, "cumulative_unique_active_users", "weekly_active_users")
      validate_upper_bound(errors, line, counts, "active_users_with_three_cards", "weekly_active_users")
      if counts.fetch("active_users_with_three_cards", 0).positive?
        if counts.key?("authored_cards")
          minimum_authored_cards = counts.fetch("active_users_with_three_cards") * 3
          if counts.fetch("authored_cards") < minimum_authored_cards
            errors << "line #{line}: authored_cards must be at least three per active_users_with_three_cards"
          end
        else
          errors << "line #{line}: authored_cards is required when active_users_with_three_cards is positive"
        end
      end
      validate_upper_bound(errors, line, counts, "strong_matches", "lookup_attempts")
      validate_upper_bound(errors, line, counts, "relevant_strong_matches", "strong_matches")
      %w[full_lookups_under_ten_seconds fixcard_used_first other_tool_used_first].each do |field|
        validate_upper_bound(errors, line, counts, field, "lookup_attempts")
      end
      validate_upper_bound(errors, line, counts, "cumulative_unique_active_users", "pilot_users")
      validate_upper_bound(errors, line, counts, "cumulative_unique_active_reusers", "cumulative_unique_active_users")
      %w[shared_accepted shared_changed shared_rejected].each do |field|
        validate_upper_bound(errors, line, counts, field, "shared_submitted")
      end
      validate_upper_bound(errors, line, counts, "differentiation_yes", "differentiation_responses")
      validate_upper_bound(errors, line, counts, "differentiation_responses", "pilot_users")
      validate_upper_bound(errors, line, counts, "users_bypassing_scanner_due_false_positives", "pilot_users")

      if counts["lookup_attempts"]
        classified = %w[strong_matches correct_abstentions incorrect_abstentions].sum { |field| counts.fetch(field, 0) }
        errors << "line #{line}: reported strong matches plus abstentions cannot exceed lookup_attempts" if classified > counts["lookup_attempts"]
        if complete_pilot && classified != counts["lookup_attempts"]
          errors << "line #{line}: strong matches plus abstentions must equal lookup_attempts for a complete pilot"
        end
      end

      if counts["lookup_attempts"]
        first_tool_total = %w[fixcard_used_first other_tool_used_first].sum { |field| counts.fetch(field, 0) }
        errors << "line #{line}: first-tool counts cannot exceed lookup_attempts" if first_tool_total > counts["lookup_attempts"]
        if complete_pilot && first_tool_total != counts["lookup_attempts"]
          errors << "line #{line}: first-tool counts must equal lookup_attempts for a complete pilot"
        end
      end

      if counts["shared_submitted"]
        reviewed = %w[shared_accepted shared_changed shared_rejected].sum { |field| counts.fetch(field, 0) }
        errors << "line #{line}: reviewed shared-card outcomes cannot exceed shared_submitted" if reviewed > counts["shared_submitted"]
      end

      sample_counts = {}
      TIMING_FIELDS.each do |field|
        next if row[field].nil? || row[field].empty?

        samples = row[field].split(";", -1)
        valid = samples.all? { |sample| numeric?(sample) && sample.to_f >= 0 }
        errors << "line #{line}: #{field} must be semicolon-separated non-negative numbers" unless valid
        sample_counts[field] = samples.length if valid
      end


      if sample_counts["end_to_end_lookup_seconds_samples"] && counts["lookup_attempts"]
        sample_count = sample_counts["end_to_end_lookup_seconds_samples"]
        if complete_pilot && sample_count != counts["lookup_attempts"]
          errors << "line #{line}: complete-pilot lookup timings must contain one sample per lookup_attempt"
        elsif sample_count > counts["lookup_attempts"]
          errors << "line #{line}: end-to-end timing samples cannot exceed lookup_attempts"
        end
      end
      if sample_counts["capture_seconds_samples"] && counts["authored_cards"]
        sample_count = sample_counts["capture_seconds_samples"]
        if complete_pilot && sample_count != counts["authored_cards"]
          errors << "line #{line}: complete-pilot capture timings must contain one sample per authored_card"
        elsif sample_count > counts["authored_cards"]
          errors << "line #{line}: capture timing samples cannot exceed authored_cards"
        end
      end
      if complete_pilot && counts["lookup_attempts"].to_i.positive? && sample_counts["end_to_end_lookup_seconds_samples"].nil?
        errors << "line #{line}: complete-pilot lookup timings are required when lookups occurred"
      end
      if complete_pilot && counts["authored_cards"].to_i.positive? && sample_counts["capture_seconds_samples"].nil?
        errors << "line #{line}: complete-pilot capture timings are required when cards were authored"
      end
      if sample_counts["end_to_end_lookup_seconds_samples"]
        observed_under_ten = row["end_to_end_lookup_seconds_samples"].split(";").count { |sample| sample.to_f < 10 }
        if counts["full_lookups_under_ten_seconds"].nil?
          errors << "line #{line}: full_lookups_under_ten_seconds is required when timing samples are present"
        elsif counts["full_lookups_under_ten_seconds"] != observed_under_ten
          errors << "line #{line}: full_lookups_under_ten_seconds must equal the count derived from timing samples"
        end
      end

      unless row["search_p95_ms"].nil? || row["search_p95_ms"].empty? || (numeric?(row["search_p95_ms"]) && row["search_p95_ms"].to_f >= 0)
        errors << "line #{line}: search_p95_ms must be a non-negative number or blank"
      end
      if complete_pilot && counts["lookup_attempts"].to_i.positive? && row["search_p95_ms"].to_s.empty?
        errors << "line #{line}: search_p95_ms is required when lookups occurred"
      end

      burden = row["maintenance_burden"].to_s
      unless burden.empty? || MAINTENANCE_VALUES.include?(burden)
        errors << "line #{line}: maintenance_burden must be blank or one of #{MAINTENANCE_VALUES.join(', ')}"
      end
      if week && week < 4
        errors << "line #{line}: differentiation is collected only in week four" if counts.key?("differentiation_yes") || counts.key?("differentiation_responses")
        errors << "line #{line}: maintenance_burden is collected only in week four" unless burden.empty?
      elsif week == 4 && complete_pilot
        errors << "line #{line}: differentiation_yes and differentiation_responses are required in week four" unless counts.key?("differentiation_yes") && counts.key?("differentiation_responses")
        errors << "line #{line}: a final maintenance decision is required" unless %w[acceptable unacceptable].include?(burden)
      end

      if counts["pilot_users"]
        previous = pilot_users_by_repository[repository]
        errors << "line #{line}: pilot_users changed within #{repository}" if previous && previous != counts["pilot_users"]
        pilot_users_by_repository[repository] = counts["pilot_users"]
      end
      weekly_active_totals[repository] += counts["weekly_active_users"] if counts["weekly_active_users"]
      active_users_by_repository[repository] << [week, counts["cumulative_unique_active_users"], line] if week && counts["cumulative_unique_active_users"]
      reusers_by_repository[repository] << [week, counts["cumulative_unique_active_reusers"], line] if week && counts["cumulative_unique_active_reusers"]
    end

    validate_monotonic(errors, active_users_by_repository, "cumulative_unique_active_users")
    validate_monotonic(errors, reusers_by_repository, "cumulative_unique_active_reusers")

    periods_by_repository.each_value do |periods|
      periods.sort_by!(&:first)
      periods.each_cons(2) do |previous, current|
        errors << "line #{current[3]}: repository-week periods must be consecutive and non-overlapping" unless current[1] == previous[2] + 1
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
        errors << "complete pilot: #{repository} had no active pilot user in any week" unless weekly_active_totals[repository].positive?
      end
    end

    errors
  end

  def validate_stage3_cross_file_coverage(pilot_table, user_reuse_table, card_reuse_table)
    errors = []
    final_active = {}
    final_reusers = {}
    authored_totals = Hash.new(0)

    pilot_table.each do |row|
      repository = row["repository_alias"].to_s
      authored_totals[repository] += integer(row["authored_cards"]).to_i
      next unless integer(row["week"]) == 4

      final_active[repository] = integer(row["cumulative_unique_active_users"])
      final_reusers[repository] = integer(row["cumulative_unique_active_reusers"])
    end

    membership_active = Hash.new(0)
    membership_reusers = Hash.new(0)
    user_reuse_table.each do |row|
      repository = row["repository_alias"].to_s
      unless final_active.key?(repository)
        errors << "active-user reuse: #{repository.inspect} is absent from the complete pilot"
        next
      end
      membership_active[repository] += 1 if row["active_during_weeks_1_4"] == "true"
      membership_reusers[repository] += 1 if row["reused_or_teammate_reused_during_weeks_1_4"] == "true"
    end

    final_active.each do |repository, expected|
      errors << "active-user reuse: #{repository} active memberships must equal week-four cumulative active users" unless membership_active[repository] == expected
      errors << "active-user reuse: #{repository} reuser memberships must equal week-four cumulative active reusers" unless membership_reusers[repository] == final_reusers[repository]
    end

    card_counts = Hash.new(0)
    card_reuse_table.each do |row|
      repository = row["repository_alias"].to_s
      unless authored_totals.key?(repository)
        errors << "eight-week card reuse: #{repository.inspect} is absent from the complete pilot"
        next
      end
      card_counts[repository] += 1
    end
    authored_totals.each do |repository, expected|
      errors << "eight-week card reuse: #{repository} rows must equal authored_cards across weeks 1–4" unless card_counts[repository] == expected
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

  def iso_date(value)
    return nil if value.to_s.empty?

    Date.iso8601(value)
  rescue ArgumentError
    nil
  end

  def validate_monotonic(errors, observations_by_repository, field)
    observations_by_repository.each_value do |observations|
      observations.sort_by!(&:first)
      observations.each_cons(2) do |previous, current|
        errors << "line #{current[2]}: #{field} cannot decrease" if current[1] < previous[1]
      end
    end
  end

  def validate_upper_bound(errors, line, counts, numerator, denominator)
    return unless counts[numerator] && counts[denominator]
    return if counts[numerator] <= counts[denominator]

    errors << "line #{line}: #{numerator} cannot exceed #{denominator}"
  end

  def validate_lower_bound(errors, line, counts, value, minimum)
    return unless counts[value] && counts[minimum]
    return if counts[value] >= counts[minimum]

    errors << "line #{line}: #{value} cannot be lower than #{minimum}"
  end

  def read_csv(path)
    raise ArgumentError, "CSV exceeds #{MAX_INPUT_BYTES} bytes" if File.size(path) > MAX_INPUT_BYTES

    table = CSV.read(path, headers: true, encoding: "UTF-8")
    oversized = table.any? do |row|
      row.fields.compact.any? { |field| field.bytesize > MAX_FIELD_BYTES }
    end
    raise ArgumentError, "CSV contains a field larger than #{MAX_FIELD_BYTES} bytes" if oversized

    table
  rescue Errno::ENOENT => e
    raise ArgumentError, "missing CSV: #{e.message}"
  rescue CSV::MalformedCSVError, EncodingError => e
    raise ArgumentError, "invalid CSV: #{e.message}"
  end
end

if $PROGRAM_NAME == __FILE__
  complete_pilot = ARGV.delete("--complete-pilot")
  stage_2 = ARGV.delete("--stage-2")
  reuse_option = ARGV.index("--active-user-reuse")
  reuse_path = reuse_option ? ARGV.delete_at(reuse_option + 1) : nil
  ARGV.delete_at(reuse_option) if reuse_option
  card_reuse_option = ARGV.index("--eight-week-card-reuse")
  card_reuse_path = card_reuse_option ? ARGV.delete_at(card_reuse_option + 1) : nil
  ARGV.delete_at(card_reuse_option) if card_reuse_option
  path = ARGV.shift
  usage = "usage: ruby scripts/research_evidence.rb [--stage-2 | --complete-pilot --active-user-reuse USER_CSV --eight-week-card-reuse CARD_CSV] CSV"
  options_valid = (!reuse_option || reuse_path) && (!card_reuse_option || card_reuse_path)
  abort usage unless path && ARGV.empty? && !(stage_2 && complete_pilot) && options_valid
  abort usage if complete_pilot && (!reuse_path || !card_reuse_path)

  begin
    registration = ResearchEvidence.load_registration
    errors = ResearchEvidence.validate_registration(registration)
    table = ResearchEvidence.read_csv(path)
    exact_version = registration.dig("pilot", "version")
    if stage_2
      errors.concat(ResearchEvidence.validate_stage2_table(table, exact_version: exact_version))
      label = "Stage 2"
    else
      eligible_on = ResearchEvidence.iso_date(registration.dig("pilot", "eligible_observations_on_or_after"))
      errors.concat(
        ResearchEvidence.validate_stage3_table(
          table,
          exact_version: exact_version,
          eligible_on: eligible_on,
          complete_pilot: complete_pilot
        )
      )
      reuse_table = nil
      if reuse_path
        reuse_table = ResearchEvidence.read_csv(reuse_path)
        errors.concat(ResearchEvidence.validate_stage3_user_reuse_table(reuse_table, exact_version: exact_version))
        unless reuse_table.any? { |row| row["active_during_weeks_1_4"] == "true" }
          errors << "complete pilot: active-user reuse denominator must contain at least one active participant"
        end
      end
      card_reuse_table = nil
      if card_reuse_path
        card_reuse_table = ResearchEvidence.read_csv(card_reuse_path)
        pilot_periods = table.each_with_object({}) do |row, periods|
          repository = row["repository_alias"]
          week = ResearchEvidence.integer(row["week"])
          start_date = ResearchEvidence.iso_date(row["observation_start"])
          end_date = ResearchEvidence.iso_date(row["observation_end"])
          periods[repository] ||= {}
          periods[repository][:start] = start_date if week == 1 && start_date
          periods[repository][:core_end] = end_date if week == 4 && end_date
        end
        pilot_periods.each_value do |period|
          period[:follow_up_end] = period[:start] + 55 if period[:start]
        end
        errors.concat(
          ResearchEvidence.validate_stage3_card_reuse_table(
            card_reuse_table,
            exact_version: exact_version,
            eligible_on: eligible_on,
            pilot_periods: pilot_periods
          )
        )
      end
      if complete_pilot && reuse_table && card_reuse_table
        errors.concat(
          ResearchEvidence.validate_stage3_cross_file_coverage(
            table,
            reuse_table,
            card_reuse_table
          )
        )
      end
      label = "Stage 3"
    end

    abort errors.join("\n") unless errors.empty?
    puts "Validated #{table.length} #{label} rows against exact build #{exact_version}"
  rescue ArgumentError => e
    abort e.message
  end
end
