# Turbo mode plugin list (the default, ZINIT_TURBO=true)
# Same plugins in the same order as zinit.zsh, but the prompt (powerlevel10k) loads straight
# away and everything else is deferred until just after the first prompt is drawn, so you get
# a prompt sooner. compinit runs once at the end of the deferred batch, as in zinit.zsh, so every
# plugin's completions are registered. Set ZINIT_TURBO=false to use zinit.zsh instead, which
# loads everything before the prompt.
zinit ice depth=1; zinit light romkatv/powerlevel10k
# Add in zsh plugins
zinit ice wait lucid; zinit light zsh-users/zsh-syntax-highlighting
zinit ice wait lucid; zinit light zsh-users/zsh-completions
zinit ice wait lucid; zinit light zsh-users/zsh-autosuggestions
zinit ice wait lucid; zinit light Aloxaf/fzf-tab
# Add in snippets
zinit ice wait lucid; zinit snippet OMZP::git
zinit ice wait lucid; zinit snippet OMZP::sudo
zinit ice wait lucid; zinit snippet OMZP::archlinux
zinit ice wait lucid; zinit snippet OMZP::aws
zinit ice wait lucid; zinit snippet OMZP::kubectl
zinit ice wait lucid; zinit snippet OMZP::kubectx
# Load completions once everything above has been loaded
zinit ice wait lucid atload"autoload -Uz compinit && compinit; zinit cdreplay -q"; zinit snippet OMZP::command-not-found
