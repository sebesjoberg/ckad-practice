# Shell started by './lab.sh pin': lab commands work without the ./lab.sh prefix.
# up/down/reset are left out - reset is a terminal command and a stray 'down' deletes the clusters.
if [ -f ~/.bashrc ]; then
  . ~/.bashrc
fi

LAB=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lab.sh
for cmd in random setup task grade hint solution drill list pin unpin; do
  eval "$cmd() { \"\$LAB\" $cmd \"\$@\"; }"
done
unset cmd

# Read by lab.sh, so the task footer names the short commands.
export LAB_SHELL=1
if [ -n "${TMUX:-}" ]; then
  tmux set-option status-right-length 80 \; \
    set-option status-right ' random · task · grade · hint · solution · drill · list · unpin '
fi
