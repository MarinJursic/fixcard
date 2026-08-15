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
deep_copy_csv = ->(table) { CSV.parse(table.to_csv, headers: true) }
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

RC7_EXPECTED_HEADERS = {
  "stage-2-observations.csv" => ResearchEvidence::RC7_STAGE_2_HEADERS,
  "stage-3-repository-weeks.csv" => ResearchEvidence::RC7_STAGE_3_HEADERS,
  "stage-3-active-user-reuse.csv" => ResearchEvidence::RC7_STAGE_3_USER_REUSE_HEADERS,
  "stage-3-eight-week-card-reuse.csv" => ResearchEvidence::RC7_STAGE_3_CARD_REUSE_HEADERS,
  "installation-receipts.csv" => ResearchEvidence::RC7_INSTALLATION_RECEIPT_HEADERS
}.freeze

RC7_EXPECTED_HEADERS.each do |name, expected|
  path = ROOT.join("research", "pilots", "rc7", "templates", name)
  unless path.file?
    errors << "missing RC7 research template: #{path.relative_path_from(ROOT)}"
    next
  end

  table = CSV.read(path, headers: true)
  errors << "#{path.relative_path_from(ROOT)}: headers differ from the RC7 schema" unless table.headers == expected
  errors << "#{path.relative_path_from(ROOT)}: distributed template must be blank" unless table.empty?
  forbidden = table.headers & FORBIDDEN_HEADERS
  errors << "#{path.relative_path_from(ROOT)}: privacy-sensitive headers: #{forbidden.join(', ')}" unless forbidden.empty?
rescue CSV::MalformedCSVError => e
  errors << "#{path.relative_path_from(ROOT)}: malformed CSV: #{e.message}"
end

known_blank_csvs = EXPECTED_HEADERS.keys.map { |name| "research/templates/#{name}" } +
                   RC7_EXPECTED_HEADERS.keys.map { |name| "research/pilots/rc7/templates/#{name}" }
public_csvs = ROOT.glob("**/*.csv").reject do |path|
  relative = path.relative_path_from(ROOT).each_filename.to_a
  relative.include?(".git") || relative.include?("target")
end
public_csvs.each do |path|
  relative = path.relative_path_from(ROOT).to_s
  errors << "unexpected public CSV may contain participant data: #{relative}" unless known_blank_csvs.include?(relative)
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
  replacement = ResearchEvidence.load_replacement_registration
  authorization = ResearchEvidence.load_intake_authorization
  github_event = if ENV["GITHUB_EVENT_PATH"]
                   ResearchEvidence.load_strict_json_object(
                     Pathname.new(ENV.fetch("GITHUB_EVENT_PATH")),
                     "GitHub Actions event"
                   )
                 else
                   {}
                 end
  activation_candidate_mode = ResearchEvidence.activation_candidate_event?(
    authorization,
    event_name: ENV["GITHUB_EVENT_NAME"],
    event: github_event
  )
  errors.concat(ResearchEvidence.validate_registration(registration, interruption: interruption))
  errors.concat(ResearchEvidence.validate_interruption(interruption))
  errors.concat(
    ResearchEvidence.validate_replacement_registration(
      replacement,
      registration: registration,
      interruption: interruption
    )
  )
  exact_version = replacement.dig("pilot", "version")
  eligible_on = ResearchEvidence.iso_date(replacement.dig("pilot", "eligible_observations_on_or_after"))

  validator_amendment = ResearchEvidence.load_validator_amendment
  validator_v2 = ResearchEvidence.load_validator_manifest_v2
  if validator_amendment.nil? || validator_v2.nil?
    errors << "RC7 validator amendment or v2 manifest is missing"
  else
    amendment_structure_errors = ResearchEvidence.validate_validator_amendment_structure(
      validator_amendment,
      validator_v2
    )
    errors << "RC7 validator amendment control failed: #{amendment_structure_errors.join('; ')}" unless
      amendment_structure_errors.empty?

    amendment_mutations = {
      "open collection" => ->(copy) { copy["collection_open"] = true },
      "nonzero evidence" => lambda do |copy|
        copy["eligible_evidence_at_amendment"]["stage_3_repositories"] = 1
      end,
      "changed gate digest" => lambda do |copy|
        copy["protocol_invariants"]["fixed_gates_canonical_json_sha256"] = "0" * 64
      end,
      "missing machine void" => ->(copy) { copy["void_records"].pop },
      "extra path" => ->(copy) { copy["allowed_changed_paths"] << "docs/validation.md" },
      "wrong pull request" => ->(copy) { copy["source_pull_request"]["number"] = 30 }
    }
    amendment_mutations.each do |label, mutation|
      copy = JSON.parse(JSON.generate(validator_amendment))
      mutation.call(copy)
      if ResearchEvidence.validate_validator_amendment_structure(copy, validator_v2, check_files: false).empty?
        errors << "validator amendment accepted #{label} mutation"
      end
    end
    v2_mutation = JSON.parse(JSON.generate(validator_v2))
    v2_mutation["files_sha256"]["scripts/research_evidence.rb"] = "0" * 64
    if ResearchEvidence.validate_validator_amendment_structure(
      validator_amendment,
      v2_mutation,
      check_files: false
    ).empty?
      errors << "validator amendment accepted a changed v2 script digest"
    end

    candidate_sha = "a" * 40
    candidate_pull = {
      "number" => ResearchEvidence::VALIDATOR_AMENDMENT_PR["number"],
      "id" => ResearchEvidence::VALIDATOR_AMENDMENT_PR["id"],
      "html_url" => ResearchEvidence::VALIDATOR_AMENDMENT_PR["url"],
      "state" => "open",
      "merged_at" => nil,
      "merge_commit_sha" => "b" * 40,
      "changed_files" => ResearchEvidence::VALIDATOR_AMENDMENT_CHANGED_PATHS.length,
      "base" => {
        "ref" => "main",
        "sha" => ResearchEvidence::RC7_REPLACEMENT_REGISTRATION_COMMIT,
        "repo" => { "id" => ResearchEvidence::VALIDATOR_AMENDMENT_PR["repository_id"] }
      },
      "head" => { "sha" => candidate_sha }
    }
    source_fetcher = lambda do |path|
      case path
      when "repos/MarinJursic/fixcard/pulls/29"
        candidate_pull
      when "repos/MarinJursic/fixcard/pulls/29/files?per_page=100"
        ResearchEvidence::VALIDATOR_AMENDMENT_CHANGED_PATHS.map { |entry| { "filename" => entry } }
      else
        ResearchEvidence.github_api_json(path)
      end
    end
    source_blob_fetcher = lambda do |commit, path|
      if commit == candidate_sha
        if ResearchEvidence::VALIDATOR_AMENDMENT_CHANGED_PATHS.include?(path)
          current = ROOT.join(path)
          current.binread if current.file?
        elsif [
          "research/pilot-intake-authorization.json",
          ResearchEvidence::PAUSED_INTAKE_DOCUMENT
        ].include?(path)
          nil
        else
          ResearchEvidence.git_blob(ResearchEvidence::RC7_REPLACEMENT_REGISTRATION_COMMIT, path)
        end
      else
        ResearchEvidence.git_blob(commit, path)
      end
    end
    candidate_source_errors = ResearchEvidence.validate_validator_amendment_source(
      validator_amendment,
      github_fetcher: source_fetcher,
      event_name: "pull_request",
      event: { "pull_request" => { "number" => 29 } },
      blob_fetcher: source_blob_fetcher,
      ancestor_checker: ->(_ancestor, _descendant) { true }
    )
    errors << "validator amendment candidate source control failed: #{candidate_source_errors.join('; ')}" unless
      candidate_source_errors.empty?
    {
      "an intake authorization" => lambda do |commit, path|
        path == "research/pilot-intake-authorization.json" ? "{}".b : source_blob_fetcher.call(commit, path)
      end,
      "the active validation form" => lambda do |commit, path|
        if path == ResearchEvidence::PAUSED_INTAKE_DOCUMENT
          ROOT.join("research", "pilots", "rc7", "validation-report.yml").binread
        else
          source_blob_fetcher.call(commit, path)
        end
      end,
      "an open public banner" => lambda do |commit, path|
        if commit == candidate_sha && path == "docs/validation.md"
          entry = ResearchEvidence.load_strict_json_object(
            ResearchEvidence::OPEN_BANNERS_PATH,
            "RC7 open-banner snapshot"
          ).fetch("documents").find { |candidate| candidate["path"] == path }
          closed = source_blob_fetcher.call(commit, path)
          closed_prefix = (Array(entry.fetch("closed_lines")).join("\n") + "\n").b
          open_prefix = (Array(entry.fetch("open_lines")).join("\n") + "\n").b
          open_prefix + closed.delete_prefix(closed_prefix)
        else
          source_blob_fetcher.call(commit, path)
        end
      end
    }.each do |label, mutated_blob_fetcher|
      if ResearchEvidence.validate_validator_amendment_source(
        validator_amendment,
        github_fetcher: source_fetcher,
        event_name: "pull_request",
        event: { "pull_request" => { "number" => 29 } },
        blob_fetcher: mutated_blob_fetcher,
        ancestor_checker: ->(_ancestor, _descendant) { true }
      ).empty?
        errors << "validator amendment candidate accepted #{label}"
      end
    end
    changed_count_fetcher = lambda do |path|
      value = source_fetcher.call(path)
      path == "repos/MarinJursic/fixcard/pulls/29" ? value.merge("changed_files" => 5) : value
    end
    if ResearchEvidence.validate_validator_amendment_source(
      validator_amendment,
      github_fetcher: changed_count_fetcher,
      event_name: "pull_request",
      event: { "pull_request" => { "number" => 29 } },
      blob_fetcher: source_blob_fetcher,
      ancestor_checker: ->(_ancestor, _descendant) { true }
    ).empty?
      errors << "validator amendment accepted an extra changed path"
    end
    merged_sha = "d" * 40
    merged_pull = candidate_pull.merge(
      "state" => "closed",
      "merged_at" => "2026-08-16T12:00:00Z",
      "merge_commit_sha" => merged_sha
    )
    merged_fetcher = lambda do |path|
      path == "repos/MarinJursic/fixcard/pulls/29" ? merged_pull : source_fetcher.call(path)
    end
    merged_blob_fetcher = lambda do |commit, path|
      source_blob_fetcher.call(commit == merged_sha ? candidate_sha : commit, path)
    end
    merged_source_errors = ResearchEvidence.validate_validator_amendment_source(
      validator_amendment,
      github_fetcher: merged_fetcher,
      event_name: "push",
      event: {},
      blob_fetcher: merged_blob_fetcher,
      ancestor_checker: ->(_ancestor, _descendant) { true }
    )
    errors << "validator amendment merged source control failed: #{merged_source_errors.join('; ')}" unless
      merged_source_errors.empty?
    if ResearchEvidence.validate_validator_amendment_source(
      validator_amendment,
      github_fetcher: merged_fetcher,
      event_name: "push",
      event: {},
      blob_fetcher: merged_blob_fetcher,
      ancestor_checker: ->(_ancestor, _descendant) { false }
    ).empty?
      errors << "validator amendment accepted a merge outside protected ancestry"
    end
    if ResearchEvidence.validate_validator_amendment_source(
      validator_amendment,
      github_fetcher: source_fetcher,
      event_name: "pull_request",
      event: { "pull_request" => { "number" => 30 } },
      blob_fetcher: source_blob_fetcher,
      ancestor_checker: ->(_ancestor, _descendant) { true }
    ).empty?
      errors << "validator amendment accepted an unrelated candidate event"
    end

    open_snapshot_blob = ResearchEvidence.git_blob(
      ResearchEvidence::RC7_REPLACEMENT_REGISTRATION_COMMIT,
      "research/pilots/rc7/open-banners.json"
    )
    open_snapshot = ResearchEvidence.parse_strict_json_object(
      open_snapshot_blob,
      "frozen RC7 open-banner snapshot"
    )
    %w[docs/research-operations.md docs/validation.md docs/dogfood.md].each do |path|
      entry = open_snapshot.fetch("documents").find { |candidate| candidate["path"] == path }
      closed = ResearchEvidence.git_blob(ResearchEvidence::RC7_REPLACEMENT_REGISTRATION_COMMIT, path)
      historical = ResearchEvidence.git_blob(ResearchEvidence::EXPECTED_REPLACEMENT.fetch("protocol_commit"), path)
      closed_prefix = (Array(entry["closed_lines"]).join("\n") + "\n").b
      open_prefix = (Array(entry["open_lines"]).join("\n") + "\n").b
      exact_open = open_prefix + closed.delete_prefix(closed_prefix)
      unless ResearchEvidence.historical_document_matches?(path, exact_open, historical, allow_overlays: true)
        errors << "exact preregistered open overlay was rejected for #{path}"
      end
      [
        exact_open.sub("[!IMPORTANT]", "[!WARNING]"),
        exact_open + "unexpected\n",
        exact_open.byteslice(0, exact_open.bytesize - 1)
      ].each do |mutation|
        if ResearchEvidence.historical_document_matches?(path, mutation, historical, allow_overlays: true)
          errors << "mutated open overlay was accepted for #{path}"
        end
      end
    end

    merged_amendment = {
      "number" => 29,
      "id" => ResearchEvidence::VALIDATOR_AMENDMENT_PR["id"],
      "html_url" => ResearchEvidence::VALIDATOR_AMENDMENT_PR["url"],
      "state" => "closed",
      "merged_at" => "2026-08-16T12:00:00Z",
      "merge_commit_sha" => "c" * 40,
      "base" => {
        "ref" => "main",
        "repo" => { "id" => ResearchEvidence::VALIDATOR_AMENDMENT_PR["repository_id"] }
      }
    }
    old_notice_errors = ResearchEvidence.validate_fresh_opening_notice(
      comment_id: ResearchEvidence::VOIDED_OPENING_NOTICE["comment_id"],
      created_at: Time.iso8601("2026-08-17T00:00:00Z"),
      amendment_pull: merged_amendment
    )
    unless old_notice_errors.any? { |error| error.include?("voided") }
      errors << "validator amendment accepted the voided opening notice"
    end
    early_notice_errors = ResearchEvidence.validate_fresh_opening_notice(
      comment_id: 5_400_000_000,
      created_at: Time.iso8601("2026-08-16T11:59:59Z"),
      amendment_pull: merged_amendment
    )
    unless early_notice_errors.any? { |error| error.include?("fresh") }
      errors << "validator amendment accepted an opening notice before its merge"
    end
    fresh_notice_errors = ResearchEvidence.validate_fresh_opening_notice(
      comment_id: 5_400_000_000,
      created_at: Time.iso8601("2026-08-16T12:00:01Z"),
      amendment_pull: merged_amendment
    )
    errors << "validator amendment rejected a fresh later opening notice" unless fresh_notice_errors.empty?
  end

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
  if authorization.nil?
    if ResearchEvidence.validate_intake_authorization(replacement, registration, interruption, authorization).empty?
      errors << "evidence intake remained open without an authorization record"
    end
  elsif activation_candidate_mode
    errors.concat(ResearchEvidence.validate_activation_candidate(authorization, replacement))
  else
    errors.concat(
      ResearchEvidence.validate_intake_authorization(
        replacement,
        registration,
        interruption,
        authorization
      )
    )
  end
  if ResearchEvidence.validate_intake_authorization(replacement, registration, interruption_mutation, authorization).empty?
    errors << "evidence intake accepted an open flag without an exact eligible build"
  end
  interruption_mutation["eligible_build"] = registration.fetch("pilot").slice("version", "tag", "commit")
  if ResearchEvidence.validate_intake_authorization(replacement, registration, interruption_mutation, authorization).empty?
    errors << "evidence intake accepted an unfrozen open RC4 mutation"
  end

  replacement_mutation = JSON.parse(JSON.generate(replacement))
  replacement_mutation["pilot"]["version"] = "1.0.0-rc.6"
  if ResearchEvidence.validate_replacement_registration(
    replacement_mutation,
    registration: registration,
    interruption: interruption
  ).empty?
    errors << "replacement registration accepted a non-RC7 pilot version"
  end
  replacement_mutations = {
    "one-week pilot" => ->(copy) { copy["pilot"]["working_weeks"] = 1 },
    "earlier eligibility date" => ->(copy) { copy["pilot"]["eligible_observations_on_or_after"] = "2026-08-16" },
    "post-observation receipts" => ->(copy) { copy["build_manifest"]["receipt_must_precede_first_observation"] = false },
    "empty opening requirements" => ->(copy) { copy["intake"]["opening_requires"] = [] },
    "changed archive digest" => lambda do |copy|
      copy["release"]["archive_sha256"][copy["release"]["archive_sha256"].keys.first] = "0" * 64
    end
  }
  replacement_mutations.each do |label, mutation|
    copy = JSON.parse(JSON.generate(replacement))
    mutation.call(copy)
    if ResearchEvidence.validate_replacement_registration(
      copy,
      registration: registration,
      interruption: interruption
    ).empty?
      errors << "replacement registration accepted #{label} mutation"
    end
  end
  rogue_authorization = {
    "collection_open" => true,
    "eligible_build" => replacement.fetch("pilot").slice("version", "tag", "commit")
  }
  if ResearchEvidence.validate_intake_authorization(
    replacement,
    registration,
    interruption,
    rogue_authorization
  ).empty?
    errors << "evidence intake accepted an unprotected RC7 opening"
  end
  replacement_sha256 = Digest::SHA256.hexdigest(JSON.generate(replacement))
  fake_stage_2_at = "2026-08-17T00:00:00Z"
  fake_stage_3_on = "2026-08-17"
  fake_body = "FIXCARD-PILOT-OPEN pilot_id=#{ResearchEvidence::EXPECTED_RC7_PILOT_ID} " \
              "registration_sha256=#{replacement_sha256} " \
              "build_commit=#{ResearchEvidence::EXPECTED_REPLACEMENT.fetch('commit')} " \
              "stage_2_eligible_at=#{fake_stage_2_at} stage_3_eligible_on=#{fake_stage_3_on} " \
              "nonce=ABCDEFGHIJKLMNOP"
  fabricated_authorization = {
    "schema_version" => 1,
    "event_type" => "collection_opened",
    "sequence" => 1,
    "previous_event_sha256" => nil,
    "pilot_id" => ResearchEvidence::EXPECTED_RC7_PILOT_ID,
    "registration" => {
      "commit" => ResearchEvidence::EXPECTED_REPLACEMENT.fetch("commit"),
      "canonical_json_sha256" => replacement_sha256,
      "pull_request_number" => 27,
      "pull_request_id" => 1,
      "pull_request_url" => "https://github.com/MarinJursic/fixcard/pull/27",
      "merged_at" => "2026-08-15T00:00:00Z"
    },
    "activation_pull_request" => {
      "number" => 999_999,
      "id" => 999_999,
      "url" => "https://github.com/MarinJursic/fixcard/pull/999999",
      "base_ref" => "main"
    },
    "issue" => {
      "repository" => "MarinJursic/fixcard",
      "repository_id" => 1_322_107_936,
      "issue_number" => 5,
      "issue_id" => 5_054_372_820,
      "comment_id" => 9_999_999_999,
      "comment_url" => "https://github.com/MarinJursic/fixcard/issues/5#issuecomment-9999999999",
      "author_login" => "MarinJursic",
      "author_id" => 50_271_892,
      "created_at" => "2026-08-15T15:00:00Z",
      "updated_at" => "2026-08-15T15:00:00Z",
      "body" => fake_body,
      "body_sha256" => Digest::SHA256.hexdigest(fake_body)
    },
    "authorized_stages" => %w[milestone_0 stage_1 stage_2 stage_3],
    "eligibility" => {
      "stage_2_eligible_at" => fake_stage_2_at,
      "stage_3_eligible_on" => fake_stage_3_on
    },
    "build" => {
      "pilot_id" => ResearchEvidence::EXPECTED_RC7_PILOT_ID,
      "version" => "1.0.0-rc.7",
      "tag" => "v1.0.0-rc.7",
      "commit" => ResearchEvidence::EXPECTED_REPLACEMENT.fetch("commit"),
      "build_manifest_sha256" => ResearchEvidence::EXPECTED_RC7_BUILD_MANIFEST_SHA256,
      "homebrew_formula_commit" => "71f00d5574ab8fe6e06c224df0219752ddd44370"
    },
    "public_form_sha256" => "280002611023b17bcf457381e769b9102950af39cefcff8c9911784656e80032",
    "eligible_evidence_at_opening" => ResearchEvidence::ELIGIBLE_EVIDENCE_KEYS.to_h { |key| [key, 0] },
    "stable_release_allowed" => false
  }
  fabricated_errors = ResearchEvidence.validate_activation_record(fabricated_authorization, replacement)
  unless fabricated_errors.any? { |error| error.include?("does not contain the replacement registration") }
    errors << "activation accepted a fabricated GitHub record or an ancestor without the preregistration"
  end
  activation_pr_number = fabricated_authorization.dig("activation_pull_request", "number")
  unless ResearchEvidence.activation_candidate_event?(
    fabricated_authorization,
    event_name: "pull_request",
    event: { "pull_request" => { "number" => activation_pr_number } }
  )
    errors << "activation candidate event did not recognize its exact pull request"
  end
  if ResearchEvidence.activation_candidate_event?(
    fabricated_authorization,
    event_name: "pull_request",
    event: { "pull_request" => { "number" => activation_pr_number + 1 } }
  )
    errors << "unrelated pull request was mistaken for the activation candidate"
  end
  if ResearchEvidence.activation_candidate_event?(
    fabricated_authorization,
    event_name: "push",
    event: { "number" => activation_pr_number }
  )
    errors << "non-pull-request event was mistaken for the activation candidate"
  end
  valid_boundary_errors = ResearchEvidence.validate_activation_boundaries(
    stage_2_value: "2026-08-17T00:00:00Z",
    stage_3_value: "2026-08-17",
    comment_value: "2026-08-15T15:00:00Z",
    merged_value: "2026-08-16T12:00:00Z",
    not_before_value: "2026-08-17"
  )
  errors << "activation boundary control failed: #{valid_boundary_errors.join('; ')}" unless valid_boundary_errors.empty?
  pre_not_before_errors = ResearchEvidence.validate_activation_boundaries(
    stage_2_value: "2026-08-16T23:59:59Z",
    stage_3_value: "2026-08-17",
    comment_value: "2026-08-15T15:00:00Z",
    merged_value: "2026-08-16T12:00:00Z",
    not_before_value: "2026-08-17"
  )
  unless pre_not_before_errors.any? { |error| error.include?("predates the registered not-before") }
    errors << "activation accepted a Stage 2 boundary before the registered not-before date"
  end
  same_day_stage_3_errors = ResearchEvidence.validate_activation_boundaries(
    stage_2_value: "2026-08-17T12:00:01Z",
    stage_3_value: "2026-08-17",
    comment_value: "2026-08-17T10:00:00Z",
    merged_value: "2026-08-17T12:00:00Z",
    not_before_value: "2026-08-17"
  )
  unless same_day_stage_3_errors.any? { |error| error.include?("strictly after") }
    errors << "activation accepted same-day Stage 3 evidence after opening"
  end
  candidate_as_of = Time.iso8601("2026-08-15T12:00:00Z")
  candidate_boundary_errors = ResearchEvidence.validate_activation_candidate_boundaries(
    stage_2_value: "2026-08-17T12:00:00Z",
    stage_3_value: "2026-08-18",
    comment_value: "2026-08-15T10:00:00Z",
    not_before_value: "2026-08-17",
    as_of: candidate_as_of
  )
  errors << "activation candidate lead-time control failed: #{candidate_boundary_errors.join('; ')}" unless
    candidate_boundary_errors.empty?
  short_lead_errors = ResearchEvidence.validate_activation_candidate_boundaries(
    stage_2_value: "2026-08-16T12:00:00Z",
    stage_3_value: "2026-08-17",
    comment_value: "2026-08-15T10:00:00Z",
    not_before_value: "2026-08-17",
    as_of: candidate_as_of
  )
  unless short_lead_errors.any? { |error| error.include?("merge lead") }
    errors << "activation candidate accepted a boundary without conservative merge lead time"
  end

  rc7_stage_2_values = ResearchEvidence::RC7_STAGE_2_HEADERS.map do |header|
    {
      "pilot_id" => ResearchEvidence::EXPECTED_RC7_PILOT_ID,
      "build_manifest_sha256" => ResearchEvidence::EXPECTED_RC7_BUILD_MANIFEST_SHA256,
      "observed_at" => "#{eligible_on.iso8601}T00:00:00Z",
      "participant_alias" => "P001",
      "card_alias" => "C001",
      "fixcard_version" => exact_version,
      "controlled_variants" => "0",
      "correct_rank_one" => "0",
      "maintainer_decision" => "not_reviewed",
      "card_committed" => "false"
    }.fetch(header, "")
  end
  rc7_stage_2 = CSV::Table.new([
    CSV::Row.new(ResearchEvidence::RC7_STAGE_2_HEADERS, rc7_stage_2_values)
  ])
  eligible_at = Time.utc(eligible_on.year, eligible_on.month, eligible_on.day)
  as_of = eligible_at + (7 * 24 * 60 * 60)
  exact_rc7_stage_2_errors = ResearchEvidence.validate_rc7_stage2_table(
    rc7_stage_2,
    eligible_at: eligible_at,
    as_of: as_of
  )
  errors << "RC7 Stage 2 exact identity control failed: #{exact_rc7_stage_2_errors.join('; ')}" unless exact_rc7_stage_2_errors.empty?

  wrong_manifest = CSV::Table.new([rc7_stage_2.first.dup])
  wrong_manifest.first["build_manifest_sha256"] = "0" * 64
  if ResearchEvidence.validate_rc7_stage2_table(wrong_manifest, eligible_at: eligible_at, as_of: as_of).empty?
    errors << "RC7 Stage 2 accepted a same-version row with the wrong build manifest"
  end

  pre_boundary = CSV::Table.new([rc7_stage_2.first.dup])
  pre_boundary.first["observed_at"] = "#{(eligible_on - 1).iso8601}T23:59:59Z"
  if ResearchEvidence.validate_rc7_stage2_table(pre_boundary, eligible_at: eligible_at, as_of: as_of).empty?
    errors << "RC7 Stage 2 accepted a pre-boundary observation"
  end

  offset_timestamp = CSV::Table.new([rc7_stage_2.first.dup])
  offset_timestamp.first["observed_at"] = "#{eligible_on.iso8601}T01:00:00+01:00"
  if ResearchEvidence.validate_rc7_stage2_table(offset_timestamp, eligible_at: eligible_at, as_of: as_of).empty?
    errors << "RC7 Stage 2 accepted a noncanonical timestamp"
  end

  future_timestamp = CSV::Table.new([rc7_stage_2.first.dup])
  future_timestamp.first["observed_at"] = "2099-01-01T00:00:00Z"
  if ResearchEvidence.validate_rc7_stage2_table(future_timestamp, eligible_at: eligible_at, as_of: as_of).empty?
    errors << "RC7 Stage 2 accepted a future observation"
  end

  # CSV::Row#dup shares its backing field array on supported Ruby versions;
  # restore the exact control row after the independent mutations above.
  rc7_stage_2.first["pilot_id"] = ResearchEvidence::EXPECTED_RC7_PILOT_ID
  rc7_stage_2.first["build_manifest_sha256"] = ResearchEvidence::EXPECTED_RC7_BUILD_MANIFEST_SHA256
  rc7_stage_2.first["observed_at"] = eligible_at.iso8601

  build_manifest = ResearchEvidence.load_strict_json_object(
    ResearchEvidence::RC7_BUILD_MANIFEST_PATH,
    "RC7 build manifest"
  )
  archive = build_manifest.dig("release", "assets").find { |asset| asset["name"].end_with?(".tar.gz") }
  receipt_values = ResearchEvidence::RC7_INSTALLATION_RECEIPT_HEADERS.map do |header|
    {
      "pilot_id" => ResearchEvidence::EXPECTED_RC7_PILOT_ID,
      "build_manifest_sha256" => ResearchEvidence::EXPECTED_RC7_BUILD_MANIFEST_SHA256,
      "installation_alias" => "I001",
      "participant_alias" => "P001",
      "repository_alias" => "R001",
      "install_method" => "archive",
      "artifact_name" => archive.fetch("name"),
      "artifact_sha256" => archive.fetch("sha256"),
      "fixcard_version_output" => "fixcard #{exact_version}",
      "fix_version_output" => "fix #{exact_version}",
      "verified_at" => eligible_at.iso8601,
      "verifier_alias" => "V001"
    }.fetch(header, "")
  end
  rc7_receipts = CSV::Table.new([
    CSV::Row.new(ResearchEvidence::RC7_INSTALLATION_RECEIPT_HEADERS, receipt_values)
  ])
  receipt_errors = ResearchEvidence.validate_rc7_installation_receipts(
    rc7_receipts,
    eligible_at: eligible_at,
    as_of: as_of
  )
  errors << "RC7 installation-receipt control failed: #{receipt_errors.join('; ')}" unless receipt_errors.empty?
  stage_2_receipt_errors = ResearchEvidence.validate_rc7_stage2_receipt_coverage(rc7_stage_2, rc7_receipts)
  errors << "RC7 Stage 2 receipt coverage failed: #{stage_2_receipt_errors.join('; ')}" unless stage_2_receipt_errors.empty?
  duplicate_participant_receipts = deep_copy_csv.call(rc7_receipts)
  second_receipt = duplicate_participant_receipts.first.fields.dup
  second_receipt[ResearchEvidence::RC7_INSTALLATION_RECEIPT_HEADERS.index("installation_alias")] = "I002"
  second_receipt[ResearchEvidence::RC7_INSTALLATION_RECEIPT_HEADERS.index("repository_alias")] = "R002"
  duplicate_participant_receipts << CSV::Row.new(ResearchEvidence::RC7_INSTALLATION_RECEIPT_HEADERS, second_receipt)
  if ResearchEvidence.validate_rc7_stage2_receipt_coverage(rc7_stage_2, duplicate_participant_receipts).empty?
    errors << "RC7 Stage 2 accepted more than one receipt for a participant"
  end

  late_receipt = deep_copy_csv.call(rc7_receipts)
  late_receipt.first["verified_at"] = (eligible_at + 60).iso8601
  if ResearchEvidence.validate_rc7_stage2_receipt_coverage(rc7_stage_2, late_receipt).empty?
    errors << "RC7 Stage 2 accepted a receipt created after observation"
  end
  wrong_receipt_digest = deep_copy_csv.call(rc7_receipts)
  wrong_receipt_digest.first["artifact_sha256"] = "0" * 64
  if ResearchEvidence.validate_rc7_installation_receipts(
    wrong_receipt_digest,
    eligible_at: eligible_at,
    as_of: as_of
  ).empty?
    errors << "RC7 installation receipt accepted the wrong archive digest"
  end
  pre_activation_receipt = deep_copy_csv.call(rc7_receipts)
  pre_activation_receipt.first["verified_at"] = (eligible_at - 1).iso8601
  if ResearchEvidence.validate_rc7_installation_receipts(
    pre_activation_receipt,
    eligible_at: eligible_at,
    as_of: as_of
  ).empty?
    errors << "RC7 installation receipt accepted pre-activation verification"
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

    receipt_stage_3 = build_row.call(
      exact_version,
      "observation_start" => eligible_on.iso8601,
      "observation_end" => (eligible_on + 6).iso8601
    )
    membership_headers = ResearchEvidence::STAGE_3_USER_REUSE_HEADERS
    membership_table = CSV::Table.new([
      CSV::Row.new(membership_headers, ["P001", "R001", exact_version, "true", "false"])
    ])
    exact_receipt_coverage = ResearchEvidence.validate_rc7_receipt_coverage(
      receipt_stage_3,
      membership_table,
      rc7_receipts
    )
    errors << "RC7 Stage 3 receipt coverage control failed: #{exact_receipt_coverage.join('; ')}" unless exact_receipt_coverage.empty?
    late_stage_3_receipt = deep_copy_csv.call(rc7_receipts)
    late_stage_3_receipt.first["verified_at"] = (eligible_at + 1).iso8601
    if ResearchEvidence.validate_rc7_receipt_coverage(
      receipt_stage_3,
      membership_table,
      late_stage_3_receipt
    ).empty?
      errors << "RC7 Stage 3 accepted a receipt after the first observation date"
    end
    unrelated_receipt = deep_copy_csv.call(rc7_receipts)
    unrelated_receipt.first["participant_alias"] = "P999"
    unrelated_receipt.first["repository_alias"] = "R999"
    if ResearchEvidence.validate_rc7_receipt_coverage(
      receipt_stage_3,
      nil,
      unrelated_receipt
    ).empty?
      errors << "RC7 Stage 3 accepted a receipt for an unrelated repository"
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

  closed_state = authorization.nil?
  dogfood = File.read(ROOT.join("docs", "dogfood.md"), encoding: "UTF-8")
  errors << "dogfood.md: must not direct pilots to the newest candidate" if dogfood.match?(/newest release candidate/i)
  dogfood_pause_prefix = ResearchEvidence::PAUSE_HEADINGS.fetch("docs/dogfood.md") + ResearchEvidence::PAUSE_BANNERS.fetch("docs/dogfood.md")
  errors << "dogfood.md: closed state must state that collection is paused" if closed_state && !dogfood.start_with?(dogfood_pause_prefix)

  rc7_dogfood = File.read(ROOT.join("docs", "dogfood-rc7.md"), encoding: "UTF-8")
  errors << "dogfood-rc7.md: must name exact pilot build #{exact_version}" unless rc7_dogfood.include?("`#{exact_version}`")
  errors << "dogfood-rc7.md: closed state must say collection is closed" if closed_state && !rc7_dogfood.include?("**Collection is closed.**")

  operations = File.read(ROOT.join("docs", "research-operations.md"), encoding: "UTF-8")
  operations_pause_prefix = ResearchEvidence::PAUSE_HEADINGS.fetch("docs/research-operations.md") + ResearchEvidence::PAUSE_BANNERS.fetch("docs/research-operations.md")
  errors << "research-operations.md: closed state must say collection is paused" if closed_state && !operations.start_with?(operations_pause_prefix)

  validation = File.read(ROOT.join("docs", "validation.md"), encoding: "UTF-8")
  validation_pause_prefix = ResearchEvidence::PAUSE_HEADINGS.fetch("docs/validation.md") + ResearchEvidence::PAUSE_BANNERS.fetch("docs/validation.md")
  errors << "validation.md: closed state must say collection and intake are paused" if closed_state && !validation.start_with?(validation_pause_prefix)

  results = File.read(ROOT.join("docs", "validation-results.md"), encoding: "UTF-8")
  errors << "validation-results.md: must name exact pilot build #{exact_version}" unless results.include?("`#{exact_version}`")
  errors << "validation-results.md: must explain activation-bound form authority" unless
    results.include?("public validation form is authoritative only when it is installed")

  research_readme = File.read(ROOT.join("research", "README.md"), encoding: "UTF-8")
  errors << "research/README.md: closed state must say RC7 is not eligible" if closed_state && !research_readme.include?("RC7 is registered but not yet eligible")

  form_path = ROOT.join(".github", "ISSUE_TEMPLATE", "validation-report.yml")
  errors << "validation-report.yml: closed collection must not expose an active submission form" if closed_state && form_path.exist?
  dormant_form = ROOT.join("research", "pilots", "rc7", "validation-report.yml")
  errors << "RC7 dormant validation form is missing" unless dormant_form.file?

  open_banners = ResearchEvidence.load_strict_json_object(
    ResearchEvidence::OPEN_BANNERS_PATH,
    "RC7 open-banner snapshot"
  )
  banner_paths = Array(open_banners["documents"]).map { |entry| entry["path"] }
  expected_banner_paths = %w[
    README.md research/README.md docs/validation.md docs/research-operations.md
    docs/dogfood.md docs/dogfood-rc7.md docs/validation-results.md
  ]
  errors << "RC7 open-banner document set differs" unless banner_paths.sort == expected_banner_paths.sort
  Array(open_banners["documents"]).each do |entry|
    current = ROOT.join(entry["path"].to_s)
    closed_prefix = Array(entry["closed_lines"]).join("\n") + "\n"
    open_prefix = Array(entry["open_lines"]).join("\n") + "\n"
    errors << "RC7 banner snapshot has identical closed/open text for #{entry['path']}" if closed_prefix == open_prefix
    expected_prefix = closed_state ? closed_prefix : open_prefix
    errors << "RC7 #{closed_state ? 'closed' : 'open'} banner does not match #{entry['path']}" unless
      current.file? && current.binread.start_with?(expected_prefix.b)
  end
  if !closed_state
    errors << "active RC7 validation form differs from dormant snapshot" unless
      form_path.file? && !form_path.symlink? && dormant_form.file? && form_path.binread == dormant_form.binread
  end

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

  Tempfile.create(["duplicate-key-registration", ".json"]) do |file|
    file.write('{"schema_version":1,"schema_version":2}')
    file.flush
    begin
      ResearchEvidence.load_replacement_registration(Pathname.new(file.path))
      errors << "replacement registration accepted a duplicate JSON key"
    rescue ArgumentError
      nil
    end
  end

  Tempfile.create(["duplicate-key-validator-amendment", ".json"]) do |file|
    file.write('{"schema_version":1,"schema_version":2}')
    file.flush
    begin
      ResearchEvidence.load_validator_amendment(Pathname.new(file.path))
      errors << "validator amendment accepted a duplicate JSON key"
    rescue ArgumentError
      nil
    end
  end

  Tempfile.create(["oversized-validator-amendment", ".json"]) do |file|
    file.write('{"padding":"')
    file.write("x" * (ResearchEvidence::MAX_INPUT_BYTES + 1))
    file.write('"}')
    file.flush
    begin
      ResearchEvidence.load_validator_amendment(Pathname.new(file.path))
      errors << "validator amendment accepted an oversized record"
    rescue ArgumentError
      nil
    end
  end

  Tempfile.create(["replacement-target", ".json"]) do |file|
    file.write('{}')
    file.flush
    link = Pathname.new("#{file.path}.link")
    File.symlink(file.path, link)
    begin
      ResearchEvidence.load_replacement_registration(link)
      errors << "replacement registration accepted a symlink"
    rescue ArgumentError
      nil
    ensure
      link.delete if link.exist? || link.symlink?
    end
  end


  Tempfile.create(["validator-amendment-target", ".json"]) do |file|
    file.write('{}')
    file.flush
    link = Pathname.new("#{file.path}.link")
    File.symlink(file.path, link)
    begin
      ResearchEvidence.load_validator_amendment(link)
      errors << "validator amendment accepted a symlink"
    rescue ArgumentError
      nil
    ensure
      link.delete if link.exist? || link.symlink?
    end
  end

  Tempfile.create(["evidence-target", ".csv"]) do |file|
    file.write("repository_alias,week\n")
    file.flush
    link = Pathname.new("#{file.path}.link")
    File.symlink(file.path, link)
    begin
      ResearchEvidence.read_csv(link)
      errors << "evidence loader accepted a symlink"
    rescue ArgumentError
      nil
    ensure
      link.delete if link.exist? || link.symlink?
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
