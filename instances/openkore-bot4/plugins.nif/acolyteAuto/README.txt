acolyteAuto - OpenKore
=======================

O que o plugin faz
------------------
1. Inicia automaticamente quando e carregado.
2. Se o personagem ainda for Novice e estiver abaixo do Job 10:
   - tenta equipar itens iniciais de Novice/Aprendiz encontrados no inventario;
   - distribui pontos somente em NV_BASIC, ate o nivel 9;
   - vai para prt_fild08;
   - ataca os monstros do mapa, mas bloqueia Creamy.
3. Quando atingir Job 10 e NV_BASIC 9:
   - vai para a igreja de Prontera;
   - executa a quest classica de Acolyte do rAthena;
   - detecta as quests 1001, 1002 ou 1003;
   - visita Rubalkabara, Mathilda ou Yosuke;
   - volta para Father Mareusis e conclui a mudanca de classe.
4. Depois de virar Acolyte:
   - volta para prt_fild08;
   - treina ate Job 12;
   - NAO distribui pontos de habilidade de Acolyte;
   - restaura as configuracoes anteriores e finaliza.

Instalacao
----------
Copie a pasta acolyteAuto para:

  openkore/plugins/acolyteAuto/

O arquivo deve ficar assim:

  openkore/plugins/acolyteAuto/acolyteAuto.pl

No console do OpenKore, carregue com:

  plugin load acolyteAuto

O processo comeca automaticamente.

Comandos
--------
  acolyteAuto status
  acolyteAuto start
  acolyteAuto stop
  acolyteAuto reset

Tambem e possivel usar o alias:

  acoauto status

Observacoes importantes
-----------------------
- O plugin foi preparado para a quest padrao do rAthena pre-renewal e inclui
  tolerancia para a versao Renewal simplificada.
- O servidor oRO pode ter alterado mapas, coordenadas, falas, respostas ou IDs.
- Se a conversa parar, copie o trecho do console desde "Talking to NPC" ate
  o erro. A sequencia do NPC precisara ser ajustada para o script do servidor.
- As alteracoes de attackAuto, lockMap e outras configuracoes sao feitas apenas
  em memoria. O plugin nao grava essas mudancas no config.txt.
- Para navegar entre mapas, o OpenKore precisa ter portals.txt/portalsLOS.txt
  corretos e estar recebendo os pacotes de mapa/NPC normalmente.
