# Contributing

Keep this package useful without depending on the SurfTap app. Bug fixes, documentation, additional providers, and well-tested improvements to forecast calculations are welcome.

## Development

Use Swift 6.0 or later. Run `swift test`, `swift build -c release`, `python3 -B -m unittest discover -s scripts/tests`, and `python3 scripts/check_public_files.py` from the package root. The tests use synthetic responses and never require API keys. The default example is offline and prints invented numbers, not a forecast: `swift run surftap-example`. Keep any demo or sample output clearly labelled as invented.

For a bug report, include the toolchain version, expected/observed behavior, and a minimal synthetic reproduction. Remove credentials, personal coordinates, routes, and real API response bodies before sharing a report.

## Pull requests

Explain the problem and changed behavior. Add regression tests for bugs and meaningful tests for new algorithms or request behavior. Preserve Swift 6 concurrency checking and cancellation. Keep measurements in SI units, use optional values for missing data, and keep UI wording and platform permissions in the consuming app.

Document any new assumptions or heuristics. Model-derived wave heights and breaking-wave estimates must not be presented as verified or observed surf heights. Changes to a formula need a published source and tests against hand-worked values. New providers belong in separate adapters conforming to `ForecastProvider`.

Avoid adding dependencies unless there is a concrete benefit that justifies their maintenance and licensing cost. Do not include artwork, app screens, signing files, credentials, build outputs, or exports from the original app repository.

Contributions are provided under this repository's MIT license. Submit only material you are entitled to contribute. Security issues should follow [SECURITY.md](SECURITY.md).
