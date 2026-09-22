# Punch Challenge Android 1.0.61 — abrir, e correr

Esta versão abandona o Windows, como pedido, e trata três coisas: **o
jogo que instala e não abre**, **a câmera que trava ao abrir** e **o
primeiro golpe que engasga**.

## O comando

```powershell
.\GERAR_APK_COMPLETO.ps1 -Instalar
```

`-Instalar` é opcional (usa o `adb`). O APK sai em
`build\android\PunchChallenge.apk`.

**Da primeira vez ele vai criar uma chave de assinatura** em
`%USERPROFILE%\.punchchallenge\`. Guarde essa pasta: um APK assinado por
outra chave não instala por cima deste, o Android exige desinstalar
antes. É também por isso que **este primeiro APK 1.0.61 precisa ser
instalado depois de desinstalar o 1.0.60** — a assinatura mudou.

---

## 1. O jogo que instala e não abre

Não vi o `logcat` da sua TV box, então não posso apontar a causa e dizer
"era esta". O que fiz foi tirar do arranque tudo que podia derrubá-lo:

**O arranque não fala mais com a ponte nativa.** Antes, a primeira coisa
que o serviço de câmera fazia no `_ready()` era chamar o plugin Android:
abrir o barramento USB, registrar o monitor do AUSBC e mexer na janela
da Activity — três coisas que podem demorar ou travar, todas antes do
primeiro quadro. Um jogo que não desenha o primeiro quadro é, para quem
está olhando, um jogo que não abre. Agora a ponte só é acordada **2,5
segundos depois**, com o jogo já desenhando.

**As classes do AUSBC não são mais carregadas no arranque.** Os três
retornos da câmera eram construídos dentro do construtor do plugin, o
que obriga o Android a carregar as bibliotecas de vídeo USB naquele
instante. Se alguma faltar no APK, a falha nasce no pior lugar possível:
dentro da criação do plugin, antes de a tela existir. Agora elas só são
tocadas quando alguém pede a câmera, e uma falha ali vira uma frase na
tela.

**`android.hardware.usb.host` deixou de ser obrigatório.** Com
`required="true"`, uma TV box cujo firmware não declara USB host — e há
muitas, inclusive com portas USB que funcionam — some com o atalho ou
abre e fecha. O jogo não precisa dessa promessa: ele pergunta pelo
barramento em tempo de execução.

**`show_as_launcher_app` desligado.** Essa opção registra o jogo como
*substituto da tela inicial* do Android. Firmwares de TV box tratam apps
com categoria `HOME` de forma especial, e vários os escondem da lista
comum. Você abre o jogo pela lista de aplicativos, não precisa disso.

**`target_sdk` de 35 para 30.** É a mudança que mais mexe no
comportamento, e vale explicar. A partir do Android 12, um aplicativo
que declara alvo 31 ou mais passa a ter regras novas exigidas pelo
sistema — entre elas, a de que todo `PendingIntent` diga se é mutável ou
não. A biblioteca de câmera USB que o jogo usa (AUSBC 3.2.7) é anterior
a essa regra em pontos do seu código de autorização. Declarando alvo 30,
o sistema aplica as regras antigas e esse caminho volta a funcionar. É
seguro aqui porque o APK é instalado à mão, não publicado em loja.
Se quiser desfazer, é uma linha em `export_presets.cfg`.

### Se ainda assim não abrir

Adicionei um modo que responde à pergunta em uma execução:

```powershell
.\GERAR_APK_COMPLETO.ps1 -SemPlugin -Instalar
```

Isso gera um APK **sem a ponte nativa** (sem câmera e sem Arduino).

- **Se este abrir** → a culpa é do plugin, e o cerco fechou.
- **Se este também não abrir** → o plugin está inocente, e o problema é
  do jogo ou do pacote.

Me diga qual dos dois aconteceu. Com essa resposta eu paro de cercar e
vou direto na causa.

E se puder, com o aparelho ligado no `adb`:

```
adb logcat -v time AndroidRuntime:E godot:V *:S
```

Abra o jogo com isso rodando. O motivo do fechamento aparece ali, e é a
única coisa que transforma hipótese em diagnóstico.

---

## 2. A câmera que trava ao abrir

Aqui achei defeitos concretos, lendo o código.

**A autorização estava sendo pedida duas vezes, por dois caminhos.** O
plugin pedia a autorização USB com um `PendingIntent` próprio **e**
mandava o AUSBC pedir com o dele. Só um podia ganhar o diálogo — e o
nosso **não tinha receiver registrado**, ou seja, o resultado do seu
toque não chegava a lugar nenhum. Autorizada por esse caminho, a webcam
ficava autorizada de verdade no sistema, mas o AUSBC nunca era avisado, e
`onConnectDev` — que é quem abre o vídeo — não acontecia. É exatamente o
que você descreveu: *"mesmo pedindo permissão ela não cede a imagem ao
Godot"*. Agora há um dono só: o AUSBC, que é quem tem o receiver.

**Um diálogo dispensado matava a câmera pelo resto da sessão.** A lista
de "já pedi para este aparelho" só crescia, nunca era limpa. Um toque
errado e a tela ficava em "AGUARDANDO AUTORIZAÇÃO" sem nunca mais
perguntar nada. Agora uma negativa volta a perguntar depois de 4
segundos.

**A leitura da imagem travava a interface.** Quando a webcam não
entregava quadros pelo caminho normal, o plugin caía num caminho
alternativo que copia a tela da câmera da GPU para a memória
(`TextureView.getBitmap`) — uma operação cara que sincroniza a thread de
desenho — **a cada 180 ms, para sempre**. Ou seja: exatamente no caso
quebrado, e exatamente com a cara de *"quando vai abrir ela trava"*.
Agora é a cada 420 ms e desiste sozinho depois de 12 tentativas sem
resultado.

**A webcam deixou de custar durante a partida.** Cada leitura de quadro
atravessa a ponte com 1,2 MB e sobe uma textura nova para a GPU. Isso
acontecia 11 vezes por segundo, **inclusive durante a rodada**, para uma
imagem que a rodada não mostra — a foto só é tirada no obturador, e a
pré-visualização só aparece nas Configurações. Agora o ritmo rápido só
vale enquanto alguém está de fato olhando.

---

## 3. O primeiro golpe

**Antes de tudo, uma correção minha.** Na sessão passada eu disse ter
consertado isto "encurtando o hit-stop na TV box". Aquilo não podia ter
ajudado em nada: `hitstop_left` é escrito, descontado por quadro e
**lido em lugar nenhum**. Eu escalei um valor morto. O travamento era
outro.

**O verdadeiro: o primeiro soco compilava meio mundo.** As duas nuvens de
partículas nascem desligadas, ou seja, nunca são desenhadas — e o Godot,
no renderizador de compatibilidade, compila o programa de um material na
primeira vez que ele é **desenhado**. A conta do primeiro soco era, toda
ela, naquele instante: compilar o programa das faíscas, compilar o do
desenho, subir a textura para a GPU, alocar os buffers, e ainda acender
pela primeira vez as luzes com o clarão no máximo.

Agora há um **ensaio geral** no arranque: nos primeiros quadros, com a
arena fora da tela, o jogo emite as duas nuvens, acende o clarão e manda
desenhar. Quando o primeiro soco de verdade chega, não há mais nada para
compilar.

**E o soco parou de realocar memória de vídeo.** Esta linha trocava o
número de partículas no instante do impacto:

```gdscript
_impacto_particulas.amount = int(lerpf(18.0, 86.0, forca) * ...)
```

Mexer em `amount` destrói o buffer de partículas na GPU e aloca outro —
no meio do quadro do golpe, que já é o quadro mais cheio do jogo. E não
era só o primeiro: era **todo** soco. Agora quem varia é `amount_ratio`,
que diz quantas das mesmas partículas já alocadas nascem desta vez.
Mesmo efeito na tela, alocação nenhuma.

---

## 4. O APK passou a ser release

Esta é a maior diferença de velocidade da versão, e ninguém a tinha
escolhido. O script gerava `--export-debug`, e o modelo debug do Godot
carrega o interpretador de GDScript **instrumentado**: cada linha
executada passa por verificação de ponto de parada e contabilidade de
perfil. Num PC isso se perde no ruído; num jogo que é quase todo GDScript
rodando numa Amlogic, é uma fatia do quadro que some de graça.

O release exigia uma chave de assinatura — e era só isso que faltava. O
script agora cria a chave sozinho, na primeira execução.

`-Depuracao` volta a gerar o APK antigo, se precisar comparar.

---

## O que eu NÃO posso afirmar

Não tenho Godot, Android SDK nem a TV box neste ambiente. **Nada disto
foi compilado nem executado por mim.** As mudanças em GDScript, Kotlin,
manifesto e preset foram escritas e revisadas à mão.

Das três queixas, a do primeiro golpe é a que tem causa identificada e
mecanismo explicado. A da câmera tem três defeitos concretos corrigidos,
mas só o aparelho dirá se eram os que importavam. A de não abrir é a que
ainda não tem causa provada — por isso o `-SemPlugin` existe.
