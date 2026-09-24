# Super Boxing — build 83

## O que mudou
- **Nada acontece durante o carregamento além de carregar.** Câmera,
  Arduino e janelas de permissão só começam quando a barra termina. Antes,
  a janela do Android abria no meio do carregamento: o jogo pausava, a
  barra congelava e a janela às vezes nem aparecia.
- **O "86%" era um quadro só**, em que o jogo inteiro era montado (arena,
  lutador, câmera, USB). Agora a arena é montada no quadro seguinte, e
  câmera e USB ficam para depois do carregamento.
- **Permissões, simples e na ordem:**
  1. depois do carregamento aparece a janela de **CÂMERA** (só câmera,
     sem microfone);
  2. respondida essa, aparece a do **Arduino**. Marque a caixa e toque
     OK, só na primeira vez.
- **A câmera abre sozinha** assim que autorizada e confere de novo toda
  vez que o jogo volta para a frente (depois de uma janela, ou quando a TV
  Box acorda). Se parar de mandar imagem, ela é religada.
- **O jogo funciona com qualquer versão do plugin:** usa só as funções que
  todas as versões têm.

## Gerar
1. `PREPARAR_PLUGIN_USB_ANDROID.bat` (recomendado: a câmera fica mais
   leve e o Arduino abre sem travar o quadro)
2. `EXPORTAR_APK_ANDROID.bat`

Se preferir desinstalar o jogo antes de instalar esta versão, o Android
pergunta as permissões de novo, uma vez.
