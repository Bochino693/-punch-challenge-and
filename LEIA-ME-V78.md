# Super Boxing — build 78

Gere o APK como sempre (`GERAR_APK_AGORA.bat`) e instale por cima
(`INSTALAR_NA_TVBOX.bat`). Ranking e ajustes ficam.

## Visual do gabinete SUPER BOXING
- Fundo de raios roxo, magenta e azul sobre azul-noite, igual à arte da
  máquina (um pouco mais escuro, para as letras lerem de longe).
- Logo SUPER BOXING (estrela, R vermelho, luva no O), "FIGHT!" e
  "NEVER GIVE UP!" na abertura e na tela de espera.
- A arena ganhou a faixa zebrada amarelo/preto com cantos chanfrados, a
  mesma do vidro do gabinete; lona com o logo, cordas amarela/magenta/azul,
  telão rolando "SUPER BOXING • FIGHT! • NEVER GIVE UP!".
- Toda a paleta das telas (placar, cartões, Top 20, carregador) passou do
  vinho/vermelho para roxo/magenta com amarelo.
- LETRAS NA TV BOX: logo e chamadas são IMAGENS prontas, com mipmap
  (`tools/gerar_tema.py`). Nenhum letreiro novo depende da fonte ser
  rasterizada na hora — é o que evita o serrilhado e o engasgo antigos.

## Boxeador
- Botas de verdade: sola de borracha, biqueira redonda, cano alto,
  cadarço em relevo e aro dourado (não é mais a forma do pé pintada).
- Luvas novas, com polegar colado, velcro e punho que abraça o
  antebraço; o punho fica reto na guarda, então a luva não "desencaixa".
- Cinturão (cós) como peça acolchoada: SUPER BOXING na frente, LAZER
  SPORT atrás, estrelas, costura e frisos.
- Corpo 4x mais definido (subdivisão da malha: 62 mil triângulos na pele).
- A arena não reduz mais a resolução quando a TV Box aperta; o que cede
  é só o antisserrilhado.

## Fluidez
- O tremor e o zoom do golpe ficam SÓ dentro do quadro da arena; o resto
  da tela não se mexe.
- O soco na tela não congela mais nada: a câmera da arena balança liso e
  para, com a rachadura só no vidro do quadro.
- O rosto do lutador só é recalculado quando a expressão muda.
