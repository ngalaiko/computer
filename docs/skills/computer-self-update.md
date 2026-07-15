---
name: computer-self-update
description: "Workflow for updating the Hermes agent VM through PRs on ngalaiko/computer — the Nix flake that builds this exe.dev VM's OCI image."
version: 1.0.0
author: Hermes Agent
metadata:
  hermes:
    tags: [exe.dev, nix, github, self-update, PR]
    related_skills: [github-pr-workflow]

---

# Self-Update Workflow — ngalaiko/computer

This repo defines the Nix-built OCI image for the `ngalaiko-computer` exe.dev VM.
Changes to it modify the running environment of Hermes Agent on that VM.

## Architecture Overview

```
ngalaiko/computer (GitHub)
  └─ flake.nix + modules/ + packages/  ←  defines the OCI image
  └─ .github/workflows/
       ├─ build.yaml   ← PR+push: flake check → build x86_64 + aarch64 → push to GHCR
       └─ deploy.yaml  ← on build success: ssh exe.dev new → fresh VM
```

**Deploy flow:** CI builds the image → pushes to `ghcr.io/ngalaiko/computer.exe:<sha>` →
deploy workflow runs `ssh exe.dev rm ngalaiko-computer && ssh exe.dev new --image=...` →
VM is **fully replaced**, restic restores `/var/lib/hermes` from B2 on boot.

## 1. GitHub Auth (exe.dev Integration)

This VM uses the **exe.dev GitHub integration** — no tokens on the VM.

On the VM, the integration is already set up. Use it with `gh` CLI:

```bash
export GH_HOST=computer.int.exe.xyz
GH_HOST=computer.int.exe.xyz gh auth status
GH_HOST=computer.int.exe.xyz gh pr list -R ngalaiko/computer
```

**Git remote** (already configured):
```
origin  https://computer.int.exe.xyz/ngalaiko/computer.git (fetch)
origin  https://computer.int.exe.xyz/ngalaiko/computer.git (push)
```

Push commits directly via this remote — git auth works through the integration.

## 2. Standard Self-Update Flow

```bash
# 1. Start from clean master
cd /var/lib/hermes/computer   # cloned path on the VM
git fetch origin
git checkout master && git pull origin master

# 2. Create a branch
git checkout -b feat/description-of-change

# 3. Make changes (use Hermes file tools: write_file, patch, read_file)
#    Typical files to modify:
#    - flake.nix — add packages, update models, change config
#    - modules/exedev/services/hermes.nix — Hermes agent config
#    - modules/exedev/nix.nix — Nix daemon settings
#    - modules/exedev/backup.nix — backup config
#    - .github/workflows/*.yaml — CI/CD changes
#    - packages/ — custom Nix packages

# 4. Test locally (Nix is available on the VM)
nix flake check --all-systems

# 5. Commit
git add <files>
git commit -m "feat: description of change"

# 6. Push
git push -u origin HEAD

# 7. Create PR
GH_HOST=computer.int.exe.xyz gh pr create \
  --title "feat: short description" \
  --body "## Summary
What this PR does and why.

## Changes
- change 1
- change 2

## Testing
- [ ] nix flake check passes
- [ ] builds for both arches" \
  -R ngalaiko/computer

# 8. Monitor CI
GH_HOST=computer.int.exe.xyz gh pr checks --watch -R ngalaiko/computer
```

## 3. CI/CD Pipeline Details

### build.yaml (runs on PR + push to master)

| Step | What it does |
|------|-------------|
| **check** | `nix flake check --all-systems` + `nix fmt . && git diff --exit-code` |
| **build** | For each arch (x86_64, aarch64): `nix build .#packages.<sys>.exedev` |
| **push** | (master only) Push the OCI tarball to GHCR via skopeo |
| **manifest** | (master only) Stitch multi-arch manifest, tag with git SHA + jj change id |

### deploy.yaml (runs on build success on master)

1. Resolve image tag (git short SHA)
2. `ssh exe.dev rm ngalaiko-computer` — deletes old VM
3. `ssh exe.dev new --image=ghcr.io/ngalaiko/computer.exe:<tag>` — creates new VM
   - Passes B2 env vars (`RESTIC_REPOSITORY`, `RESTIC_PASSWORD`, `B2_ACCOUNT_ID`, `B2_ACCOUNT_KEY`)
   - restic restores `/var/lib/hermes` on boot
4. Re-attaches the `computer` GitHub integration

### Key Config Values

| Parameter | Value |
|-----------|-------|
| VM name | `ngalaiko-computer` |
| GHCR image | `ghcr.io/ngalaiko/computer.exe` |
| GitHub integration name | `computer` |
| Integration domain | `computer.int.exe.xyz` |
| B2 bucket | `b2:ngalaiko-backups:exedev` |
| Hermes user home | `/var/lib/hermes` |
| exe.dev LLM gateway | `llm.int.exe.xyz` |

## 4. Important Considerations

### ⚠️ Redeploy = New VM

When the PR merges to master and deploy.yaml runs, **the VM is destroyed and replaced**:

- SSH host keys change
- Any local state NOT in `/var/lib/hermes` is lost
- The hermes backup (restic → B2) restores `/var/lib/hermes` on boot
- GitHub integration is re-attached automatically via deploy.yaml

### Common Change Patterns

**Add a system package to the image:**
Edit `flake.nix` → add the nixpkgs attribute to `image.packages`.

**Change Hermes model/provider settings:**
Edit `flake.nix` → `services.hermes.settings.providers` (the `exe-anthropic`,
`exe-openai`, `exe-fireworks` blocks). Update `model_aliases` and default model.

**Add a new s6 service:**
Create `modules/exedev/services/<name>.nix` following `sshd.nix` or `hermes.nix`.

**Change CI/CD:**
Edit `.github/workflows/build.yaml` or `.github/workflows/deploy.yaml`.

## 5. Quick Reference

```bash
# === GitHub (via exe.dev integration) ===
GH_HOST=computer.int.exe.xyz gh pr list -R ngalaiko/computer
GH_HOST=computer.int.exe.xyz gh pr view <N> -R ngalaiko/computer
GH_HOST=computer.int.exe.xyz gh pr checks -R ngalaiko/computer
GH_HOST=computer.int.exe.xyz gh run list -R ngalaiko/computer

# === Git ===
cd /var/lib/hermes/computer
git status
git diff
git log --oneline -5

# === Exe.dev ===
ssh exe.dev ls                        # list VMs
ssh exe.dev stat ngalaiko-computer    # VM metrics
ssh exe.dev whoami                    # account info
```
