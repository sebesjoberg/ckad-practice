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
