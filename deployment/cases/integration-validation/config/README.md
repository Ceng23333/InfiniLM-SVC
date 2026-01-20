# integration-validation case configs

Files under this directory are staged by `scripts/install.sh` when using:

```bash
./scripts/install.sh --deployment-case integration-validation
```

They will be copied into:

- `/app/config/cases/integration-validation/` (inside images / staged app root)

Put babysitter TOML configs and any other runtime presets here.
