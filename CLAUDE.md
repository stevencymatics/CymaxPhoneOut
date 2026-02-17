# Cymatics Mix Link - Project Instructions

## Deploying to /Applications

When copying the built app to `/Applications/`:
1. **Kill the running app first** — `pkill -f "Cymatics Mix Link" 2>/dev/null; sleep 2`
2. **Delete the old bundle** — `rm -rf "/Applications/Cymatics Mix Link.app"`
3. **Then copy** — `cp -R "...source.app" "/Applications/Cymatics Mix Link.app"`
4. **Verify** — compare `ls -la` binary size/timestamp between build output and `/Applications/`

Plain `cp -R` over a running or locked `.app` bundle silently fails to overwrite files. Always `rm -rf` first.
