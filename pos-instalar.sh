#!/usr/bin/env bash
# Segunda etapa, no GNOME, como seu usuário (não como root):
#   ./pos-instalar.sh
#
# Instala paru, Claude (Desktop e CLI), Codex, ferramentas dos plugins,
# Flutter e o SDK do Android; conecta o GitHub e traz o ~/.claude.
# Pode rodar de novo: cada passo pula o que já está feito.
#
# REVISAR=0 ./pos-instalar.sh  pula a revisão dos PKGBUILDs do AUR.
set -euo pipefail

REVISAR=${REVISAR:-1}
SDK="$HOME/Android/Sdk"

PACMAN=(
  github-cli jq unzip
  nodejs npm go gopls pyright typescript-language-server openai-codex
  jdk21-openjdk
  # Cowork (máquina virtual) e sandbox do Claude Code
  qemu-system-x86 edk2-ovmf virtiofsd bubblewrap socat gjs
  docker docker-compose docker-buildx
  openssh tailscale
)

AUR=(claude-desktop google-chrome flutter-bin android-sdk-cmdline-tools-latest)

passo() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
aviso() { printf '\033[1;33m%s\033[0m\n' "$*"; }
erro() { printf '\033[1;31mErro: %s\033[0m\n' "$*" >&2; exit 1; }
tem() { command -v "$1" >/dev/null 2>&1; }

[[ $EUID -ne 0 ]] || erro "rode como seu usuário, não como root."
ping -c1 -W3 archlinux.org >/dev/null 2>&1 || erro "sem internet."

# Uma senha só: o sudo fica renovado enquanto o script roda.
sudo -v
while sudo -n true 2>/dev/null; do sleep 50; kill -0 "$$" 2>/dev/null || exit; done &

# --- Pacotes ------------------------------------------------------------------

passo "Pacotes dos repositórios oficiais"
sudo pacman -Syu --needed --noconfirm "${PACMAN[@]}"

if ! tem paru; then
  passo "Instalando o paru"
  tmp=$(mktemp -d)
  git clone --depth 1 https://aur.archlinux.org/paru-bin.git "$tmp/paru-bin"
  (cd "$tmp/paru-bin" && makepkg -si --noconfirm)
  rm -rf "$tmp"
fi

passo "Pacotes do AUR: ${AUR[*]}"
if [[ $REVISAR == 1 ]]; then
  echo "O paru mostra cada PKGBUILD para revisão. Confira as URLs de download."
  paru -S --needed "${AUR[@]}"
else
  paru -S --needed --noconfirm --skipreview "${AUR[@]}"
fi

passo "Grupos kvm, flutter e docker, linger e Docker"
sudo usermod -aG kvm,flutter,docker "$USER"
sudo loginctl enable-linger "$USER"
# Logs dos containers com teto de 30 MB cada (3 arquivos de 10 MB).
if [[ ! -f /etc/docker/daemon.json ]]; then
  sudo mkdir -p /etc/docker
  echo '{ "log-driver": "json-file", "log-opts": { "max-size": "10m", "max-file": "3" } }' \
    | sudo tee /etc/docker/daemon.json >/dev/null
fi
# O socket sobe o daemon na primeira chamada do docker, sem pesar no boot.
sudo systemctl enable --now docker.socket

passo "Servidor SSH"
# Login por senha fica no padrão do Arch (ligado); root só entra com chave.
# O limit do ufw bloqueia quem tentar mais de 6 conexões em 30 segundos.
sudo systemctl enable --now sshd
sudo ufw limit 22/tcp >/dev/null

passo "Tailscale"
# As máquinas da tailnet acessam tudo; a rede local segue só com a porta 22.
sudo systemctl enable --now tailscaled
sudo ufw allow in on tailscale0 >/dev/null
if ! tailscale status >/dev/null 2>&1; then
  echo "Abra o link que aparecer e autorize esta máquina na sua conta."
  # --operator deixa usar o comando tailscale sem sudo.
  sudo tailscale up --operator="$USER" --hostname="$(cat /etc/hostname)"
fi

# --- GNOME ----------------------------------------------------------------------

gsettings set org.gnome.desktop.interface show-battery-percentage true
gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click true

# --- Shell ----------------------------------------------------------------------

passo "Variáveis no ~/.bashrc"
if ! grep -q '# arch-setup' ~/.bashrc 2>/dev/null; then
  cat >>~/.bashrc <<'EOF'

# arch-setup
export PATH="$HOME/.local/bin:$PATH"
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
export CHROME_EXECUTABLE=/usr/bin/google-chrome-stable
EOF
fi
export PATH="$HOME/.local/bin:$PATH"

# --- Claude Code CLI ------------------------------------------------------------

if ! tem claude; then
  passo "Instalando o Claude Code CLI"
  curl -fsSL https://claude.ai/install.sh | bash
fi

# --- GitHub ---------------------------------------------------------------------

passo "GitHub"
if ! gh auth status >/dev/null 2>&1; then
  echo "Na pergunta da chave SSH, responda Yes e dê o nome da máquina como título."
  gh auth login --git-protocol ssh --web
fi
gh auth setup-git

if [[ -z $(git config --global user.name || true) ]]; then
  nome=$(gh api user -q '.name // empty' 2>/dev/null || true)
  read -r -p "Nome nos commits [${nome}]: " r; git config --global user.name "${r:-$nome}"
fi
if [[ -z $(git config --global user.email || true) ]]; then
  email=$(gh api user -q '.email // empty' 2>/dev/null || true)
  read -r -p "E-mail nos commits [${email}]: " r; git config --global user.email "${r:-$email}"
fi
git config --global init.defaultBranch main

# --- ~/.claude ------------------------------------------------------------------

CONFIG_REPO=${CONFIG_REPO:-"$(gh api user -q .login)/skills"}
if [[ ! -d ~/.claude/.git ]] && gh repo view "$CONFIG_REPO" >/dev/null 2>&1; then
  passo "Trazendo $CONFIG_REPO para o ~/.claude"
  # O ~/.claude pode já ter estado de runtime do Claude; o .gitignore do repo
  # cobre essas pastas, então o checkout entra por cima sem conflito.
  mkdir -p ~/.claude
  git -C ~/.claude init -q -b main
  git -C ~/.claude remote add origin "git@github.com:$CONFIG_REPO.git"
  git -C ~/.claude fetch -q origin main
  git -C ~/.claude checkout -q -t origin/main
fi
sync_bin=~/.claude/configsync/dist/claude-config-sync-linux-amd64
if [[ -x $sync_bin ]] && ! systemctl --user is-enabled claude-config-sync.timer >/dev/null 2>&1; then
  passo "Agendando o claude-config-sync"
  "$sync_bin" instalar
fi

# --- Codex ----------------------------------------------------------------------

if ! codex login status >/dev/null 2>&1; then
  passo "Login no Codex"
  codex login || aviso "Login do Codex ficou para depois: rode codex login."
fi

# --- Android SDK e Flutter ------------------------------------------------------

if [[ ! -d $SDK/platform-tools ]]; then
  passo "SDK do Android em $SDK (responda y na licença)"
  /opt/android-sdk/cmdline-tools/latest/bin/sdkmanager --sdk_root="$SDK" \
    "cmdline-tools;latest" "platform-tools" "platforms;android-36" "build-tools;36.0.0"
fi
# Antes do próximo login o grupo flutter ainda não vale; o flutter-bin cai no unionfs e funciona igual.
flutter config --android-sdk "$SDK" >/dev/null

# --- Claude Remote Control ------------------------------------------------------

# Sessões do Claude neste notebook, abertas de claude.ai/code ou do celular.
# Fica habilitado mas parado: antes ele precisa do login do CLI e da confiança
# em ~/projects, as duas coisas feitas à mão no fim.
passo "Serviço claude-remote-control"
mkdir -p ~/projects ~/.config/systemd/user
cat >~/.config/systemd/user/claude-remote-control.service <<'EOF'
[Unit]
Description=Claude Remote Control
After=network-online.target

[Service]
WorkingDirectory=%h/projects
# Sem dormir enquanto o serviço estiver no ar: tampa fechada não suspende.
ExecStart=/usr/bin/systemd-inhibit --what=sleep:handle-lid-switch --mode=block --who=claude-remote-control --why="acesso remoto" %h/.local/bin/claude remote-control --permission-mode auto
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload
systemctl --user enable claude-remote-control >/dev/null 2>&1

# --- Fim ------------------------------------------------------------------------

passo "Pronto"
cat <<'EOF'
Saia e entre de novo na sessão do GNOME, para valerem os grupos kvm, flutter e docker.
Depois:
  cd ~/projects && claude   # login, plugins e confiança na pasta (/exit no fim)
  claude remote-control     # responda y, espere a sessão subir e saia com Ctrl+C
  systemctl --user start claude-remote-control
  flutter doctor            # tudo deve aparecer com ✓
EOF
