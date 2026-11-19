# Releasing

A checklist for maintainers. The package is pre-1.0: the public API may change between minor versions, and each change is listed in the release notes.

## Before every release

1. Run the local checks from the package root:

   ```sh
   python3 scripts/check_public_files.py
   python3 -B -m unittest discover -s scripts/tests
   swift test
   swift build -c release
   swift run surftap-example
   ```

2. Confirm both CI jobs, macOS and Linux, pass on the commit being released.
3. Build the two library products for the Apple platforms you intend to support. The package has no device, simulator or UI tests.
4. Run the opt-in live check with your own Stormglass key and a known coastal spot:

   ```sh
   swift run surftap-example --live LATITUDE LONGITUDE OCEANWARD_BEARING
   ```

   Compare the weather, both tide endpoints, the datum and the station details with the service. This uses three requests of quota. Keep the key and raw responses out of issues, logs and release notes.
5. Review the complete file list of the release commit. It should contain source, tests, scripts and documentation only: no build output, editor or agent folders, archives, signing files, or anything from an application that uses this package.
6. Write release notes covering public API changes, behavior changes and fixed bugs. Call out breaking changes explicitly.
7. Tag the release using semantic versioning.

## First publication

- Publish from a new repository with fresh history.
- Enable private vulnerability reporting, secret scanning and push protection in the repository settings.
- Replace the local-path installation note in the README with the repository URL.
- Tag `0.1.0` only after the checks above pass.

## Standing rules

- Add a regression test with every bug fix, and a hand-worked test with every formula change.
- Keep credentials out of CI. No job needs a Stormglass key.
- Review compatibility when raising the minimum Swift toolchain or deployment targets.
- Stormglass pricing and data terms are separate from the code license. Link to the current official terms rather than restating plan allowances.
