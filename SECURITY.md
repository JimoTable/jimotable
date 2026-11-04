# Security Policy

## Supported versions

| Version | Platform | Supported |
| --- | --- | --- |
| 0.2.1 | linux/amd64 | Yes |
| 0.2.0 and earlier | any | No |

Only the current Free release on `linux/amd64` receives security fixes. ARM64 is not qualified for this release and is not covered.

## Reporting a vulnerability

Do **not** open a public issue for a security problem.

- Preferred: use **Security → Advisories → Report a vulnerability** on this repository. The report stays private until a fix is available.
- If private reporting is unavailable, write to `contact@jimotable.com` and say that you are reporting a security issue.

Please include the affected version and build information (`build-info.json` or the About dialog), the platform, the configuration that matters (for example reverse proxy in front of the API), and reproduction steps. Do not include live credentials, database dumps or customer data.

## What to expect

- Acknowledgement within 5 business days.
- An assessment with a severity and a fix plan, or a reasoned decision that the report is out of scope.
- Credit in the release notes if you want it.

## In scope

- The Free self-host distribution in this repository: install scripts, Docker Compose templates, the published image `ghcr.io/jimotable/jimotable`, and the bundled agent skills.
- Authentication, credential handling and tenant isolation in the Free edition.
- Anything that lets a low-privilege actor read or modify data outside its Base, table or field scope.

## Out of scope

- The Cloud and enterprise editions, which are not distributed from this repository.
- Deployments that removed the documented safeguards, for example publishing the API without an HTTPS reverse proxy or sharing the operator credential.
- Findings that require write access to the host, the Docker socket or the `.env` file.
- Missing hardening headers on a deployment whose reverse proxy was configured outside the templates here.
- Denial of service through resource exhaustion on a host that does not meet the documented minimum of 2 vCPU, 4 GiB RAM and 20 GiB disk.

## Licence note

This distribution is not open source. `LICENSE` is a custom Community Free License: self-hosting and internal evaluation are permitted, reverse-engineering or modifying the proprietary core binaries is not. A vulnerability report is still welcome regardless of how the licence is worded.
