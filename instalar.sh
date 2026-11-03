#!/usr/bin/env bash
# Instala Arch Linux + GNOME enxuto a partir do live ISO oficial.
#
# Uso, no root@archiso, com a internet já conectada (iwctl ou cabo):
#   curl -fsSL https://raw.githubusercontent.com/vitoramaral10/arch-setup/main/instalar.sh | bash
#
# O script apaga o disco escolhido inteiro. Ele pede o nome do disco
# digitado por extenso antes de formatar.
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/vitoramaral10/arch-setup/main"

FUSO="America/Sao_Paulo"
TECLADO="br-abnt2"
LAYOUT_X="br"
IDIOMA="pt_BR.UTF-8"

# GNOME enxuto: o grupo gnome sem navegador, mapas, clima, música, leitor de
# tela e loja de apps. Cada pacote foi escolhido na instalação da tivit.
GNOME=(
  gdm gnome-shell gnome-session gnome-settings-daemon gnome-control-center
  gnome-keyring gnome-console nautilus gvfs gvfs-mtp xdg-desktop-portal-gnome
  xdg-user-dirs-gtk gnome-backgrounds gnome-calculator gnome-disk-utility
  gnome-system-monitor gnome-text-editor gnome-color-manager gst-thumbnailers
  loupe papers showtime tecla
  # Opcionais do gnome-shell: eventos na agenda do relógio e gravação de tela
  evolution-data-server gst-plugin-pipewire
)

BASE=(
  base base-devel linux linux-lts linux-firmware
  networkmanager sudo nano git zram-generator
  pipewire pipewire-pulse pipewire-jack wireplumber sof-firmware
  bluez bluez-utils noto-fonts mesa mesa-utils btop
  # Energia, manutenção automática e firewall
  power-profiles-daemon fwupd pacman-contrib reflector ufw
  # Conforto no terminal e fontes com emoji e CJK
  bash-completion man-db man-pages tmux noto-fonts-emoji noto-fonts-cjk
)

# Toda leitura vem do terminal: com "curl | bash", o stdin é o próprio script.
perguntar() { # perguntar VAR "texto" [padrão]
  local resposta
  read -r -p "$2${3:+ [$3]}: " resposta </dev/tty
  printf -v "$1" '%s' "${resposta:-${3:-}}"
}

perguntar_senha() { # perguntar_senha VAR "texto"
  local a b
  while :; do
    read -r -s -p "$2: " a </dev/tty; echo
    read -r -s -p "Repita: " b </dev/tty; echo
    [[ -n $a && $a == "$b" ]] && break
    echo "As senhas não batem ou estão vazias. De novo."
  done
  printf -v "$1" '%s' "$a"
}

passo() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
erro() { printf '\033[1;31mErro: %s\033[0m\n' "$*" >&2; exit 1; }

# --- Pré-requisitos -----------------------------------------------------------

[[ $EUID -eq 0 ]] || erro "rode como root, no live ISO."
[[ -d /run/archiso ]] || erro "isto não parece o live ISO do Arch."
[[ $(cat /sys/firmware/efi/fw_platform_size 2>/dev/null) == 64 ]] \
  || erro "o boot não está em UEFI 64 bits. Este script só cobre UEFI."
ping -c1 -W3 archlinux.org >/dev/null 2>&1 \
  || erro "sem internet. Conecte com iwctl (station wlan0 connect REDE) e rode de novo."

loadkeys "$TECLADO" || true
timedatectl set-ntp true

# --- Perguntas ---------------------------------------------------------------

passo "Discos disponíveis"
# O pendrive do live ISO fica de fora da lista.
pendrive=$(lsblk -no PKNAME "$(findmnt -no SOURCE /run/archiso/bootmnt 2>/dev/null)" 2>/dev/null || true)
mapfile -t discos < <(lsblk -dno NAME,TYPE | awk '$2=="disk"{print $1}' | grep -vE "^(loop|sr|zram)" | grep -vx "${pendrive:-__nenhum__}")
[[ ${#discos[@]} -gt 0 ]] || erro "nenhum disco encontrado."
lsblk -do NAME,SIZE,MODEL "${discos[@]/#//dev/}"

perguntar DISCO "Disco para instalar" "${discos[0]}"
DISCO=${DISCO#/dev/}
[[ -b /dev/$DISCO ]] || erro "/dev/$DISCO não existe."

perguntar MAQUINA "Nome da máquina" "tivit"
perguntar USUARIO "Seu usuário" "vitor"
[[ $USUARIO =~ ^[a-z_][a-z0-9_-]*$ ]] || erro "usuário inválido: use minúsculas, números, - ou _."
perguntar_senha SENHA "Senha de $USUARIO (também usada no sudo)"

# Microcode e driver Vulkan conforme o hardware.
case $(grep -m1 vendor_id /proc/cpuinfo) in
  *GenuineIntel*) BASE+=(intel-ucode thermald) ;;
  *AuthenticAMD*) BASE+=(amd-ucode) ;;
esac
video=$(lspci | grep -iE 'vga|3d|display' || true)
grep -qi intel <<<"$video" && BASE+=(vulkan-intel intel-media-driver libva-utils)
grep -qiE 'amd|ati' <<<"$video" && BASE+=(vulkan-radeon libva-mesa-driver)
grep -qi nvidia <<<"$video" && BASE+=(nvidia-open nvidia-utils)

# Partições: nvme0n1 -> nvme0n1p1; sda -> sda1.
if [[ $DISCO =~ [0-9]$ ]]; then PART="/dev/${DISCO}p"; else PART="/dev/${DISCO}"; fi

echo
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS "/dev/$DISCO"
echo
echo "TUDO em /dev/$DISCO será apagado. Isso não tem volta."
perguntar CONFIRMA "Digite o nome do disco ($DISCO) para confirmar"
[[ $CONFIRMA == "$DISCO" ]] || erro "confirmação não bate. Nada foi alterado."

# --- Disco --------------------------------------------------------------------

passo "Particionando /dev/$DISCO (1 GB EFI + raiz ext4)"
umount -R /mnt 2>/dev/null || true
wipefs -af "/dev/$DISCO"
sgdisk --zap-all "/dev/$DISCO"
sgdisk -n1:0:+1G -t1:ef00 -c1:EFI -n2:0:0 -t2:8304 -c2:raiz "/dev/$DISCO"
partprobe "/dev/$DISCO"; udevadm settle

mkfs.fat -F32 -n EFI "${PART}1"
mkfs.ext4 -F -L raiz "${PART}2"

# noatime: sem escrita no disco a cada leitura de arquivo; o genfstab copia.
mount -o noatime "${PART}2" /mnt
# fmask/dmask 0077: o bootctl reclama de /boot com leitura para todos.
mount --mkdir -o fmask=0077,dmask=0077 "${PART}1" /mnt/boot

# --- Pacotes ------------------------------------------------------------------

passo "Instalando os pacotes (demora alguns minutos)"
sed -i 's/^#Color/Color/; s/^#\?ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
pacstrap -K /mnt "${BASE[@]}" "${GNOME[@]}"
genfstab -U /mnt >>/mnt/etc/fstab
cp /etc/pacman.conf /mnt/etc/pacman.conf

# Wi-Fi do live ISO (iwd) vira conexão do NetworkManager, para o GNOME já
# subir conectado. Redes com nome codificado (=hex) ficam de fora.
for psk in /var/lib/iwd/*.psk; do
  [[ -e $psk ]] || continue
  ssid=$(basename "$psk" .psk)
  [[ $ssid == =* ]] && continue
  senha_wifi=$(sed -n 's/^Passphrase=//p' "$psk")
  [[ -n $senha_wifi ]] || continue
  arq="/mnt/etc/NetworkManager/system-connections/$ssid.nmconnection"
  cat >"$arq" <<EOF
[connection]
id=$ssid
type=wifi

[wifi]
mode=infrastructure
ssid=$ssid

[wifi-security]
key-mgmt=wpa-psk
psk=$senha_wifi

[ipv4]
method=auto

[ipv6]
method=auto
EOF
  chmod 600 "$arq"
done

# --- Configuração do sistema -------------------------------------------------

passo "Configurando fuso, idioma, usuário e boot"
UUID_RAIZ=$(blkid -s UUID -o value "${PART}2")

arch-chroot /mnt /bin/bash -euo pipefail <<EOF
ln -sf /usr/share/zoneinfo/$FUSO /etc/localtime
hwclock --systohc

sed -i 's/^#pt_BR.UTF-8/pt_BR.UTF-8/; s/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo LANG=$IDIOMA >/etc/locale.conf
printf 'KEYMAP=%s\nXKBLAYOUT=%s\n' $TECLADO $LAYOUT_X >/etc/vconsole.conf

echo $MAQUINA >/etc/hostname
cat >/etc/hosts <<HOSTS
127.0.0.1 localhost
::1       localhost
127.0.1.1 $MAQUINA
HOSTS

useradd -m -G wheel $USUARIO
echo '%wheel ALL=(ALL:ALL) ALL' >/etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel
passwd -l root

printf '[zram0]\nzram-size = ram / 2\n' >/etc/systemd/zram-generator.conf
# Valores da ArchWiki para swap em zram: o padrão 60 é pensado para disco.
printf 'vm.swappiness = 180\nvm.watermark_boost_factor = 0\nvm.watermark_scale_factor = 125\nvm.page-cluster = 0\n' \
  >/etc/sysctl.d/99-zram.conf

echo 'MAKEFLAGS="-j\$(nproc)"' >/etc/makepkg.conf.d/jobs.conf
printf -- '--country Brazil\n--protocol https\n--latest 10\n--sort rate\n--save /etc/pacman.d/mirrorlist\n' \
  >/etc/xdg/reflector/reflector.conf
# A política padrão do ufw já bloqueia a entrada; o ufw enable não roda em
# chroot, então o firewall é ligado pelo arquivo de configuração.
sed -i 's/^ENABLED=no/ENABLED=yes/' /etc/ufw/ufw.conf

mkdir -p /etc/systemd/journald.conf.d /etc/systemd/system.conf.d /etc/systemd/user.conf.d
printf '[Journal]\\nSystemMaxUse=200M\\n' >/etc/systemd/journald.conf.d/10-tamanho.conf
# Desligamento: 15 s por serviço em vez de 90.
printf '[Manager]\\nDefaultTimeoutStopSec=15s\\n' >/etc/systemd/system.conf.d/10-desligamento.conf
printf '[Manager]\\nDefaultTimeoutStopSec=15s\\n' >/etc/systemd/user.conf.d/10-desligamento.conf
# Watchdog não serve num notebook e gasta energia.
echo 'kernel.nmi_watchdog = 0' >/etc/sysctl.d/10-watchdog.conf
echo 'blacklist iTCO_wdt' >/etc/modprobe.d/10-watchdog.conf
# GPU Intel (i915) com mínimo de 600 MHz: as animações não esperam ela acelerar
# desde 300. Parada, ela desliga (RC6) do mesmo jeito. Outras GPUs não têm o atributo.
echo 'SUBSYSTEM=="drm", KERNEL=="card[0-9]", ATTR{gt_min_freq_mhz}=="?*", ATTR{gt_min_freq_mhz}="600"' \
  >/etc/udev/rules.d/99-gpu-intel-minimo.rules

bootctl install
# timeout 0: o menu só aparece segurando Espaço no boot (para escolher o LTS).
printf 'default arch.conf\ntimeout 0\n' >/boot/loader/loader.conf
for k in linux linux-lts; do
  nome=arch; titulo="Arch Linux"
  [[ \$k == linux-lts ]] && nome=arch-lts && titulo="Arch Linux (LTS)"
  printf 'title %s\nlinux /vmlinuz-%s\ninitrd /initramfs-%s.img\noptions root=UUID=%s rw\n' \
    "\$titulo" \$k \$k $UUID_RAIZ >/boot/loader/entries/\$nome.conf
done

systemctl enable NetworkManager gdm bluetooth fstrim.timer systemd-boot-update \
  power-profiles-daemon systemd-oomd paccache.timer reflector.timer fwupd-refresh.timer ufw
if pacman -Q thermald >/dev/null 2>&1; then systemctl enable thermald; fi
EOF

# A senha passa por stdin, fora da linha de comando e do heredoc acima.
printf '%s:%s\n' "$USUARIO" "$SENHA" | arch-chroot /mnt chpasswd
unset SENHA

passo "Baixando o pos-instalar.sh para /home/$USUARIO"
curl -fsSL "$REPO_RAW/pos-instalar.sh" -o "/mnt/home/$USUARIO/pos-instalar.sh"
chmod +x "/mnt/home/$USUARIO/pos-instalar.sh"
arch-chroot /mnt chown "$USUARIO:$USUARIO" "/home/$USUARIO/pos-instalar.sh"

umount -R /mnt

passo "Pronto"
cat <<EOF
Tire o pendrive e reinicie com: reboot

No GNOME, entre como $USUARIO, abra o Console e rode:
  ./pos-instalar.sh
Ele instala paru, Claude, Codex, Flutter e o resto das ferramentas.
EOF
