# Contributing

## Scope

This project focuses on Ubuntu offline installation of:

- `zsh`
- `oh-my-zsh`
- `zsh-autosuggestions`
- `zsh-completions`
- `zsh-syntax-highlighting`
- `powerlevel10k`

Please keep changes aligned with this scope.

## Before You Submit

1. Keep scripts POSIX/Bash friendly and avoid introducing non-portable dependencies.
2. Preserve offline-first behavior.
3. Do not commit generated artifacts (`*.tar.gz`, `*.deb`, `bundle/`, `.apt-work/`).
4. Run syntax checks:

```bash
bash -n collect_target_params.sh prepare_online_bundle.sh fill_debs_on_ubuntu.sh offline/install_offline.sh
```

## Pull Request Notes

Please include:

1. What changed.
2. Why the change is needed.
3. How you validated the change.
4. Any compatibility impact (Ubuntu version, architecture, mirror assumptions).

## Safety Rules

- Do not broaden dependency resolution to core system chains casually.
- Keep `libc6` exclusion unless there is a clearly justified migration plan.
- Any change touching installation behavior must document rollback and failure handling.
