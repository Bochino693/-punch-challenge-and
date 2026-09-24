# Punch Challenge — build 77

Gere o APK como sempre (`GERAR_APK_AGORA.bat`) e instale por cima
(`INSTALAR_NA_TVBOX.bat`). Ranking e ajustes ficam.

## Pontuação mais volátil
- Nenhum número fixo: a nota sai de um sorteio em sino (±13%), com
  "dia bom / dia ruim" de vez em quando, tremido nos últimos dígitos e
  desvio de números redondos e de notas repetidas (memória das últimas 16).
- Acima de 8000 a subida é assintótica: passar de 8000 continua raro,
  passar de 9500 é raríssimo. O 9998 de "encostou no teto" acabou: quem
  encosta no teto cai espalhado entre ~9000 e ~9900; 9999 continua sendo
  o prêmio de 1 em 1000.

## Lutador novo: boxeador de verdade
Ver `LEIA-ME-LUTADOR-3D.txt`. Pés plantados com passos reais, IK de
pernas e braços, combinações de golpes, reações com mola, expressões no
rosto, festa longa com deboche quando o jogador perde.

## Torcida
- Plateia em silhueta no fundo da arena que pula e levanta os braços;
  telão rolando.
- Jogador perdeu (melhor soco < 4000): VAIA longa enquanto o lutador tira
  onda (a arena fica ~7 s no ar antes do ranking).
- Jogador ganhou (nocaute ou >= 6500): torcida agitada e festa longa.

## Soco na tela
Se o jogador demora (7 a 11 s sem bater), o lutador avança e soca a
câmera: a tela racha, escurece nas bordas e "cambaleia" com travadinhas
sorteadas — nunca duas vezes iguais.

## Sem engasgo na primeira vez
Enquanto a tela de carregamento está no ar, o jogo ensaia escondido cada
tela pesada (os 8 níveis do resultado, o círculo do placar, o anúncio
de NOVO CAMPEÃO, o Top 20, a rachadura, a contagem, os confetes) e o
lutador mostra todas as poses e expressões. Os shaders compilam e as
texturas sobem antes do primeiro soco do dia.
