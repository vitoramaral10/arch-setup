# AGENTS.md

Scripts que instalam o Arch Linux em duas etapas: `instalar.sh` roda como root no
live ISO oficial e `pos-instalar.sh` roda como o usuário no primeiro login. O
`README.md` descreve o que cada etapa entrega.

## Git

- Todo o trabalho vai direto na `main`. Não crie branch nem worktree.
- Commit e push só quando o usuário pedir.
- Mensagens em Conventional Commits, em português, no presente e sem escopo:
  `feat: adiciona ...`, `fix: deixa ...`. Nada de crédito a IA (`Co-Authored-By`
  ou menção a assistente).
- O live ISO baixa os scripts da `main` no GitHub (`curl .../main/instalar.sh`):
  uma mudança só vale na próxima instalação depois do push.

## Scripts

- Bash com `set -euo pipefail`. Use os helpers que já existem (`passo`, `aviso`,
  `erro`, `tem`, `perguntar`) em vez de criar outros.
- No `instalar.sh`, toda leitura vem de `/dev/tty`: com `curl | bash`, o stdin é
  o próprio script.
- No heredoc do `arch-chroot`, variáveis do live ISO entram sem escape (`$UUID_RAIZ`)
  e as do chroot com escape (`\$k`). Confira cada uma ao mexer ali.
- O `pos-instalar.sh` precisa poder rodar de novo: cada passo pula o que já está feito.
- Diferenças entre `desktop` e `servidor` passam por `$PERFIL`; o `instalar.sh`
  grava o perfil em `/etc/arch-setup-perfil` e o `pos-instalar.sh` lê de lá.
- Pacotes só do pacman e do AUR (via `paru`). Sem Flatpak nem Snap.
- Comentários em português e só para o porquê que o código não mostra.

## Decisões que não devem voltar

- Disco: os tamanhos acompanham a máquina, nunca valores fixos. EFI 1 GiB, raiz
  com 15% do disco (40 a 120 GiB), swap do tamanho da RAM, `/tmp` com 3% do disco
  (4 a 16 GiB, `nosuid,nodev`) e `/home` com o resto (`nodev`), tudo ext4.
- O `/tmp` é a partição do `fstab`. Não mascare o `tmp.mount`: a máscara em
  `/etc/systemd/system` também esconde a montagem gerada pelo `fstab`.
- O zram (prioridade 100) fica na frente; a swap de disco tem `pri=0` e serve
  para hibernar, com `resume=UUID=` nas entradas do systemd-boot.
- Boot só UEFI, com systemd-boot.

## Validação

- Nunca rode o `instalar.sh` nesta máquina: ele apaga o disco. Teste numa VM
  UEFI (QEMU com OVMF) a partir do live ISO.
- Antes de commitar: `bash -n instalar.sh pos-instalar.sh` e, se instalado,
  `shellcheck`.
- Mudou o que um script entrega? Atualize a tabela do `README.md` no mesmo commit.
