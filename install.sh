#!/bin/bash


#will move Femto and femto.boot to /local/bin
#init.lst and r5rs to home
#Temporary solution .


chmod 777 femto 
cp femto /usr/local/bin
cp femto.boot /usr/local/bin
cp init.lsp ~/
cp r5rs.scm ~/
