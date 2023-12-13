# Workspace Sidecar

This container is deployed by [Hatchery](https://github.com/uc-cdis/hatchery) as a sidecar to a main Gen3 workspace container.

The `sidecar.sh` script mounts files to the user's workspace:
- It queries the [Manifest Service](https://github.com/uc-cdis/manifestservice) and present the manifests in a consumable manner.
- It queries Hatchery's `/mount-files` endpoint and mounts the returned files.

## Local testing

Create a .env file with the following format:

```
GEN3_API_KEY=YOUR_API_KEY_HERE
GEN3_ENDPONT=somecommons.url.here.com
```

Then run:
```
docker compose up
```
