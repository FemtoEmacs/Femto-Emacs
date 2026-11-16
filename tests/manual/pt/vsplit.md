# vsplit.md: teste de C-x 3 com o backdoor aberto

Deixe este roteiro no painel esquerdo e faça os testes no painel direito.
Digite só no painel direito; vsplit-test.md e vsplit-test.c (ao lado deste
arquivo) são descartáveis, altere-os à vontade.

O backdoor precisa estar configurado para este teste: o passo 0 copia
tests/manual/backdoor.conf para ~/.chezemax/backdoor-claude.conf.

**Se o cursor sumir em qualquer momento**, anote o passo sem mover nada:
M-: e depois (troque o número)

    (fe-backdoor-note "PASSO 7 cursor sumiu")

e continue. Se o próprio M-: não mostrar o cursor, digite às cegas; a nota
é registrada mesmo assim. O mesmo vale para qualquer coisa estranha:
"PASSO 5 a página pulou".

Enquanto o backdoor está aberto, a linha de modo (mode line) mostra B/D, e
um painel é estreito demais para B/D, os botões e o nome inteiro: o nome é
cortado à esquerda. Isso é esperado; também é esperado um nome cortado
("nal*") para *terminal*, cuja linha de modo também mostra Term.

## 0. Preparar e começar

Se você ainda não fez o teste natbrowser-interaction.org, instale o
Chezweb como diz o README.md do repositório (o .deb no Ubuntu, ou git
clone e make), e copie os testes e a configuração do backdoor, na pasta do
repositório (Femto-Emacs):

    cp -r tests/manual/pt ~/chezweb-testes
    mkdir -p ~/.chezemax
    cp tests/manual/backdoor.conf ~/.chezemax/backdoor-claude.conf

Depois:

    cd ~/chezweb-testes
    chezweb vsplit.md

### No Windows

O Chezweb abre pelo menu Iniciar. Se ainda não copiou os testes, baixe
o repositório (Code >
Download ZIP no GitHub), descompacte, e no Prompt de Comando (cmd), dentro
da pasta descompactada:

    mkdir "%USERPROFILE%\.chezemax"
    copy tests\manual\backdoor.conf "%USERPROFILE%\.chezemax\backdoor-claude.conf"
    xcopy /E /I tests\manual\pt "%USERPROFILE%\chezweb-testes"

Abra o Chezweb pelo menu Iniciar e dê C-x C-f chezweb-testes/vsplit.md
RET. A versão atual aceita caminhos do Windows e do Unix. No fim, o
registro está em
%USERPROFILE%\.chezemax\backdoor.txt:

    copy "%USERPROFILE%\.chezemax\backdoor.txt" "%USERPROFILE%\chezweb-testes\backdoor-vsplit.txt"

No passo 23, o M-x term do Windows abre o cmd: digite `dir` no lugar de
`ls`, e pule o `seq 1 100`. No passo 31, `echo hi` funciona igual.

1. M-x backdoor-claude (B/D aparece na linha de modo).

## 1. Dividir, mantendo a janela

2. C-v, depois C-n três vezes, de modo que o cursor fique na 4ª linha de
   uma janela rolada.
3. C-x 3. Os dois painéis devem mostrar as mesmas linhas de antes, com o
   cursor ainda na 4ª linha do painel esquerdo (e não na última).
4. C-x o: o cursor passa para o painel direito, na mesma linha.
5. C-x C-f vsplit-test.md RET no painel direito.

## 2. Digitar e mover no painel direito

6. Digite algumas palavras na primeira linha. O cursor acompanha cada
   caractere.
7. M-> e depois M-<: o fim e o início do arquivo.
8. C-s Coreano RET, depois C-n duas vezes: a linha em coreano. C-f várias
   vezes sobre 이상순 e os outros caracteres largos; C-e; C-a. O cursor
   nunca deve ficar entre as duas colunas de um caractere nem passar da
   barra.
9. Digite 가 no meio da linha em coreano (com a sua entrada de coreano),
   depois DEL.
10. C-s Acentos RET, C-n duas vezes, depois C-f sobre ação e coração;
    digite ã e DEL.
11. C-s longo RET, C-n duas vezes: o parágrafo quebrado. C-n e C-p pelas
    linhas dele; C-e numa dessas linhas.
12. C-v três vezes, depois M-v três vezes.

## 3. Um arquivo que não quebra as linhas

13. C-x C-f vsplit-test.c RET. C-n duas vezes: a linha longa.
14. C-e: o fim da linha visível. C-a, C-n, C-p.

## 4. O mouse

15. Clique numa palavra do painel esquerdo (este roteiro): o cursor vai
    para lá, e o painel esquerdo fica ativo. Não digite nada.
16. Clique numa palavra do painel direito: o cursor vai para lá, na coluna
    em que você clicou.
17. Role a roda do mouse para baixo e para cima sobre o painel direito,
    depois sobre o painel esquerdo.
18. Clique de novo no painel direito.

## 5. O mesmo arquivo nos dois painéis

19. C-x o (para o painel esquerdo), C-x b, digite vsplit-test.c, RET.
20. C-x o, digite XYZ no painel direito: aparece nos dois painéis; o
    cursor fica no painel direito.
21. C-x o, C-x b, digite vsplit.md, RET: este roteiro de novo à esquerda.
    C-x o.

## 6. O terminal no painel direito

22. M-x term RET no painel direito. O editor desenha o cursor do terminal
    como um bloco.
23. Digite `ls` RET, depois `seq 1 100` RET.
24. C-c o: de volta ao painel esquerdo, com o cursor visível lá. C-x o: de
    volta ao terminal.
25. C-c C-x C-c: a pergunta "A terminal is still running; quit anyway
    (y/n) ?" deve mostrar o cursor depois da pergunta. Responda n.
26. C-c M-x seguido de backdoor-claude fecharia o backdoor: não faça isso;
    só confira que C-c M-x mostra o cursor no minibuffer, depois C-g.
27. C-c o, para sair do terminal.

## 7. O que é recusado, e o encerramento

28. C-x 2 (você está no painel esquerdo): é recusado; a linha de mensagens
    diz "Vertically split panes do not accept further splits".
29. Com o mouse, deixe a janela do terminal mais estreita e depois mais
    larga. A barra e os dois painéis acompanham; o cursor continua
    visível.
30. C-x 0 no painel esquerdo: o painel esquerdo fecha e o terminal ocupa a
    tela inteira, com o bloco do cursor desenhado.
31. C-c C-x 3: dois painéis de novo, o terminal nos dois. Digite
    `echo hi` RET: aparece nos dois.
32. C-c C-x 1: um painel só, na largura toda.
33. C-c C-x b, digite vsplit.md, RET: este roteiro de novo.

## 8. Fechar o backdoor

34. M-x backdoor-claude (B/D desaparece).
35. C-x C-c; responda y às perguntas (os arquivos de teste e o terminal
    são descartáveis).

Depois guarde o registro do backdoor junto dos arquivos de teste:

    cp ~/.chezemax/backdoor.txt ~/chezweb-testes/backdoor-vsplit.txt

e envie a pasta ~/chezweb-testes para quem pediu o teste, ou peça ao Claude
da sua máquina, aberto na pasta do repositório, que confira o resultado
com tests/manual/EXPECTED.md.
