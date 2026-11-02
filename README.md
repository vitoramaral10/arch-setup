# arch-setup

Arch Linux com GNOME enxuto, em duas etapas: o `instalar.sh` roda no live ISO
oficial e o `pos-instalar.sh` roda no primeiro login.

## 1. No live ISO (`root@archiso`)

Conecte a internet. Por cabo, ela já funciona. Por Wi-Fi:

```
iwctl station wlan0 connect "NOME_DA_REDE"
```

Depois rode:

```
curl -fsSL https://raw.githubusercontent.com/vitoramaral10/arch-setup/main/instalar.sh | bash
```

O script pergunta o disco, o nome da máquina, o usuário e a senha. Antes de
apagar o disco, ele pede o nome do disco digitado por extenso.

| Item | Como fica |
|---|---|
| Boot | UEFI (BIOS legacy não é suportada) e systemd-boot com entradas `linux` e `linux-lts` |
| Disco | 1 GB EFI em `/boot` (`fmask=0077`) e o resto em ext4, sem partição de swap |
| Swap | zram com metade da RAM |
| Rede | NetworkManager, já com o Wi-Fi usado no live ISO |
| Desktop | GNOME enxuto (sem navegador, loja, mapas, clima, música e leitor de tela) |
| Áudio | PipeWire (`pipewire-pulse` e `pipewire-jack`) |
| Hardware | microcode e driver Vulkan conforme a CPU e a GPU detectadas |
| Idioma | `pt_BR.UTF-8`, teclado `br-abnt2`, fuso `America/Sao_Paulo` |
| Contas | root bloqueado; o seu usuário usa sudo pelo grupo `wheel` |

## 2. No GNOME, como seu usuário

```
./pos-instalar.sh
```

| Etapa | O que faz |
|---|---|
| Pacotes | paru, Claude Desktop, Chrome, Codex, LSPs (Go, Python, TypeScript), Node, `jq` |
| Cowork | QEMU, OVMF, virtiofsd e grupo `kvm` |
| Claude Code | CLI instalado em `~/.local/bin` |
| GitHub | `gh` com chave SSH e identidade do git |
| `~/.claude` | clone do repositório de configuração e agendamento do `claude-config-sync` |
| Flutter | Flutter e SDK do Android em `~/Android/Sdk`, sem o Android Studio |

O script pode rodar de novo: cada etapa pula o que já está feito. Por padrão, o
paru mostra cada PKGBUILD do AUR para revisão. Com `REVISAR=0`, essa revisão é
pulada.

No fim, saia e entre de novo na sessão. Depois rode `claude` (login e plugins)
e `flutter doctor`.
