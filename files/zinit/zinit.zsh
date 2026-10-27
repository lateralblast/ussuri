# Add in zsh plugins
zinit light zsh-users/zsh-syntax-highlighting
zinit light zsh-users/zsh-completions
zinit light zsh-users/zsh-autosuggestions
zinit light Aloxaf/fzf-tab
# Add in snippets (one line each: they are run one line at a time)
zinit snippet OMZP::git
zinit snippet OMZP::sudo
if os_is_like arch; then zinit snippet OMZP::archlinux; fi
zinit snippet OMZP::aws
zinit snippet OMZP::kubectl
zinit snippet OMZP::kubectx
zinit snippet OMZP::command-not-found
# Load completions
autoload -Uz compinit && compinit
zinit cdreplay -q
zinit ice depth=1; zinit light romkatv/powerlevel10k