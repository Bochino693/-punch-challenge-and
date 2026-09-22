/*
  TESTE DO SENSOR -- SEM O JOGO NO MEIO.

  Este sketch existe para responder UMA pergunta, em dois minutos, sem
  depender de nada que eu tenha escrito no jogo:

      O MPU-6050 esta entregando leitura quando voce soca?

  COMO USAR
  ---------
  1. Grave este sketch na placa (Ferramentas > Placa: Arduino Uno ou Nano).
  2. Abra FERRAMENTAS > PLOTTER SERIAL (nao o Monitor), em 115200.
  3. Deixe a maquina parada dez segundos. A linha tem de ficar rente ao
     zero.
  4. De um soco. A linha tem de dar um pico alto e voltar.

  O QUE CADA RESULTADO QUER DIZER
  -------------------------------
  - Linha no zero parada, PICO ALTO no soco  -> o sensor esta perfeito.
    O problema esta no meu codigo, e o numero do pico me diz qual limiar
    usar. Me mande esse numero.

  - Linha inquieta, subindo e descendo sozinha com a maquina parada
    -> vibracao na montagem, ou fio de I2C mal encaixado.

  - Linha reta em zero absoluto, sem mexer nem com o soco
    -> o sensor nao esta respondendo. E fio: confira SDA=A4, SCL=A5,
    VCC e GND. O sketch avisa no Monitor Serial se nao achar o MPU.

  O numero impresso e a ACELERACAO EM g, ja sem a gravidade: parado da
  perto de 0, e um soco de verdade passa de 3.
*/

#include <Wire.h>

uint8_t endereco = 0x68;
float base[3] = {0, 0, 0};
bool temBase = false;
float pico = 0.0f;
unsigned long picoEm = 0;

bool responde(uint8_t e) {
  Wire.beginTransmission(e);
  return Wire.endTransmission() == 0;
}

bool ler(float *g) {
  Wire.beginTransmission(endereco);
  Wire.write(0x3B);
  if (Wire.endTransmission(false) != 0) return false;
  if (Wire.requestFrom(endereco, (uint8_t)6) != 6) return false;
  for (uint8_t i = 0; i < 3; i++) {
    int16_t bruto = (int16_t)((Wire.read() << 8) | Wire.read());
    g[i] = (float)bruto / 2048.0f;   // escala +/-16 g
  }
  return true;
}

void setup() {
  Serial.begin(115200);
  delay(200);
  Wire.begin();
  Wire.setClock(400000);

  if (!responde(0x68) && !responde(0x69)) {
    Serial.println();
    Serial.println(F("SENSOR NAO ENCONTRADO."));
    Serial.println(F("Confira: SDA no A4, SCL no A5, VCC e GND."));
    Serial.println(F("(o modulo responde em 0x68 ou 0x69)"));
    while (true) { delay(1000); }
  }
  endereco = responde(0x68) ? 0x68 : 0x69;

  // Acorda o MPU na mesma escala que o jogo usa.
  Wire.beginTransmission(endereco); Wire.write(0x6B); Wire.write(0x01); Wire.endTransmission();
  Wire.beginTransmission(endereco); Wire.write(0x1A); Wire.write(0x03); Wire.endTransmission();
  Wire.beginTransmission(endereco); Wire.write(0x1C); Wire.write(0x18); Wire.endTransmission();
  delay(50);

  Serial.println();
  Serial.print(F("Sensor encontrado em 0x"));
  Serial.println(endereco, HEX);
  Serial.println(F("Abra o PLOTTER SERIAL. Parado = perto de 0. Soco = pico alto."));
  delay(600);
}

void loop() {
  float a[3];
  if (!ler(a)) {
    Serial.println(F("falha de leitura"));
    delay(200);
    return;
  }

  if (!temBase) {
    for (uint8_t i = 0; i < 3; i++) base[i] = a[i];
    temBase = true;
  }
  // A base persegue a leitura devagar: tira gravidade e inclinacao
  // sozinha, e nao alcanca um soco, que dura milissegundos.
  for (uint8_t i = 0; i < 3; i++) base[i] += (a[i] - base[i]) * 0.002f;

  const float x = a[0] - base[0], y = a[1] - base[1], z = a[2] - base[2];
  const float forca = sqrt(x * x + y * y + z * z);

  // Guarda o maior valor dos ultimos tres segundos, para dar tempo de
  // ler o numero do soco depois de bater.
  if (forca > pico) { pico = forca; picoEm = millis(); }
  if (millis() - picoEm > 3000) pico = 0.0f;

  // Duas linhas no plotter: a forca agora, e o maior pico recente.
  Serial.print(forca, 2);
  Serial.print(' ');
  Serial.println(pico, 2);
  delay(10);
}
