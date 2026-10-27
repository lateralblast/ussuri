# Add in zsh plugins
zinit light zsh-users/zsh-syntax-highlighting
zinit light zsh-users/zsh-completions
zinit light zsh-users/zsh-autosuggestions
zinit light Aloxaf/fzf-tab
zinit light zsh-users/zsh-history-substring-search
bind_history_search
# Add in snippets (one line each: they are run one line at a time)
zinit snippet OMZP::git
zinit snippet OMZP::sudo
if os_is_like arch; then zinit snippet OMZP::archlinux; fi
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