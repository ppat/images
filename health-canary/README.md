# health-canary

`ppatlabs/health-canary` is the runtime for the cluster's scheduled health canaries and backup restore checks. The
scripts live with the Kubernetes manifests that run them. This image only supplies the tools those scripts call.

| Tool | Source | Used for |
| --- | --- | --- |
| `s5cmd` | [peak/s5cmd](https://github.com/peak/s5cmd) release binary | S3 PUT, GET, LIST and DELETE against object storage endpoints |
| `kubectl` | `dl.k8s.io` release binary | creating and inspecting the objects a restore check needs |
| `sqlite3` | Alpine `sqlite` | integrity checks on restored SQLite databases |
| `jq` | Alpine `jq` | reading JSON from `kubectl` and S3 listings |
| `curl` | Alpine `curl` | HTTP checks |
| `bash` | Alpine `bash` | the scripts' interpreter |

The `kubectl` and `s5cmd` downloads are checked against the checksums each project publishes with its release, and
Renovate tracks both versions through the `ARG` pins in the [Dockerfile](./Dockerfile).

The image runs as uid/gid `65532` with `HOME=/tmp`, so it works with `runAsNonRoot` and a read-only root filesystem as
long as `/tmp` is a writable volume.

```shell
docker run --rm ppatlabs/health-canary:<version> -c 's5cmd version && kubectl version --client'
```
