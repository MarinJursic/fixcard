#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "net/http"
require "open3"
require "pathname"
require "uri"

require_relative "research_evidence"

ROOT = Pathname.new(__dir__).join("..").cleanpath
MANIFEST_PATH = ROOT.join("research", "pilots", "rc7", "build-manifest.json")
CYCLONEDX_PREDICATE = "https://cyclonedx.org/bom"

def capture!(*argv)
  stdout, stderr, status = Open3.capture3(*argv)
  raise "#{argv.join(' ')} failed: #{stderr.strip}" unless status.success?

  stdout
end

def assert_equal!(label, actual, expected)
  return if actual == expected

  raise "#{label} differs: expected #{expected.inspect}, got #{actual.inspect}"
end

historical_registration = ResearchEvidence.load_registration
interruption = ResearchEvidence.load_interruption
replacement = ResearchEvidence.load_replacement_registration
registration_errors = ResearchEvidence.validate_replacement_registration(
  replacement,
  registration: historical_registration,
  interruption: interruption
)
raise registration_errors.join("\n") unless registration_errors.empty?

manifest = ResearchEvidence.load_strict_json_object(MANIFEST_PATH, "RC7 build manifest")
manifest_sha256 = Digest::SHA256.hexdigest(JSON.generate(manifest))
assert_equal!(
  "build manifest canonical SHA-256",
  manifest_sha256,
  replacement.dig("build_manifest", "canonical_json_sha256")
)
assert_equal!("pilot ID", manifest["pilot_id"], ResearchEvidence::EXPECTED_RC7_PILOT_ID)
repository = manifest.fetch("repository")
tag = manifest.fetch("tag")
commit = manifest.fetch("commit")

resolved = capture!("git", "-C", ROOT.to_s, "rev-parse", "refs/tags/#{tag}^{commit}").strip
assert_equal!("tag commit", resolved, commit)

release = JSON.parse(capture!("gh", "api", "repos/#{repository}/releases/tags/#{tag}"))
expected_release = manifest.fetch("release")
assert_equal!("release id", release["id"], expected_release.fetch("id"))
assert_equal!("release tag", release["tag_name"], tag)
assert_equal!("release immutability", release["immutable"], expected_release.fetch("immutable"))
assert_equal!("release created_at", release["created_at"], expected_release.fetch("created_at"))
assert_equal!("release published_at", release["published_at"], expected_release.fetch("published_at"))

normalize_asset = lambda do |asset|
  {
    "id" => asset.fetch("id"),
    "name" => asset.fetch("name"),
    "size" => asset.fetch("size"),
    "sha256" => asset.fetch("digest").delete_prefix("sha256:")
  }
end
actual_assets = release.fetch("assets").map(&normalize_asset).sort_by { |asset| asset.fetch("name") }
expected_assets = expected_release.fetch("assets").sort_by { |asset| asset.fetch("name") }
assert_equal!("release assets", actual_assets, expected_assets)

workflow = manifest.fetch("release_workflow")
run = JSON.parse(capture!("gh", "api", "repos/#{repository}/actions/runs/#{workflow.fetch('id')}"))
{
  "run_attempt" => "attempt",
  "workflow_id" => "workflow_id",
  "path" => "path",
  "event" => "event",
  "head_sha" => "head_sha",
  "conclusion" => "conclusion"
}.each do |api_field, manifest_field|
  assert_equal!("release workflow #{api_field}", run[api_field], workflow.fetch(manifest_field))
end

formula = manifest.fetch("homebrew")
response = Net::HTTP.get_response(URI(formula.fetch("formula_url")))
raise "formula download failed with HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

assert_equal!("formula SHA-256", Digest::SHA256.hexdigest(response.body), formula.fetch("formula_sha256"))

assets_dir_index = ARGV.index("--assets-dir")
if assets_dir_index
  assets_dir_value = ARGV[assets_dir_index + 1]
  abort "usage: ruby scripts/verify_rc7_supply_chain.rb [--assets-dir DIR]" unless
    assets_dir_value && ARGV.length == 2
  assets_dir = Pathname.new(assets_dir_value)
  signer = manifest.dig("attestations", "signer_workflow")
  expected_assets.each do |asset|
    path = assets_dir.join(asset.fetch("name"))
    raise "missing downloaded release asset #{path}" unless path.file?

    assert_equal!("#{asset.fetch('name')} SHA-256", Digest::SHA256.file(path).hexdigest, asset.fetch("sha256"))
    next unless asset.fetch("name").match?(/\.(?:tar\.gz|zip)\z/)

    common = [
      "gh", "attestation", "verify", path.to_s,
      "--repo", repository,
      "--signer-workflow", signer,
      "--source-digest", commit,
      "--source-ref", "refs/tags/#{tag}",
      "--deny-self-hosted-runners"
    ]
    capture!(*common)
    capture!(*common, "--predicate-type", CYCLONEDX_PREDICATE)
  end
elsif !ARGV.empty?
  abort "usage: ruby scripts/verify_rc7_supply_chain.rb [--assets-dir DIR]"
end

puts "Verified exact RC7 tag, release assets, workflow, formula#{assets_dir_index ? ', checksums, and attestations' : ''}"
