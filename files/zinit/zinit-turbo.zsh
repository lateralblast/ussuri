# Turbo mode plugin list (the default, ZINIT_TURBO=true)
# Same plugins in the same order as zinit.zsh, but the prompt (powerlevel10k) loads straight
# away and everything else is deferred until just after the first prompt is drawn, so you get
# a prompt sooner. compinit runs once at the end of the deferred batch, as in zinit.zsh, so every
# plugin's completions are registered. Set ZINIT_TURBO=false to use zinit.zsh instead, which
# loads everything before the prompt.
if prompt_engine_is p10k; then zinit ice depth=1; zinit light romkatv/powerlevel10k; fi
# Add in zsh plugins
zinit ice wait lucid; zinit light zsh-users/zsh-syntax-highlighting
zinit ice wait lucid; zinit light zsh-users/zsh-completions
zinit ice wait lucid; zinit light zsh-users/zsh-autosuggestions
zinit ice wait lucid; zinit light Aloxaf/fzf-tab
zinit ice wait lucid atload"bind_history_search"; zinit light zsh-users/zsh-history-substring-search
zinit ice wait lucid; zinit light MichaelAquilina/zsh-you-should-use
# Add in snippets (one line each: they are run one line at a time)
zinit ice wait lucid; zinit snippet OMZP::git
zinit ice wait lucid; zinit snippet OMZP::sudo
if os_is_like arch; then zinit ice wait lucid; zinit snippet OMZP::archlinux; fi
# Aliases for what this machine has, each checked once as this list is read: brew, docker and docker-compose if the
# command is on the PATH, systemd where systemctl is (Linux), and the apt (debian, ubuntu, mint...) and dnf (fedora)
# ones on those distributions. OMZP::macos is not loaded: it sources two more files (music, spotify) that a zinit
# snippet does not download, so it prints an error on every shell.
if (( $+commands[brew] )); then zinit ice wait lucid; zinit snippet OMZP::brew; fi
if (( $+commands[docker] )); then zinit ice wait lucid; zinit snippet OMZP::docker; fi
if (( $+commands[docker-compose] )); then zinit ice wait lucid; zinit snippet OMZP::docker-compose; fi
if is_linux && (( $+commands[systemctl] )); then zinit ice wait lucid; zinit snippet OMZP::systemd; fi
if os_is_like debian; then zinit ice wait lucid; zinit snippet OMZP::debian; fi
if os_is_like fedora; then zinit ice wait lucid; zinit snippet OMZP::dnf; fi
zinit ice wait lucid; zinit snippet OMZP::aws
zinit ice wait lucid; zinit snippet OMZP::kubectl
zinit ice wait lucid; zinit snippet OMZP::kubectx
# forgit: interactive git commands (fzf). It defines short aliases, and 16 of them (ga, gd, gco, gcb, gss, glo...)
# have the same name as aliases in the git snippet above, which would silently change what they do
# (gcb creates a branch today, but forgit's gcb is an interactive picker). So those are renamed with an f
# in front (fga, fgd, fgco, fgcb...) before it loads. Its others (gi, gat, gfu...) keep their names.
export forgit_add=fga forgit_branch_delete=fgbd forgit_blame=fgbl forgit_checkout_branch=fgcb forgit_checkout_file=fgcf forgit_clean=fgclean forgit_checkout_commit=fgco forgit_cherry_pick=fgcp forgit_diff=fgd forgit_log=fglo forgit_rebase=fgrb forgit_reset_head=fgrh forgit_restore=fgrs forgit_stash_show=fgss forgit_switch_branch=fgsw forgit_worktree=fgwt
zinit ice wait lucid; zinit light wfxr/forgit
# Load completions once everything above has been loaded (and zoxide's, which is set up before compinit has run here)
zinit ice wait lucid atload"autoload -Uz compinit && compinit; zinit cdreplay -q; register_zoxide_completion"; zinit snippet OMZP::command-not-found
