class_name Versao
extends RefCounted

## O CARIMBO DA BUILD.
##
## Este é o número que responde à pergunta "atualizei a máquina e não
## mudou nada?". Ele aparece no rodapé da abertura e na Central Técnica,
## então basta olhar a tela do fliperama para saber qual versão está
## rodando — sem abrir terminal, sem conferir git.
##
## REGRA: sempre que uma mudança visível for para o repositório, suba o
## NUMERO em um e escreva em NOTA o que mudou. Um carimbo que não sobe
## mente, e um carimbo que mente é pior do que carimbo nenhum.

const NUMERO := 84
const DATA := "24/09/2026"
const NOTA := "câmera e Arduino só depois da abertura, em etapas; diário da inicialização; logos nítidas"

## Rodapé da abertura: cabe em uma linha discreta.
static func curta() -> String:
	return "BUILD %02d  •  %s" % [NUMERO, DATA]

## Central Técnica: aqui há espaço para a nota, que diz ao operador o que
## esperar de diferente nesta versão.
static func longa() -> String:
	return "BUILD %02d  •  %s  •  %s" % [NUMERO, DATA, NOTA]


## A PROVA DE QUE O ARQUIVO CHEGOU INTEIRO.
##
## Numa tela do gabinete, "CENTRAL TÉCNICA" apareceu com dois
## caracteres estranhos no lugar do "É", e "Configuração" com dois no
## lugar de cada acento. Isso não é fonte, nem Godot, nem tradução: é o
## ARQUIVO .gd tendo sido lido como Latin-1 e gravado como UTF-8 em
## algum momento — um script de PowerShell com `Get-Content` e
## `Set-Content` sem `-Encoding UTF8` faz exatamente isso, e o estrago
## fica gravado no fonte.
##
## (O exemplo estragado NÃO é reproduzido aqui de propósito: um arquivo
## que documenta a corrupção contendo a corrupção faz o verificador
## `tools/conferir_utf8.sh` acusar a si mesmo, e verificador que dá
## alarme falso é verificador que se aprende a ignorar.)
##
## Depois de estragado não há como adivinhar o texto certo. O que dá, e
## é o que importa, é a máquina PERCEBER e dizer, em vez de mostrar sopa
## de letra e deixar todo mundo procurando em fonte, em tradução e em
## configuração de tela.
##
## A prova: esta palavra tem TRÊS caracteres. Se o arquivo foi
## duplamente codificado, cada letra acentuada virou DUAS, e a mesma
## palavra passa a ter cinco. Um `length()` responde na hora, sem
## precisar comparar com nada.
const PROVA := "ção"

static func acentos_inteiros() -> bool:
	return PROVA.length() == 3

## O aviso, quando não estão.
static func recado_do_estrago() -> String:
	return "ARQUIVOS CORROMPIDOS NA CÓPIA — refaça o git clone (acentos duplicados)"
