# Recursos do Punch Challenge

## Organização

| Pasta ou arquivo | Responsabilidade |
| --- | --- |
| assets/branding/punch_emblem.svg | Símbolo vetorial de boxe; arte fonte editável, 900 × 900 |
| scripts/presentation/arcade_stage.gd | Cenografia vermelha, luzes, brasão e abertura de 4,2 segundos |
| scripts/paleta.gd | Cores compartilhadas com as telas e efeitos existentes |
| scripts/audio/audio_catalog.gd | Nomes, caminhos e classificação dos loops de áudio |
| scripts/audio_bank.gd | Reprodução, volume, interrupção e redução da trilha |
| assets/audio/arcade/ | Banco atual de WAVs originais de 48 kHz |
| tools/estudio/ | A mesa de som em GDScript: DSP, instrumentos e as receitas de cada efeito |
| tools/gerar_audio.gd | Reescreve o banco inteiro; roda dentro do Godot, sem nada instalado |
| tools/conferir_audio.gd | Confere um banco novo contra o do repositório (duração, pico, RMS, espectro) |
| scripts/main.gd | Estados da partida, câmera, pontuação e montagem das telas |
| tests/test_show_flow.gd | Captura antes da jogada, estados da abertura e controle dos sons |
| tests/test_serial_teimoso.gd | A busca pelo Arduino: fila de portas, varredura cega, troca de caminho e ressurreição da ponte |

O projeto não depende de Python para NADA — nem para jogar, nem para
refazer o banco de áudio, nem para redesenhar o ícone, nem para construir
o lutador da arena. A webcam no Windows usa
o backend nativo Windows Media Foundation incluído em CameraServerExtension.

## Alteração das artes

Edite o SVG na pasta branding e mantenha o nome; Godot reimporta a imagem.
O brasão é um símbolo próprio do jogo, separado da marca Lazer & Sport.
Edite as cores do cenário em ArcadeStage e as cores das telas em Paleta.
Os nomes CIANO e ROSA permanecem como aliases para compatibilidade com os
componentes antigos; nesta edição apontam para amarelo e vermelho.

## Abertura e partida

Abertura animada ao ligar → tela de convite → pose e foto → soco → círculo
de pontuação → ranking. START pode iniciar a partida durante a abertura,
respeitando o saldo de créditos. Não há cobrança para assistir à abertura.
O círculo de pontuação não aparece na preparação ou no convite.

## Arquivos de usuário e exportação

Fotos e configurações ficam no user:// do Godot, fora dos recursos do jogo.
Não copie os dados de uma máquina para outra ao atualizar as artes.
Os arquivos .import e .uid acompanham os recursos no Git; o cache de
importação não é necessário para distribuir o projeto.
O preset Windows usa all_resources para incluir SVG, WAV e scripts.
Excluímos docs, tests, tools/capturar_telas* e deliverables da exportação,
mantendo a ponte da webcam e o gerador de som disponíveis no projeto fonte.

## Verificação

Execute com Godot 4.6:

```
godot --headless --path . --editor --quit
godot --headless --path . --script tests/test_core.gd
godot --headless --path . --script tests/test_show_flow.gd
godot --headless --path . --script tests/test_serial_teimoso.gd
godot --headless --path . --script tests/test_arena.gd
godot --headless --path . --script tests/test_quadro_liso.gd
godot --headless --path . --script tests/test_enquadramento_responsivo.gd
sh tools/conferir_ponte.sh
```

Depois valide imagem, volume e câmera na máquina. O canvas é 1080 × 1920;
o monitor e o Windows também devem usar a resolução nativa para a imagem
não ser reduzida por uma configuração externa ao jogo.
