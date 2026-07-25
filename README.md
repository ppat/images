# images

Docker images published to Docker Hub as `ppatlabs/<image>`, each versioned and released
independently of the others. See each image's own README for what it does and how to run it;
see [DESIGN.md](DESIGN.md) for why the repo and its CI/release pipeline are structured this way,
and [CLAUDE.md](CLAUDE.md) for build/lint commands.

| image | build-status |
| --- | --- |
| [bitwarden-cli](./bitwarden-cli/) | [![test-build-bitwarden-cli](https://github.com/ppat/images/actions/workflows/test-build-bitwarden-cli.yaml/badge.svg)](https://github.com/ppat/images/actions/workflows/test-build-bitwarden-cli.yaml) |
| [tools](./tools/) | [![test-tools](https://github.com/ppat/images/actions/workflows/test-build-tools.yaml/badge.svg)](https://github.com/ppat/images/actions/workflows/test-build-tools.yaml) |
| [freeradius-server](./freeradius-server/) | [![test-build-freeradius-server](https://github.com/ppat/images/actions/workflows/test-build-freeradius-server.yaml/badge.svg)](https://github.com/ppat/images/actions/workflows/test-build-freeradius-server.yaml) |

## Releases

Each image gets its own GitHub Release, tagged `<image>/<version>-<timestamp>`, cut automatically
on merge to `main` when that image's files changed — a release only happens if there are actual
changes to release. See [DESIGN.md](DESIGN.md#decisions-and-trade-offs) for the full mechanics.

## Contributing

Commit messages follow Conventional Commits, checked by commitlint against a fixed scope list
(see `commitlint.config.js`). For local build/lint commands and the pattern for adding a new
image, see [CLAUDE.md](CLAUDE.md).

## License

[GNU AGPLv3](LICENSE)
