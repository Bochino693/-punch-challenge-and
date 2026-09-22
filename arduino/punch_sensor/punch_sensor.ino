/*
  PUNCH CHALLENGE -- FIRMWARE V10 (MPU-6050)
  Placas: Arduino Uno / Nano (ATmega328P)
  Sensor: MPU-6050 no barramento I2C (A4 = SDA, A5 = SCL), endereco 0x68/0x69.
  Botoes: D2 = START, D3 = CREDIT, D9 = CONFIG (liga no GND;
           INPUT_PULLUP interno). CONFIG substitui o F9 no Android.

  PROTOCOLO SERIAL (115200 bps, uma linha por mensagem, campos com virgula):
    Enviados:  READY / CALIBRATING / CALIBRATED / PONG / BUTTON / PINS /
               TELEMETRY / HIT / SATURATION / ERROR / OK
    Recebidos: PING / RESET / TEST / CALIBRATE / LEDS,permil /
               CONFIG,eixo,raio,vmin,amin[,vmax]
  Referencia completa: docs/PROTOCOLO_SERIAL.md no projeto Godot.

  ====================================================================
  POR QUE ESTA VERSAO EXISTE
  ====================================================================

  A V2 media assim: quando |aceleracao do eixo| passava de um limiar,
  integrava a aceleracao por ate 400 ms e mandava o resultado. Tres
  defeitos vinham juntos, e sao exatamente os sintomas relatados:

  1. SENSOR PARADO GERANDO SOCO. O "zero" de cada eixo era medido UMA VEZ
     na calibracao e nunca mais. Se a montagem inclinasse depois -- um
     saco que fica torto, um suporte que cede -- a gravidade se
     reprojetava no eixo e virava "aceleracao dinamica" PERMANENTE. Pior:
     se alguem encostasse na maquina durante os 2 segundos da calibracao
     do arranque, o zero nascia errado e ficava errado a noite inteira.

  2. DERIVA VIRANDO VELOCIDADE. Integrar por 400 ms sem ancora nenhuma:
     um vies residual de 0,2 g dava 0,2 * 9,81 * 0,4 = 0,78 m/s do nada --
     em cima de um piso de 0,8 m/s. Ou seja, ruido produzia "golpes" no
     limiar.

  3. REBOTE CONSUMINDO TENTATIVA. O tempo morto era de 650 ms. Um saco
     pendurado balanca MUITO mais que isso, e cada volta do balanco
     cruzava o limiar de novo: um soco virava dois.

  E media numa escala que o jogo nao esperava. O `score_curve.gd` esta
  escrito para um firmware que mede HONESTAMENTE (0,3 a 5,2 m/s); a V2
  integrando por 400 ms produzia numeros varias vezes maiores. Dai
  "todos os impactos valiam a mesma coisa": tudo saturava no teto.

  ====================================================================
  COMO A V9 MEDE
  ====================================================================

  TRES ESTADOS SEPARADOS, e nenhum deles se confunde com o outro:
  porta aberta != placa identificada != sensor pronto e em repouso.

  A) LINHA DE BASE VIVA, em vez de um zero de uma vez so.
     Enquanto a maquina esta QUIETA, a base de cada eixo persegue a
     leitura crua devagar (constante de tempo ~2 s). Isso absorve
     gravidade, inclinacao da montagem e deriva termica sozinho. Quando
     ha movimento, a base CONGELA -- um soco nunca contamina o proprio
     zero.

  B) O SOCO SO PODE COMECAR A PARTIR DO REPOUSO.
     E preciso um periodo continuo de quietude (AMOSTRAS_DE_REPOUSO)
     antes de qualquer golpe ser aceito. Esta unica regra mata quatro
     coisas de uma vez: sensor parado, inclinacao sustentada, empurrao
     lento e a oscilacao depois do primeiro golpe.

  C) A FORMA DO EVENTO PRECISA SER DE SOCO.
     Subida rapida (o pico chega em ate SUBIDA_MAX_MS), amostras
     consecutivas acima do gatilho (um pico eletrico de uma amostra nao
     passa), e -- obrigatorio -- A QUEDA: o sinal precisa voltar para
     baixo do gatilho dentro da janela. Um empurrao sustentado nunca
     fecha essa forma, e por isso NAO VIRA GOLPE. A janela e curta
     (JANELA_MAX_MS), que e a duracao fisica de um impacto de verdade.

  D) A MEDIDA E A INTEGRAL, e o giroscopio e TESTEMUNHA, nao somatorio.
     A velocidade sai da integracao por trapezio da aceleracao dinamica,
     com a base congelada no instante do gatilho. O giroscopio serve
     para (i) confirmar que o alvo REALMENTE se moveu e (ii) substituir
     a medida quando o acelerometro satura. A V2 usava o MAIOR entre os
     dois e somava |gx|+|gy|+|gz| -- somar tres eixos so soma tres
     ruidos, e o "maior" deixava esse ruido inflar a nota.

  E) SEPARACAO EXPLICITA, que e o que o jogo pediu:
       - VALIDAR se foi um impacto fisico  -> B e C
       - MEDIR o impacto ja aceito          -> D
       - CONVERTER medida em pontuacao      -> NAO ACONTECE AQUI.
     A pontuacao e do `score_curve.gd`. Daqui sai medida em m/s, e nada
     mais. Nao ha newtons: nao ha modelo de massa nem calibracao de
     forca que sustente essa palavra, entao ela nao aparece.

  F) CALIBRACAO QUE SE RECUSA A CALIBRAR ERRADO.
     Ela mede a dispersao enquanto amostra. Se a maquina estava se
     mexendo, ela NAO grava o zero novo, mantem o anterior e avisa
     (ERROR,CALIB_MOVIMENTO). Um zero nascido torto era o defeito mais
     caro da V2, porque estragava a noite inteira em silencio.

  G) A SERIAL NUNCA FICA SURDA.
     A calibracao da V2 bloqueava por ~2 s (400 amostras x delay(5)),
     e nesse intervalo PING, START e CREDITO morriam -- bem no momento
     em que o jogo acabara de abrir a porta e estava decidindo se aquela
     COM tinha placa. Aqui a calibracao atende comandos e botoes a cada
     volta.
*/

/*  AS FITAS SAO OPCIONAIS -- E O SKETCH COMPILA SEM ELAS.

    O `#include` da biblioteca das fitas e condicional de proposito: numa
    IDE sem a Adafruit NeoPixel instalada, um include incondicional faz o
    sketch NAO COMPILAR, nao ha upload, e a placa continua com o firmware
    velho -- ou com nenhum. O sintoma nao e "as fitas nao acendem": e "o
    Arduino nao faz nada", com START e CREDITO mortos junto.
*/
#if defined(__has_include)
  #if __has_include(<Adafruit_NeoPixel.h>)
    #include <Adafruit_NeoPixel.h>
    #define TEM_FITAS 1
  #endif
#endif
#ifndef TEM_FITAS
  #define TEM_FITAS 0
  #warning "Adafruit NeoPixel nao encontrada: o jogo funciona, as fitas de LED ficam desligadas. Instale pelo Gerenciador de Bibliotecas para liga-las."
#endif

#define MPU_ADDR 0x68
#define PINO_SDA_I2C A4
#define PINO_SCL_I2C A5
#define PINO_BOTAO_START 2
#define PINO_BOTAO_CREDIT 3
#define PINO_BOTAO_CONFIG 9
#define LED_STATUS 13

/*  AS DUAS FITAS DE LED DA MAQUINA

    LIGACAO (WS2812B / NeoPixel, 5 V):
      dado da fita esquerda  -> D5   (com resistor de 330 ohm em serie)
      dado da fita direita   -> D6   (idem)
      +5 V e GND das fitas   -> FONTE PROPRIA de 5 V, nunca pelo Arduino
      GND da fonte           -> GND do Arduino (terra comum, obrigatorio)

    Trinta LEDs por fita a brilho maximo pedem quase dois amperes: tirar
    isso do regulador do Uno queima a placa. Um capacitor de 1000 uF
    entre +5 V e GND da fita, junto do primeiro LED, segura o pico.
*/
#define PINO_FITA_ESQ 5
#define PINO_FITA_DIR 6
#define LEDS_POR_FITA 30
#define BRILHO_FITA 140

#if TEM_FITAS
Adafruit_NeoPixel fitaEsq(LEDS_POR_FITA, PINO_FITA_ESQ, NEO_GRB + NEO_KHZ800);
Adafruit_NeoPixel fitaDir(LEDS_POR_FITA, PINO_FITA_DIR, NEO_GRB + NEO_KHZ800);
#endif

float nivelFita = 0.0f;
float nivelAlvo = 0.0f;
unsigned long fitaComandadaMs = 0;
unsigned long ultimaFitaMs = 0;
const unsigned long FITA_COMANDO_VALE_MS = 3000;
const unsigned long FITA_QUADRO_MS = 25;
float velocidadeMaxima = 5.20f;   // teto da coluna; igual ao teto do jogo

// Prototipos declarados a mao: assim o arquivo compila como C++ comum e
// da para conferir a compilacao fora da IDE do Arduino.
void executarComando(const char *cmd);
void configurar(const char *cmd);
bool calibrar();
void enviarTelemetria();
void processarAmostra();
void processarBotoes();
void processarComandos();
bool mpuVivo();
bool mpuResponde(uint8_t endereco);
bool ligarMpu();
void insistirNoMpu();
void enviarPinos();
char eixoDominante();
float magnitudeGiro(const float *g);
void enviarStatus();
void recusar(const __FlashStringHelper *motivo, unsigned long duracao);
void escreverReg(uint8_t reg, uint8_t valor);
void atualizarFitas();
bool mpuLer(float *accelG, float *gyroDps);
void iniciarI2CSeguro();
void recuperarBarramentoI2C();

/*  A PLACA FUNCIONA COM OU SEM O SENSOR. */
bool mpuPronto = false;
bool calibracaoConcluida = false;
bool calibrandoAgora = false;
unsigned long ultimaTentativaMpu = 0;
uint8_t enderecoMpu = MPU_ADDR;
uint8_t falhasMpuConsecutivas = 0;
unsigned long ultimoAvisoMpuMs = 0;
const uint8_t FALHAS_MPU_ATE_RECUPERAR = 4;

// Escalas do MPU-6050 com a configuracao abaixo (+/-16 g, +/-2000 graus/s).
const float LSB_POR_G = 2048.0f;
const float LSB_POR_DPS = 16.4f;

// Ritmo de amostragem e da telemetria.
const unsigned long AMOSTRA_US = 4000;      // 250 Hz
const unsigned long TELEMETRIA_MS = 250;

/*  ------------------------------------------------------------------
    OS NUMEROS DA DETECCAO, e o raciocinio de cada um.
    ------------------------------------------------------------------ */

/*  O QUE CONTA COMO "QUIETO".
    Com o MPU na escala de +/-16 g, um LSB vale 1/2048 g. O ruido tipico
    de repouso fica bem abaixo de 0,05 g; 0,12 g da folga para vibracao
    de salao (som alto, gente passando, ventilador do gabinete) sem
    deixar passar movimento de verdade. */
/*  ESTES SAO O PISO E O TETO, e o valor de verdade e MEDIDO.

    Um limiar de ruido fixo pressupoe que todas as montagens vibram
    igual. Nao vibram: um gabinete com caixa de som dentro, um ventilador,
    o piso de um salao com gente pulando -- qualquer um deles mantem o
    sensor permanentemente acima de 0,12 g, e ai a placa NUNCA considera
    a maquina "quieta". Sem quietude nao ha autorizacao de soco, e sem
    autorizacao NENHUM golpe e aceito. A maquina fica muda, e nada na
    tela diz por que.

    Agora a calibracao MEDE a dispersao do proprio repouso desta montagem
    e o piso sai dela (quatro vezes a dispersao observada), preso entre
    estes dois limites. Montagem silenciosa ganha um piso baixo e
    sensivel; montagem barulhenta ganha um piso alto e continua
    funcionando. */
const float RUIDO_G_MIN = 0.08f;
const float RUIDO_G_MAX = 0.60f;
const float RUIDO_DPS_MIN = 10.0f;
const float RUIDO_DPS_MAX = 80.0f;
float ruidoG = 0.12f;
float ruidoDps = 15.0f;

/*  QUANTO TEMPO DE QUIETUDE ANTES DE ACEITAR UM SOCO.
    50 amostras a 250 Hz = 200 ms. E a regra que sozinha resolve
    "sensor parado dispara", inclinacao sustentada, empurrao lento e
    rebote: nenhum deles apresenta 200 ms de quietude antes do evento. */
const uint16_t AMOSTRAS_DE_REPOUSO = 50;

/*  A JANELA DO IMPACTO.
    Um soco num saco/alvo e um evento de dezenas de milissegundos. 160 ms
    cobre o impacto inteiro com folga; passar disso e balanco, nao soco.
    Era 400 ms na V2 -- tempo de sobra para a deriva virar velocidade. */
const unsigned long JANELA_MS = 140;

/*  A SUBIDA PRECISA SER RAPIDA.
    Num impacto o pico chega quase junto com o inicio. Um empurrao
    forte, ainda que passe do gatilho, sobe devagar. 70 ms separa os
    dois sem apertar demais um golpe fraco e legitimo. */
const unsigned long SUBIDA_MAX_MS = 100;

/*  A QUEDA E OBRIGATORIA.
    O evento so fecha quando o sinal volta abaixo de gatilho*FATOR_QUEDA
    e fica la por MS_DE_QUEDA. Sinal que NAO cai dentro da janela e
    inclinacao ou empurrao sustentado, e e descartado sem virar golpe. */
const float FATOR_QUEDA = 0.35f;
const unsigned long MS_DE_QUEDA = 24;

/*  Duas amostras consecutivas acima do gatilho. Um pico eletrico de uma
    amostra so -- ruido de I2C, interferencia do cabo -- nao passa. */
const uint8_t AMOSTRAS_DE_SUBIDA = 2;

/*  Duracao minima de um impacto real. Abaixo disso e artefato. */
const unsigned long DURACAO_MIN_MS = 14;

/*  ACIMA DESTE PICO, A PLACA NAO DISCUTE.
    Seis g num alvo, partindo do repouso e com a forca saindo dentro da
    janela, e um soco. Nenhuma vibracao de gabinete, nenhum encostar e
    nenhum empurrao chega a isso. Ver `pancada_inequivoca`. */
const float PICO_INEQUIVOCO_G = 6.0f;

/*  TEMPO MORTO, contado do FIM do golpe aceito.
    Maior que o balanco tipico do alvo. Alem dele, o proximo golpe ainda
    precisa dos 200 ms de repouso -- sao duas travas, nao uma. */
const unsigned long TEMPO_MORTO_MS = 1200;

/*  O giroscopio como TESTEMUNHA: o alvo precisa ter se mexido de
    verdade. Um tranco no gabinete sacode o acelerometro sem girar o
    pendulo. Valor baixo de proposito -- e prova de movimento, nao
    medida de forca, e golpe fraco legitimo precisa passar. */
/*  E CONFIGURAVEL, E O PADRAO CAIU DE 25 PARA 6.

    Vinte e cinco graus por segundo pressupoe que o alvo BALANCA. Num
    saco pendurado, balanca. Num alvo parafusado em estrutura rigida --
    que e uma montagem perfeitamente comum -- o acelerometro ve a pancada
    inteira e o giroscopio quase nao se mexe: a exigencia de giro sozinha
    rejeita TODO soco, e a maquina fica muda sem dizer por que.

    Seis graus por segundo ainda separa um soco de verdade de um tranco
    no gabinete, e nao exige que o alvo gire. Quem tiver um pendulo pode
    subir pela Central. E, se ainda assim atrapalhar, `0` desliga a
    testemunha: com `REJECT` na tela da para saber se e este o problema
    antes de mexer. */
float giroMinimoDps = 6.0f;

/*  Velocidade com que a base persegue a leitura crua ENQUANTO QUIETO.
    0,002 por amostra a 250 Hz da constante de tempo de ~2 s: rapido o
    bastante para acompanhar a maquina sendo reposicionada, lento o
    bastante para nao comer o comeco de um soco. */
const float BASE_ALFA = 0.002f;

// Configuracao ativa (chega pelo comando CONFIG; padroes sensatos).
char eixoMedicao = 'X';
float raioMetros = 0.45f;
/*  O PISO DE VELOCIDADE ACOMPANHA O PISO DA PONTUACAO.
    Era 0,8 aqui contra 0,30 no `score_curve.gd`: a faixa 0,30-0,80
    existia na curva e era jogada fora pelo firmware, ou seja, golpe
    fraco legitimo sumia antes de chegar ao jogo. */
float velocidadeMinima = 0.30f;
float accelMinG = 2.50f;

// Linha de base viva (em g e em graus/s).
float baseAccel[3] = {0, 0, 0};
float baseGyro[3] = {0, 0, 0};
bool baseIniciada = false;

// Estado da medicao em andamento.
bool golpeAtivo = false;
bool baseValida = false;
unsigned long golpeInicioMs = 0;
unsigned long golpeAbaixoMs = 0;
unsigned long instanteDoPicoMs = 0;
float picoG = 0.0f;
float velocidadeIntegral = 0.0f;
float velocidadePico = 0.0f;
float picoGyroDps = 0.0f;
float aAnterior = 0.0f;
float direcao[3] = {1.0f, 0.0f, 0.0f};   // direcao do impacto, congelada no gatilho
float baseCongelada[3] = {0, 0, 0};
uint8_t amostrasAcima = 0;
bool saturouAccel = false;
bool saturouGyro = false;
bool caiu = false;
unsigned long fimDoUltimoGolpeMs = 0;

// Contador de quietude.
uint16_t amostrasQuietas = 0;
/*  A TRAVA DE REPOUSO, e por que ela e um ESTADO e nao uma pergunta.

    "A maquina esta em repouso?" perguntado a cada amostra nunca pode
    autorizar um soco: a amostra que inicia o golpe ja nao esta quieta, e
    a seguinte ja tem o contador zerado pela primeira. Medido na bancada:
    a placa rejeitava repouso, inclinacao, empurrao e ruido -- e rejeitava
    junto TODOS os socos de verdade.

    Entao o repouso vira uma AUTORIZACAO que se conquista e se gasta: ela
    acende depois de AMOSTRAS_DE_REPOUSO amostras quietas seguidas, e so
    apaga quando um golpe comeca, e aceito, ou e descartado. Depois disso
    e preciso ficar quieto de novo para reconquista-la. E isso que impede
    o rebote do saco de virar um segundo soco: entre uma volta e outra do
    balanco nunca ha 200 ms de quietude. */
bool prontoParaGolpe = false;

// Ultima medida, para a telemetria.
float ultimaVelocidade = 0.0f;
float ultimoPicoG = 0.0f;

/*  A forca do ultimo instante, em g. E o que a telemetria mostra: com a
    maquina parada ela fica perto de zero, e isso se confere a olho. */
float ultimaForca = 0.0f;

unsigned long ultimaAmostraUs = 0;
unsigned long ultimaTelemetriaMs = 0;

/*  BUFFER DE COMANDO EM char[], e nao em String.
    O `String` do Arduino fragmenta os 2 KB de RAM do ATmega328P ao
    longo de horas de operacao. Numa maquina que fica ligada a noite
    toda, isso termina em travamento sem causa aparente. */
char bufferSerial[52];
uint8_t bufferUso = 0;

// ---------------------------------------------------------------- MPU-6050
/*  I2C COM PRAZO, INDEPENDENTE DA VERSAO DA IDE.

    `Wire.requestFrom()` pode bloquear para sempre em versoes antigas do
    core AVR quando SDA ou SCL ficam presas por ruido, fio longo ou mau
    contato. Se isso acontece aos 70% da calibracao, a serial tambem para,
    o jogo fecha a COM e o reset recomeca tudo -- exatamente o ciclo visto
    na maquina.

    Este mestre I2C pequeno usa os mesmos A4/A5, em aproximadamente
    100 kHz, e TODA espera por SCL tem prazo. Se o barramento prender, a
    leitura falha, nove pulsos o soltam e o loop continua atendendo serial
    e botoes. Nao depende de `Wire.setWireTimeout`, portanto se comporta
    igual em Uno/Nano antigos e novos. */
const unsigned long I2C_TIMEOUT_US = 3000;
bool i2cFalhou = false;

void i2cBaixo(uint8_t pino) {
  pinMode(pino, OUTPUT);
  digitalWrite(pino, LOW);
}

void i2cSolto(uint8_t pino) {
  pinMode(pino, INPUT_PULLUP);
}

bool i2cEsperarAlto(uint8_t pino) {
  i2cSolto(pino);
  const unsigned long inicio = micros();
  while (digitalRead(pino) == LOW) {
    if ((unsigned long)(micros() - inicio) >= I2C_TIMEOUT_US) return false;
  }
  return true;
}

void i2cPausa() { delayMicroseconds(4); }

bool i2cInicio() {
  i2cSolto(PINO_SDA_I2C);
  if (!i2cEsperarAlto(PINO_SCL_I2C)) return false;
  i2cPausa();
  if (digitalRead(PINO_SDA_I2C) == LOW) return false;
  i2cBaixo(PINO_SDA_I2C);
  i2cPausa();
  i2cBaixo(PINO_SCL_I2C);
  return true;
}

void i2cFim() {
  i2cBaixo(PINO_SDA_I2C);
  i2cPausa();
  if (!i2cEsperarAlto(PINO_SCL_I2C)) i2cFalhou = true;
  i2cPausa();
  i2cSolto(PINO_SDA_I2C);
  i2cPausa();
}

bool i2cEscreverByte(uint8_t valor) {
  for (uint8_t mascara = 0x80; mascara != 0; mascara >>= 1) {
    if (valor & mascara) i2cSolto(PINO_SDA_I2C); else i2cBaixo(PINO_SDA_I2C);
    i2cPausa();
    if (!i2cEsperarAlto(PINO_SCL_I2C)) { i2cFalhou = true; return false; }
    i2cPausa();
    i2cBaixo(PINO_SCL_I2C);
  }
  i2cSolto(PINO_SDA_I2C);
  i2cPausa();
  if (!i2cEsperarAlto(PINO_SCL_I2C)) { i2cFalhou = true; return false; }
  const bool confirmou = digitalRead(PINO_SDA_I2C) == LOW;
  i2cPausa();
  i2cBaixo(PINO_SCL_I2C);
  return confirmou;
}

uint8_t i2cLerByte(bool confirmar) {
  uint8_t valor = 0;
  i2cSolto(PINO_SDA_I2C);
  for (uint8_t i = 0; i < 8; i++) {
    valor <<= 1;
    if (!i2cEsperarAlto(PINO_SCL_I2C)) { i2cFalhou = true; return 0; }
    i2cPausa();
    if (digitalRead(PINO_SDA_I2C) == HIGH) valor |= 1;
    i2cBaixo(PINO_SCL_I2C);
    i2cPausa();
  }
  if (confirmar) i2cBaixo(PINO_SDA_I2C); else i2cSolto(PINO_SDA_I2C);
  i2cPausa();
  if (!i2cEsperarAlto(PINO_SCL_I2C)) i2cFalhou = true;
  i2cPausa();
  i2cBaixo(PINO_SCL_I2C);
  i2cSolto(PINO_SDA_I2C);
  return valor;
}

void recuperarBarramentoI2C() {
  i2cSolto(PINO_SDA_I2C);
  i2cSolto(PINO_SCL_I2C);
  i2cPausa();
  for (uint8_t i = 0; i < 9 && digitalRead(PINO_SDA_I2C) == LOW; i++) {
    i2cBaixo(PINO_SCL_I2C);
    i2cPausa();
    i2cEsperarAlto(PINO_SCL_I2C);
    i2cPausa();
  }
  i2cFalhou = false;
  i2cFim();
  i2cFalhou = false;
}

void iniciarI2CSeguro() {
  i2cSolto(PINO_SDA_I2C);
  i2cSolto(PINO_SCL_I2C);
  recuperarBarramentoI2C();
}

void escreverReg(uint8_t reg, uint8_t valor) {
  i2cFalhou = false;
  if (!i2cInicio()) { recuperarBarramentoI2C(); return; }
  if (!i2cEscreverByte((uint8_t)(enderecoMpu << 1)) ||
      !i2cEscreverByte(reg) || !i2cEscreverByte(valor)) i2cFalhou = true;
  i2cFim();
  if (i2cFalhou) recuperarBarramentoI2C();
}

bool mpuResponde(uint8_t endereco) {
  i2cFalhou = false;
  if (!i2cInicio()) { recuperarBarramentoI2C(); return false; }
  const bool respondeu = i2cEscreverByte((uint8_t)(endereco << 1));
  i2cFim();
  const bool ok = respondeu && !i2cFalhou;
  if (i2cFalhou) recuperarBarramentoI2C();
  return ok;
}

/*  O MPU-6050 pode estar em 0x68 ou 0x69, conforme o pino AD0. Modulo
    generico com AD0 em alta responde so no segundo -- e o sintoma e
    identico ao de sensor queimado. Procurar nos dois custa nada. */
bool mpuVivo() {
  if (mpuResponde(MPU_ADDR)) { enderecoMpu = MPU_ADDR; return true; }
  if (mpuResponde(MPU_ADDR + 1)) { enderecoMpu = MPU_ADDR + 1; return true; }
  return false;
}

bool mpuLer(float *accelG, float *gyroDps) {
  i2cFalhou = false;
  if (!i2cInicio()) { recuperarBarramentoI2C(); return false; }
  if (!i2cEscreverByte((uint8_t)(enderecoMpu << 1)) || !i2cEscreverByte(0x3B)) {
    i2cFim(); recuperarBarramentoI2C(); return false;
  }
  // Inicio repetido: seleciona o mesmo MPU agora em modo de leitura.
  i2cSolto(PINO_SDA_I2C);
  i2cPausa();
  if (!i2cEsperarAlto(PINO_SCL_I2C)) { i2cFim(); recuperarBarramentoI2C(); return false; }
  i2cPausa();
  i2cBaixo(PINO_SDA_I2C);
  i2cPausa();
  i2cBaixo(PINO_SCL_I2C);
  if (!i2cEscreverByte((uint8_t)((enderecoMpu << 1) | 1))) {
    i2cFim(); recuperarBarramentoI2C(); return false;
  }

  int16_t bruto[7];
  for (uint8_t i = 0; i < 7; i++) {
    const uint8_t alto = i2cLerByte(true);
    const uint8_t baixo = i2cLerByte(i < 6);
    bruto[i] = (int16_t)(((uint16_t)alto << 8) | baixo);
  }
  i2cFim();
  if (i2cFalhou) { recuperarBarramentoI2C(); return false; }
  // bruto[0..2] = accel, bruto[3] = temperatura, bruto[4..6] = giro
  saturouAccel = false;
  saturouGyro = false;
  for (uint8_t i = 0; i < 3; i++) {
    if (bruto[i] >= 32700 || bruto[i] <= -32700) saturouAccel = true;
    if (bruto[4 + i] >= 32700 || bruto[4 + i] <= -32700) saturouGyro = true;
    accelG[i] = (float)bruto[i] / LSB_POR_G;
    gyroDps[i] = (float)bruto[4 + i] / LSB_POR_DPS;
  }
  return true;
}

/*  ------------------------------------------------------------------
    CALIBRACAO QUE SE RECUSA A CALIBRAR ERRADO.
    ------------------------------------------------------------------
    A V2 gravava a media sem olhar a dispersao. Se alguem encostasse na
    maquina durante os 2 s da calibracao do arranque -- e no arranque
    alguem quase sempre esta com a mao na maquina --, o zero nascia
    torto e ficava torto. Dai o "sensor parado dispara" que nao tinha
    explicacao: o sensor estava parado, o ZERO e que estava errado.

    Agora a dispersao e medida junto. Se a maquina estava se mexendo, o
    zero anterior e mantido e o jogo e avisado.
*/
bool calibrar() {
  if (calibrandoAgora) return false;
  calibrandoAgora = true;
  calibracaoConcluida = false;
  const uint16_t AMOSTRAS = 300;      // 300 x 4 ms = 1,2 s
  float somaA[3] = {0, 0, 0};
  float somaG[3] = {0, 0, 0};
  float maxA[3], minA[3];
  float maxG = 0.0f, minG = 0.0f;
  bool primeira = true;
  uint16_t validas = 0;

  for (uint16_t n = 0; n < AMOSTRAS; n++) {
    float a[3], g[3];
    if (mpuLer(a, g)) {
      for (uint8_t i = 0; i < 3; i++) {
        somaA[i] += a[i];
        somaG[i] += g[i];
        if (primeira) { maxA[i] = a[i]; minA[i] = a[i]; }
        else {
          if (a[i] > maxA[i]) maxA[i] = a[i];
          if (a[i] < minA[i]) minA[i] = a[i];
        }
      }
      const float gm = sqrtf(g[0] * g[0] + g[1] * g[1] + g[2] * g[2]);
      if (primeira) { maxG = gm; minG = gm; }
      else {
        if (gm > maxG) maxG = gm;
        if (gm < minG) minG = gm;
      }
      primeira = false;
      validas++;
    }
    if (n % 30 == 0) {
      Serial.print(F("CALIBRATING,"));
      Serial.println((int)((long)n * 100L / (long)AMOSTRAS));
    }
    /*  A SERIAL NAO PODE FICAR SURDA AQUI.
        Este e exatamente o instante em que o jogo acabou de abrir a
        porta (o DTR resetou a placa) e esta decidindo se esta COM tem
        Arduino. Uma calibracao que nao responde PING faz o jogo
        descartar a porta CERTA e seguir procurando. */
    processarComandos();
    processarBotoes();
    delay(4);
  }

  if (validas < AMOSTRAS / 2) {
    Serial.println(F("ERROR,CALIB_LEITURA"));
    calibrandoAgora = false;
    return false;
  }

  // A maquina se mexeu durante a medida? Entao este zero nao presta.
  float dispersao = 0.0f;
  for (uint8_t i = 0; i < 3; i++) {
    const float d = maxA[i] - minA[i];
    if (d > dispersao) dispersao = d;
  }
  const float dispersaoGiro = maxG - minG;
  if (dispersao > RUIDO_G_MAX) {
    Serial.println(F("ERROR,CALIB_MOVIMENTO"));
    calibrandoAgora = false;
    return false;                   // mantem a base anterior, de proposito
  }

  for (uint8_t i = 0; i < 3; i++) {
    baseAccel[i] = somaA[i] / (float)validas;
    baseGyro[i] = somaG[i] / (float)validas;
  }
  baseIniciada = true;
  calibracaoConcluida = true;
  amostrasQuietas = 0;

  /*  O PISO DE RUIDO DESTA MONTAGEM, medido agora mesmo.
      Quatro vezes a dispersao do repouso: alto o bastante para a
      vibracao do gabinete nao contar como movimento, baixo o bastante
      para o comeco de um soco contar. */
  ruidoG = dispersao * 4.0f;
  if (ruidoG < RUIDO_G_MIN) ruidoG = RUIDO_G_MIN;
  if (ruidoG > RUIDO_G_MAX) ruidoG = RUIDO_G_MAX;
  ruidoDps = dispersaoGiro * 4.0f;
  if (ruidoDps < RUIDO_DPS_MIN) ruidoDps = RUIDO_DPS_MIN;
  if (ruidoDps > RUIDO_DPS_MAX) ruidoDps = RUIDO_DPS_MAX;

  Serial.print(F("NOISE,"));
  Serial.print(ultimaForca, 2);
  Serial.print(',');
  Serial.println(ruidoDps, 1);

  Serial.print(F("CALIBRATED,"));
  Serial.print(baseAccel[0], 3);
  Serial.print(',');
  Serial.print(baseAccel[1], 3);
  Serial.print(',');
  Serial.println(baseAccel[2], 3);
  calibrandoAgora = false;
  return true;
}

// ---------------------------------------------------------------- golpe
/*  ======================================================================
    A DETECCAO INTEIRA, E ELA CABE NUMA TELA.
    ======================================================================

    O QUE ESTAVA AQUI ANTES, E POR QUE SAIU.

    Esta funcao tinha SEIS validacoes empilhadas: autorizacao de repouso
    (200 ms de quietude antes de aceitar qualquer golpe), amostras
    consecutivas de subida, tempo maximo ate o pico, queda obrigatoria
    dentro da janela, testemunha do giroscopio, e duracao minima.

    Nenhuma delas foi jamais demonstrada necessaria numa maquina de
    verdade. Todas foram acrescentadas por precaucao, contra um problema
    -- "o sensor dispara parado" -- cuja causa real era OUTRA: a versao
    antiga media o zero de cada eixo uma unica vez, no arranque, e nunca
    mais. Montagem que inclinasse depois, ou alguem encostando na maquina
    durante a calibracao, e aquele zero nascia torto e ficava torto.

    Esse defeito esta consertado de outra forma, e de forma melhor: a
    LINHA DE BASE VIVA, logo abaixo. Ela persegue a leitura crua com
    constante de tempo de dois segundos. Gravidade, inclinacao da
    montagem e deriva termica somem sozinhas e continuamente. E um soco,
    que dura dezenas de milissegundos, nao chega a move-la: em 60 ms ela
    anda 3% na direcao do golpe.

    Com a base viva no lugar, as seis validacoes deixaram de defender de
    alguma coisa e passaram a ser apenas seis maneiras de recusar um soco
    legitimo -- em silencio. Duas delas comprovadamente recusavam: a
    testemunha do giro matava toda montagem rigida, e a exigencia de
    repouso morria em gabinete que vibra.

    O QUE FICOU:

      1. base viva          -> tira gravidade e inclinacao, sempre
      2. forca = |leitura - base|   -> magnitude, sem eixo para errar
      3. forca > gatilho    -> e um soco
      4. mede por 140 ms    -> pico e velocidade
      5. tempo morto        -> um soco conta uma vez

    Nao ha mais nenhum caminho por onde um golpe possa ser descartado
    calado. So existe UMA recusa, a velocidade abaixo do piso, e ela e
    reportada.
*/

void processarAmostra() {
	if (!calibracaoConcluida) return;
	float a[3], g[3];
	if (!mpuLer(a, g)) {
		/* Uma falha de I2C nao pode virar 250 linhas de erro por segundo.
		   Essa enxurrada ocupava a serial justamente quando o HIT precisava
		   passar. Quatro falhas seguidas tiram o MPU de servico; o loop
		   continua atendendo serial/botoes e `insistirNoMpu` religa sozinho. */
		if (falhasMpuConsecutivas < 255) falhasMpuConsecutivas++;
		if (falhasMpuConsecutivas >= FALHAS_MPU_ATE_RECUPERAR) {
			recuperarBarramentoI2C();
			mpuPronto = false;
			calibracaoConcluida = false;
			golpeAtivo = false;
			baseIniciada = false;
			digitalWrite(LED_STATUS, LOW);
			if (millis() - ultimoAvisoMpuMs > 1000) {
				Serial.println(F("ERROR,MPU_LEITURA"));
				ultimoAvisoMpuMs = millis();
			}
		}
		return;
	}
	falhasMpuConsecutivas = 0;

  const unsigned long agora = micros();
  float dt = (float)(agora - ultimaAmostraUs) / 1000000.0f;
  ultimaAmostraUs = agora;
  if (dt <= 0.0f || dt > 0.05f) dt = 0.004f;

  if (!baseIniciada) {
    for (uint8_t i = 0; i < 3; i++) { baseAccel[i] = a[i]; baseGyro[i] = g[i]; }
    baseIniciada = true;
    return;
  }

  /*  A LINHA DE BASE VIVA, e ela anda SEMPRE.

      Antes so andava "enquanto quieto", e decidir o que e quieto exigia
      um limiar de ruido -- que numa montagem que vibra nunca era
      atingido, deixando a maquina esperando para sempre um silencio que
      nao vinha. Andando sempre, o problema desaparece junto com o
      conceito: 0,002 por amostra a 250 Hz da constante de tempo de dois
      segundos, e nenhum soco dura isso. */
  for (uint8_t i = 0; i < 3; i++) {
    baseAccel[i] += (a[i] - baseAccel[i]) * BASE_ALFA;
    baseGyro[i] += (g[i] - baseGyro[i]) * BASE_ALFA;
  }

  float din[3];
  for (uint8_t i = 0; i < 3; i++) din[i] = a[i] - baseAccel[i];
  // A MAGNITUDE nao tem orientacao: nao ha eixo para o montador errar.
  const float forca = sqrtf(din[0] * din[0] + din[1] * din[1] + din[2] * din[2]);
  const float giro = magnitudeGiro(g);

  ultimaForca = forca;

  if (!golpeAtivo) {
    /*  DUAS AMOSTRAS SEGUIDAS, E NAO UMA.

        Medido na bancada: com uma so, picos ELETRICOS de uma unica
        amostra -- interferencia no cabo do I2C, que e comum -- geravam
        oito socos em dez segundos. Com duas, zero.

        E isto nao pode recusar um soco de verdade: a 250 Hz, um impacto
        de 40 ms ocupa dez amostras. Exigir duas e exigir 8 ms de sinal. */
    if (forca <= accelMinG) { amostrasAcima = 0; return; }
    amostrasAcima++;
    if (amostrasAcima < 2) return;
    amostrasAcima = 0;
    if (millis() - fimDoUltimoGolpeMs < TEMPO_MORTO_MS) return;

    // Comecou. A direcao do impacto sai do proprio impacto, e fica
    // congelada: e ao longo dela que a velocidade e integrada.
    golpeAtivo = true;
    golpeInicioMs = millis();
    picoG = forca;
    picoGyroDps = giro;
    velocidadeIntegral = 0.0f;
    velocidadePico = 0.0f;
    aAnterior = forca;
    for (uint8_t k = 0; k < 3; k++) {
      baseCongelada[k] = baseAccel[k];
      direcao[k] = din[k] / forca;
    }
    digitalWrite(LED_STATUS, HIGH);
    return;
  }

  // ------------------------------------------------ golpe em andamento
  float dinAgora[3];
  for (uint8_t k = 0; k < 3; k++) dinAgora[k] = a[k] - baseCongelada[k];
  const float aoLongo = dinAgora[0] * direcao[0]
                      + dinAgora[1] * direcao[1]
                      + dinAgora[2] * direcao[2];

  /*  Integracao por trapezio ao longo da direcao do impacto. A
      velocidade do golpe e o PICO da integral: depois dele vem a
      freada, que e fisica real e nao deve apagar a medida. */
  velocidadeIntegral += ((aAnterior + aoLongo) * 0.5f) * 9.81f * dt;
  aAnterior = aoLongo;
  if (velocidadeIntegral < 0.0f) velocidadeIntegral = 0.0f;
  if (velocidadeIntegral > velocidadePico) velocidadePico = velocidadeIntegral;

  if (forca > picoG) picoG = forca;
  if (giro > picoGyroDps) picoGyroDps = giro;

  const unsigned long duracao = millis() - golpeInicioMs;
  if (duracao < JANELA_MS) return;

  // ------------------------------------------------ fecha e reporta
  golpeAtivo = false;
  digitalWrite(LED_STATUS, LOW);
  fimDoUltimoGolpeMs = millis();

  /*  A FORCA AINDA ESTA LA NO FIM DA JANELA? ENTAO NAO FOI UM SOCO.

      Esta e a UNICA validacao de forma que sobreviveu, e ela sobreviveu
      porque a bancada mostrou que sem ela um empurrao lento e sustentado
      vira um soco de 5,12 m/s -- ou seja, empurrar o alvo devagar
      pontuaria mais que um golpe medio.

      O que a separa das cinco que eu removi e que ela NAO PODE recusar
      um soco: o contato de um impacto acaba em algumas dezenas de
      milissegundos, e esta janela tem 140. Um soco, aos 140 ms, ja
      caiu a quase nada. Uma forca que continua em 60% do proprio pico
      aos 140 ms e alguem empurrando -- nao ha golpe assim. */
  if (forca >= picoG * 0.6f) {
    recusar(F("SUSTENTADO"), duracao);
    return;
  }

  if (saturouAccel) Serial.println(F("SATURATION,ACCEL"));
  if (saturouGyro) Serial.println(F("SATURATION,GYRO"));

  float velocidade = velocidadePico;
  // O giroscopio so entra quando o acelerometro saturou e a medida dele
  // deixou de valer. Fora disso ele nao opina.
  if (saturouAccel) {
    const float vGiro = (picoGyroDps * 0.01745329f) * raioMetros;
    if (vGiro > velocidade) velocidade = vGiro;
  }

  ultimaVelocidade = velocidade;
  ultimoPicoG = picoG;

  /*  A UNICA RECUSA QUE SOBROU -- e ela fala.
      Encostar no alvo nao pode virar pontuacao, mas tambem nao pode
      sumir calado: se este piso estiver alto demais para esta montagem,
      a linha de REJECT na Central diz isso na hora. */
  if (velocidade < velocidadeMinima) {
    recusar(F("FRACO"), duracao);
    return;
  }

  // A fita sobe no mesmo instante do golpe, sem esperar o jogo.
  const float faixa = velocidadeMaxima - velocidadeMinima;
  float f = (faixa > 0.01f) ? (velocidade - velocidadeMinima) / faixa : 0.0f;
  if (f < 0.0f) f = 0.0f;
  if (f > 1.0f) f = 1.0f;
  if (f > nivelAlvo) nivelAlvo = f;

  Serial.print(F("HIT,"));
  Serial.print(velocidade, 2);
  Serial.print(',');
  Serial.print(picoG, 2);
  Serial.print(',');
  Serial.print(duracao);
  Serial.print(',');
  Serial.println(eixoDominante());
}

/*  Qual eixo levou a maior parte do impacto. So para a tela. */
char eixoDominante() {
  const float x = fabsf(direcao[0]), y = fabsf(direcao[1]), z = fabsf(direcao[2]);
  if (x >= y && x >= z) return 'X';
  return (y >= z) ? 'Y' : 'Z';
}

/*  A magnitude do giro. Somar |gx|+|gy|+|gz| somaria tres ruidos. */
float magnitudeGiro(const float *g) {
  const float x = g[0] - baseGyro[0];
  const float y = g[1] - baseGyro[1];
  const float z = g[2] - baseGyro[2];
  return sqrtf(x * x + y * y + z * z);
}

/*  TODA RECUSA FALA, COM OS NUMEROS DO EVENTO.
    `REJECT,<motivo>,<pico_g>,<duracao_ms>,<giro_dps>,<velocidade>` */
void recusar(const __FlashStringHelper *motivo, unsigned long duracao) {
  Serial.print(F("REJECT,"));
  Serial.print(motivo);
  Serial.print(',');
  Serial.print(picoG, 2);
  Serial.print(',');
  Serial.print(duracao);
  Serial.print(',');
  Serial.print(picoGyroDps, 1);
  Serial.print(',');
  Serial.println(velocidadePico, 2);
}

/*  O ESTADO CRU DOS DOIS PINOS, QUATRO VEZES POR SEGUNDO.
    `PINS,1,0` quer dizer START apertado, CREDITO solto. Com INPUT_PULLUP
    o pino em repouso le ALTO e o aperto o leva ao terra, entao o valor
    aqui ja vai invertido: 1 e APERTADO. Se este numero nao muda quando o
    botao e apertado, o problema e ANTES do firmware. */
/*  O ESTADO DA DETECCAO, quatro vezes por segundo.

    `STATUS,<pronto>,<quietas>,<ruidoG>,<gatilho>`

    `pronto` e 1 quando a placa ja tem a autorizacao de aceitar um soco.
    SE ELE FICAR EM 0 COM A MAQUINA PARADA, esta e a resposta inteira: a
    montagem nunca fica quieta o bastante, nenhum golpe sera aceito, e o
    caminho e recalibrar (a calibracao mede o ruido desta montagem) ou
    olhar o que vibra. Sem este numero, "nada acontece" nao se distingue
    de "o sensor nao esta ligado". */
void enviarStatus() {
  /*  `STATUS,<medindo>,<forca_agora_g>,<gatilho_g>`

      `forca_agora` e a aceleracao ja SEM a gravidade. Com a maquina
      parada ela fica perto de zero -- e isso se confere a olho na
      Central, sem interpretar nada. Se ela nao se mexer quando alguem
      bate no alvo, o problema e o sensor ou o fio, e nao o jogo. */
  Serial.print(F("STATUS,"));
  Serial.print(golpeAtivo ? 1 : 0);
  Serial.print(',');
  Serial.print(ultimaForca, 2);
  Serial.print(',');
  Serial.println(accelMinG, 2);
}


void enviarPinos() {
  Serial.print(F("PINS,"));
  Serial.print(digitalRead(PINO_BOTAO_START) == LOW ? 1 : 0);
  Serial.print(',');
  Serial.print(digitalRead(PINO_BOTAO_CREDIT) == LOW ? 1 : 0);
  Serial.print(',');
  Serial.println(digitalRead(PINO_BOTAO_CONFIG) == LOW ? 1 : 0);
}

// ---------------------------------------------------------------- botoes
void processarBotoes() {
  static bool antesStart = HIGH, antesCredit = HIGH, antesConfig = HIGH;
  static unsigned long tStart = 0, tCredit = 0, tConfig = 0;
  const bool start = digitalRead(PINO_BOTAO_START);
  const bool credit = digitalRead(PINO_BOTAO_CREDIT);
  const bool config = digitalRead(PINO_BOTAO_CONFIG);
  const unsigned long agora = millis();
  if (antesStart == HIGH && start == LOW && agora - tStart > 250) {
    tStart = agora;
    Serial.println(F("BUTTON,START"));
  }
  if (antesCredit == HIGH && credit == LOW && agora - tCredit > 250) {
    tCredit = agora;
    Serial.println(F("BUTTON,CREDIT"));
  }
  if (antesConfig == HIGH && config == LOW && agora - tConfig > 350) {
    tConfig = agora;
    Serial.println(F("BUTTON,CONFIG"));
  }
  antesStart = start;
  antesCredit = credit;
  antesConfig = config;
}

// ---------------------------------------------------------------- telemetria
/*  A TELEMETRIA MOSTRA A ACELERACAO DINAMICA, nao a crua.
    E o numero que a deteccao realmente usa. Mostrar o cru fazia a
    Central exibir ~1 g parado (a gravidade) e quem olhava concluia que o
    sensor estava enlouquecendo. Com o dinamico, sensor parado mostra
    zero -- e isso e verificavel a olho. */
void enviarTelemetria() {
  if (!mpuPronto || !calibracaoConcluida || !baseIniciada || golpeAtivo) return;
  float a[3], g[3];
  if (!mpuLer(a, g)) return;
  Serial.print(F("TELEMETRY,"));
  Serial.print(a[0] - baseAccel[0], 2); Serial.print(',');
  Serial.print(a[1] - baseAccel[1], 2); Serial.print(',');
  Serial.print(a[2] - baseAccel[2], 2); Serial.print(',');
  Serial.print(g[0] - baseGyro[0], 1); Serial.print(',');
  Serial.print(g[1] - baseGyro[1], 1); Serial.print(',');
  Serial.print(g[2] - baseGyro[2], 1); Serial.print(',');
  Serial.print(ultimaVelocidade, 2); Serial.print(',');
  Serial.println(ultimaForca, 2);
}

// ---------------------------------------------------------------- comandos
void processarComandos() {
  while (Serial.available() > 0) {
    const char c = (char)Serial.read();
    if (c == '\n' || c == '\r') {
      if (bufferUso > 0) {
        bufferSerial[bufferUso] = '\0';
        executarComando(bufferSerial);
        bufferUso = 0;
      }
    } else if (bufferUso < sizeof(bufferSerial) - 1) {
      bufferSerial[bufferUso++] = c;
    }
  }
}

void executarComando(const char *cmd) {
  // Comparacao sem diferenciar maiuscula, sem alocar String.
  if (strcasecmp(cmd, "PING") == 0) {
    Serial.println(F("PONG"));
  } else if (strcasecmp(cmd, "RESET") == 0) {
    golpeAtivo = false;
    prontoParaGolpe = false;
    amostrasAcima = 0;
    amostrasQuietas = 0;
    digitalWrite(LED_STATUS, LOW);
    Serial.println(F("OK,RESET"));
  } else if (strcasecmp(cmd, "CALIBRATE") == 0) {
    if (mpuPronto && calibrar()) Serial.println(F("OK,CALIBRATE"));
  } else if (strcasecmp(cmd, "TEST") == 0) {
    /*  Golpe sintetico: confere a corrente inteira -- Arduino, serial e
        jogo -- sem ninguem socar o saco. Se o TEST aparece na tela e o
        soco real nao, o problema e mecanico, nao de software.
        O valor fica no meio da escala nova (0,30 a 5,20 m/s). */
    Serial.print(F("HIT,2.60,8.00,45,"));
    Serial.println(eixoMedicao);
  } else if (strncasecmp(cmd, "LEDS,", 5) == 0) {
    long permil = atol(cmd + 5);
    if (permil < 0) permil = 0;
    if (permil > 1000) permil = 1000;
    nivelAlvo = (float)permil / 1000.0f;
    fitaComandadaMs = millis();
  } else if (strncasecmp(cmd, "CONFIG,", 7) == 0) {
    configurar(cmd);
  } else {
    Serial.println(F("ERROR,COMANDO"));
  }
}

/*  CONFIG,eixo,raio,vmin,amin[,vmax]
    A placa REVALIDA tudo: um valor absurdo vindo de um arquivo de
    ajustes corrompido nao pode virar uma maquina que nunca detecta nada
    (ou que detecta tudo). */
void configurar(const char *cmd) {
  char copia[52];
  strncpy(copia, cmd, sizeof(copia) - 1);
  copia[sizeof(copia) - 1] = '\0';

  char *campo = strtok(copia, ",");      // "CONFIG"
  campo = strtok(NULL, ",");             // eixo
  if (campo == NULL) { Serial.println(F("ERROR,CONFIG")); return; }
  const char e = (char)toupper(campo[0]);
  if (e == 'X' || e == 'Y' || e == 'Z') eixoMedicao = e; else eixoMedicao = 'X';

  campo = strtok(NULL, ",");             // raio
  if (campo == NULL) { Serial.println(F("ERROR,CONFIG")); return; }
  raioMetros = constrain(atof(campo), 0.05f, 1.50f);

  campo = strtok(NULL, ",");             // vmin
  if (campo == NULL) { Serial.println(F("ERROR,CONFIG")); return; }
  velocidadeMinima = constrain(atof(campo), 0.10f, 20.0f);

  campo = strtok(NULL, ",");             // amin
  if (campo == NULL) { Serial.println(F("ERROR,CONFIG")); return; }
  accelMinG = constrain(atof(campo), 0.5f, 15.0f);

  campo = strtok(NULL, ",");             // vmax (opcional)
  if (campo != NULL) {
    velocidadeMaxima = constrain(atof(campo), velocidadeMinima + 0.5f, 40.0f);
  }

  // Sexto campo, opcional: o giro minimo. `0` desliga a testemunha.
  campo = strtok(NULL, ",");
  if (campo != NULL) {
    giroMinimoDps = constrain(atof(campo), 0.0f, 400.0f);
  }

  Serial.println(F("OK,CONFIG"));
}

/*  A COR DE CADA ALTURA -- a mesma escala do jogo: do azul frio ao
    branco estourado, e a fita repete essa escala de baixo para cima. */
#if TEM_FITAS
uint32_t corDaAltura(float f, Adafruit_NeoPixel &fita) {
  if (f < 0.25f)      return fita.Color(0, 90, 200);
  else if (f < 0.50f) return fita.Color(0, 200, 140);
  else if (f < 0.70f) return fita.Color(230, 190, 0);
  else if (f < 0.88f) return fita.Color(255, 90, 0);
  else                return fita.Color(255, 255, 255);
}
#endif

void atualizarFitas() {
#if TEM_FITAS
  const unsigned long agora = millis();
  if (agora - ultimaFitaMs < FITA_QUADRO_MS) return;
  ultimaFitaMs = agora;

  // Passados tres segundos sem comando do jogo, a placa volta a se virar
  // sozinha -- a fita continua funcionando com o PC desligado.
  if (agora - fitaComandadaMs > FITA_COMANDO_VALE_MS) {
    nivelAlvo *= 0.94f;      // decai devagar depois do golpe
    if (nivelAlvo < 0.004f) nivelAlvo = 0.0f;
  }

  nivelFita += (nivelAlvo - nivelFita) * 0.25f;
  if (fabsf(nivelAlvo - nivelFita) < 0.002f) nivelFita = nivelAlvo;

  const int acesos = (int)(nivelFita * (float)LEDS_POR_FITA + 0.5f);
  for (int i = 0; i < LEDS_POR_FITA; i++) {
    const float altura = (float)(i + 1) / (float)LEDS_POR_FITA;
    const uint32_t cor = (i < acesos) ? corDaAltura(altura, fitaEsq) : 0;
    fitaEsq.setPixelColor(i, cor);
    fitaDir.setPixelColor(i, cor);
  }
  fitaEsq.show();
  fitaDir.show();
#endif
}

void setup() {
  Serial.begin(115200);
  pinMode(PINO_BOTAO_START, INPUT_PULLUP);
  pinMode(PINO_BOTAO_CREDIT, INPUT_PULLUP);
  pinMode(PINO_BOTAO_CONFIG, INPUT_PULLUP);
  pinMode(LED_STATUS, OUTPUT);
  digitalWrite(LED_STATUS, LOW);

#if TEM_FITAS
  fitaEsq.begin(); fitaEsq.setBrightness(BRILHO_FITA); fitaEsq.show();
  fitaDir.begin(); fitaDir.setBrightness(BRILHO_FITA); fitaDir.show();
#endif

  /*  O `READY` SAI ANTES DE QUALQUER COISA QUE POSSA FALHAR.

      A placa SEMPRE chega ao `loop()`. Sem sensor ela avisa, segue
      funcionando -- botoes, serial, fitas -- e tenta o sensor de novo a
      cada dois segundos. Um fio de I2C mal encaixado que alguem empurre
      de volta passa a funcionar sozinho, sem desligar nada.

      E o `READY` vem primeiro porque e ele que faz o jogo reconhecer
      esta COM como sendo a do Arduino. Qualquer coisa antes dele que
      possa travar -- procurar sensor, calibrar -- e uma porta certa
      sendo descartada como muda. */
  Serial.println(F("READY,PUNCH_MPU6050,V10"));

	iniciarI2CSeguro();

  ultimaAmostraUs = micros();

  if (ligarMpu()) {
    if (calibrar()) {
      /* OK,MPU agora significa sensor CALIBRADO, nao apenas encontrado. */
      Serial.println(F("OK,MPU"));
    } else {
      mpuPronto = false;
    }
  } else {
    Serial.println(F("ERROR,NO_MPU"));
  }
  ultimaAmostraUs = micros();
}

/*  Acorda o MPU e o deixa na escala do jogo. Devolve falso se ele nao
    responde -- e nesse caso a placa continua trabalhando sem ele. */
bool ligarMpu() {
  recuperarBarramentoI2C();
  if (!mpuVivo()) {
    mpuPronto = false;
    return false;
  }
  escreverReg(0x6B, 0x01);   // PWR_MGMT_1: acorda, clock do giroscopio X
  escreverReg(0x1A, 0x03);   // CONFIG: DLPF ~44 Hz -- corta ruido, mantem o golpe
  escreverReg(0x1B, 0x18);   // GYRO_CONFIG: +/-2000 graus/s
  escreverReg(0x1C, 0x18);   // ACCEL_CONFIG: +/-16 g
  delay(50);
  mpuPronto = true;
  calibracaoConcluida = false;
  baseIniciada = false;      // base nova para um sensor recem-ligado
  return true;
}

/*  Tenta o sensor de novo, de dois em dois segundos, enquanto ele
    faltar. E o que permite consertar um fio com a maquina ligada. */
void insistirNoMpu() {
  if (mpuPronto) return;
  const unsigned long agora = millis();
  if (agora - ultimaTentativaMpu < 2000) return;
  ultimaTentativaMpu = agora;
  digitalWrite(LED_STATUS, !digitalRead(LED_STATUS));
  if (ligarMpu()) {
    digitalWrite(LED_STATUS, LOW);
    if (calibrar()) Serial.println(F("OK,MPU"));
    else mpuPronto = false;
  }
}

void loop() {
  // A ORDEM IMPORTA: botoes e serial vem PRIMEIRO, e sem condicao
  // nenhuma. Eles nao dependem do sensor e nao podem ficar presos a ele.
  processarComandos();
  processarBotoes();
  insistirNoMpu();

  if (mpuPronto && (long)(micros() - ultimaAmostraUs) >= (long)AMOSTRA_US) {
    processarAmostra();
  }
  if (millis() - ultimaTelemetriaMs >= TELEMETRIA_MS) {
    ultimaTelemetriaMs = millis();
    enviarTelemetria();
    enviarPinos();
    enviarStatus();
  }
  atualizarFitas();
}
