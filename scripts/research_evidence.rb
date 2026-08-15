#!/usr/bin/env ruby
# frozen_string_literal: true

require "csv"
require "date"
require "digest"
require "json"
require "net/http"
require "open3"
require "pathname"
require "time"
require "uri"

module ResearchEvidence
  ROOT = Pathname.new(__dir__).join("..").cleanpath
  REGISTRATION_PATH = ROOT.join("research", "pilot-registration.json")
  INTERRUPTION_PATH = ROOT.join("research", "pilot-interruption.json")
  REPLACEMENT_REGISTRATION_PATH = ROOT.join("research", "pilot-replacement-registration.json")
  INTAKE_AUTHORIZATION_PATH = ROOT.join("research", "pilot-intake-authorization.json")
  ACTIVATION_POLICY_PATH = ROOT.join("research", "pilots", "rc7", "activation-policy.json")
  VALIDATOR_MANIFEST_PATH = ROOT.join("research", "pilots", "rc7", "validator-manifest.json")
  VALIDATOR_AMENDMENT_PATH = ROOT.join("research", "pilots", "rc7", "validator-amendment-1.json")
  VALIDATOR_MANIFEST_V2_PATH = ROOT.join("research", "pilots", "rc7", "validator-manifest-v2.json")
  VALIDATOR_AMENDMENT_2_PATH = ROOT.join("research", "pilots", "rc7", "validator-amendment-2.json")
  VALIDATOR_MANIFEST_V3_PATH = ROOT.join("research", "pilots", "rc7", "validator-manifest-v3.json")
  OPEN_BANNERS_PATH = ROOT.join("research", "pilots", "rc7", "open-banners.json")
  STAGE_2_TEMPLATE_PATH = ROOT.join("research", "templates", "stage-2-observations.csv")
  STAGE_3_TEMPLATE_PATH = ROOT.join("research", "templates", "stage-3-repository-weeks.csv")
  STAGE_3_USER_REUSE_TEMPLATE_PATH = ROOT.join("research", "templates", "stage-3-active-user-reuse.csv")
  STAGE_3_CARD_REUSE_TEMPLATE_PATH = ROOT.join("research", "templates", "stage-3-eight-week-card-reuse.csv")
  RC7_TEMPLATE_DIR = ROOT.join("research", "pilots", "rc7", "templates")
  RC7_BUILD_MANIFEST_PATH = ROOT.join("research", "pilots", "rc7", "build-manifest.json")

  MAX_INPUT_BYTES = 10 * 1024 * 1024
  MAX_FIELD_BYTES = 100_000

  class DuplicateJsonKeyError < StandardError; end

  class StrictJsonObject < Hash
    def []=(key, value)
      raise DuplicateJsonKeyError, "duplicate JSON key #{key.inspect}" if key?(key)

      super
    end
  end

  EXPECTED_PILOT = {
    "registered_on" => "2026-08-05",
    "protocol_commit" => "c513e51501fb878dce67f268cffb36593e6ac88d",
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

  EXPECTED_INTERRUPTION = {
    "schema_version" => 1,
    "status" => "collection_paused",
    "paused_at" => "2026-08-15T11:25:11Z",
    "source_issue_comment" => "https://github.com/MarinJursic/fixcard/issues/5#issuecomment-5302005971",
    "interrupted_pilot" => {
      "version" => "1.0.0-rc.4",
      "tag" => "v1.0.0-rc.4",
      "commit" => "acf0c07944700085d56f50a02b26bbdf2525272d"
    },
    "restart_rule" => "security_fix_stop_document_and_preregister_restart",
    "reason_classes" => [
      "bounded_committed_card_resource_handling",
      "runtime_risk_classification"
    ],
    "eligible_evidence_at_interruption" => {
      "permissioned_second_reviewed_real_pairs" => 0,
      "stage_1_recruited_participants" => 0,
      "stage_1_completed_two_week_diaries" => 0,
      "stage_2_real_card_observations" => 0,
      "stage_3_repositories" => 0,
      "stage_3_repository_weeks" => 0
    },
    "carry_forward_eligible_evidence" => false,
    "eligible_build" => nil,
    "replacement_registration" => nil,
    "collection_open" => false,
    "stable_release_allowed" => false
  }.freeze

  EXPECTED_REPLACEMENT = {
    "registered_on" => "2026-08-15",
    "protocol_commit" => "c513e51501fb878dce67f268cffb36593e6ac88d",
    "version" => "1.0.0-rc.7",
    "tag" => "v1.0.0-rc.7",
    "commit" => "165ef5cd4790002516de9c327d634d342842288d",
    "eligible_on" => "2026-08-17"
  }.freeze

  EXPECTED_RC7_PILOT_ID = "fixcard-rc7-2026-08-15"
  EXPECTED_RC7_BUILD_MANIFEST_SHA256 = "f18abc931e870a3a934877b4d33611e8f84190f2e9d765335885dde0d1fa7987"
  RC7_REPLACEMENT_REGISTRATION_COMMIT = "de3d745f3d307e6df875cbd03afa56b115aa022b"
  RC7_REPLACEMENT_REGISTRATION_SHA256 = "f09face4eabb46cf218888fa7cfcdc7d2997b7f7b5290fa0d4992beeffee4fad"
  RC7_VALIDATOR_V1_SHA256 = "62379900066613161099f0af9bf2022f0725fbc47733b62e5fb4dc8299d97997"
  RC7_PROTOCOL_MANIFEST_SHA256 = "3c307cf8589d1ccc437d550b11b99086d277a7b358f9202d9a591a8872097eae"
  RC7_FIXED_GATES_SHA256 = "bc0f1db8ee5283de08f776056c37b8373170414798dd88740cf0a20012ceeabf"
  RC7_KILL_CRITERIA_SHA256 = "3823dc19439500f6f7c660ecf5bf31da808a497b1c4570c94f6bef231f1f0c89"
  VALIDATOR_SCRIPT_PATHS = %w[
    scripts/check_research_kit.rb scripts/research_evidence.rb
    scripts/verify_rc7_supply_chain.rb
  ].freeze
  VALIDATOR_AMENDMENT_CHANGED_PATHS = %w[
    research/pilots/rc7/validator-amendment-1.json
    research/pilots/rc7/validator-manifest-v2.json
    scripts/check_research_kit.rb
    scripts/research_evidence.rb
  ].freeze
  VALIDATOR_AMENDMENT_PR = {
    "repository" => "MarinJursic/fixcard",
    "repository_id" => 1_322_107_936,
    "number" => 29,
    "id" => 4_286_922_642,
    "url" => "https://github.com/MarinJursic/fixcard/pull/29",
    "base_ref" => "main"
  }.freeze
  VOIDED_OPENING_NOTICE = {
    "comment_id" => 5_303_156_985,
    "comment_url" => "https://github.com/MarinJursic/fixcard/issues/5#issuecomment-5303156985",
    "created_at" => "2026-08-15T16:28:29Z",
    "updated_at" => "2026-08-15T16:28:29Z",
    "body_sha256" => "30807447dba31d9b893d26ace992bf5fbc8e322ff9d0b7561c85923de7f3e587"
  }.freeze
  HUMAN_VOID_RECORD = {
    "comment_id" => 5_303_181_461,
    "comment_url" => "https://github.com/MarinJursic/fixcard/issues/5#issuecomment-5303181461",
    "created_at" => "2026-08-15T16:34:31Z",
    "updated_at" => "2026-08-15T16:34:31Z",
    "body_sha256" => "62d06883c4b796593f772ce91f2ae47cdc74a7cd54c14de09597d6b351ae6266"
  }.freeze
  MACHINE_VOID_RECORD = {
    "comment_id" => 5_303_200_367,
    "comment_url" => "https://github.com/MarinJursic/fixcard/issues/5#issuecomment-5303200367",
    "created_at" => "2026-08-15T16:39:11Z",
    "updated_at" => "2026-08-15T16:39:11Z",
    "body_sha256" => "bee094a964cba336ccd7fe91b42d4be44553ee157b582e44873f5b72af2ee3b2"
  }.freeze
  RC7_VALIDATOR_AMENDMENT_1_COMMIT = "ead9b88fc5090e72860eda848423128b037e8b52"
  RC7_VALIDATOR_AMENDMENT_1_SHA256 = "5483c2fdfc6468cb5a4e9124c0ed0eba453b29af18ea19454410e8fce653793d"
  RC7_VALIDATOR_V2_SHA256 = "9366f7d2a0b5c6237682bfa7f95ccabd3c10a19de39d7f5ad98005b5b23cf06b"
  VALIDATOR_AMENDMENT_2_CHANGED_PATHS = %w[
    research/pilots/rc7/validator-amendment-2.json
    research/pilots/rc7/validator-manifest-v3.json
    scripts/check_research_kit.rb
    scripts/research_evidence.rb
  ].freeze
  VALIDATOR_AMENDMENT_2_PR = {
    "repository" => "MarinJursic/fixcard",
    "repository_id" => 1_322_107_936,
    "number" => 30,
    "id" => 4_287_023_204,
    "url" => "https://github.com/MarinJursic/fixcard/pull/30",
    "base_ref" => "main"
  }.freeze
  VOIDED_OPENING_NOTICE_2 = {
    "comment_id" => 5_303_294_092,
    "comment_url" => "https://github.com/MarinJursic/fixcard/issues/5#issuecomment-5303294092",
    "created_at" => "2026-08-15T17:02:32Z",
    "updated_at" => "2026-08-15T17:02:32Z",
    "body_sha256" => "8c594b572f1f5391b6ecd55e3b5b2883d557e9e013aaede2fdaad87753b4d329"
  }.freeze
  HUMAN_VOID_RECORD_2 = {
    "comment_id" => 5_303_311_823,
    "comment_url" => "https://github.com/MarinJursic/fixcard/issues/5#issuecomment-5303311823",
    "created_at" => "2026-08-15T17:07:00Z",
    "updated_at" => "2026-08-15T17:07:00Z",
    "body_sha256" => "dc932ca6603f5357cf0ed86701f2397cf7f2fa6a1047cd9f48a5d27419d30e1c"
  }.freeze
  MACHINE_VOID_RECORD_2 = {
    "comment_id" => 5_303_311_881,
    "comment_url" => "https://github.com/MarinJursic/fixcard/issues/5#issuecomment-5303311881",
    "created_at" => "2026-08-15T17:07:00Z",
    "updated_at" => "2026-08-15T17:07:00Z",
    "body_sha256" => "158ae925197ea71fc505294af49d2c79be23ad8f9f638596cd703b33d8f58064"
  }.freeze

  PAUSE_BANNERS = {
    "docs/research-study.md" => <<~MARKDOWN,
      > [!IMPORTANT]
      > The dogfood link in the frozen body below is historical RC4 material. Current
      > coordinators must use the [RC7 operating snapshot](dogfood-rc7.md).

    MARKDOWN
    "docs/dogfood.md" => <<~MARKDOWN,
      > [!CAUTION]
      > **Collection is paused.** RC7 is the preregistered replacement treatment,
      > but it is not eligible until a later explicit opening comment in issue #5
      > and a protected intake-authorization record. The RC4 instructions below are
      > the frozen historical treatment and must not be followed. RC4–RC6, untagged
      > builds, and moving package-manager heads remain ineligible; no evidence from
      > the interrupted treatment carries forward. See the
      > [replacement registration](../research/pilot-replacement-registration.json)
      > and the [current RC7 operating snapshot](dogfood-rc7.md).

    MARKDOWN
    "docs/research-operations.md" => <<~MARKDOWN,
      > [!CAUTION]
      > **Collection is paused.** RC7 is now the protected replacement
      > preregistration, not an authorization to collect. Observation can start only
      > after the 2026-08-17 not-before date, a later explicit opening comment in
      > issue #5, and a protected intake-authorization record. No RC4 evidence
      > carries forward. The body below preserves the historical protocol; use the
      > [RC7 operating snapshot](dogfood-rc7.md) for current treatment instructions
      > after activation. See the
      > [replacement registration](../research/pilot-replacement-registration.json).

    MARKDOWN
    "docs/validation.md" => <<~MARKDOWN
      > [!CAUTION]
      > **All validation collection is paused.** Milestone 0 and Stage 1 are
      > build-independent; Stage 2 and Stage 3 are bound to RC7. None is open, and
      > the public intake form is disabled. Observation and submission can restart
      > only for stages explicitly named after the 2026-08-17 not-before date, a
      > later opening comment in issue #5, and a protected activation record. No RC4
      > evidence carries forward.
      > Use the [current RC7 operating snapshot](dogfood-rc7.md); the RC4 dogfood body
      > is historical.

    MARKDOWN
  }.freeze

  PAUSE_HEADINGS = {
    "docs/research-study.md" => "# Pre-pilot research protocol\n\n",
    "docs/dogfood.md" => "# Release-candidate dogfood program\n\n",
    "docs/research-operations.md" => "# Research operations guide\n\n",
    "docs/validation.md" => "# Validation plan\n\n"
  }.freeze

  STAGE_2_HEADERS = %w[
    participant_alias card_alias maintainer_alias fixcard_version
    creation_seconds controlled_variants correct_rank_one
    fixcard_lookup_seconds_samples normal_search_seconds_samples
    metadata_confusion_observed privacy_edits scanner_false_positives
    trust_preferred maintainer_decision card_committed
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

  RC7_STAGE_2_HEADERS = %w[pilot_id build_manifest_sha256 observed_at].concat(STAGE_2_HEADERS).freeze
  RC7_STAGE_3_HEADERS = %w[pilot_id build_manifest_sha256].concat(STAGE_3_HEADERS).freeze
  RC7_STAGE_3_USER_REUSE_HEADERS = %w[pilot_id build_manifest_sha256].concat(STAGE_3_USER_REUSE_HEADERS).freeze
  RC7_STAGE_3_CARD_REUSE_HEADERS = %w[pilot_id build_manifest_sha256].concat(STAGE_3_CARD_REUSE_HEADERS).freeze
  RC7_INSTALLATION_RECEIPT_HEADERS = %w[
    pilot_id build_manifest_sha256 installation_alias participant_alias
    repository_alias install_method
    artifact_name artifact_sha256 formula_commit formula_sha256
    fixcard_version_output fix_version_output verified_at verifier_alias
  ].freeze

  RC7_PROTOCOL_FILE_PATHS = %w[
    README.md research/README.md docs/README.md docs/installation.md docs/validation-results.md
    .github/workflows/ci.yml
    docs/research-study.md docs/research-operations.md docs/validation.md
    docs/dogfood.md docs/dogfood-rc7.md
    research/templates/stage-1-participants.csv
    research/templates/stage-2-observations.csv
    research/templates/stage-3-repository-weeks.csv
    research/templates/stage-3-active-user-reuse.csv
    research/templates/stage-3-eight-week-card-reuse.csv
    research/templates/aggregate-report.md
    research/pilots/rc7/build-manifest.json
    research/pilots/rc7/templates/stage-2-observations.csv
    research/pilots/rc7/templates/stage-3-repository-weeks.csv
    research/pilots/rc7/templates/stage-3-active-user-reuse.csv
    research/pilots/rc7/templates/stage-3-eight-week-card-reuse.csv
    research/pilots/rc7/templates/installation-receipts.csv
    research/pilots/rc7/activation-policy.json
    research/pilots/rc7/open-banners.json
    research/pilots/rc7/validation-report.yml
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
  RC7_REPLACEMENT_DOCUMENTS = (
    EXPECTED_PROTOCOL_DOCUMENTS +
    %w[
      README.md research/README.md docs/README.md docs/installation.md docs/validation-results.md
      .github/workflows/ci.yml
      docs/dogfood-rc7.md research/pilots/rc7/build-manifest.json
      research/pilots/rc7/protocol-manifest.json
      research/pilots/rc7/validator-manifest.json
      research/pilots/rc7/templates/stage-2-observations.csv
      research/pilots/rc7/templates/stage-3-repository-weeks.csv
      research/pilots/rc7/templates/stage-3-active-user-reuse.csv
      research/pilots/rc7/templates/stage-3-eight-week-card-reuse.csv
      research/pilots/rc7/templates/installation-receipts.csv
      research/pilots/rc7/activation-policy.json
      research/pilots/rc7/open-banners.json
      research/pilots/rc7/validation-report.yml
    ]
  ).freeze
  PAUSED_INTAKE_DOCUMENT = ".github/ISSUE_TEMPLATE/validation-report.yml"

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
  STAGE_2_TRUST_VALUES = %w[fixcard normal_search no_preference].freeze
  STAGE_2_MAINTAINER_DECISIONS = %w[accepted changes_requested rejected not_reviewed].freeze

  module_function

  def load_registration(path = REGISTRATION_PATH)
    load_strict_json_object(path, "registration")
  end

  def load_interruption(path = INTERRUPTION_PATH)
    load_strict_json_object(path, "interruption record")
  end

  def load_replacement_registration(path = REPLACEMENT_REGISTRATION_PATH)
    load_strict_json_object(path, "replacement registration")
  end

  def load_intake_authorization(path = INTAKE_AUTHORIZATION_PATH)
    load_strict_json_object(path, "intake authorization", required: false)
  end

  def load_validator_amendment(path = VALIDATOR_AMENDMENT_PATH)
    load_strict_json_object(path, "RC7 validator amendment", required: false)
  end

  def load_validator_manifest_v2(path = VALIDATOR_MANIFEST_V2_PATH)
    load_strict_json_object(path, "RC7 validator manifest v2", required: false)
  end

  def load_validator_amendment_2(path = VALIDATOR_AMENDMENT_2_PATH)
    load_strict_json_object(path, "RC7 validator amendment 2", required: false)
  end

  def load_validator_manifest_v3(path = VALIDATOR_MANIFEST_V3_PATH)
    load_strict_json_object(path, "RC7 validator manifest v3", required: false)
  end

  def parse_strict_json_object(data, label)
    source = data.dup.force_encoding(Encoding::UTF_8)
    raise ArgumentError, "invalid #{label} encoding" unless source.valid_encoding?

    object = JSON.parse(source, object_class: StrictJsonObject)
    raise ArgumentError, "#{label} top level must be an object" unless object.is_a?(Hash)

    object
  rescue DuplicateJsonKeyError, JSON::ParserError => e
    raise ArgumentError, "invalid #{label} JSON: #{e.message}"
  end

  def load_strict_json_object(path, label, required: true)
    path = Pathname.new(path)
    return nil unless required || path.exist?

    before = path.lstat
    raise ArgumentError, "#{label} must be a regular non-symlink file" if before.symlink? || !before.file?

    data = nil
    opened = nil
    path.open("rb") do |file|
      opened = file.stat
      data = file.read(MAX_INPUT_BYTES + 1)
    end
    after = path.lstat
    identity = ->(stat) { [stat.dev, stat.ino, stat.size, stat.mtime.to_r] }
    unless identity.call(before) == identity.call(opened) && identity.call(opened) == identity.call(after)
      raise ArgumentError, "#{label} changed while it was being read"
    end
    raise ArgumentError, "#{label} exceeds #{MAX_INPUT_BYTES} bytes" if data.bytesize > MAX_INPUT_BYTES

    parse_strict_json_object(data, label)
  rescue Errno::ENOENT => e
    raise ArgumentError, "missing #{label}: #{e.message}" if required

    nil
  end

  def validate_interruption(interruption)
    return ["interruption: top level must be an object"] unless interruption.is_a?(Hash)

    return [] if interruption == EXPECTED_INTERRUPTION

    ["interruption: record differs from the frozen RC4 security-pause record"]
  end

  def validate_intake_authorization(replacement, registration, interruption, authorization)
    unless validate_interruption(interruption).empty?
      return ["evidence intake: interruption record is not the protected pause record"]
    end

    unless replacement.is_a?(Hash) &&
           replacement["status"] == "replacement_preregistered_collection_closed" &&
           replacement["registered_on"] == EXPECTED_REPLACEMENT.fetch("registered_on") &&
           replacement.dig("pilot", "pilot_id") == EXPECTED_RC7_PILOT_ID &&
           replacement.dig("pilot", "version") == EXPECTED_REPLACEMENT.fetch("version") &&
           replacement.dig("pilot", "tag") == EXPECTED_REPLACEMENT.fetch("tag") &&
           replacement.dig("pilot", "commit") == EXPECTED_REPLACEMENT.fetch("commit") &&
           replacement.dig("intake", "authorization_record_present") == false &&
           replacement["stable_release_allowed"] == false
      return ["evidence intake: replacement registration is not the protected RC7 record"]
    end

    return ["evidence intake: collection is closed pending a protected opening authorization"] if authorization.nil?

    activation_errors = validate_activation_record(authorization, replacement)
    return activation_errors.map { |error| "evidence intake: #{error}" } unless activation_errors.empty?

    []
  rescue TypeError, NoMethodError
    ["evidence intake: authorization record has invalid types"]
  end

  def canonical_utc_time(value)
    parsed = Time.iso8601(value.to_s)
    parsed if parsed.utc.iso8601 == value
  rescue ArgumentError
    nil
  end

  def validate_activation_boundaries(stage_2_value:, stage_3_value:, comment_value:, merged_value:, not_before_value:)
    stage_2_at = canonical_utc_time(stage_2_value)
    stage_3_on = iso_date(stage_3_value)
    comment_at = canonical_utc_time(comment_value)
    merged_at = canonical_utc_time(merged_value)
    registered_not_before = iso_date(not_before_value)
    errors = []
    errors << "activation Stage 2 boundary must be canonical UTC RFC3339" unless stage_2_at
    errors << "activation Stage 3 boundary must be a real YYYY-MM-DD date" unless stage_3_on
    errors << "activation opening comment timestamp must be canonical UTC RFC3339" unless comment_at
    errors << "activation merge timestamp must be canonical UTC RFC3339" unless merged_at
    errors << "activation registered not-before date is invalid" unless registered_not_before
    return errors unless stage_2_at && stage_3_on && comment_at && merged_at && registered_not_before

    registered_at = Time.utc(
      registered_not_before.year,
      registered_not_before.month,
      registered_not_before.day
    )
    latest_event = [comment_at, merged_at].max
    errors << "activation Stage 2 boundary predates the registered not-before date" if stage_2_at < registered_at
    errors << "activation Stage 2 boundary must be later than opening and activation merge" unless stage_2_at > latest_event
    earliest_stage_3 = [comment_at.to_date, merged_at.to_date, registered_not_before - 1].max
    errors << "activation Stage 3 boundary must be strictly after opening, merge, and the registered minimum" unless
      stage_3_on > earliest_stage_3
    errors
  end

  def validate_fresh_opening_notice(comment_id:, created_at:, amendment_pull:)
    errors = []
    errors << "activation cannot reuse the voided opening notice" if
      [VOIDED_OPENING_NOTICE["comment_id"], VOIDED_OPENING_NOTICE_2["comment_id"]].include?(comment_id)
    amendment_merged_at = canonical_utc_time(amendment_pull["merged_at"])
    errors << "validator amendment 2 must be merged before activation" unless
      amendment_pull["id"] == VALIDATOR_AMENDMENT_2_PR["id"] &&
      amendment_pull["number"] == VALIDATOR_AMENDMENT_2_PR["number"] &&
      amendment_pull["html_url"] == VALIDATOR_AMENDMENT_2_PR["url"] &&
      amendment_pull["state"] == "closed" && amendment_merged_at &&
      amendment_pull.dig("base", "ref") == "main" &&
      amendment_pull.dig("base", "repo", "id") == VALIDATOR_AMENDMENT_2_PR["repository_id"] &&
      amendment_pull["merge_commit_sha"].to_s.match?(/\A[0-9a-f]{40}\z/)
    errors << "opening comment must be fresh and later than the validator amendment merge" unless
      created_at && amendment_merged_at && created_at > amendment_merged_at
    errors
  rescue TypeError, NoMethodError
    ["fresh opening notice validation failed closed"]
  end

  def git_blob(commit, path)
    stdout, _stderr, status = Open3.capture3("git", "-C", ROOT.to_s, "show", "#{commit}:#{path}")
    status.success? ? stdout.b : nil
  end

  def github_api_json(path)
    stdout, stderr, status = Open3.capture3("gh", "api", "--method", "GET", path)
    raise ArgumentError, "GitHub verification failed closed for #{path}: #{stderr.strip}" unless status.success?

    JSON.parse(stdout)
  rescue JSON::ParserError => e
    raise ArgumentError, "GitHub verification returned invalid JSON for #{path}: #{e.message}"
  end

  def github_event
    path = ENV["GITHUB_EVENT_PATH"]
    path ? load_strict_json_object(Pathname.new(path), "GitHub Actions event") : {}
  end

  def validator_amendment_candidate_event?(event_name:, event:)
    return false unless event_name == "pull_request" && event.is_a?(Hash)

    event_number = event.dig("pull_request", "number") || event["number"]
    event_number == VALIDATOR_AMENDMENT_PR.fetch("number")
  rescue TypeError, NoMethodError
    false
  end

  def git_ancestor?(ancestor, descendant)
    system(
      "git", "-C", ROOT.to_s, "merge-base", "--is-ancestor", ancestor, descendant,
      out: File::NULL, err: File::NULL
    )
  end

  def expected_validator_amendment(v2_digest)
    {
      "schema_version" => 1,
      "status" => "validator_amendment_registered_collection_closed",
      "registered_on" => "2026-08-15",
      "pilot_id" => EXPECTED_RC7_PILOT_ID,
      "reason" => "repair_exact_preregistered_open_banner_projection_without_changing_protocol_or_gates",
      "source_pull_request" => VALIDATOR_AMENDMENT_PR,
      "allowed_changed_paths" => VALIDATOR_AMENDMENT_CHANGED_PATHS,
      "historical_registration" => {
        "commit" => RC7_REPLACEMENT_REGISTRATION_COMMIT,
        "canonical_json_sha256" => RC7_REPLACEMENT_REGISTRATION_SHA256
      },
      "historical_validator_manifest" => {
        "path" => "research/pilots/rc7/validator-manifest.json",
        "canonical_json_sha256" => RC7_VALIDATOR_V1_SHA256
      },
      "replacement_validator_manifest" => {
        "path" => "research/pilots/rc7/validator-manifest-v2.json",
        "canonical_json_sha256" => v2_digest
      },
      "protocol_invariants" => {
        "protocol_manifest_canonical_json_sha256" => RC7_PROTOCOL_MANIFEST_SHA256,
        "fixed_gates_canonical_json_sha256" => RC7_FIXED_GATES_SHA256,
        "kill_criteria_count" => 10,
        "kill_criteria_canonical_json_sha256" => RC7_KILL_CRITERIA_SHA256,
        "build_manifest_canonical_json_sha256" => EXPECTED_RC7_BUILD_MANIFEST_SHA256,
        "build_switching" => "forbidden"
      },
      "voided_opening_notice" => VOIDED_OPENING_NOTICE,
      "void_records" => [HUMAN_VOID_RECORD, MACHINE_VOID_RECORD],
      "fresh_opening_notice_must_follow_amendment_merge" => true,
      "activation_must_use_separate_pull_request" => true,
      "eligible_evidence_at_amendment" => ELIGIBLE_EVIDENCE_KEYS.to_h { |key| [key, 0] },
      "collection_open" => false,
      "authorization_record_present" => false,
      "carry_forward_eligible_evidence" => false,
      "stable_release_allowed" => false
    }
  end

  def validate_void_comment(record, github_fetcher)
    live = github_fetcher.call("repos/MarinJursic/fixcard/issues/comments/#{record.fetch('comment_id')}")
    errors = []
    expected = {
      "id" => record["comment_id"],
      "html_url" => record["comment_url"],
      "created_at" => record["created_at"],
      "updated_at" => record["updated_at"]
    }
    expected.each do |field, value|
      errors << "validator amendment void comment #{field} differs" unless live[field] == value
    end
    errors << "validator amendment void comment author differs" unless
      live.dig("user", "login") == "MarinJursic" && live.dig("user", "id") == 50_271_892
    errors << "validator amendment void comment body digest differs" unless
      Digest::SHA256.hexdigest(live["body"].to_s) == record["body_sha256"]
    errors
  end

  def validate_validator_amendment_source(
    amendment,
    github_fetcher: method(:github_api_json),
    event_name: ENV["GITHUB_EVENT_NAME"],
    event: github_event,
    blob_fetcher: method(:git_blob),
    ancestor_checker: method(:git_ancestor?)
  )
    errors = []
    pull = github_fetcher.call("repos/MarinJursic/fixcard/pulls/29")
    files = github_fetcher.call("repos/MarinJursic/fixcard/pulls/29/files?per_page=100")
    errors << "validator amendment repository identity differs" unless
      pull.dig("base", "repo", "id") == VALIDATOR_AMENDMENT_PR["repository_id"]
    errors << "validator amendment pull request identity differs" unless
      pull["number"] == VALIDATOR_AMENDMENT_PR["number"] &&
      pull["id"] == VALIDATOR_AMENDMENT_PR["id"] &&
      pull["html_url"] == VALIDATOR_AMENDMENT_PR["url"] &&
      pull.dig("base", "ref") == VALIDATOR_AMENDMENT_PR["base_ref"]
    changed_paths = Array(files).map { |entry| entry["filename"] }.sort
    errors << "validator amendment changed-path count differs" unless
      pull["changed_files"] == VALIDATOR_AMENDMENT_CHANGED_PATHS.length
    errors << "validator amendment changed-path set differs" unless
      changed_paths == VALIDATOR_AMENDMENT_CHANGED_PATHS.sort

    candidate = validator_amendment_candidate_event?(event_name: event_name, event: event)
    if candidate
      errors << "validator amendment candidate pull request must remain open" unless
        pull["state"] == "open" && pull["merged_at"].nil?
      source_commit = pull.dig("head", "sha").to_s
      errors << "validator amendment candidate head commit is invalid" unless source_commit.match?(/\A[0-9a-f]{40}\z/)
      base_commit = pull.dig("base", "sha").to_s
      errors << "validator amendment candidate base lacks the preregistration" unless
        base_commit.match?(/\A[0-9a-f]{40}\z/) &&
        ancestor_checker.call(RC7_REPLACEMENT_REGISTRATION_COMMIT, base_commit)
    else
      errors << "validator amendment pull request must be merged to protected main" unless
        pull["state"] == "closed" && pull["merged_at"] && pull.dig("base", "ref") == "main"
      source_commit = pull["merge_commit_sha"].to_s
      errors << "validator amendment merge commit is invalid" unless source_commit.match?(/\A[0-9a-f]{40}\z/)
      if source_commit.match?(/\A[0-9a-f]{40}\z/)
        errors << "validator amendment merge is not an ancestor of this checkout" unless
          ancestor_checker.call(source_commit, "HEAD")
        errors << "validator amendment was not based on the preregistration" unless
          ancestor_checker.call(RC7_REPLACEMENT_REGISTRATION_COMMIT, "#{source_commit}^")
      end
    end

    if source_commit&.match?(/\A[0-9a-f]{40}\z/)
      VALIDATOR_AMENDMENT_CHANGED_PATHS.each do |path|
        current = ROOT.join(path)
        frozen = blob_fetcher.call(source_commit, path)
        errors << "validator amendment source does not contain exact #{path}" unless
          frozen && current.file? && !current.symlink? && frozen == current.binread
      end
      errors << "validator amendment source contains an intake authorization" if
        blob_fetcher.call(source_commit, "research/pilot-intake-authorization.json")
      errors << "validator amendment source exposes the active validation form" if
        blob_fetcher.call(source_commit, PAUSED_INTAKE_DOCUMENT)
      snapshot = parse_strict_json_object(
        blob_fetcher.call(RC7_REPLACEMENT_REGISTRATION_COMMIT, "research/pilots/rc7/open-banners.json"),
        "frozen RC7 open-banner snapshot"
      )
      Array(snapshot["documents"]).each do |entry|
        path = entry["path"].to_s
        errors << "validator amendment source changes closed public status: #{path}" unless
          blob_fetcher.call(source_commit, path) == blob_fetcher.call(RC7_REPLACEMENT_REGISTRATION_COMMIT, path)
      end
    end
    [VOIDED_OPENING_NOTICE, HUMAN_VOID_RECORD, MACHINE_VOID_RECORD].each do |record|
      errors.concat(validate_void_comment(record, github_fetcher))
    end
    errors
  rescue TypeError, NoMethodError, KeyError, ArgumentError => e
    ["validator amendment source failed closed: #{e.message}"]
  end

  def validate_validator_amendment_structure(amendment, v2, check_files: true)
    errors = []
    v2_digest = Digest::SHA256.hexdigest(JSON.generate(v2))
    errors << "validator amendment differs from the strict registered record" unless
      amendment == expected_validator_amendment(v2_digest)
    expected_v2 = {
      "schema_version" => 2,
      "pilot_id" => EXPECTED_RC7_PILOT_ID,
      "amendment" => "research/pilots/rc7/validator-amendment-1.json",
      "supersedes" => {
        "registration_commit" => RC7_REPLACEMENT_REGISTRATION_COMMIT,
        "path" => "research/pilots/rc7/validator-manifest.json",
        "canonical_json_sha256" => RC7_VALIDATOR_V1_SHA256
      }
    }
    expected_v2.each do |field, value|
      errors << "validator manifest v2 #{field} differs" unless v2[field] == value
    end
    v2_files = v2["files_sha256"]
    unless v2.keys.sort == %w[amendment files_sha256 pilot_id schema_version supersedes].sort &&
           v2_files.is_a?(Hash) && v2_files.keys.sort == VALIDATOR_SCRIPT_PATHS.sort
      errors << "validator manifest v2 file set or keys differ"
      return errors
    end
    if check_files
      v2_files.each do |relative, expected_sha256|
        file = ROOT.join(relative)
        if !file.file? || file.symlink?
          errors << "validator v2 file is missing or unsafe: #{relative}"
        elsif Digest::SHA256.file(file).hexdigest != expected_sha256
          errors << "validator v2 file digest differs: #{relative}"
        end
      end
    end
    errors
  rescue TypeError, NoMethodError, KeyError, ArgumentError => e
    ["validator amendment structure failed closed: #{e.message}"]
  end

  def validator_amendment_2_candidate_event?(event_name:, event:)
    return false unless event_name == "pull_request" && event.is_a?(Hash)

    event_number = event.dig("pull_request", "number") || event["number"]
    event_number == VALIDATOR_AMENDMENT_2_PR.fetch("number")
  rescue TypeError, NoMethodError
    false
  end

  def expected_validator_amendment_2(v3_digest)
    {
      "schema_version" => 1,
      "status" => "validator_amendment_2_registered_collection_closed",
      "registered_on" => "2026-08-15",
      "pilot_id" => EXPECTED_RC7_PILOT_ID,
      "reason" => "repair_binary_open_banner_validation_and_boundary_aware_status_without_changing_protocol_or_gates",
      "source_pull_request" => VALIDATOR_AMENDMENT_2_PR,
      "allowed_changed_paths" => VALIDATOR_AMENDMENT_2_CHANGED_PATHS,
      "historical_registration" => {
        "commit" => RC7_REPLACEMENT_REGISTRATION_COMMIT,
        "canonical_json_sha256" => RC7_REPLACEMENT_REGISTRATION_SHA256
      },
      "historical_validator_amendment" => {
        "commit" => RC7_VALIDATOR_AMENDMENT_1_COMMIT,
        "amendment_path" => "research/pilots/rc7/validator-amendment-1.json",
        "amendment_canonical_json_sha256" => RC7_VALIDATOR_AMENDMENT_1_SHA256,
        "manifest_path" => "research/pilots/rc7/validator-manifest-v2.json",
        "manifest_canonical_json_sha256" => RC7_VALIDATOR_V2_SHA256
      },
      "replacement_validator_manifest" => {
        "path" => "research/pilots/rc7/validator-manifest-v3.json",
        "canonical_json_sha256" => v3_digest
      },
      "protocol_invariants" => {
        "protocol_manifest_canonical_json_sha256" => RC7_PROTOCOL_MANIFEST_SHA256,
        "fixed_gates_canonical_json_sha256" => RC7_FIXED_GATES_SHA256,
        "kill_criteria_count" => 10,
        "kill_criteria_canonical_json_sha256" => RC7_KILL_CRITERIA_SHA256,
        "build_manifest_canonical_json_sha256" => EXPECTED_RC7_BUILD_MANIFEST_SHA256,
        "build_switching" => "forbidden"
      },
      "voided_opening_notice" => VOIDED_OPENING_NOTICE_2,
      "void_records" => [HUMAN_VOID_RECORD_2, MACHINE_VOID_RECORD_2],
      "fresh_opening_notice_must_follow_amendment_merge" => true,
      "forbidden_activation_pull_requests" => [29, 30],
      "eligible_evidence_at_amendment" => ELIGIBLE_EVIDENCE_KEYS.to_h { |key| [key, 0] },
      "collection_open" => false,
      "authorization_record_present" => false,
      "carry_forward_eligible_evidence" => false,
      "stable_release_allowed" => false
    }
  end

  def validate_validator_amendment_2_structure(amendment, v3, check_files: true)
    errors = []
    v3_digest = Digest::SHA256.hexdigest(JSON.generate(v3))
    errors << "validator amendment 2 differs from the strict registered record" unless
      amendment == expected_validator_amendment_2(v3_digest)
    expected_v3 = {
      "schema_version" => 3,
      "pilot_id" => EXPECTED_RC7_PILOT_ID,
      "amendment" => "research/pilots/rc7/validator-amendment-2.json",
      "supersedes" => {
        "commit" => RC7_VALIDATOR_AMENDMENT_1_COMMIT,
        "path" => "research/pilots/rc7/validator-manifest-v2.json",
        "canonical_json_sha256" => RC7_VALIDATOR_V2_SHA256
      }
    }
    expected_v3.each do |field, value|
      errors << "validator manifest v3 #{field} differs" unless v3[field] == value
    end
    v3_files = v3["files_sha256"]
    unless v3.keys.sort == %w[amendment files_sha256 pilot_id schema_version supersedes].sort &&
           v3_files.is_a?(Hash) && v3_files.keys.sort == VALIDATOR_SCRIPT_PATHS.sort
      errors << "validator manifest v3 file set or keys differ"
      return errors
    end
    if check_files
      v3_files.each do |relative, expected_sha256|
        file = ROOT.join(relative)
        errors << "validator v3 file digest differs: #{relative}" unless
          file.file? && !file.symlink? && Digest::SHA256.file(file).hexdigest == expected_sha256
      end
    end
    errors
  rescue TypeError, NoMethodError, KeyError, ArgumentError => e
    ["validator amendment 2 structure failed closed: #{e.message}"]
  end

  def validate_validator_amendment_2_source(
    github_fetcher: method(:github_api_json),
    event_name: ENV["GITHUB_EVENT_NAME"],
    event: github_event,
    blob_fetcher: method(:git_blob),
    ancestor_checker: method(:git_ancestor?)
  )
    errors = []
    pull = github_fetcher.call("repos/MarinJursic/fixcard/pulls/30")
    files = github_fetcher.call("repos/MarinJursic/fixcard/pulls/30/files?per_page=100")
    errors << "validator amendment 2 pull request identity differs" unless
      pull["number"] == VALIDATOR_AMENDMENT_2_PR["number"] &&
      pull["id"] == VALIDATOR_AMENDMENT_2_PR["id"] &&
      pull["html_url"] == VALIDATOR_AMENDMENT_2_PR["url"] &&
      pull.dig("base", "ref") == "main" &&
      pull.dig("base", "repo", "id") == VALIDATOR_AMENDMENT_2_PR["repository_id"]
    errors << "validator amendment 2 changed-path count differs" unless
      pull["changed_files"] == VALIDATOR_AMENDMENT_2_CHANGED_PATHS.length
    errors << "validator amendment 2 changed-path set differs" unless
      Array(files).map { |entry| entry["filename"] }.sort == VALIDATOR_AMENDMENT_2_CHANGED_PATHS.sort

    candidate = validator_amendment_2_candidate_event?(event_name: event_name, event: event)
    if candidate
      errors << "validator amendment 2 candidate must remain open" unless
        pull["state"] == "open" && pull["merged_at"].nil?
      source_commit = pull.dig("head", "sha").to_s
      base_commit = pull.dig("base", "sha").to_s
      errors << "validator amendment 2 candidate head is invalid" unless source_commit.match?(/\A[0-9a-f]{40}\z/)
      errors << "validator amendment 2 candidate base lacks amendment 1" unless
        base_commit.match?(/\A[0-9a-f]{40}\z/) &&
        ancestor_checker.call(RC7_VALIDATOR_AMENDMENT_1_COMMIT, base_commit)
    else
      errors << "validator amendment 2 must be merged to protected main" unless
        pull["state"] == "closed" && pull["merged_at"]
      source_commit = pull["merge_commit_sha"].to_s
      errors << "validator amendment 2 merge commit is invalid" unless source_commit.match?(/\A[0-9a-f]{40}\z/)
      if source_commit.match?(/\A[0-9a-f]{40}\z/)
        errors << "validator amendment 2 merge is not an ancestor of this checkout" unless
          ancestor_checker.call(source_commit, "HEAD")
        errors << "validator amendment 2 was not based on amendment 1" unless
          ancestor_checker.call(RC7_VALIDATOR_AMENDMENT_1_COMMIT, "#{source_commit}^")
      end
    end

    if source_commit&.match?(/\A[0-9a-f]{40}\z/)
      VALIDATOR_AMENDMENT_2_CHANGED_PATHS.each do |path|
        current = ROOT.join(path)
        frozen = blob_fetcher.call(source_commit, path)
        errors << "validator amendment 2 source does not contain exact #{path}" unless
          frozen && current.file? && !current.symlink? && frozen == current.binread
      end
      errors << "validator amendment 2 source contains an intake authorization" if
        blob_fetcher.call(source_commit, "research/pilot-intake-authorization.json")
      errors << "validator amendment 2 source exposes the active validation form" if
        blob_fetcher.call(source_commit, PAUSED_INTAKE_DOCUMENT)
      snapshot = parse_strict_json_object(
        blob_fetcher.call(RC7_REPLACEMENT_REGISTRATION_COMMIT, "research/pilots/rc7/open-banners.json"),
        "frozen RC7 open-banner snapshot"
      )
      Array(snapshot["documents"]).each do |entry|
        path = entry["path"].to_s
        errors << "validator amendment 2 source changes closed public status: #{path}" unless
          blob_fetcher.call(source_commit, path) == blob_fetcher.call(RC7_VALIDATOR_AMENDMENT_1_COMMIT, path)
      end
    end
    [VOIDED_OPENING_NOTICE_2, HUMAN_VOID_RECORD_2, MACHINE_VOID_RECORD_2].each do |record|
      errors.concat(validate_void_comment(record, github_fetcher))
    end
    errors
  rescue TypeError, NoMethodError, KeyError, ArgumentError => e
    ["validator amendment 2 source failed closed: #{e.message}"]
  end

  def validate_historical_validator_amendment_1(
    amendment,
    v2,
    github_fetcher: method(:github_api_json),
    blob_fetcher: method(:git_blob),
    ancestor_checker: method(:git_ancestor?)
  )
    errors = validate_validator_amendment_structure(amendment, v2, check_files: false)
    errors << "historical validator amendment 1 digest differs" unless
      Digest::SHA256.hexdigest(JSON.generate(amendment)) == RC7_VALIDATOR_AMENDMENT_1_SHA256
    errors << "historical validator manifest v2 digest differs" unless
      Digest::SHA256.hexdigest(JSON.generate(v2)) == RC7_VALIDATOR_V2_SHA256
    {
      "research/pilots/rc7/validator-amendment-1.json" => VALIDATOR_AMENDMENT_PATH,
      "research/pilots/rc7/validator-manifest-v2.json" => VALIDATOR_MANIFEST_V2_PATH
    }.each do |path, current|
      errors << "historical validator amendment 1 blob differs: #{path}" unless
        current.file? && !current.symlink? && blob_fetcher.call(RC7_VALIDATOR_AMENDMENT_1_COMMIT, path) == current.binread
    end
    Hash(v2["files_sha256"]).each do |path, digest|
      frozen = blob_fetcher.call(RC7_VALIDATOR_AMENDMENT_1_COMMIT, path)
      errors << "historical validator v2 file differs: #{path}" unless
        frozen && Digest::SHA256.hexdigest(frozen) == digest
    end
    pull = github_fetcher.call("repos/MarinJursic/fixcard/pulls/29")
    files = github_fetcher.call("repos/MarinJursic/fixcard/pulls/29/files?per_page=100")
    errors << "historical validator amendment 1 pull request differs" unless
      pull["number"] == VALIDATOR_AMENDMENT_PR["number"] &&
      pull["id"] == VALIDATOR_AMENDMENT_PR["id"] &&
      pull["state"] == "closed" && pull["merged_at"] &&
      pull["merge_commit_sha"] == RC7_VALIDATOR_AMENDMENT_1_COMMIT &&
      pull.dig("base", "ref") == "main" &&
      pull.dig("base", "repo", "id") == VALIDATOR_AMENDMENT_PR["repository_id"] &&
      pull["changed_files"] == VALIDATOR_AMENDMENT_CHANGED_PATHS.length &&
      Array(files).map { |entry| entry["filename"] }.sort == VALIDATOR_AMENDMENT_CHANGED_PATHS.sort &&
      ancestor_checker.call(RC7_REPLACEMENT_REGISTRATION_COMMIT, "#{RC7_VALIDATOR_AMENDMENT_1_COMMIT}^") &&
      ancestor_checker.call(RC7_VALIDATOR_AMENDMENT_1_COMMIT, "HEAD")
    [VOIDED_OPENING_NOTICE, HUMAN_VOID_RECORD, MACHINE_VOID_RECORD].each do |record|
      errors.concat(validate_void_comment(record, github_fetcher))
    end
    errors
  rescue TypeError, NoMethodError, KeyError, ArgumentError => e
    ["historical validator amendment 1 failed closed: #{e.message}"]
  end

  def validate_validator_manifest(
    replacement,
    registration_commit: nil,
    github_fetcher: method(:github_api_json),
    event_name: ENV["GITHUB_EVENT_NAME"],
    event: github_event,
    blob_fetcher: method(:git_blob),
    ancestor_checker: method(:git_ancestor?)
  )
    binding = replacement["validator_manifest"]
    return ["validator manifest binding is missing"] unless binding.is_a?(Hash)

    path = binding["path"].to_s
    return ["validator manifest path differs"] unless path == "research/pilots/rc7/validator-manifest.json"

    manifest = load_strict_json_object(ROOT.join(path), "RC7 historical validator manifest")
    errors = []
    errors << "validator manifest canonical digest differs" unless
      Digest::SHA256.hexdigest(JSON.generate(manifest)) == binding["canonical_json_sha256"] &&
      binding["canonical_json_sha256"] == RC7_VALIDATOR_V1_SHA256
    errors << "validator manifest pilot_id differs" unless manifest["pilot_id"] == EXPECTED_RC7_PILOT_ID
    files = manifest["files_sha256"]
    unless files.is_a?(Hash) && files.keys.sort == VALIDATOR_SCRIPT_PATHS.sort
      errors << "validator manifest file set differs"
      return errors
    end
    files.each do |relative, expected_sha256|
      frozen_file = blob_fetcher.call(RC7_REPLACEMENT_REGISTRATION_COMMIT, relative)
      errors << "historical validator file differs at preregistration: #{relative}" unless
        frozen_file && Digest::SHA256.hexdigest(frozen_file) == expected_sha256
    end
    frozen_manifest = blob_fetcher.call(RC7_REPLACEMENT_REGISTRATION_COMMIT, path)
    errors << "preregistration commit does not contain the historical validator manifest" unless frozen_manifest
    errors << "historical validator manifest differs from the preregistration commit" unless
      frozen_manifest && frozen_manifest == ROOT.join(path).binread
    if registration_commit
      errors << "activation registration commit is not the preregistration commit" unless
        registration_commit == RC7_REPLACEMENT_REGISTRATION_COMMIT
      frozen_manifest = blob_fetcher.call(registration_commit, path)
      errors << "registration commit does not contain the validator manifest" unless frozen_manifest
      errors << "validator manifest differs from the registration commit" if
        frozen_manifest && frozen_manifest != ROOT.join(path).binread
    end

    amendment = load_validator_amendment
    v2 = load_validator_manifest_v2
    return errors << "historical validator amendment 1 or manifest v2 is missing" unless amendment && v2
    errors.concat(
      validate_historical_validator_amendment_1(
        amendment,
        v2,
        github_fetcher: github_fetcher,
        blob_fetcher: blob_fetcher,
        ancestor_checker: ancestor_checker
      )
    )

    amendment_2 = load_validator_amendment_2
    if amendment_2.nil?
      Hash(v2["files_sha256"]).each do |relative, expected_sha256|
        file = ROOT.join(relative)
        errors << "validator v2 file changed without amendment 2: #{relative}" unless
          file.file? && !file.symlink? && Digest::SHA256.file(file).hexdigest == expected_sha256
      end
      return errors
    end

    v3 = load_validator_manifest_v3
    return errors << "validator manifest v3 is missing" unless v3
    errors.concat(validate_validator_amendment_2_structure(amendment_2, v3))
    errors.concat(
      validate_validator_amendment_2_source(
        github_fetcher: github_fetcher,
        event_name: event_name,
        event: event,
        blob_fetcher: blob_fetcher,
        ancestor_checker: ancestor_checker
      )
    )
    errors
  rescue TypeError, NoMethodError, KeyError, ArgumentError => e
    ["validator manifest is invalid: #{e.message}"]
  end

  def validate_activation_record(
    authorization,
    replacement,
    github_fetcher: method(:github_api_json),
    require_merged: true
  )
    return ["activation record top level must be an object"] unless authorization.is_a?(Hash)

    policy = load_strict_json_object(ACTIVATION_POLICY_PATH, "RC7 activation policy")
    errors = []
    errors << "activation record keys differ from the preregistered schema" unless
      authorization.keys.sort == policy.fetch("required_top_level_keys").sort
    errors << "activation schema_version must be 1" unless authorization["schema_version"] == 1
    errors << "activation event_type differs" unless authorization["event_type"] == policy["event_type"]
    errors << "activation event sequence must be 1" unless authorization["sequence"] == 1
    errors << "activation previous event must be null" unless authorization["previous_event_sha256"].nil?
    errors << "activation pilot_id differs" unless authorization["pilot_id"] == EXPECTED_RC7_PILOT_ID

    registration_binding = authorization["registration"]
    expected_registration_sha256 = Digest::SHA256.hexdigest(JSON.generate(replacement))
    expected_registration_keys = %w[
      commit canonical_json_sha256 pull_request_number pull_request_id
      pull_request_url merged_at
    ]
    unless registration_binding.is_a?(Hash) && registration_binding.keys.sort == expected_registration_keys.sort
      errors << "activation registration binding keys differ"
    end
    registration_commit = registration_binding&.fetch("commit", "").to_s
    errors << "activation registration commit must be a full SHA-1" unless registration_commit.match?(/\A[0-9a-f]{40}\z/)
    errors << "activation registration digest differs" unless
      registration_binding&.fetch("canonical_json_sha256", nil) == expected_registration_sha256
    if registration_commit.match?(/\A[0-9a-f]{40}\z/)
      _stdout, _stderr, exists = Open3.capture3("git", "-C", ROOT.to_s, "cat-file", "-e", "#{registration_commit}^{commit}")
      errors << "activation registration commit does not exist" unless exists.success?
      _stdout, _stderr, ancestor = Open3.capture3("git", "-C", ROOT.to_s, "merge-base", "--is-ancestor", registration_commit, "HEAD")
      errors << "activation registration commit is not an ancestor of this checkout" unless ancestor.success?
      frozen_registration = git_blob(registration_commit, "research/pilot-replacement-registration.json")
      if frozen_registration.nil?
        errors << "activation registration commit does not contain the replacement registration"
      else
        begin
          frozen_object = JSON.parse(frozen_registration, object_class: StrictJsonObject)
          errors << "activation registration commit contains a different registration" unless frozen_object == replacement
          errors << "activation registration digest differs from committed registration" unless
            Digest::SHA256.hexdigest(JSON.generate(frozen_object)) == expected_registration_sha256
        rescue DuplicateJsonKeyError, JSON::ParserError
          errors << "activation registration commit contains invalid registration JSON"
        end
      end
    end

    # Do not perform network checks for a record that fails the immutable
    # registration binding. This makes fabricated or same-PR activations close
    # deterministically even when GitHub is unavailable.
    return errors unless errors.empty?

    errors.concat(validate_validator_manifest(replacement, registration_commit: registration_commit))
    return errors unless errors.empty?

    issue = authorization["issue"]
    expected_issue_keys = %w[
      repository repository_id issue_number issue_id comment_id comment_url
      author_login author_id created_at updated_at body body_sha256
    ]
    errors << "activation issue binding keys differ" unless issue.is_a?(Hash) && issue.keys.sort == expected_issue_keys.sort
    policy_issue = policy.fetch("issue")
    %w[repository repository_id issue_number issue_id author_login author_id].each do |field|
      errors << "activation issue #{field} differs" unless issue&.fetch(field, nil) == policy_issue.fetch(field)
    end
    comment_id = issue&.fetch("comment_id", nil)
    errors << "activation comment_id must be a positive integer" unless comment_id.is_a?(Integer) && comment_id.positive?
    expected_url = "https://github.com/MarinJursic/fixcard/issues/5#issuecomment-#{comment_id}"
    errors << "activation comment URL differs" unless issue&.fetch("comment_url", nil) == expected_url
    created_at = canonical_utc_time(issue&.fetch("created_at", nil))
    updated_at = canonical_utc_time(issue&.fetch("updated_at", nil))
    errors << "activation comment created_at must be canonical UTC RFC3339" unless created_at
    errors << "activation comment must be unedited" unless created_at && updated_at == created_at

    body = issue&.fetch("body", "").to_s
    body_sha256 = issue&.fetch("body_sha256", "").to_s
    errors << "activation comment body digest differs" unless Digest::SHA256.hexdigest(body) == body_sha256
    registration_sha256 = registration_binding&.fetch("canonical_json_sha256", "").to_s
    stage_2_value = authorization.dig("eligibility", "stage_2_eligible_at").to_s
    stage_3_value = authorization.dig("eligibility", "stage_3_eligible_on").to_s
    body_pattern = /\AFIXCARD-PILOT-OPEN pilot_id=#{Regexp.escape(EXPECTED_RC7_PILOT_ID)} registration_sha256=#{Regexp.escape(registration_sha256)} build_commit=#{EXPECTED_REPLACEMENT.fetch('commit')} stage_2_eligible_at=#{Regexp.escape(stage_2_value)} stage_3_eligible_on=#{Regexp.escape(stage_3_value)} nonce=[A-Z0-9]{16}\z/
    errors << "activation comment body does not match the preregistered grammar" unless body.match?(body_pattern)

    errors << "activation stage set differs" unless authorization["authorized_stages"] == policy["authorized_stages"]
    eligibility = authorization["eligibility"]
    errors << "activation eligibility keys differ" unless
      eligibility.is_a?(Hash) && eligibility.keys.sort == %w[stage_2_eligible_at stage_3_eligible_on].sort
    stage_2_at = canonical_utc_time(stage_2_value)
    stage_3_on = iso_date(stage_3_value)
    errors << "activation Stage 2 boundary must be canonical UTC RFC3339" unless stage_2_at
    errors << "activation Stage 3 boundary must be a real YYYY-MM-DD date" unless stage_3_on
    registered_not_before = iso_date(policy.dig("eligibility", "registered_not_before"))
    registered_not_before_at = Time.utc(
      registered_not_before.year,
      registered_not_before.month,
      registered_not_before.day
    ) if registered_not_before
    errors << "activation Stage 2 boundary predates the registered not-before date" if
      stage_2_at && registered_not_before_at && stage_2_at < registered_not_before_at
    errors << "activation Stage 3 boundary predates the registered not-before date" if
      stage_3_on && registered_not_before && stage_3_on < registered_not_before

    build = authorization["build"]
    expected_build = {
      "pilot_id" => EXPECTED_RC7_PILOT_ID,
      "version" => EXPECTED_REPLACEMENT.fetch("version"),
      "tag" => EXPECTED_REPLACEMENT.fetch("tag"),
      "commit" => EXPECTED_REPLACEMENT.fetch("commit"),
      "build_manifest_sha256" => EXPECTED_RC7_BUILD_MANIFEST_SHA256,
      "homebrew_formula_commit" => "71f00d5574ab8fe6e06c224df0219752ddd44370"
    }
    errors << "activation build binding differs" unless build == expected_build
    errors << "activation public form differs" unless
      authorization["public_form_sha256"] == policy["public_form_sha256"]
    counts = authorization["eligible_evidence_at_opening"]
    unless counts.is_a?(Hash) && counts.keys.sort == ELIGIBLE_EVIDENCE_KEYS.sort && counts.values.all? { |value| value == 0 }
      errors << "activation must start every eligible-evidence count at zero"
    end
    errors << "activation cannot allow stable release" unless authorization["stable_release_allowed"] == false

    activation = authorization["activation_pull_request"]
    expected_activation_keys = %w[number id url base_ref]
    errors << "activation pull-request binding keys differ" unless
      activation.is_a?(Hash) && activation.keys.sort == expected_activation_keys.sort
    errors << "activation pull-request number must be positive" unless activation&.fetch("number", nil).is_a?(Integer) && activation["number"].positive?
    errors << "activation pull-request id must be positive" unless activation&.fetch("id", nil).is_a?(Integer) && activation["id"].positive?
    errors << "activation pull-request base must be main" unless activation&.fetch("base_ref", nil) == "main"
    expected_pr_url = "https://github.com/MarinJursic/fixcard/pull/#{activation&.fetch('number', '')}"
    errors << "activation pull-request URL differs" unless activation&.fetch("url", nil) == expected_pr_url
    errors << "activation must use a pull request separate from both validator amendments" if
      [VALIDATOR_AMENDMENT_PR["number"], VALIDATOR_AMENDMENT_2_PR["number"]].include?(
        activation&.fetch("number", nil)
      )
    return errors unless errors.empty?

    registration_pr_number = registration_binding.fetch("pull_request_number")
    errors << "registration pull-request number must be positive" unless registration_pr_number.is_a?(Integer) && registration_pr_number.positive?
    return errors unless errors.empty?

    repository_api = github_fetcher.call("repos/MarinJursic/fixcard")
    issue_api = github_fetcher.call("repos/MarinJursic/fixcard/issues/5")
    comment_api = github_fetcher.call("repos/MarinJursic/fixcard/issues/comments/#{comment_id}")
    registration_pull_api = github_fetcher.call("repos/MarinJursic/fixcard/pulls/#{registration_pr_number}")
    amendment_pull_api = github_fetcher.call("repos/MarinJursic/fixcard/pulls/30")
    pull_api = github_fetcher.call("repos/MarinJursic/fixcard/pulls/#{activation.fetch('number')}")
    errors << "GitHub repository identity differs" unless
      repository_api["id"] == policy_issue["repository_id"] && repository_api["full_name"] == policy_issue["repository"]
    errors << "GitHub issue identity differs" unless
      issue_api["id"] == policy_issue["issue_id"] && issue_api["number"] == policy_issue["issue_number"]
    errors << "GitHub issue must remain locked during controlled intake" unless issue_api["locked"] == true
    {
      "id" => comment_id,
      "html_url" => issue["comment_url"],
      "created_at" => issue["created_at"],
      "updated_at" => issue["updated_at"],
      "body" => issue["body"]
    }.each do |field, expected|
      errors << "GitHub opening comment #{field} differs" unless comment_api[field] == expected
    end
    errors << "GitHub opening-comment author differs" unless
      comment_api.dig("user", "login") == policy_issue["author_login"] &&
      comment_api.dig("user", "id") == policy_issue["author_id"]
    expected_registration_url = "https://github.com/MarinJursic/fixcard/pull/#{registration_pr_number}"
    errors << "registration pull request identity differs" unless
      registration_pull_api["id"] == registration_binding["pull_request_id"] &&
      registration_pull_api["number"] == registration_pr_number &&
      registration_pull_api["html_url"] == expected_registration_url &&
      registration_binding["pull_request_url"] == expected_registration_url
    errors << "registration pull request must be merged to main" unless
      registration_pull_api["state"] == "closed" && registration_pull_api["merged_at"] &&
      registration_pull_api.dig("base", "ref") == "main" &&
      registration_pull_api.dig("base", "repo", "id") == policy_issue["repository_id"]
    errors << "registration merge commit differs" unless registration_pull_api["merge_commit_sha"] == registration_commit
    errors << "registration merge timestamp differs" unless
      registration_pull_api["merged_at"] == registration_binding["merged_at"] &&
      canonical_utc_time(registration_binding["merged_at"])
    registration_merged_at = canonical_utc_time(registration_pull_api["merged_at"])
    errors << "opening comment must be later than the protected preregistration merge" unless
      created_at && registration_merged_at && created_at > registration_merged_at
    amendment_merge_commit = amendment_pull_api["merge_commit_sha"].to_s
    errors.concat(
      validate_fresh_opening_notice(
        comment_id: comment_id,
        created_at: created_at,
        amendment_pull: amendment_pull_api
      )
    )
    errors << "activation pull request identity differs" unless
      pull_api["id"] == activation["id"] && pull_api["number"] == activation["number"] &&
      pull_api["html_url"] == activation["url"]
    if require_merged
      errors << "activation pull request must be merged" unless pull_api["merged_at"] && pull_api["state"] == "closed"
    else
      errors << "activation candidate pull request must still be open" unless pull_api["merged_at"].nil? && pull_api["state"] == "open"
    end
    errors << "activation pull request base differs" unless
      pull_api.dig("base", "ref") == activation["base_ref"] &&
      pull_api.dig("base", "repo", "id") == policy_issue["repository_id"]

    merged_at = canonical_utc_time(pull_api["merged_at"])
    merge_commit = pull_api["merge_commit_sha"].to_s
    if require_merged && merged_at && merge_commit.match?(/\A[0-9a-f]{40}\z/)
      _stdout, _stderr, ancestor = Open3.capture3("git", "-C", ROOT.to_s, "merge-base", "--is-ancestor", merge_commit, "HEAD")
      errors << "activation merge commit is not an ancestor of this checkout" unless ancestor.success?
      errors << "replacement registration was not merged before activation" unless
        system("git", "-C", ROOT.to_s, "merge-base", "--is-ancestor", registration_commit, "#{merge_commit}^", out: File::NULL, err: File::NULL)
      errors << "validator amendment was not merged before activation" unless
        amendment_merge_commit.match?(/\A[0-9a-f]{40}\z/) &&
        git_ancestor?(amendment_merge_commit, "#{merge_commit}^")
      frozen_authorization = git_blob(merge_commit, "research/pilot-intake-authorization.json")
      errors << "activation merge commit does not contain this authorization" unless
        frozen_authorization && frozen_authorization == INTAKE_AUTHORIZATION_PATH.binread
      errors.concat(
        validate_activation_boundaries(
          stage_2_value: stage_2_value,
          stage_3_value: stage_3_value,
          comment_value: issue["created_at"],
          merged_value: pull_api["merged_at"],
          not_before_value: policy.dig("eligibility", "registered_not_before")
        )
      )
    elsif require_merged
      errors << "activation pull request merge metadata is invalid"
    else
      head_commit = pull_api.dig("head", "sha").to_s
      base_commit = pull_api.dig("base", "sha").to_s
      errors << "activation candidate head commit is invalid" unless head_commit.match?(/\A[0-9a-f]{40}\z/)
      errors << "activation candidate base does not contain the preregistration" unless
        base_commit.match?(/\A[0-9a-f]{40}\z/) &&
        system("git", "-C", ROOT.to_s, "merge-base", "--is-ancestor", registration_commit, base_commit, out: File::NULL, err: File::NULL)
      errors << "activation candidate base does not contain the validator amendment" unless
        base_commit.match?(/\A[0-9a-f]{40}\z/) &&
        amendment_merge_commit.match?(/\A[0-9a-f]{40}\z/) &&
        git_ancestor?(amendment_merge_commit, base_commit)
      frozen_authorization = git_blob(head_commit, "research/pilot-intake-authorization.json")
      errors << "activation candidate head does not contain this authorization" unless
        frozen_authorization && frozen_authorization == INTAKE_AUTHORIZATION_PATH.binread
      errors << "activation and registration must use different pull requests" if activation["number"] == registration_pr_number
      errors.concat(
        validate_activation_candidate_boundaries(
          stage_2_value: stage_2_value,
          stage_3_value: stage_3_value,
          comment_value: issue["created_at"],
          not_before_value: policy.dig("eligibility", "registered_not_before")
        )
      )
    end

    dormant_form = ROOT.join("research", "pilots", "rc7", "validation-report.yml")
    active_form = ROOT.join(".github", "ISSUE_TEMPLATE", "validation-report.yml")
    errors << "active validation form is not the preregistered RC7 form" unless
      dormant_form.file? && active_form.file? && !active_form.symlink? && dormant_form.binread == active_form.binread
    errors.concat(validate_open_banners(registration_commit))
    _stdout, supply_stderr, supply_status = Open3.capture3(
      "ruby",
      ROOT.join("scripts", "verify_rc7_supply_chain.rb").to_s
    )
    errors << "live RC7 release/formula verification failed closed: #{supply_stderr.strip}" unless supply_status.success?
    errors
  rescue TypeError, NoMethodError, KeyError, ArgumentError => e
    ["activation record failed closed: #{e.message}"]
  end

  def validate_activation_candidate(authorization, replacement, github_fetcher: method(:github_api_json))
    validate_activation_record(
      authorization,
      replacement,
      github_fetcher: github_fetcher,
      require_merged: false
    )
  end

  def activation_candidate_event?(authorization, event_name:, event:)
    return false unless event_name == "pull_request"
    return false unless authorization.is_a?(Hash) && event.is_a?(Hash)

    candidate_number = authorization.dig("activation_pull_request", "number")
    event_number = event.dig("pull_request", "number") || event["number"]
    candidate_number.is_a?(Integer) && candidate_number.positive? && event_number == candidate_number
  rescue TypeError, NoMethodError
    false
  end

  def validate_activation_candidate_boundaries(stage_2_value:, stage_3_value:, comment_value:, not_before_value:, as_of: Time.now.utc)
    stage_2_at = canonical_utc_time(stage_2_value)
    stage_3_on = iso_date(stage_3_value)
    comment_at = canonical_utc_time(comment_value)
    not_before = iso_date(not_before_value)
    errors = []
    errors << "activation candidate Stage 2 boundary is invalid" unless stage_2_at
    errors << "activation candidate Stage 3 boundary is invalid" unless stage_3_on
    errors << "activation candidate comment timestamp is invalid" unless comment_at
    errors << "activation candidate not-before date is invalid" unless not_before
    return errors unless stage_2_at && stage_3_on && comment_at && not_before

    not_before_at = Time.utc(not_before.year, not_before.month, not_before.day)
    errors << "activation candidate Stage 2 boundary must preserve at least 48 hours of merge lead time" unless
      stage_2_at >= as_of + (48 * 60 * 60)
    errors << "activation candidate Stage 2 boundary must be after the comment and not-before date" unless
      stage_2_at > [comment_at, not_before_at - 1].max
    errors << "activation candidate Stage 3 boundary must preserve at least three UTC dates of merge lead time" unless
      stage_3_on >= as_of.to_date + 3
    errors << "activation candidate Stage 3 boundary must be after the comment and not-before date" unless
      stage_3_on > [comment_at.to_date, not_before - 1].max
    errors
  end

  def activation_status_message(authorization, as_of: Time.now.utc)
    stage_2_value = authorization.dig("eligibility", "stage_2_eligible_at").to_s
    stage_3_value = authorization.dig("eligibility", "stage_3_eligible_on").to_s
    stage_2_at = canonical_utc_time(stage_2_value)
    stage_3_on = iso_date(stage_3_value)
    raise ArgumentError, "activation status boundaries are invalid" unless stage_2_at && stage_3_on

    stage_2_state = as_of < stage_2_at ? "NOT YET REACHED" : "OPEN"
    stage_3_state = as_of.to_date < stage_3_on ? "NOT YET REACHED" : "OPEN"
    "OPEN — Milestone 0 and Stage 1 are open. " \
      "Stage 2 boundary #{stage_2_value} (#{stage_2_state}); " \
      "Stage 3 boundary #{stage_3_value} (#{stage_3_state})."
  end

  def validate_open_banners(
    registration_commit,
    current_reader: lambda do |path|
      file = ROOT.join(path)
      file.binread if file.file? && !file.symlink?
    end
  )
    snapshot = load_strict_json_object(OPEN_BANNERS_PATH, "RC7 open-banner snapshot")
    Array(snapshot["documents"]).each_with_object([]) do |entry, errors|
      path = entry["path"].to_s
      frozen = git_blob(registration_commit, path)
      current = current_reader.call(path)
      unless frozen && current
        errors << "activation public-status document is missing or unsafe: #{path}"
        next
      end
      closed_prefix = (Array(entry["closed_lines"]).join("\n") + "\n").b
      open_prefix = (Array(entry["open_lines"]).join("\n") + "\n").b
      unless frozen.start_with?(closed_prefix)
        errors << "preregistered closed banner differs for #{path}"
        next
      end
      expected = open_prefix + frozen.delete_prefix(closed_prefix)
      errors << "active public banner differs for #{path}" unless current == expected
    end
  rescue TypeError, NoMethodError, KeyError, ArgumentError => e
    ["open-banner snapshot is invalid: #{e.message}"]
  end

  def validate_replacement_registration(replacement, registration:, interruption:)
    return ["replacement registration: top level must be an object"] unless replacement.is_a?(Hash)

    errors = []
    expected_top_keys = %w[
      schema_version status registered_on source_issue_comment interruption
      protocol protocol_manifest validator_manifest pilot build_manifest release
      intake stable_release_allowed
    ]
    errors << "replacement registration: top-level keys differ" unless replacement.keys.sort == expected_top_keys.sort
    errors.concat(validate_registration(registration, interruption: interruption))
    errors << "replacement registration: schema_version must be 1" unless replacement["schema_version"] == 1
    errors << "replacement registration: status differs" unless replacement["status"] == "replacement_preregistered_collection_closed"
    errors << "replacement registration: registered_on differs" unless replacement["registered_on"] == EXPECTED_REPLACEMENT.fetch("registered_on")
    errors << "replacement registration: pilot ID differs" unless replacement.dig("pilot", "pilot_id") == EXPECTED_RC7_PILOT_ID
    errors << "replacement registration: version differs" unless replacement.dig("pilot", "version") == EXPECTED_REPLACEMENT.fetch("version")
    errors << "replacement registration: tag differs" unless replacement.dig("pilot", "tag") == EXPECTED_REPLACEMENT.fetch("tag")
    errors << "replacement registration: build commit differs" unless replacement.dig("pilot", "commit") == EXPECTED_REPLACEMENT.fetch("commit")
    errors << "replacement registration: build manifest binding differs" unless
      replacement.dig("build_manifest", "canonical_json_sha256") == EXPECTED_RC7_BUILD_MANIFEST_SHA256
    errors << "replacement registration: authorization record must remain absent" unless
      replacement.dig("intake", "authorization_record_present") == false
    errors << "replacement registration: every stage must remain closed" unless
      replacement.dig("intake", "stage_authorization") == {
        "milestone_0" => false, "stage_1" => false, "stage_2" => false, "stage_3" => false
      }
    errors << "replacement registration: stable release must remain disallowed" unless replacement["stable_release_allowed"] == false

    expected_zero_counts = ELIGIBLE_EVIDENCE_KEYS.to_h { |key| [key, 0] }
    expected_interruption = {
      "record" => "research/pilot-interruption.json",
      "source_issue_comment" => EXPECTED_INTERRUPTION.fetch("source_issue_comment"),
      "supersedes" => EXPECTED_INTERRUPTION.fetch("interrupted_pilot"),
      "rule" => EXPECTED_INTERRUPTION.fetch("restart_rule"),
      "carry_forward_eligible_evidence" => false,
      "eligible_evidence_at_replacement_registration" => expected_zero_counts
    }
    errors << "replacement registration: interruption binding differs" unless replacement["interruption"] == expected_interruption
    errors << "replacement registration: source status comment differs" unless
      replacement["source_issue_comment"] == "https://github.com/MarinJursic/fixcard/issues/5#issuecomment-5302745106"

    expected_pilot = {
      "pilot_id" => EXPECTED_RC7_PILOT_ID,
      "version" => EXPECTED_REPLACEMENT.fetch("version"),
      "tag" => EXPECTED_REPLACEMENT.fetch("tag"),
      "commit" => EXPECTED_REPLACEMENT.fetch("commit"),
      "eligible_observations_on_or_after" => EXPECTED_REPLACEMENT.fetch("eligible_on"),
      "working_weeks" => 4,
      "stable_decision_after_weeks" => 8,
      "repositories" => { "minimum" => 5, "maximum" => 8 },
      "build_switching" => "forbidden",
      "security_fix_rule" => "stop_document_and_preregister_restart"
    }
    errors << "replacement registration: pilot rules differ" unless replacement["pilot"] == expected_pilot

    expected_build_binding = {
      "path" => "research/pilots/rc7/build-manifest.json",
      "canonical_json_sha256" => EXPECTED_RC7_BUILD_MANIFEST_SHA256,
      "required_on_every_stage_2_and_stage_3_row" => true,
      "installation_receipt_required_per_participant_repository_membership" => true,
      "stage_2_receipt_required_per_observed_participant" => true,
      "receipt_must_precede_first_observation" => true
    }
    errors << "replacement registration: build/receipt rules differ" unless
      replacement["build_manifest"] == expected_build_binding

    form_sha256 = if ROOT.join("research", "pilots", "rc7", "validation-report.yml").file?
                    Digest::SHA256.file(ROOT.join("research", "pilots", "rc7", "validation-report.yml")).hexdigest
                  end
    expected_intake = {
      "stage_authorization" => {
        "milestone_0" => false, "stage_1" => false, "stage_2" => false, "stage_3" => false
      },
      "authorization_record" => "research/pilot-intake-authorization.json",
      "authorization_record_present" => false,
      "dormant_public_form" => "research/pilots/rc7/validation-report.yml",
      "dormant_public_form_sha256" => form_sha256,
      "activation_form_target" => ".github/ISSUE_TEMPLATE/validation-report.yml",
      "activation_form_must_be_byte_identical" => true,
      "activation_policy" => "research/pilots/rc7/activation-policy.json",
      "open_banner_snapshot" => "research/pilots/rc7/open-banners.json",
      "activation_boundary" => {
        "stage_2_field" => "stage_2_eligible_at",
        "stage_2_format" => "canonical_utc_rfc3339",
        "stage_2_rule" => "later_than_opening_comment_and_activation_merge",
        "stage_3_field" => "stage_3_eligible_on",
        "stage_3_format" => "YYYY-MM-DD",
        "stage_3_rule" => "strictly_after_opening_comment_activation_merge_and_registered_minimum",
        "reject_future_observations_at_validation_time" => true
      },
      "opening_requires" => %w[
        replacement_registration_merged_to_protected_main
        activation_binds_the_protected_main_registration_commit_and_validator_tree
        eligible_start_date_reached later_explicit_issue_5_opening_comment
        protected_exact_authorization_record sanitized_public_intake_restored
      ]
    }
    errors << "replacement registration: intake/activation rules differ" unless replacement["intake"] == expected_intake

    errors << "replacement registration: historical registration binding differs" unless
      replacement.dig("protocol", "fixed_gates_binding") == {
        "source" => "research/pilot-registration.json#/fixed_gates",
        "canonical_json_sha256" => Digest::SHA256.hexdigest(JSON.generate(registration["fixed_gates"]))
      }
    errors << "replacement registration: kill-criteria binding differs" unless
      replacement.dig("protocol", "kill_criteria_binding") == {
        "source" => "research/pilot-registration.json#/kill_criteria",
        "count" => 10,
        "canonical_json_sha256" => Digest::SHA256.hexdigest(JSON.generate(registration["kill_criteria"]))
      }
    errors << "replacement registration: all ten kill criteria must remain bound" unless
      replacement.dig("protocol", "kill_criteria_binding", "count") == 10 &&
      Array(registration["kill_criteria"]).length == 10

    registered_on = iso_date(replacement["registered_on"])
    eligible_on = iso_date(replacement.dig("pilot", "eligible_observations_on_or_after"))
    errors << "replacement registration: registered_on must be a real YYYY-MM-DD date" unless registered_on
    errors << "replacement registration: eligible observation date must use YYYY-MM-DD" unless eligible_on
    errors << "replacement registration: observations must begin after registration" if registered_on && eligible_on && eligible_on <= registered_on

    documents = Array(replacement.dig("protocol", "documents"))
    errors << "replacement registration: protocol document set differs" unless documents == RC7_REPLACEMENT_DOCUMENTS
    errors << "replacement registration: protocol object keys differ" unless
      replacement["protocol"].is_a?(Hash) && replacement["protocol"].keys.sort == %w[
        commit documents raw_data_location public_data_policy fixed_gates_binding
        kill_criteria_binding response_bias_reporting
      ].sort
    errors << "replacement registration: historical protocol commit differs" unless
      replacement.dig("protocol", "commit") == EXPECTED_REPLACEMENT.fetch("protocol_commit")
    errors << "replacement registration: raw-data location differs" unless
      replacement.dig("protocol", "raw_data_location") == "access_controlled_outside_public_repository"
    errors << "replacement registration: public-data policy differs" unless
      replacement.dig("protocol", "public_data_policy") == "sanitized_cross_repository_aggregates_with_small_cell_suppression"
    errors << "replacement registration: response-bias reporting differs" unless
      replacement.dig("protocol", "response_bias_reporting") ==
      "publish_response_counts_missingness_attrition_and_all_recruited_or_all_active_sensitivity_views"
    errors << "replacement registration: protocol-manifest path differs" unless
      replacement.dig("protocol_manifest", "path") == "research/pilots/rc7/protocol-manifest.json"
    errors << "replacement registration: validator-manifest path differs" unless
      replacement.dig("validator_manifest", "path") == "research/pilots/rc7/validator-manifest.json"
    historical_documents = Array(registration.dig("protocol", "documents"))
    documents.select { |document| document.is_a?(String) }.each do |document|
      next if ROOT.join(document).file?
      next if document == PAUSED_INTAKE_DOCUMENT

      errors << "replacement registration: missing bound document #{document}"
    end
    build_manifest_path = ROOT.join(replacement.dig("build_manifest", "path").to_s)
    if build_manifest_path.file?
      manifest = load_strict_json_object(build_manifest_path, "RC7 build manifest")
      manifest_sha256 = Digest::SHA256.hexdigest(JSON.generate(manifest))
      errors << "replacement registration: build manifest digest differs" unless
        manifest_sha256 == replacement.dig("build_manifest", "canonical_json_sha256")
      assets = manifest.dig("release", "assets")
      archives = assets.select { |asset| asset["name"].match?(/\.(?:tar\.gz|zip)\z/) }
      archive_sha256 = archives.to_h { |asset| [asset["name"], asset["sha256"]] }
      checksum = assets.find { |asset| asset["name"] == "SHA256SUMS" }
      sbom = assets.find { |asset| asset["name"] == "fixcard.cdx.json" }
      expected_release = {
        "url" => manifest.dig("release", "url"),
        "workflow_url" => manifest.dig("release_workflow", "url"),
        "prerelease" => true,
        "asset_count" => manifest.dig("release", "asset_count"),
        "checksum_asset" => "SHA256SUMS",
        "checksum_asset_sha256" => checksum&.fetch("sha256", nil),
        "sbom_asset" => "fixcard.cdx.json",
        "sbom_asset_sha256" => sbom&.fetch("sha256", nil),
        "archive_sha256" => archive_sha256,
        "slsa_provenance_attestations_verified" => manifest.dig("attestations", "slsa_provenance_subjects_verified"),
        "cyclonedx_sbom_attestations_verified" => manifest.dig("attestations", "cyclonedx_subjects_verified"),
        "homebrew_formula_commit" => manifest.dig("homebrew", "formula_commit"),
        "homebrew_formula_url" => manifest.dig("homebrew", "formula_url"),
        "homebrew_workflow_url" => manifest.dig("homebrew", "workflow_url"),
        "homebrew_verified_platforms" => manifest.dig("homebrew", "verified_platforms")
      }
      errors << "replacement registration: release/supply-chain binding differs" unless replacement["release"] == expected_release
    else
      errors << "replacement registration: build manifest is missing"
    end
    protocol_manifest_path = ROOT.join(replacement.dig("protocol_manifest", "path").to_s)
    if protocol_manifest_path.file?
      protocol_manifest = load_strict_json_object(protocol_manifest_path, "RC7 protocol manifest")
      protocol_manifest_sha256 = Digest::SHA256.hexdigest(JSON.generate(protocol_manifest))
      errors << "replacement registration: protocol manifest digest differs" unless
        protocol_manifest_sha256 == replacement.dig("protocol_manifest", "canonical_json_sha256")
      errors << "replacement registration: protocol manifest file set differs" unless
        protocol_manifest["files_sha256"].is_a?(Hash) &&
        protocol_manifest["files_sha256"].keys.sort == RC7_PROTOCOL_FILE_PATHS.sort
      Hash(protocol_manifest["files_sha256"]).each do |path, expected_sha256|
        file_path = ROOT.join(path)
        if !file_path.file? || file_path.symlink?
          errors << "replacement registration: bound protocol file is missing or unsafe: #{path}"
        elsif !protocol_file_matches_closed_or_open?(path, file_path, expected_sha256)
          errors << "replacement registration: bound protocol file changed: #{path}"
        end
      end
    else
      errors << "replacement registration: protocol manifest is missing"
    end
    errors.concat(validate_validator_manifest(replacement)) if errors.empty?
    errors.concat(validate_git_bindings(
                    replacement.dig("protocol", "commit").to_s,
                    replacement.dig("pilot", "commit").to_s,
                    replacement.dig("pilot", "tag").to_s,
                    replacement.dig("pilot", "version").to_s,
                    historical_documents,
                    allow_pause_banners: true
                  ))
    errors
  rescue TypeError, NoMethodError
    ["replacement registration: nested values have invalid types"]
  end

  def protocol_file_matches_closed_or_open?(path, file_path, expected_sha256)
    return true if Digest::SHA256.file(file_path).hexdigest == expected_sha256

    snapshot = load_strict_json_object(OPEN_BANNERS_PATH, "RC7 open-banner snapshot")
    entry = Array(snapshot["documents"]).find { |candidate| candidate["path"] == path }
    return false unless entry

    current = file_path.binread
    closed_prefix = (Array(entry["closed_lines"]).join("\n") + "\n").b
    open_prefix = (Array(entry["open_lines"]).join("\n") + "\n").b
    return false unless current.start_with?(open_prefix)

    reconstructed_closed = closed_prefix + current.delete_prefix(open_prefix)
    Digest::SHA256.hexdigest(reconstructed_closed) == expected_sha256
  rescue ArgumentError, TypeError, NoMethodError
    false
  end

  def validate_registration(registration, interruption: nil)
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

    interruption ||= load_interruption
    interruption_errors = validate_interruption(interruption)
    pause_is_frozen = interruption_errors.empty?

    documents = Array(registration.dig("protocol", "documents"))
    errors << "registration: protocol document set differs" unless documents == EXPECTED_PROTOCOL_DOCUMENTS
    documents.select { |document| document.is_a?(String) }.each do |document|
      next if ROOT.join(document).file?
      next if pause_is_frozen && document == PAUSED_INTAKE_DOCUMENT

      errors << "registration: missing protocol document #{document}"
    end

    errors.concat(interruption_errors)
    errors.concat(validate_git_bindings(
                    protocol_commit,
                    expected_commit,
                    expected_tag,
                    expected_version,
                    documents,
                    allow_pause_banners: interruption_errors.empty?
                  ))

    errors
  rescue TypeError, NoMethodError
    ["registration: nested values have invalid types"]
  end

  def historical_document_matches?(document, current, frozen, allow_overlays:)
    return true if current == frozen
    return false unless allow_overlays

    heading = PAUSE_HEADINGS[document]
    return false unless heading

    prefixes = []
    pause_banner = PAUSE_BANNERS[document]
    prefixes << "#{heading}#{pause_banner}".b if pause_banner
    snapshot_blob = git_blob(
      RC7_REPLACEMENT_REGISTRATION_COMMIT,
      "research/pilots/rc7/open-banners.json"
    )
    snapshot = parse_strict_json_object(snapshot_blob, "frozen RC7 open-banner snapshot")
    entry = Array(snapshot["documents"]).find { |candidate| candidate["path"] == document }
    prefixes << (Array(entry["open_lines"]).join("\n") + "\n").b if entry
    prefixes.any? do |prefix|
      current.start_with?(prefix) && heading.b + current.delete_prefix(prefix) == frozen
    end
  rescue TypeError, NoMethodError, KeyError, ArgumentError
    false
  end

  def validate_git_bindings(protocol_commit, product_commit, tag, version, documents, allow_pause_banners: false)
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
        frozen, _stderr, status = Open3.capture3("git", "-C", ROOT.to_s, "show", "#{protocol_commit}:#{document}")
        if !status.success?
          errors << "registration: #{document} is absent from the protocol commit"
        elsif !current_path.file?
          unless allow_pause_banners && document == PAUSED_INTAKE_DOCUMENT
            errors << "registration: missing protocol document #{document}"
          end
        elsif allow_pause_banners && document == PAUSED_INTAKE_DOCUMENT
          dormant = ROOT.join("research", "pilots", "rc7", "validation-report.yml")
          errors << "registration: active validation form is not the exact RC7 snapshot" unless
            dormant.file? && current_path.binread == dormant.binread
        else
          current = current_path.binread
          errors << "registration: #{document} differs from the protocol commit" unless
            historical_document_matches?(
              document,
              current,
              frozen.b,
              allow_overlays: allow_pause_banners
            )
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
    trust_by_participant = {}

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
      if row["correct_rank_one"].to_s.empty? || row["controlled_variants"].to_s.empty?
        errors << "line #{line}: controlled_variants and correct_rank_one are required together"
      end
      errors << "line #{line}: correct_rank_one cannot exceed controlled_variants" if variants && correct && correct > variants
      unless row["creation_seconds"].to_s.empty? || (numeric?(row["creation_seconds"]) && row["creation_seconds"].to_f >= 0)
        errors << "line #{line}: creation_seconds must be a non-negative number or blank"
      end

      timing_counts = {}
      %w[fixcard_lookup_seconds_samples normal_search_seconds_samples].each do |field|
        next if row[field].to_s.empty?

        samples = row[field].split(";", -1)
        valid = samples.all? { |sample| numeric?(sample) && sample.to_f >= 0 }
        errors << "line #{line}: #{field} must be semicolon-separated non-negative numbers" unless valid
        timing_counts[field] = samples.length if valid
      end
      if timing_counts.length == 1
        errors << "line #{line}: Fixcard and normal-search timing samples must be reported together"
      elsif timing_counts.length == 2 && timing_counts.values.uniq.length != 1
        errors << "line #{line}: Fixcard and normal-search timing samples must have equal counts"
      end

      trust = row["trust_preferred"].to_s
      unless trust.empty?
        errors << "line #{line}: trust_preferred must be one of #{STAGE_2_TRUST_VALUES.join(', ')}" unless STAGE_2_TRUST_VALUES.include?(trust)
        previous_trust = trust_by_participant[participant]
        if previous_trust && previous_trust != trust
          errors << "line #{line}: trust_preferred conflicts with this participant's earlier response"
        elsif STAGE_2_TRUST_VALUES.include?(trust)
          trust_by_participant[participant] = trust
        end
      end

      metadata_confusion = row["metadata_confusion_observed"].to_s
      unless metadata_confusion.empty? || %w[true false].include?(metadata_confusion)
        errors << "line #{line}: metadata_confusion_observed must be true, false, or blank"
      end

      maintainer = row["maintainer_alias"].to_s
      decision = row["maintainer_decision"].to_s
      committed = row["card_committed"].to_s
      unless STAGE_2_MAINTAINER_DECISIONS.include?(decision)
        errors << "line #{line}: maintainer_decision must be one of #{STAGE_2_MAINTAINER_DECISIONS.join(', ')}"
      end
      errors << "line #{line}: card_committed must be true or false" unless %w[true false].include?(committed)
      if %w[accepted changes_requested rejected].include?(decision)
        errors << "line #{line}: reviewed cards require a maintainer_alias like M001" unless maintainer.match?(/\AM\d{3,}\z/)
      elsif decision == "not_reviewed" && !maintainer.empty?
        errors << "line #{line}: not_reviewed cards must not name a maintainer_alias"
      end
      if committed == "true" && decision != "accepted"
        errors << "line #{line}: only an accepted card may be recorded as committed"
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

  def validate_rc7_identity(table, expected_headers:, legacy_headers:, eligible_at: nil, observed_at: false, as_of: Time.now.utc)
    errors = []
    errors << "RC7 CSV: headers differ from the registered schema" unless table.headers == expected_headers
    legacy_rows = []

    table.each_with_index do |row, index|
      line = index + 2
      errors << "line #{line}: pilot_id must be exactly #{EXPECTED_RC7_PILOT_ID.inspect}" unless
        row["pilot_id"].to_s == EXPECTED_RC7_PILOT_ID
      errors << "line #{line}: build_manifest_sha256 must bind the exact RC7 build" unless
        row["build_manifest_sha256"].to_s == EXPECTED_RC7_BUILD_MANIFEST_SHA256

      if observed_at
        value = row["observed_at"].to_s
        timestamp = begin
          parsed = Time.iso8601(value)
          parsed if parsed.utc.iso8601 == value
        rescue ArgumentError
          nil
        end
        errors << "line #{line}: observed_at must be canonical UTC RFC3339" unless timestamp
        errors << "line #{line}: observed_at predates the protected activation boundary" if
          timestamp && eligible_at && timestamp < eligible_at
        errors << "line #{line}: observed_at is in the future" if timestamp && timestamp > as_of
      end

      legacy_rows << CSV::Row.new(legacy_headers, legacy_headers.map { |header| row[header] })
    end

    [errors, CSV::Table.new(legacy_rows)]
  end

  def validate_rc7_stage2_table(table, eligible_at:, as_of: Time.now.utc)
    errors, legacy = validate_rc7_identity(
      table,
      expected_headers: RC7_STAGE_2_HEADERS,
      legacy_headers: STAGE_2_HEADERS,
      eligible_at: eligible_at,
      observed_at: true,
      as_of: as_of
    )
    errors.concat(validate_stage2_table(legacy, exact_version: EXPECTED_REPLACEMENT.fetch("version")))
  end

  def validate_rc7_stage3_table(table, eligible_on:, complete_pilot: false, as_of: Date.today)
    errors, legacy = validate_rc7_identity(
      table,
      expected_headers: RC7_STAGE_3_HEADERS,
      legacy_headers: STAGE_3_HEADERS,
      eligible_at: nil
    )
    errors.concat(
      validate_stage3_table(
        legacy,
        exact_version: EXPECTED_REPLACEMENT.fetch("version"),
        eligible_on: eligible_on,
        complete_pilot: complete_pilot
      )
    )
    table.each_with_index do |row, index|
      observation_end = iso_date(row["observation_end"])
      errors << "line #{index + 2}: observation_end is in the future" if observation_end && observation_end > as_of
    end
    errors
  end

  def validate_rc7_stage3_user_reuse_table(table, eligible_on:)
    errors, legacy = validate_rc7_identity(
      table,
      expected_headers: RC7_STAGE_3_USER_REUSE_HEADERS,
      legacy_headers: STAGE_3_USER_REUSE_HEADERS,
      eligible_at: nil
    )
    errors.concat(
      validate_stage3_user_reuse_table(
        legacy,
        exact_version: EXPECTED_REPLACEMENT.fetch("version")
      )
    )
  end

  def validate_rc7_stage3_card_reuse_table(table, eligible_on:, pilot_periods: nil, as_of: Date.today)
    errors, legacy = validate_rc7_identity(
      table,
      expected_headers: RC7_STAGE_3_CARD_REUSE_HEADERS,
      legacy_headers: STAGE_3_CARD_REUSE_HEADERS,
      eligible_at: nil
    )
    errors.concat(
      validate_stage3_card_reuse_table(
        legacy,
        exact_version: EXPECTED_REPLACEMENT.fetch("version"),
        eligible_on: eligible_on,
        pilot_periods: pilot_periods
      )
    )
    table.each_with_index do |row, index|
      follow_up_end = iso_date(row["follow_up_end"])
      errors << "line #{index + 2}: follow_up_end is in the future" if follow_up_end && follow_up_end > as_of
    end
    errors
  end

  def validate_rc7_installation_receipts(table, eligible_at:, as_of: Time.now.utc)
    errors = []
    errors << "RC7 installation receipts: headers differ from the registered schema" unless
      table.headers == RC7_INSTALLATION_RECEIPT_HEADERS
    manifest = load_strict_json_object(RC7_BUILD_MANIFEST_PATH, "RC7 build manifest")
    archive_sha256 = manifest.dig("release", "assets").each_with_object({}) do |asset, hashes|
      name = asset.fetch("name")
      hashes[name] = asset.fetch("sha256") if name.match?(/\.(?:tar\.gz|zip)\z/)
    end
    formula_commit = manifest.dig("homebrew", "formula_commit")
    formula_sha256 = manifest.dig("homebrew", "formula_sha256")
    seen_installations = {}
    seen_memberships = {}

    table.each_with_index do |row, index|
      line = index + 2
      repository = row["repository_alias"].to_s
      participant = row["participant_alias"].to_s
      installation = row["installation_alias"].to_s
      errors << "line #{line}: pilot_id must be exactly #{EXPECTED_RC7_PILOT_ID.inspect}" unless
        row["pilot_id"].to_s == EXPECTED_RC7_PILOT_ID
      errors << "line #{line}: build_manifest_sha256 must bind the exact RC7 build" unless
        row["build_manifest_sha256"].to_s == EXPECTED_RC7_BUILD_MANIFEST_SHA256
      errors << "line #{line}: repository_alias must look like R001" unless repository.match?(/\AR\d{3,}\z/)
      errors << "line #{line}: participant_alias must look like P001" unless participant.match?(/\AP\d{3,}\z/)
      errors << "line #{line}: installation_alias must look like I001" unless installation.match?(/\AI\d{3,}\z/)
      errors << "line #{line}: duplicate installation_alias #{installation.inspect}" if seen_installations[installation]
      seen_installations[installation] = true
      membership = [participant, repository]
      errors << "line #{line}: duplicate participant/repository installation receipt" if seen_memberships[membership]
      seen_memberships[membership] = true
      errors << "line #{line}: verifier_alias must look like V001" unless row["verifier_alias"].to_s.match?(/\AV\d{3,}\z/)
      errors << "line #{line}: fixcard_version_output must be exact" unless
        row["fixcard_version_output"].to_s == "fixcard #{EXPECTED_REPLACEMENT.fetch('version')}"
      errors << "line #{line}: fix_version_output must be exact" unless
        row["fix_version_output"].to_s == "fix #{EXPECTED_REPLACEMENT.fetch('version')}"

      verified_at_value = row["verified_at"].to_s
      verified_at = begin
        parsed = Time.iso8601(verified_at_value)
        parsed if parsed.utc.iso8601 == verified_at_value
      rescue ArgumentError
        nil
      end
      errors << "line #{line}: verified_at must be canonical UTC RFC3339" unless verified_at
      errors << "line #{line}: verified_at predates the protected activation boundary" if
        verified_at && eligible_at && verified_at < eligible_at
      errors << "line #{line}: verified_at is in the future" if verified_at && verified_at > as_of

      case row["install_method"].to_s
      when "archive"
        name = row["artifact_name"].to_s
        errors << "line #{line}: archive receipt names an unregistered asset" unless archive_sha256.key?(name)
        errors << "line #{line}: archive receipt digest differs" unless archive_sha256[name] == row["artifact_sha256"].to_s
        errors << "line #{line}: archive receipt must not include formula fields" unless
          row["formula_commit"].to_s.empty? && row["formula_sha256"].to_s.empty?
      when "homebrew"
        errors << "line #{line}: Homebrew formula commit differs" unless row["formula_commit"].to_s == formula_commit
        errors << "line #{line}: Homebrew formula digest differs" unless row["formula_sha256"].to_s == formula_sha256
        errors << "line #{line}: Homebrew receipt must not include archive fields" unless
          row["artifact_name"].to_s.empty? && row["artifact_sha256"].to_s.empty?
      else
        errors << "line #{line}: install_method must be archive or homebrew"
      end
    end
    errors
  end

  def validate_rc7_stage2_receipt_coverage(stage2_table, receipt_table)
    participants = stage2_table.map { |row| row["participant_alias"].to_s }.reject(&:empty?).uniq.sort
    receipt_participants = receipt_table.map { |row| row["participant_alias"].to_s }.reject(&:empty?).uniq.sort
    errors = []
    errors << "Stage 2: installation receipts must cover exactly every observed participant" unless
      participants == receipt_participants
    receipt_counts = receipt_table.each_with_object(Hash.new(0)) do |row, counts|
      participant = row["participant_alias"].to_s
      counts[participant] += 1 unless participant.empty?
    end
    errors << "Stage 2: every observed participant must have exactly one installation receipt" unless
      participants.all? { |participant| receipt_counts[participant] == 1 } &&
      receipt_counts.keys.sort == participants
    first_observation = stage2_table.each_with_object({}) do |row, times|
      timestamp = canonical_utc_time(row["observed_at"])
      participant = row["participant_alias"].to_s
      times[participant] = [times[participant], timestamp].compact.min if timestamp
    end
    receipt_table.each_with_index do |row, index|
      verified_at = canonical_utc_time(row["verified_at"])
      observed_at = first_observation[row["participant_alias"].to_s]
      errors << "line #{index + 2}: installation receipt must precede the participant's first Stage 2 observation" if
        verified_at && observed_at && verified_at > observed_at
    end
    errors
  end

  def validate_rc7_receipt_coverage(stage3_table, user_reuse_table, receipt_table)
    errors = []
    pilot_repositories = stage3_table.map { |row| row["repository_alias"].to_s }.reject(&:empty?).uniq.sort
    receipt_repositories = receipt_table.map { |row| row["repository_alias"].to_s }.reject(&:empty?).uniq.sort
    errors << "Stage 3: installation receipts must cover exactly every observed repository" unless
      pilot_repositories == receipt_repositories
    if user_reuse_table
      pilot_memberships = user_reuse_table.map do |row|
        [row["participant_alias"].to_s, row["repository_alias"].to_s]
      end.reject { |membership| membership.any?(&:empty?) }.uniq.sort
      receipt_memberships = receipt_table.map do |row|
        [row["participant_alias"].to_s, row["repository_alias"].to_s]
      end.reject { |membership| membership.any?(&:empty?) }.uniq.sort
      errors << "complete pilot: installation receipts must cover exactly every participant/repository membership" unless
        pilot_memberships == receipt_memberships
    end
    first_observation = stage3_table.each_with_object({}) do |row, starts|
      repository = row["repository_alias"].to_s
      start_date = iso_date(row["observation_start"])
      starts[repository] = [starts[repository], start_date].compact.min if start_date
    end
    receipt_table.each_with_index do |row, index|
      verified_at = canonical_utc_time(row["verified_at"])
      start_date = first_observation[row["repository_alias"].to_s]
      start_at = Time.utc(start_date.year, start_date.month, start_date.day) if start_date
      errors << "line #{index + 2}: installation receipt must precede the repository's first Stage 3 observation date" if
        verified_at && start_at && verified_at > start_at
    end
    errors
  end

  def read_csv(path)
    path = Pathname.new(path)
    before = path.lstat
    raise ArgumentError, "CSV must be a regular non-symlink file" if before.symlink? || !before.file?

    data = nil
    opened = nil
    path.open("rb") do |file|
      opened = file.stat
      data = file.read(MAX_INPUT_BYTES + 1)
    end
    after = path.lstat
    identity = ->(stat) { [stat.dev, stat.ino, stat.size, stat.mtime.to_r] }
    unless identity.call(before) == identity.call(opened) && identity.call(opened) == identity.call(after)
      raise ArgumentError, "CSV changed while it was being read"
    end
    raise ArgumentError, "CSV exceeds #{MAX_INPUT_BYTES} bytes" if data.bytesize > MAX_INPUT_BYTES

    data.force_encoding(Encoding::UTF_8)
    raise ArgumentError, "invalid CSV encoding" unless data.valid_encoding?
    table = CSV.parse(data, headers: true)
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
  if ARGV == ["--status"]
    begin
      registration = ResearchEvidence.load_registration
      interruption = ResearchEvidence.load_interruption
      replacement = ResearchEvidence.load_replacement_registration
      authorization = ResearchEvidence.load_intake_authorization
      errors = ResearchEvidence.validate_replacement_registration(
        replacement,
        registration: registration,
        interruption: interruption
      )
      abort errors.join("\n") unless errors.empty?
      if authorization.nil?
        puts "CLOSED — RC7 is registered but not eligible; wait for issue #5 and a protected activation record"
      else
        authorization_errors = ResearchEvidence.validate_intake_authorization(
          replacement,
          registration,
          interruption,
          authorization
        )
        abort authorization_errors.join("\n") unless authorization_errors.empty?
        puts ResearchEvidence.activation_status_message(authorization)
      end
      exit 0
    rescue ArgumentError => e
      abort e.message
    end
  end

  complete_pilot = ARGV.delete("--complete-pilot")
  stage_2 = ARGV.delete("--stage-2")
  reuse_option = ARGV.index("--active-user-reuse")
  reuse_path = reuse_option ? ARGV.delete_at(reuse_option + 1) : nil
  ARGV.delete_at(reuse_option) if reuse_option
  card_reuse_option = ARGV.index("--eight-week-card-reuse")
  card_reuse_path = card_reuse_option ? ARGV.delete_at(card_reuse_option + 1) : nil
  ARGV.delete_at(card_reuse_option) if card_reuse_option
  receipts_option = ARGV.index("--installation-receipts")
  receipts_path = receipts_option ? ARGV.delete_at(receipts_option + 1) : nil
  ARGV.delete_at(receipts_option) if receipts_option
  path = ARGV.shift
  usage = "usage: ruby scripts/research_evidence.rb --status | --stage-2 --installation-receipts RECEIPTS_CSV STAGE2_CSV | --installation-receipts RECEIPTS_CSV [--complete-pilot --active-user-reuse USER_CSV --eight-week-card-reuse CARD_CSV] STAGE3_CSV"
  options_valid = (!reuse_option || reuse_path) && (!card_reuse_option || card_reuse_path) &&
                  (!receipts_option || receipts_path)
  stage_2_extras = stage_2 && (complete_pilot || reuse_option || card_reuse_option)
  abort usage unless path && ARGV.empty? && !stage_2_extras && options_valid
  abort usage unless receipts_path
  abort usage if complete_pilot && (!reuse_path || !card_reuse_path || !receipts_path)

  begin
    registration = ResearchEvidence.load_registration
    interruption = ResearchEvidence.load_interruption
    replacement = ResearchEvidence.load_replacement_registration
    authorization = ResearchEvidence.load_intake_authorization
    errors = ResearchEvidence.validate_replacement_registration(
      replacement,
      registration: registration,
      interruption: interruption
    )
    errors.concat(
      ResearchEvidence.validate_intake_authorization(
        replacement,
        registration,
        interruption,
        authorization
      )
    )
    abort errors.join("\n") unless errors.empty?
    table = ResearchEvidence.read_csv(path)
    exact_version = replacement.dig("pilot", "version")
    eligibility = authorization&.fetch("eligibility", nil)
    eligible_on_value = eligibility&.fetch("stage_3_eligible_on", nil) ||
                        replacement.dig("pilot", "eligible_observations_on_or_after")
    eligible_on = ResearchEvidence.iso_date(eligible_on_value)
    eligible_at = if authorization
                    Time.iso8601(eligibility.fetch("stage_2_eligible_at"))
                  else
                    Time.utc(eligible_on.year, eligible_on.month, eligible_on.day)
                  end
    if stage_2
      errors.concat(ResearchEvidence.validate_rc7_stage2_table(table, eligible_at: eligible_at))
      receipt_table = ResearchEvidence.read_csv(receipts_path)
      errors.concat(
        ResearchEvidence.validate_rc7_installation_receipts(
          receipt_table,
          eligible_at: eligible_at
        )
      )
      errors.concat(ResearchEvidence.validate_rc7_stage2_receipt_coverage(table, receipt_table))
      label = "Stage 2"
    else
      errors.concat(
        ResearchEvidence.validate_rc7_stage3_table(
          table,
          eligible_on: eligible_on,
          complete_pilot: complete_pilot
        )
      )
      reuse_table = nil
      if reuse_path
        reuse_table = ResearchEvidence.read_csv(reuse_path)
        errors.concat(
          ResearchEvidence.validate_rc7_stage3_user_reuse_table(
            reuse_table,
            eligible_on: eligible_on
          )
        )
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
          ResearchEvidence.validate_rc7_stage3_card_reuse_table(
            card_reuse_table,
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
      if receipts_path
        receipt_table = ResearchEvidence.read_csv(receipts_path)
        errors.concat(
          ResearchEvidence.validate_rc7_installation_receipts(
            receipt_table,
            eligible_at: eligible_at
          )
        )
        errors.concat(ResearchEvidence.validate_rc7_receipt_coverage(table, reuse_table, receipt_table))
      end
      label = "Stage 3"
    end

    abort errors.join("\n") unless errors.empty?
    puts "Validated #{table.length} #{label} rows against exact build #{exact_version}"
  rescue ArgumentError => e
    abort e.message
  end
end
