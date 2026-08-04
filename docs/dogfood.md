# Release-candidate dogfood program

Fixcard reaches stable 1.0 only after every stage in
[Validation](validation.md) passes. This program covers the four-week Stage 3
pilot and collects evidence without telemetry or raw development logs. The
Stage 1 and 2 protocols are separate because problem diaries must not begin by
pitching Fixcard.

## Who should participate

Developers maintaining an active repository where failures recur and where at
least one resolution is worth preserving. The study needs 5–8 repositories
covering more than one ecosystem and both personal and team use where possible.

## Start

1. Install the newest release candidate from the
   [releases page](https://github.com/MarinJursic/fixcard/releases).
2. Run `fixcard status` and confirm the expected storage paths.
3. Choose repository, clone-private, or user-global scope deliberately.
4. Use the installed `fix PROGRAM [ARGS...]` companion, or its explicit
   `fixcard run -- PROGRAM [ARGS...]` equivalent.
5. Do not create synthetic successes. Record normal development incidents.

Before the first incident, record a stable random repository alias, the exact
output of `fixcard --version`, the number of pilot users with repository access,
and the report week. Never use the real repository name as its alias.

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
- end-to-end lookup duration and whether Fixcard was used before other tools;
- median observed authoring time and sample size;
- weekly active-user capture behavior and its denominator;
- author and teammate reuse rates and counts;
- shared-card acceptance through normal pull-request review;
- scanner catches, false positives, missed secrets, and safety incidents;
- differentiation responses and maintenance burden;
- repository/ecosystem coverage;
- an explicit go, change, or stop decision.

Missing data is reported as missing. Stars, downloads, total card count, and
synthetic examples do not substitute for relevance or reuse.
