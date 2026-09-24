# Super Boxing — build 81

## IMPORTANTE: gere o plugin de novo antes do APK
Quase todas as correções de travamento desta versão estão no plugin
Android. Rode, nesta ordem:

1. `PREPARAR_PLUGIN_USB_ANDROID.bat`
2. `EXPORTAR_APK_ANDROID.bat` (ou `GERAR_APK_AGORA.bat`)

Sem o passo 1, o APK sai com o plugin antigo e os travamentos continuam.

## Permissões sem travar (Arduino e câmera)
- **Era isso que travava:** a atividade de "encaixe USB" do plugin abria o
  jogo de novo por cima dele mesmo. Com o jogo já aberto, isso empilhava uma
  segunda tela do Godot e a TV Box travava na hora de autorizar o Arduino.
  Agora ela só guarda a permissão e não abre nada. Quem abre o jogo é a
  inicialização da TV Box.
- As janelas agora vêm **uma de cada vez**: primeiro o Arduino, depois a
  câmera (só quando o Arduino já respondeu), depois a webcam USB. Enquanto
  uma janela do Android está na tela, o jogo não mexe em USB.
- Na janela do Arduino, **marque a caixa e toque OK uma vez só**. Dependendo
  do Android, a caixa aparece como "Usar por padrão" ou "Sempre abrir…
  quando conectado". Ela só serve para o Android guardar a permissão: o jogo
  não é mais aberto sozinho quando o cabo é ligado.
- A permissão do microfone é pedida uma vez na vida do aparelho, junto com a
  câmera, numa janela só. O microfone não grava nada.

## Sair pelo controle sem travar
O VOLTAR do controle fecha o jogo na hora. Arduino e câmera são soltos em
segundo plano, os ajustes são gravados e o processo termina. Não congela
mais no último quadro. Na Central, o VOLTAR continua fechando só a Central.

## Mais leve (o que agarrava o processador)
- **Câmera:** o plugin convertia 11 quadros por segundo de 640x480 o dia
  inteiro, mesmo sem a imagem aparecer, e criava 1,2 MB de lixo de memória
  a cada quadro. Agora converte só no ritmo que o jogo pede (rápido só na
  contagem da foto), em meia resolução fora da foto, sem gerar lixo.
- **Arduino:** abrir a porta e listar a USB rodavam dentro do quadro do jogo,
  cinco vezes por segundo enquanto a permissão não vinha. Agora rodam numa
  thread do plugin, e enquanto a permissão está pendente o jogo espera 2,5 s
  entre tentativas.
- **Arena:** não é mais desenhada durante a contagem da foto (ela nem
  aparece nessa hora). Liga meio segundo antes do soco.
- **Lutador:** botas e luvas com metade dos triângulos (165 mil → 119 mil
  no total).

## Lutador
- **Botas:** sola fina, escura e do tamanho da bota. Antes ela era branca e
  mais larga, e virava uma prancha quando o pé inclinava. A biqueira não
  dobra mais em bico.
- **Luvas:** a mancha escura no polegar sumiu (a "costura" pintava o polegar
  inteiro).
- **Soco médio/forte que não derruba:** ele vai de costas até as cordas,
  apoia os braços nelas, as cordas cedem e o devolvem ao centro.
- **Derrota:** a vaia só vem quando o jogador PERDE A LUTA. O lutador
  provoca, avança e acerta a tela. O vidro racha, a arena fica vermelha e
  aparece "K.O. — VOCÊ FOI NOCAUTEADO". Só depois disso a torcida vaia. Soco
  fraco no meio da luta não tem vaia: a torcida incentiva.

## Abertura
- O fundo do gabinete ganhou vida, calculada na placa de vídeo: respira
  devagar, a luz corre pelos riscos e um relâmpago acende de vez em quando.
- O escudo SUPER BOXING respira, balança de leve e tem um brilho varrendo o
  logo. Tem raios girando atrás e brilhos piscando nas pontas da estrela.
- **Créditos:** cada ficha entra como uma moeda de ouro girando pelo ar até
  a placa. A placa pula, acende e o número sobe no impacto, com "+1",
  faíscas e onda. Várias fichas seguidas entram em fila.

## Carregamento
Barra nova, no estilo medidor de energia de jogo de luta: pontas
chanfradas, moldura de metal com fio de ouro, células acendendo, energia
correndo por dentro e ponta em brasa. Sempre em movimento.
