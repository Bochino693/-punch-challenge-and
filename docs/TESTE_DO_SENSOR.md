# Descobrir, em dois minutos, se o problema é o sensor ou o jogo

Enquanto essa pergunta não tiver resposta, qualquer conserto é chute.
Este teste responde sem o jogo no meio.

## O que fazer

1. Abra a IDE do Arduino.
2. Abra `arduino/teste_sensor/teste_sensor.ino`.
3. Grave na placa (Ferramentas → Placa: Arduino Uno ou Nano; a porta COM
   que aparecer).
4. Abra **Ferramentas → Plotter Serial** — o *Plotter*, não o Monitor —
   e ponha **115200** no canto.
5. Deixe a máquina parada por dez segundos.
6. Dê um soco.

## O que você vai ver, e o que cada coisa quer dizer

**Linha rente ao zero quando parado, PICO ALTO quando você soca**
→ O sensor está perfeito, e o problema é meu, no jogo.
Me diga **até quanto o pico subiu** (o segundo número, que fica
segurado por três segundos). Com esse número eu acerto o limiar de uma
vez, sem adivinhar.

**A linha fica inquieta sozinha, com a máquina parada**
→ Vibração na montagem ou fio de I2C mal encaixado. Balance o cabo com
o plotter aberto: se a linha pular, é o fio.

**Linha reta em zero, não mexe nem com o soco**
→ O sensor não está respondendo. É ligação: confira **SDA no A4**,
**SCL no A5**, o VCC e o GND. O sketch também avisa no Monitor Serial
se não encontrar o MPU (ele procura nos dois endereços, 0x68 e 0x69).

**Aparece "SENSOR NAO ENCONTRADO"**
→ O Arduino está vivo e o MPU não. É fio, ou o módulo está queimado.

## Depois do teste

Regrave o `arduino/punch_sensor/punch_sensor.ino` para voltar ao
firmware do jogo. O sketch de teste não fala com o jogo — ele serve só
para esta pergunta.
