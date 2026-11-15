# Transcrição · Consulta com o professor (2026-11-11)

Fonte: áudio `WhatsApp Audio 2026-11-11 at 21.39.32.opus` (18 min 40 s).

Transcrição automática feita com Whisper `large-v3-turbo` (faster-whisper, idioma `pt`).
**Não foi revisada.** Há trechos com erros de reconhecimento: por exemplo, "aí de vídeo" é
"ID de vídeo", "polvor" é "povoar", "chave surrogate não gera retominação" provavelmente é
"não gera redundância", "crocas"/"fachas" são as FKs e "explainanalyzer" é `EXPLAIN ANALYZE`.
Entre 15:42 e 16:06 o áudio fica inaudível.

O resumo e o plano de ação estão em [CONSULTA_PROFESSOR.md](CONSULTA_PROFESSOR.md).

Formato: `[mm:ss]` é o início do trecho no áudio.

---

[00:00] A primeira coisa que eu fiz foi com relação à criação das configurações, eu criei um modelo de dados inicial, eu criei lá um DDL para representar exatamente o que estava na área que você tinha mostrado.  
[00:15] Luiz, vocês não podem fugir, cara, dessa estrutura do relacional aqui.  
[00:20] Perfeito.  
[00:21] Perfeito. Então, por exemplo, não pode criar coluna, não pode excluir coluna, não pode excluir coluna que está sem, não pode tirar atributo derivado que está aqui, por exemplo, beleza?  
[00:32] Perfeito.  
[00:32] Tá bom.  
[00:33] Tá. Aí o que eu fiz, né? Eu peguei e montei. Aí, para olhar esse modelo aqui e ver, tipo, com relação à redundância, onde estava a redundância, vou dar um exemplo.  
[00:42] Tipo, essa, esse canal, né? Eu criei o ID canal e adicionei as outras chaves como...  
[00:50] Como unique.  
[00:51] Isso, como unique. Eu criei uma unique com a identidade que ele coloca dentro dos requisitos.  
[00:55] No canal, no caso, é número, plataforma e nome.  
[00:58] Isso.  
[00:58] Beleza.  
[01:00] É... Aí, beleza. Aí a partir de, assim...  
[01:03] Aí essa chave se propaga depois.  
[01:04] Se propaga depois para os outros. E, por exemplo, coisas que eu tenho que melhorar aqui ainda, né?  
[01:08] Por relação ao comentário, né? Eu não pensei ainda. Eu fiz uma... Ah, estava com uma chave composta aqui, né?  
[01:13] Mas ela não tem como ser isso, que não seja composta. Por exemplo, ó, o carro que você criou o ID canal.  
[01:18] Ela vai se propagar, por exemplo, com a patrocínio.  
[01:21] Certo.  
[01:22] Aí a chave de patrocínio vai passar a ser número empresa e ID canal.  
[01:26] Certo.  
[01:26] E vai ter uma chave unique...  
[01:28] É...  
[01:30] Não, tá certo. Vai só isso. Número empresa e ID canal.  
[01:34] Número empresa e ID canal.  
[01:35] Beleza. Então tá.  
[01:36] Então, só para eu garantir que ela vai se propagando.  
[01:38] Isso.  
[01:39] Aí ela vai se propagar eventualmente para vídeo.  
[01:42] Aí vídeo você pode melhorar também.  
[01:43] Que tá número... É, título e data hora.  
[01:46] Isso.  
[01:47] Aí você pode criar um ID do vídeo.  
[01:49] Aqui é uma situação que você pode manter ID do canal e do vídeo.  
[01:54] Caso você ache que a chave que você tem não é suficiente para representar a quantidade de vídeos.  
[01:59] Certo.  
[02:00] Ou só criar um ID do vídeo se você tiver um atributo que você tem para representar todos os vídeos que você tem lá na sua plataforma.  
[02:06] É, como é que eu tomo essa decisão no sentido de, é, eu imagino que essa tabela de vídeos, a quantidade de registro dentro dela vai crescer exponencialmente.  
[02:13] Ela vai, ela vai crescer exponencialmente.  
[02:16] Aí é o que você tem que pensar.  
[02:17] Mas, só, só, só com o produto, Davidinho, é, é, é, porque, por exemplo, se eu for usar uma carta proposta, eu entendo que eu tenho um ganho, né, relacionado a eu fazer uma consulta por canal e vídeo e conseguir obter todos os vídeos daquele canal em específico.  
[02:30] Por exemplo, além de conseguir guardar todos os vídeos.  
[02:32] É, além de conseguir guardar todos os vídeos, mas, por outro lado, eu tenho uma duplicação, né, do, não, mas o ID do canal sempre vai ter uma duplicação.  
[02:40] Você não sempre vai ter duplicação.  
[02:41] Sim.  
[02:42] Não vou ter.  
[02:43] A decisão aí é só, a chave surrogate não gera retominação.  
[02:48] Certo.  
[02:49] É.  
[02:50] Mas aqui eu teria que colocar uma chave composta, né?  
[02:52] Você vê o que você falou?  
[02:53] Não necessariamente, por exemplo.  
[02:54] Você pode falar, cara, não vai entrar vídeo de Tik Tok aqui, por exemplo.  
[02:57] Aí eu acho que o vídeo segura.  
[02:58] Então, eu vou supor, né?  
[02:59] E eu acho que não tem, né?  
[03:00] Se você olhar, ela é só para streamer.  
[03:02] Streamer sério.  
[03:03] Então, não vai entrar, ela segura.  
[03:07] Agora, o comentário, com certeza, não vai segurar.  
[03:09] Tá.  
[03:10] Mais argumentos que você quer quando eu for trazer as decisões do porquê eu tomei essa decisão.  
[03:15] E é só isso em relação a cardinalidade.  
[03:17] Você fala, cara, eu to trabalhando com o tipo do dado que eu espero que vai entrar no  
[03:22] universo de TV.  
[03:23] É um tipo de vídeo longo, acima de 5 minutos.  
[03:27] Certo.  
[03:28] E a quantidade de vídeos produzidos.  
[03:30] Aí você pode tirar uma média lá.  
[03:31] Pode até vir com a CorelD, mas você tem um vazamento melhor de luz.  
[03:35] Mas você vai ver, cara, se você ficar filmando 24 horas todos os streamers o tempo todo  
[03:40] e fazendo um vídeo a cada 10 minutos, você vai ver que você não vai conseguir estourar o  
[03:44] aí de vídeo, por exemplo.  
[03:46] Certo.  
[03:47] Beleza.  
[03:48] Você vai ter uma noção para isso.  
[03:49] Agora, se o cara fica mandando um short de 10 em 10 segundos e replicando isso para  
[03:54] 60 plataformas, aí não vai ter como, entendeu?  
[03:57] É.  
[03:58] E outra coisa.  
[03:59] Tem uma das constraints lá embaixo do trabalho, né?  
[04:03] Que ela fala sobre as tabelas que elas tem que ter entre...  
[04:06] Acho que é o número 1 aqui do jeito de mandatório, né?  
[04:09] Ela tem que ter entre 3 mil.  
[04:11] Isso aqui é um valor pequeno que está aí só de referência para a gente ter uma  
[04:16] ideia.  
[04:17] Eu não espero que você vá colocar 10 mil no país, porque não tem ela para colocar.  
[04:21] Exato.  
[04:22] Eu fiz isso.  
[04:23] Eu assumi isso.  
[04:24] Falei, não, beleza.  
[04:25] Isso aqui é só para falar, cara, tenta polvor o seu banco.  
[04:29] Até com esse PDF, o ministro, esses números estão bem baixinhos.  
[04:34] Porque a gente fazia a instalação no curso, no outro lugar na página de tamanho menor e  
[04:38] tal.  
[04:39] Minha sugestão é polvor o máximo que você conseguir, idealmente com centenas de milhares  
[04:43] de tuplas.  
[04:44] Agora, a única coisa é tentar pensar em uma distribuição do dado que seja realística.  
[04:49] Certo.  
[04:50] Então, você vai ter canais que tem mais vídeos do que outros, bem mais.  
[04:54] E você vai ter vídeos que vão ter muito mais comentários do que outros.  
[04:57] Sim, sim.  
[04:58] Então, é uma distribuição desbalanceada para tentar fazer um mirror da realidade.  
[05:02] Ou um conteúdo, não precisa ser um conteúdo verdadeiro.  
[05:06] Pode ser um conteúdo totalmente artificial, tá bom?  
[05:08] É, então o nosso seed está nessa linha mesmo, né?  
[05:12] Eu botei desbalanceado, em relação aos comentários, alguns vídeos com mais comentários, outros  
[05:18] com menos.  
[05:19] Foi muito nessa linha.  
[05:20] Tipicamente, um vídeo que tem, tipo, 300 milhões de comentários, ele tem 300 milhões de visualizações,  
[05:25] ele tem muito comentários.  
[05:26] Sim, sim.  
[05:27] Então, você tem algumas relações que você pode usar isso, que você pode usar tranquilamente.  
[05:31] Aí, isso aqui é por causa do cara querer fazer um crawler, entendeu?  
[05:34] Aí, tá, essa informação está nesse sentido.  
[05:37] Tá, entendi.  
[05:38] É, tá, beleza.  
[05:40] Aí, só para entender também, né?  
[05:42] Com relação a como a gente está seguindo a metodologia do trabalho, eu...  
[05:45] Então, ele vai de vídeo só para fechar, né?  
[05:47] Não está errado, beleza?  
[05:48] Que só...  
[05:49] Aí, é bom que o aí de comentário, o comentário vai ficar com o aí de vídeo, você conhece,  
[05:53] você conhece isso aí, entendeu?  
[05:55] Aham.  
[05:56] Toma cuidado aqui com...  
[05:57] É, beleza.  
[05:58] Esse cara tem a chave estrangeira, né?  
[05:59] Tem para...  
[06:00] Usuário, no caso, né?  
[06:01] O nick usuário aqui, ó.  
[06:02] É.  
[06:03] Aí, tá passando por vídeo também?  
[06:04] Não, não.  
[06:05] O nick usuário tem que ter uma referência com a tabela usuário, que o cara fez comentário.  
[06:10] Tem, tem.  
[06:11] Aqui, ó.  
[06:12] Pô, por que você não colocou um ID usuário nesse cara?  
[06:13] Não, eu ainda não mexi no usuário, não.  
[06:14] Eu peguei a parte de canal, aí eu fui vendo todas as tabelas de vídeo.  
[06:15] Isso é a principal que vai ser cascateada, né?  
[06:16] É, é porque eu...  
[06:17] Assim, eu li canal e vídeo, eu li cheio de relação, aí eu falei assim, tá, beleza.  
[06:18] Vou conversar por ela, acho que...  
[06:19] É, isso, é isso.  
[06:20] Ela é a...  
[06:21] Ela é só as principais.  
[06:22] É, aí quando...  
[06:23] Porque assim, quando eu mudei o ID canal aqui, eu vi, caraca...  
[06:25] É, tá, beleza.  
[06:26] Aí, beleza.  
[06:27] Aí, beleza.  
[06:28] É só pra entender aqui o relacionamento do hoje é o trabalho, né?  
[06:41] Eu tô...  
[06:43] É...  
[06:44] Eu criei aqui a...  
[06:47] As fachas.  
[06:48] Isso, as crocas aqui, como...  
[06:50] As fachas, não é?  
[06:52] Beleza.  
[06:54] aí beleza aí eu queria as funções e daí para adicionar as para adicionar os índices né que  
[07:03] que eu tô fazendo eu tô basicamente olhando as que a gente definiu aqui eu vou dar uma coisa  
[07:07] que a gente definiu aqui eu vou dar uma coisa ainda mas eu vejo os três casos aí eu e se você  
[07:11] vai olhar as coisas vai olhar a complexidade das coisas e a similaridade do predicado das  
[07:16] queres só a cara isso aqui porque você vai olhar a similaridade e você vai olhar a similaridade  
[07:22] não faz sentido ter o índice ou se não vai adiantar nada porque a distribuição é tão pesada que a  
[07:26] questão 3 da p2 por exemplo a distribuição é tão pesada que não compensa ter o índice sim e depois  
[07:32] você vai olhar o predicado da da distribuição tão pesada que não compensa ter o índice aí você  
[07:38] não vai ter o índice ah não tá tá entendi tipo você tem uma coluna tipo e daí você vai ter uma  
[07:44] distribuição que não faz sentido é bom suposto que você fazer sequencial lá se fosse só tem dados  
[07:50] streamers americanos aí você tem lá tudo o país e os estados unidos aí vai filtrar todo mundo que é  
[07:55] do mesmo lugar não adianta você criar um índice ali sim depois você vai olhar o predicado para verificar  
[08:00] o tipo do índice que você tem que criar certo e a gente discutiu o hash p3 e aí a partir do do tipo  
[08:06] do predicado você vai falar o cara que é um hash isso tipicamente vão ser índices secundários que  
[08:12] vão envolver parte da chave primária anterior sim sim e eventualmente vão ser índices hash é e uma coisa que  
[08:16] eu tinha percebido isso ao longo da matéria mas confirmou aí que é os predicados eles não mudam  
[08:21] geralmente então mesmo que você vá fazer mudar aqui e ali eles continuam os mesmos ali né isso é  
[08:25] interessante exatamente mas aí eu fiz isso assim eu não trabalhei um com as queridos porque eu  
[08:30] voltei o passo melhor o melhor que você conseguir as consultas porque aí os índices vão assim em cima  
[08:35] disso agora você consegue até isso se o índice é bom é isso que o outro grupo tava aqui falando isso que eu  
[08:39] vou chegar lá calma é que eu também pensei nisso eu escutei o seu falando na saída também eu queria te  
[08:46] perguntar como que eu faço isso eu sei que tem a explainanalyzer ali você vai usar explainanalyzer  
[08:50] mas aí antes e depois você vai fazer isso você vai tirar antes e vai rodar pegar a medida só qual o  
[08:56] problema o sdb tem cache então se ficar mandando a query ele vai quebrar eu tô rodando no docker aí  
[09:02] você vai mandar o comando e pegar a resposta do comando pra ver o cp o time daquele treco mas você  
[09:10] vai não esquecer de pegar direto já que você tá usando o docker você vai mandar o comando e pegar a  
[09:27] do comando pra ver o cp o time daquele treco mas você vai não esquece do cash é a mensagem principal  
[09:35] isso é muito mais fácil de ver também que o outro grupo tava falando quando você tem muitos dados que  
[09:40] por exemplo a gente discutiu aqui na aula 1 que a gente traz esses dados de bloco né parece bobeira mas é a  
[09:47] hora que você vai olhar pra cara no bloco do post eu tô conseguindo guardar mil comentários dois mil  
[09:52] então assim aí o cara bota lá 10 mil comentários aí roda o índice na verdade não aconteceu nada que ele  
[10:01] fez um swap colocou aquilo ali em memória principal e acabou assim só é uma petri de uma folha que é uma  
[10:08] raiz né então se você quiser ter uma medida é mais tranquila você realmente vai precisar povoar algumas  
[10:14] tabelas mais que as que você tava relacionado com o índice que você criou obviamente né é aí você vai ter o  
[10:21] efeito de verdade no índice que assim um dois três swaps dois swaps que você fizer a diferença vai ser muito  
[10:27] grande de exerção entendeu é agora só toma cuidado com isso porque um bloco cabe muita coisa não parece  
[10:33] mas um bloco cabe coisa para caramba então toma esse cuidado aí tá beleza aí eu só tento tomar aqui a gente  
[10:41] tava falando sobre você falou das consultas tá das consultas beleza você falou dos predicados com relação à  
[10:47] a similaridade né ver se a distribuição da tabela né tá aí com relação a como eu vou te apresentar  
[10:56] decisões que a gente tomou né é eu posso atingir a isso dentro de um celular que vai me ter aqui é na  
[11:02] verdade o que vai vai acontecer é o seguinte vocês vão me mandar um arquivo entre três e cinco arquivos mas  
[11:11] basicamente vai ser tipo um ddl que tem todas as tabelas todos os links um workload vai ser um arquivo os  
[11:18] dados que vocês usaram pelo menos um sample que eu consiga reproduzir aqui certo é e um dml que vão ter  
[11:25] basicamente todas as consultas para rodar para eu responder aquelas consultas eventualmente eu vou ver  
[11:30] porque tem uns caras que estão fazendo umas triggers muito esquisitos e eu acho que eu vou colocar as triggers  
[11:35] separadas para não ter problema na hora de fazer inserção que o caderno você entra em um pi quase que infinito  
[11:40] é é isso esses vão entregar um pdf com as decisões do projeto que pode ser gerado a partir do markdown que  
[11:47] você está colocando muito curto tipo duas páginas só para explicar quais foram as decisões tá bom pode  
[11:54] comentar bem o código o código eu vou rodar aí é prefiro que você deixe outras informações que não são  
[12:01] as decisões projetos agora tá aí eu tenho mais dúvidas aqui relacionados ao nosso mini mundo né é nos um  
[12:09] mundo a gente tem aqui né a definição de que quer dizer não só no mini mundo né mas no nosso modelo de  
[12:16] dados eu tenho esse cara aqui né que é o que é o que é o conversão e que é que conversa isso país conversão  
[12:27] e eu tenho a moeda isso no país eu tenho a moeda e daí eu queria entender eu vou usar essa conversão a  
[12:38] partir do país do usuário para definir essa é uma decisão de projeto eu tô me dizendo que sim eu tô  
[12:43] fazendo por quê tanto para doação quanto para o da empresa a empresa tem relação com o país tem também  
[12:50] que eu estou usando todos os dois tá bom então é beleza é aceitável coloca lá no indicativo agora tem  
[12:55] duas coisas para você pensar a empresa tem vários pode ser a empresa e usuário na verdade só que  
[13:00] exatamente não usuário tem país só né usuário não pode ter até país de residência isso mas a empresa  
[13:08] não a empresa tá falando por causa do patrocínio é o patrocínio é mas aí o patrocínio pode assumir que é  
[13:18] o patrocínio já coloca o valor armazenado eu acho que eu entendi o que você falou é porque se eu  
[13:26] fosse pegar o valor é não não o patrocínio tu bota em dólar porque o patrocínio tem tem tem um  
[13:32] contrato externo vai dar uma noite se a gente tentar fazer isso sim bota sempre em dólar agora a conversão  
[13:37] você pode tentar fazer de duas formas diferentes da doação especificamente é só o país de residência né  
[13:44] é isso que a gente está falando aí você tem duas opções possíveis mas é isso mesmo ou você faz a  
[13:59] conversão no momento da doação e guarda em dólar o valor da doação já dolarizado ou no momento da consulta se  
[14:06] converte do do do do do do país do carro para ter que fazer uma consulta eu tô fazendo com a semane que  
[14:13] é bem diferente né para para para pensar assim o valor é o valor histórico dolarizado e o outro  
[14:19] valor é o valor corrigido dolarizado só tem que tomar esse cuidado assim é o ruim é porque eu vou ter  
[14:24] uma mesma tabela diferentes tipos de moeda né e já não vou saber porque lá por exemplo a tabela não  
[14:30] as duas estão certas só que a consulta ela recupera o valor corrigido certo então não é o valor que o  
[14:36] cara realmente em bolso é um valor que o cara o patrimônio correspondente ao que o cara o cara que  
[14:42] o cara vale é um é tipo o word word né não o net word word da doação e a outra é o quanto o cara botou no  
[14:50] bolso não tem uma diferença porque pra é até engraçado que pra o tipo de sistema que a gente tá fazendo o  
[14:56] o outro é mais importante até porque isso aqui é feito para escolher quem é o canal você vai  
[15:01] patrocinar entendeu aí é pra isso que tá aí então o outro do cara não necessariamente o conteúdo  
[15:05] botou no bolso mas eu contei que ele vale eu vou ter que mudar essa aqui ó então não pensa as duas  
[15:10] alternativas estão corretas não tem não tem nenhuma correta a maior parte tá fazendo armazenado  
[15:14] você falando você falando eu acho que vai mais sentido você ver sei lá coberta sempre com a droga e  
[15:23] a gente não tem site aqui né eu tô fazendo isso aqui no btl mesmo é mas não tem essa essa lógica de  
[15:30] não não precisa agora você tem uma fonte a prova beleza mas eu posso colocar isso lá na decisão também  
[15:36] não tem problema de você fazer consulta ali né de uma coisa assim que a gente tá  
[16:06] com as triggers né com relação com as triggers ali cara tinha uma outra dúvida que eu tinha  
[16:11] é tá lembrei tem um campo aqui que é quantidade alguma coisa acho que é o quantidade a quantidade  
[16:20] de visualizações essa é a quantidade total de publicações que o canal já teve certo é mas aí  
[16:25] essa quantidade de visualizações ela é a soma da quantidade de visualizações dos vídeos né  
[16:29] essencialmente você pode considerar isso como valor médio e você faria porque a forma do cálculo não tá aí né  
[16:36] se você achar te atribuir para fazer você pode fazer ela relativa que é o que a soma de quantidade  
[16:41] de visualizações dos vídeos pela quantidade de vídeos certo ou a soma bruta de quantidade de  
[16:45] visualizações dos vídeos seria meio ruim porque com o tempo esse número vai começar a crescer mas  
[16:50] mas não vai não vai estourar se você colocar um valor bem grande a quantidade de visualizações  
[16:59] não vai estourar só beleza não dá para pegar e quebrar esse número também não dá não sei se eu  
[17:07] pensar numa matemática que se divide de 100 por cento ou por mil por milhão você só vai para segunda  
[17:14] o segundo caso que é a quantidade de visualizações de vídeos é uma rede assim acho que vale a pena guardar a  
[17:24] total só uma todos os vídeos e isso aí toda vez que você fizer um instante na tabela de vídeo que  
[17:32] tem ou fazer um malter table né que tenha até ação aí aí você tem que pensar na trilha  
[17:38] tá perfeito é é isso que acontece também na quantidade de usuários lá sim sim sim eu sei que tem dois campos do que eu  
[17:48] eu ia falar isso tem dois campos de quantidade que eu falei cara eu acho que precisa de uma trilha né  
[17:53] os dois por cento isso acho que de resto a redundância eu acho que esses campos aqui debaixo também  
[18:02] tem qual tipo um vídeo se quiser comentário certo do assunto mas eu acho que você falava que não tem muito para  
[18:12] isso aqui né não vai ter muito bem porque eu vou botar aqui um somente para a gente não falei certo né  
[18:23] falei certo né porque eu ia criar uma chave isso aí mas não tem como mas não tem como já estourou bem  
[18:32] tá fechou eu acho que é isso professor  
