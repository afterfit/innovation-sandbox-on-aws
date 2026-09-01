# Shirokuma — Sync with Upstream & Deploy

How to pull the latest AWS upstream changes into our fork and deploy the
Shirokuma-customized build. All custom work lives on the **`shirokuma`** branch.

## Repos & branches

| Remote     | URL                                                | Purpose                          |
| ---------- | -------------------------------------------------- | -------------------------------- |
| `origin`   | `github.com/afterfit/innovation-sandbox-on-aws`    | Our fork (custom Shirokuma code) |
| `upstream` | `github.com/aws-solutions/innovation-sandbox-on-aws` | AWS official source            |

- `main` — tracks AWS upstream (kept clean, no custom changes).
- `shirokuma` — our deploy branch (custom config + customizations), rebased on top of `main`.

## 1. Sync with upstream

One-time: add the upstream remote (skip if `git remote -v` already lists it):

```bash
git remote add upstream https://github.com/aws-solutions/innovation-sandbox-on-aws.git
```

Pull the latest upstream release into `main`, then rebase `shirokuma` on top:

```bash
# Update main from AWS upstream
git fetch upstream
git checkout main
git merge --ff-only upstream/main
git push origin main

# Replay the Shirokuma customizations on top of the latest upstream
git checkout shirokuma
git rebase main
# resolve any conflicts (watch global-config.yaml / .env-driven files), then:
#   git add <files> && git rebase --continue
git push --force-with-lease origin shirokuma
```

> Rebasing rewrites the `shirokuma` branch history, so the push needs
> `--force-with-lease`. Resolve conflicts in favor of keeping our Shirokuma
> customizations while adopting upstream bug fixes, then re-run the test suite
> (`npm run test`) before deploying.

## 2. Deploy (Shirokuma)

Deploys run from the `shirokuma` branch.

```bash
git checkout shirokuma
npm install

# One-time per machine: create local config (not committed)
npm run env:init   # creates .env from .env.example — fill in Shirokuma account values
```

Authenticate to both AWS accounts via SSO (the deploy scripts use these profiles):

```bash
aws sso login --profile hub
aws sso login --profile management
```

### Preview changes first

```bash
npm run diff:all   # or diff:account-pool / diff:idc / diff:data / diff:compute
```

### Deploy 

Deploy all four stacks with confirmation:

```bash
npm run deploy:all
```

This deploys in order:

1. `InnovationSandbox-AccountPool` (management account / `MANAGER_PROFILE`)
2. `InnovationSandbox-IDC` (management account / `MANAGER_PROFILE`)
3. `InnovationSandbox-Data` (hub account / `HUB_PROFILE`)
4. `InnovationSandbox-Compute` (hub account / `HUB_PROFILE`)

Deploy a single stack

```bash
npm run deploy:account-pool
npm run deploy:idc
npm run deploy:data
npm run deploy:compute
```

## Notes

- Bootstrap CDK once per account: `npm run bootstrap:hub` and `npm run bootstrap:manage`.
- Account-cleaner image (if changed): `npm run docker:build-and-push`.
