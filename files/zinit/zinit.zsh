# Add in zsh plugins
zinit light zsh-users/zsh-syntax-highlighting
zinit light zsh-users/zsh-completions
zinit light zsh-users/zsh-autosuggestions
zinit light Aloxaf/fzf-tab
zinit light zsh-users/zsh-history-substring-search
bind_history_search
zinit light MichaelAquilina/zsh-you-should-use
# Add in snippets (one line each: they are run one line at a time)
zinit snippet OMZP::git
zinit snippet OMZP::sudo
# Archives, the clipboard and suspending: extract (x), copypath, copyfile and copybuffer (Ctrl-O) need clipcopy,
# which lives in an Oh My Zsh library file (a snippet downloads one file, so it is loaded first), and Ctrl-Z fg
zinit snippet OMZL::clipboard.zsh
zinit snippet OMZP::extract
zinit snippet OMZP::copypath
zinit snippet OMZP::copyfile
zinit snippet OMZP::copybuffer
zinit snippet OMZP::fancy-ctrl-z
if os_is_like arch; then zinit snippet OMZP::archlinux; fi
# common-aliases: many short aliases (l, ll, la, H, T, G...). zsh-you-should-use is told to leave them alone,
# or it would mention them all the time. The aliases still work, except that rm, cp and mv are put back to the
# plain commands (the snippet makes them ask first, -i)
mark_aliases
zinit snippet OMZP::common-aliases
plain_file_aliases
ignore_new_aliases
# Aliases for what this machine has, each checked once as this list is read: brew, docker and docker-compose if the
# command is on the PATH, systemd where systemctl is (Linux), and the apt (debian, ubuntu, mint...) and dnf (fedora)
# ones on those distributions. OMZP::macos is not loaded: it sources two more files (music, spotify) that a zinit
# snippet does not download, so it prints an error on every shell.
if (( $+commands[brew] )); then zinit snippet OMZP::brew; fi
if (( $+commands[docker] )); then zinit snippet OMZP::docker; fi
if (( $+commands[docker-compose] )); then zinit snippet OMZP::docker-compose; fi
if is_linux && (( $+commands[systemctl] )); then zinit snippet OMZP::systemd; fi
if os_is_like debian; then zinit snippet OMZP::debian; fi
if os_is_like fedora; then zinit snippet OMZP::dnf; fi
zinit snippet OMZP::aws
zinit snippet OMZP::kubectl
zinit snippet OMZP::kubectx
# forgit: interactive git commands (fzf). It defines short aliases, and 16 of them (ga, gd, gco, gcb, gss, glo...)
# have the same name as aliases in the git snippet above, which would silently change what they do
# (gcb creates a branch today, but forgit's gcb is an interactive picker). So those are renamed with an f
# in front (fga, fgd, fgco, fgcb...) before it loads. Its others (gi, gat, gfu...) keep their names.
export forgit_add=fga forgit_branch_delete=fgbd forgit_blame=fgbl forgit_checkout_branch=fgcb forgit_checkout_file=fgcf forgit_clean=fgclean forgit_checkout_commit=fgco forgit_cherry_pick=fgcp forgit_diff=fgd forgit_log=fglo forgit_rebase=fgrb forgit_reset_head=fgrh forgit_restore=fgrs forgit_stash_show=fgss forgit_switch_branch=fgsw forgit_worktree=fgwt
zinit light wfxr/forgit
zinit snippet OMZP::command-not-found
# Load completions
autoload -Uz compinit && compinit
zinit cdreplay -q
if prompt_engine_is p10k; then zinit ice depth=1; zinit light romkatv/powerlevel10k; fi