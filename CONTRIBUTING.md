# Contributing

- Run `scripts/test.sh` before opening a pull request. It must pass; new logic needs a test.
- Keep `NodCore` free of AppKit and I/O so it stays testable without AirPods. Hardware access belongs in `Sources/Nod`.
- Code, comments, identifiers and commit messages are in English. Commits follow `type(scope): subject` (for example `fix(classifier): ...`).
- No private Bluetooth APIs, no telemetry, no network access.
- Motion recordings: `open -n -W --stdout out.txt dist/Nod.app --args --record <label> <seconds>` writes a JSONL take to `~/Library/Application Support/Nod/recordings/`. Attach takes only if you are fine with them being public; they contain head angles and rates, nothing else.
- Classifier changes should be checked against the committed fixtures in `Tests/NodCoreTests/Fixtures`, and ideally against a new real recording.
