# TODO

Findings from the review of `ussuri.zsh` v1.1.6 (2026-10-26). Line numbers refer to that version.
Tick items off (`- [x]`) and add the version and date when done, e.g. `(1.1.7, 2026-11-01)`.

Suggested first batch: B1, B2, B3, B5 and P1.

## Bugs

Follow-up from B1/B2 (done, 1.1.9, 2026-10-26): `set_env` now only exports `GOPATH`, so a login shell no longer leaks its inline `DO_*` values into manual runs or nested shells. Anything else a child process needs must be added to the `case` in `set_env`.

- [x] **B1. `--dryrun` is not dry** (1.1.7, 2026-10-26) (`:1316` vs `:1440`). `set_defaults` runs before argument parsing and line 372 resets `DO_DRYRUN`. Confirmed in a sandboxed `$HOME`: `--dryrun` made 108 `defaults write` calls, created dirs, copied `files/`, left the lock file. `--help`/`--version` do the same. `--confirm` is bypassed too. Fix: parse args first, then `set_defaults`, or move `set_osx_*_defaults` into `check_defaults`.
- [x] **B2. `set_env` always overwrites** (1.1.8, 2026-10-26; now unset-only with `force`, uses `typeset -gx`) (`:668-675`). Unconditional `eval export`, so the documented override does not work, and `set_inline_defaults` resets flags set earlier. Fix: return if already set, add an always-override list, use `typeset -gx` instead of `eval`.
- [x] **B3. Prompt and brew env never applied** (1.2.0, 2026-10-26) (`:853`, `:1098`, `:1131`, `:1137`). `oh-my-posh init zsh` and `brew shellenv` output is discarded. Fix: `eval "$(...)"`.
- [x] **B4. Lock leaks on early exit** (1.2.1, 2026-10-26) (`:1470`, `:1501`, `:1508`, `:1529`, `:1545`). `exit` while holding the lock blocks installs for 10 minutes. Check-then-touch (`:139-151`) is racy. Fix: acquire with `mkdir` after arg parsing, release in a `trap ... EXIT`.
- [x] **B5. `files/defaults/macos.defaults` does not exist** (1.2.2, 2026-10-26) (`:332-334`, `:926`). `! -f DEFAULTS_FILE` is always true, so the `tar` copy runs on every shell start. `tr < REQUIRED_FILE` errors when the file is missing.
- [x] **B6. pyenv/rbenv logic errors.** (1.2.3, 2026-10-26)
  - `:804` prints `RUBY_VER` in the pyenv section.
  - `:803`, `:811` say "local" but run `pyenv global`.
  - `:770` `rbenv local` writes `.ruby-version` into the current directory on every login.
  - `install --list` runs on every shell start (slow) and `grep | tail -1` is not a reliable "latest"; use `sort -V`.
  - `global` is set to a version that may not be installed when `DO_BUILD` is false.
- [x] **B7. Homebrew installer downloaded during dry-run** (1.2.4, 2026-10-26) (`:1117`). `$(curl ...)` expands before `execute_command` is called.
- [x] **B8. Package install problems.** (1.2.5, 2026-10-26)
  - `grep "^${PACKAGE}$"` treats names as regex; use `grep -Fxq`.
  - Missing `INSTALLED_FILE` makes grep error.
  - `pacman -Sy pkg` is a partial upgrade; use `-S --needed`.
  - `apt install` without `apt-get update`.
  - `-mtime -2` trigger misses list changes; use a checksum stamp file.
- [x] **B9. Unsafe sudoers handling** (1.2.6, 2026-10-26) (`:710-717`). No `visudo -cf` validation, `tee -a` appends duplicates, file mode not `0440`, `sudo -l` can block on a password prompt, default is `NOPASSWD:ALL`.
- [x] **B10. Silent hangs.** (1.2.7, 2026-10-26) Non-verbose `execute_command` sends output to `/dev/null`, so sudo/git prompts and long builds look like a frozen shell.
- [x] **B11. Smaller bugs.** (1.2.8, and the last two resolved 2026-10-27)
  - [x] `:44` banner printed on every shell; gate on `DO_VERBOSE` (breaks p10k instant prompt).
  - [x] `curl -vs ... 2>&1 | grep` (`:1161`, `:1187`); use `curl -fsS`.
  - [x] Empty `REMOTE_VERSION` breaks the `[ -lt ]` comparison.
  - [x] `update_script` only compares versions, never updates.
  - [x] `check_for_update` and `update_script` are near-duplicates.
  - [x] Finder defaults listed twice (`:165-168` repeat `:159-162`).
  - [x] `"$*" =~ "force"` / `"install"` match substrings of any argument.
  - [x] `exp_env` substring regex gives false positives.
  - [x] `LD_LIBRARY_PATH=/usr/lib:/usr/local/lib:/` (`:1095`) has a stray `/` and is meaningless on macOS.
  - [x] (decided to leave as is, 2026-10-27) Global `LDFLAGS`/`CPPFLAGS`/`PKG_CONFIG_PATH` can affect unrelated builds. Measured on this machine: native builds pick up openssl@4 (4.0.3, linked in /opt/homebrew) rather than the installed-but-unlinked openssl@3 (3.5.9), and builds are not hermetic. Without the flags a plain `#include <openssl/...>` is not found at all. To opt out: set `DO_LDFLAGS_CHECK=false`, `DO_CPPFLAGS_CHECK=false` and `DO_PKGCONFIG_CHECK=false` in `~/.ussuri/config`; `PKG_CONFIG_PATH` is redundant with Homebrew's own pkg-config.
  - [x] (1.4.8, 2026-10-27) Transmission blocklist URL is plain HTTP on a third-party host. The old host was in fact dead. Now iblocklist.com Level 1 over HTTPS, overridable with `TRANSMISSION_BLOCKLIST_URL`, checked for reachability before it is written.
  - [x] CLAUDE.md describes the guard as `CALLER != "X11.bin"`; the script uses `X11|Antigravity`. Update the doc.

- [x] **B12. `files/` copy could unpack into the current directory** (1.2.9, 2026-10-26). Found while testing: `( cd src ; tar -cpf - . )|( cd dst ; tar -xpf - )` kept going after a failed `cd dst`. Now uses `&&`.

## Performance / best practices

- [x] **P1. Startup cost.** (1.3.0 defaults stamp, 1.3.1 init cache, 1.3.2 fork-free shell work, 2026-10-26) Measured in a sandbox: 133 external processes and about 1390 ms per login down to 1 process (oh-my-posh) and about 70 ms, with init commands stubbed. Follow-ups: oh-my-posh init is not cached (its output embeds a per-run POSH_SESSION_ID, ~250 ms); applying defaults still forks `defaults read` per key (batch with one read per domain); zinit plugins load eagerly (see C7).
- [x] **P2. Quoting / injection.** (1.3.5, 2026-10-26) Unquoted paths in command strings and `eval` with embedded values. Done with `${(q)var}` at every interpolation (tested with a hostile home directory name). `zinit.zsh` lines run by `execute_from_file` are still evaluated as written, by design.
- [x] **P3. Zsh idioms.** (1.3.4, 2026-10-26) `typeset -U path`, `path+=`, `$commands` lookups. Not done: converting the ~600 `[ ]` tests to `[[ ]]` (works as is, no bug).
- [x] **P4. Argument parsing.** (1.3.6, 2026-10-26) `zparseopts -F` replaces the loop (also fixes `-g` with no value looping forever, and allows bundling like `-vt`). The small whole-argument pre-scan for `-F`/`-I`/`-v` stays because the lock and verbose output are needed before parsing.
- [x] **P5. Supply chain.** (1.3.7, 2026-10-26) Installers are downloaded then run, with an optional `*_INSTALL_SHA256` check; clones take an optional `*_REF` pin. Both are opt-in (pinning by default would stop rbenv/pyenv learning new versions, and there is no checksum that does not go stale). Not done: `brew bundle` (a Brewfile needs the formula/cask/tap distinction the plain lists lack, and one failing package would no longer be isolated), and `--update` still trusts the `main` branch (could take a `SCRIPT_SHA256`).
- [x] **P6. `--confirm`.** (1.3.3, 2026-10-26) `vared` itself worked on a terminal and did not hang without one; the real bug was that the prompt did not show the command unless `--verbose`. Now `read` with the command in the prompt, and a visible warning when there is no terminal.
- [x] **P7. Maintenance.** (1.3.8, 2026-10-26) `have_lock`/`is_osx`/`is_linux`, `copy_support_files` and early returns in the package and defaults checks; `tests/smoke.zsh` (zsh, no extra dependencies) covers the fixes above.

## New capabilities

- [x] **C1.** (1.4.3, 2026-10-27) `--backups`, `--rollback [N]`, `--uninstall`; the replaced .zshrc is saved first so it is reversible. Original item: `--uninstall` / `--rollback` to restore the timestamped `.zshrc.*` backups.
- [x] **C2.** Real self-update: download to temp, verify version, `zsh -n`, atomic replace. (1.2.8, 2026-10-26)
- [x] **C3.** (1.4.4, 2026-10-27) `--drift`: actual -> expected per setting, read only, exit status 1 on drift. OS X only for now (Linux in C4). Original item: Drift report: compare actual `defaults read` against the lists and show a diff.
- [x] **C4.** (1.4.5, 2026-10-27) 14 GNOME settings via `gsettings`, skipped when absent, opt-in on login (`DO_GNOME_DEFAULTS`), covered by `--drift`. Tested against a stateful gsettings stub only, not a real GNOME session: the key names are ones I know exist but are unverified here. Original item: Linux defaults (`gsettings`/`dconf`); `check_linux_defaults` is a stub.
- [x] **C5.** (1.4.6, 2026-10-27) dnf, apk and nix (plus Debian/Arch/Red Hat derivatives via ID_LIKE) behind one `set_pkg_manager`. Tested against stubbed package managers only; the new package lists are an unverified conservative subset, and the nix list parser handles two documented formats. Original item: More package managers (dnf, Alpine, Nix); use `/etc/os-release` instead of `lsb_release`.
- [x] **C6.** (1.4.7, 2026-10-27) fnm, rustup, uv and mise via `--tool NAME` or `INSTALL_<NAME>=true`. fnm rather than nvm (nvm init costs hundreds of ms), mise rather than asdf (mise reads .tool-versions). Tested against stub installers only: the installer flags (`--install-dir --skip-shell`, `-y --no-modify-path`, `UV_NO_MODIFY_PATH`/`UV_INSTALL_DIR`, `MISE_INSTALL_PATH`) are from their documentation and unverified here. Original item: More language managers: nvm/fnm, rustup, uv, or mise/asdf as a replacement for pyenv/rbenv.
- [x] **C7.** (1.3.9, 2026-10-26) Measured instead of assumed: turbo mode takes time to first prompt from about 141ms to 64ms and the cached pyenv init no longer forks bash. Lazy-loading wrappers for rbenv/pyenv were not built: with the cache, rbenv init costs about 0.1ms. Original item: Lazy-load `pyenv`/`rbenv` init and use zinit `wait` ice.
- [x] **C8.** (1.4.0, 2026-10-26) `-x|--doctor`, read only, with ok/warn/FAIL and an exit status. Original item: `--doctor` command (required tools, fonts, lock state, stale backups).
- [x] **C9.** (1.4.1, 2026-10-26) `~/.ussuri/config` plus `--config`; precedence is defaults, environment, config, switches. Original item: `~/.ussuri/config` for overrides.
- [x] **C10.** (1.4.2, 2026-10-26) `--dotfiles`/`--unlink`/`--profile`, layered common/profile/host, with backups. Original item: Dotfile linking (chezmoi/stow style) and machine-specific profiles.

## Plugins and shell setup (from the review of 2026-10-27)

Housekeeping on what is already loaded:

- [x] **H1. Conditional snippets.** (1.4.9, 2026-10-27) `os_is_like arch` guard in both lists; tested for arch, endeavouros and manjaro (load) and ubuntu, fedora, debian, macOS (do not). Existing installs need `--install` to refresh their copy of the lists. `OMZP::archlinux` is loaded on every OS but only adds Arch/pacman aliases. Load it only on Arch and derivatives. Existing installs keep their copy of the list until it is replaced (see the note in the changelog when this ships).
- [x] **H2. `OMZP::command-not-found` on macOS.** (checked 2026-10-27, no change needed) The snippet is cross-platform: on macOS it sources Homebrew's own built-in handler (`/opt/homebrew/Library/Homebrew/command-not-found/handler.sh`, present here) and a fresh interactive shell has `command_not_found_handler` defined. Not triggered for real, as it can download Homebrew's database. Unchecked whether it does anything there. Verify, then keep it, make it conditional, or drop it.
- [x] **H3. History settings.** (1.5.0, 2026-10-27) `HISTORY_SIZE` (50000), `DO_HISTORY`, `HISTFILE` default, four hist_* options. Read back from a sourced shell in the tests. The script sets only `inc_append_history` and `share_history`: no size, no dedupe. macOS `/etc/zshrc` gives `HISTSIZE=2000`. Add sensible, overridable defaults (size, ignore duplicates and leading-space commands). Do this before T1, which is most useful with a long history.

Plugins to add (all checked as maintained on 2026-10-27, none tested in a shell yet; add to both `zinit-turbo.zsh` and `zinit.zsh` in the same order):

- [x] **T1. `zsh-users/zsh-history-substring-search`** (1.5.1, 2026-10-27) Verified in a pty with the real plugin: Up after typing `echo a` recalls `echo alpha` rather than the previous command, for both `^[[A` and `^[OA`. The offline tests check list placement and the bindings. (last push 2026-09). Up/Down searches history for the typed text. Must load after zsh-syntax-highlighting; needs key bindings.
- [x] **T2. `wfxr/forgit`** (1.5.2, 2026-10-27) 16 of its 29 aliases clashed with the OMZ git snippet (ga, gd, gco, gcb, gss, glo...), so they are renamed `fg*`. Verified in a pty that the git aliases keep their meaning. `tests/forgit-aliases.zsh` re-checks against upstream. (2026-10). Interactive git commands driven by fzf (fzf is already in the package list).
- [x] **T3. `zoxide`** (1.5.3, 2026-10-27) In every package list; set up on login only when installed, cached. Not run against the real binary (see below): its init template was read from the source and its compdef guard emulated with a stub in a pty, which found that turbo mode needed `register_zoxide_completion` after compinit. Re-verify with the real binary once zoxide is installed. (2026-10). A tool, not a plugin: smarter `cd`. Add to the package lists and set it up through `cached_eval`. Not in `macos.brew` or installed today.
- [ ] **T4. `MichaelAquilina/zsh-you-should-use`** (2026-05, optional). Reminds you of aliases you did not use.
- [ ] **T5. `atuin`** (2026-10, optional). Searchable, optionally synced history database replacing Ctrl-R. Opinionated and heavier.
- [ ] **T6. `jeffreytse/zsh-vi-mode`** (2026-07, optional). Only if you use vi bindings.

Decided against: fast-syntax-highlighting (alternative to the one already loaded), zsh-autocomplete (conflicts with fzf-tab), zsh-z (zoxide is better), zsh-defer (zinit `wait` does it, stale since 2024), zsh-autopair (stale since 2024).

## Housekeeping when a fix ships

Bump `# Version:` in `ussuri.zsh`, `Current Version` in `README.md`, and add a `CHANGELOG.md` entry (single digits per component, per CLAUDE.md).
