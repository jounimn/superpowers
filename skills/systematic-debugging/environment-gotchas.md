# Environment Gotchas

**Load this reference when:** a failure looks like a permissions, sandbox or code problem but the code doesn't explain it — environment traps that imitate bugs.

## `EACCES` when a server binds a port on Windows

- **Symptom:** `listen EACCES: permission denied` on a port no process is using (`netstat` shows no listener); disabling the sandbox or changing permissions doesn't help.
- **Cause:** Windows reserves port ranges (commonly for Hyper-V or WSL) that no process can bind, whatever its permissions, and `netstat` doesn't list them. The ranges can change after a reboot, so a port that worked before can be reserved now.
- **Fix:** before touching permissions, the firewall or the sandbox, run `netsh interface ipv4 show excludedportrange protocol=tcp` and move that one service to a port outside every listed range — not a machine-wide network change.
