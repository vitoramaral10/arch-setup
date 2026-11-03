# arch-setup

Arch Linux em dois perfis, **desktop** (GNOME enxuto) ou **servidor** (sem
interface gráfica), em duas etapas: o `instalar.sh` roda no live ISO oficial e o
`pos-instalar.sh` roda no primeiro login.

## 1. No live ISO (`root@archiso`)

Conecte a internet. Por cabo, ela já funciona. Por Wi-Fi:

```
iwctl station wlan0 connect "NOME_DA_REDE"
```

Depois rode:

```
curl -fsSL https://raw.githubusercontent.com/vitoramaral10/arch-setup/main/instalar.sh | bash
```

O script pergunta o disco, o perfil (`desktop` ou `servidor`), o nome da
máquina, o usuário e a senha. Antes de apagar o disco, ele pede o nome do disco
digitado por extenso. O perfil fica gravado em `/etc/arch-setup-perfil`, e o
`pos-instalar.sh` lê de lá.

Os itens marcados com *(desktop)* ou *(servidor)* valem só naquele perfil.

| Item | Como fica |
|---|---|
| Boot | UEFI (BIOS legacy não é suportada) e systemd-boot com entradas `linux` e `linux-lts` |
| Disco | 1 GB EFI em `/boot` (`fmask=0077`) e o resto em ext4, sem partição de swap |
| Swap | zram com metade da RAM |
| Rede | NetworkManager, já com o Wi-Fi usado no live ISO |
| Desktop *(desktop)* | GNOME enxuto (sem navegador, loja, mapas, clima, música e leitor de tela) |
| Áudio *(desktop)* | PipeWire (`pipewire-pulse` e `pipewire-jack`) e `sof-firmware` para placas Intel com DSP |
| Hardware | microcode conforme a CPU; no desktop, driver Vulkan conforme a GPU |
| Idioma | `pt_BR.UTF-8`, teclado `br-abnt2`, fuso `America/Sao_Paulo` |
| Contas | root bloqueado; o seu usuário usa sudo pelo grupo `wheel` |
| Energia | `thermald` em CPU Intel; no desktop, `power-profiles-daemon` (seletor no GNOME) |
| Tampa *(servidor)* | fechar a tampa não suspende |
| Memória | zram com `swappiness=180` e `page-cluster=0`, mais `systemd-oomd` |
| Manutenção | TRIM semanal, limpeza do cache do pacman, mirrors do Brasil (`reflector`) e firmware (`fwupd`) |
| Firewall | `ufw` ligado, bloqueando a entrada |
| Pacotes | pacman com cor e 10 downloads paralelos; `makepkg` com todos os núcleos |
| Boot e disco | menu do systemd-boot sem espera (segure Espaço para o LTS), raiz com `noatime`, journal até 200 MB, desligamento em até 15 s por serviço, watchdog desligado |
| GPU Intel *(desktop)* | frequência mínima de 600 MHz, para as animações não engasgarem enquanto a GPU acelera |
| Extras | `bash-completion`, `man`, `tmux`; no desktop, emoji e CJK nas fontes e VA-API (`intel-media-driver`) para vídeo por hardware |

## 2. Como seu usuário (no GNOME ou no console do servidor)

```
./pos-instalar.sh
```

| Etapa | O que faz |
|---|---|
| Pacotes | paru, Codex, LSPs (Go, Python, TypeScript), Node, `jq`; no desktop, Claude Desktop e Chrome |
| Docker | `docker`, `docker compose` e `buildx`, grupo `docker` e logs limitados a 30 MB por container |
| Cowork *(desktop)* | QEMU, OVMF, virtiofsd e grupo `kvm` |
| SSH | `sshd` ligado, com login por senha (root só por chave) e porta 22 com limite de tentativas no `ufw` |
| Tailscale | `tailscaled` ligado, login pelo link e acesso liberado no `ufw` para a interface `tailscale0` |
| Claude Code | CLI em `~/.local/bin` e serviço `claude-remote-control` (sessões abertas de claude.ai/code ou do celular, sem suspender com a tampa fechada) |
| GitHub | `gh` com chave SSH e identidade do git |
| `~/.claude` | clone do repositório de configuração e agendamento do `claude-config-sync` |
| Flutter *(desktop)* | Flutter e SDK do Android em `~/Android/Sdk`, sem o Android Studio |
| Visual *(desktop)* | tema Orchis claro e escuro, ícones Tela-circle, papel de parede do Orchis e as extensões User Themes, Blur my Shell, Dash to Dock (embaixo), Just Perfection e AppIndicator (bandeja de ícones) |

O script pode rodar de novo: cada etapa pula o que já está feito. Por padrão, o
paru mostra cada PKGBUILD do AUR para revisão. Com `REVISAR=0`, essa revisão é
pulada.

### Visual do GNOME

O Orchis só tem suporte oficial até o GNOME 48. Dois scripts em `gnome/` cobrem
a diferença, e o `pos-instalar.sh` instala os dois em `~/.local/bin`:

- `orchis-completar-51 <Orchis-Dark|Orchis-Light>` copia do tema padrão do
  GNOME as regras dos elementos que o Orchis não estiliza: janela do Alt+F2,
  botão Limpar das notificações, eventos da agenda, indicadores de gravação de
  tela e tela de desbloqueio. Rode de novo depois de reinstalar o Orchis, que
  sobrescreve os arquivos.
- `orchis-segue-tema`, iniciado pelo serviço de usuário
  `orchis-segue-tema.service`, troca o tema do GTK e dos apps libadwaita entre
  Orchis-Light e Orchis-Dark quando você aperta o botão de modo claro/escuro.
  O shell (painel e menus) fica sempre no Orchis-Dark, combinando com o fundo
  escuro que o Blur my Shell dá aos menus.

No fim, saia e entre de novo na sessão. Depois rode `claude` (login e plugins)
e, no desktop, `flutter doctor`.
