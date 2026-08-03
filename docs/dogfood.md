# Release-candidate dogfood program

Fixcard reaches stable 1.0 only after real use supports the thresholds in
[Validation](validation.md). This program collects that evidence without
telemetry or raw development logs.

## Who should participate

Developers maintaining an active repository where failures recur and where at
least one resolution is worth preserving. The study needs 5–8 repositories
covering more than one ecosystem and both personal and team use where possible.

## Start

1. Install the newest release candidate from the
   [releases page](https://github.com/MarinJursic/fixcard/releases).
2. Run `fixcard status` and confirm the expected storage paths.
3. Choose repository, clone-private, or user-global scope deliberately.
4. Use `fixcard run -- PROGRAM [ARGS...]`, or opt into
   `fix PROGRAM [ARGS...]` after inspecting `fixcard shell-init <shell>`.
5. Do not create synthetic successes. Record normal development incidents.

## Private local worksheet

Keep this table locally. Do not commit raw failures or submit them publicly.

| Date | Lookup? | Strong result? | Relevant? | Abstention correct? | Card authored? | Authoring seconds | Reused by author? | Reused by teammate? | Safety incident? |
| --- | --- | --- | --- | --- | --- | ---: | --- | --- | --- |
| | | | | | | | | | |

“Relevant” means the first strong result was the correct recorded response for
the actual incident. A plausible but wrong result is irrelevant. No strong
result is often the safe and correct outcome.

Authoring time starts only after the developer already knows the resolution. It
ends when the card is saved. Do not estimate a duration later if it was not
observed.

## Weekly report

Submit one aggregated
[validation report](https://github.com/MarinJursic/fixcard/issues/new?template=validation-report.yml)
per repository each week. Repository names may remain undisclosed. Reports must
not contain:

- raw command output or stack traces;
- credentials, tokens, cookies, or connection strings;
- internal hostnames, customer identifiers, or private paths;
- proprietary source, commands, or repository names.

Report a suspected security problem through
[private vulnerability reporting](../SECURITY.md), not a public validation
issue.

## Decision

After four weeks, maintainers aggregate only the submitted counts and publish:

- strong rank-one relevance and its denominator;
- median observed authoring time and sample size;
- author and teammate reuse counts;
- safety incidents and maintenance burden;
- repository/ecosystem coverage;
- an explicit go, change, or stop decision.

Missing data is reported as missing. Stars, downloads, total card count, and
synthetic examples do not substitute for relevance or reuse.
