# Security

## Credentials

Supply your own Stormglass key at runtime. Never commit it, place it in a request URL, attach it to a public issue, or put it in a shared screenshot. `.gitignore` helps prevent accidental additions; it does not remove secrets already committed or make keys in a compiled app private.

The default adapter uses HTTPS to a fixed Stormglass origin, puts the key only in the Authorization header, rejects redirects, and uses an ephemeral URLSession with cookies, credential storage, and disk response caching disabled. Its errors exclude response bodies and underlying error descriptions. Debug descriptions and mirrors redact credentials. Keys still exist in process memory while requests are made.

Custom `HTTPTransport` implementations receive the authenticated request. They are responsible for protecting headers and rejecting unsafe redirects. Avoid request/response logging in production. Third-party proxies and diagnostic tools are outside this package's control.

For an app using your centrally billed account, keep the service key on a backend that authenticates users and enforces limits. Developer-local experiments and apps where users provide their own keys can use the adapter directly with appropriate credential storage.

## Privacy

The package collects nothing on its own: no analytics, telemetry, device identifiers, or files written to disk. `ForecastCache` exists in memory only.

Each forecast request sends the coordinate you supply, to six decimal places (roughly 0.1 m), and the time window to Stormglass in the HTTPS query string. A person's location is personal data. If your app uses a user's position, tell them it is sent to Stormglass, consider rounding it before building the query when your use allows, and keep coordinates out of logs, analytics, and bug reports. Stormglass handles what it receives under its own terms and privacy policy.

A saved list of `SurfSpot` values can reveal where someone lives or spends time. Storing, syncing and sharing spots is your app's responsibility; the package never persists or transmits a spot's name or bearing.

## Reporting

Use the repository's GitHub **Security → Report a vulnerability** feature when it is enabled. Do not put secret values in public issues. If private reporting is unavailable, open an issue asking the maintainer to enable a private channel, without including vulnerability details or credentials.

If a key has been exposed, revoke/rotate it in Stormglass. Removing a file alone does not remove prior copies, repository history, forks, or downloaded archives.

## Checks and limits

`scripts/check_public_files.py` checks the working tree and tracked paths for common passwords, API keys, access tokens, private keys, authenticated URLs, email addresses, local account paths and excluded app/configuration files. Findings report categories and relative filenames, never matched values. The placeholder example and explicitly synthetic test credential are allowed. Regression tests cover the scanner itself: `python3 -B -m unittest discover -s scripts/tests`.

These checks are an additional guard, not a comprehensive secret detector or Git-history audit. Review the actual release file list and enable GitHub secret scanning and push protection where available when creating the public repository. Do not distribute build products or local logs; they can contain machine paths and account names even when the source is clean.
