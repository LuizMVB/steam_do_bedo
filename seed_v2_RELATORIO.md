# Relatório do `seed_v2.sql`

## Regra principal: o `seed_v2.sql` substitui o `seed.sql`

Este seed substitui o seed.sql; nunca execute os dois.

O `seed_v2.sql` é autossuficiente. Ele parte de um banco que tem só o schema do
`ddl.sql`, com todas as tabelas vazias, e gera tudo do zero, inclusive as
dimensões pequenas (`Conversao`, `Pais`, `Plataforma`, `Empresa`).

Ordem de execução exata:

```bash
psql -U admin -d steam-do-bedo-db -f ddl.sql
```

```bash
psql -U admin -d steam-do-bedo-db -f seed_v2.sql
```

Para recomeçar, rode o `ddl.sql` de novo (ele recria o schema) e depois o
`seed_v2.sql`.

## Como a independência é garantida

| Regra | Como o script cumpre |
|---|---|
| Banco vazio como premissa | Um bloco `DO` no início faz `SELECT count(*)` nas 20 tabelas. Se alguma tiver linhas, aborta com `RAISE EXCEPTION` e lista as tabelas ocupadas. Também aborta se o schema ou alguma tabela não existir. |
| Parar no primeiro erro | `\set ON_ERROR_STOP on` na primeira linha executável. Sem isso o `psql` seguiria executando os `INSERT` depois da falha da checagem. |
| Nada parcial | Tudo roda numa única transação (`BEGIN` … `COMMIT`). Qualquer erro desfaz a carga inteira. |
| Só dados próprios | Cada tabela é populada por `VALUES`, `generate_series` ou `JOIN` com tabelas que o próprio `seed_v2.sql` já populou. |
| Chaves de identidade | `Empresa.nro`, `Plataforma.nro`, `Canal.id_canal` e `Video.id_video` nunca são números fixos. São obtidas por `JOIN` pelo nome (empresas e plataformas reais) ou pela ordem de inserção. |
| Sem mexer no schema | Não há `DROP`, `CREATE TABLE`, `TRUNCATE`, `ALTER`, `DELETE` nem `\i`. Os dois `UPDATE` calculam atributos derivados (`Plataforma.qtd_users` e `Canal.qtd_visualizacoes`) das linhas inseridas pelo próprio script. |
| Sem referência ao `seed.sql` | O nome só aparece num comentário do cabeçalho. A mensagem de erro fala em "banco não está vazio", sem citar outro seed. |
| Volume do item mandatório 1 | Um segundo bloco `DO`, antes do `COMMIT`, confere que cada tabela tem entre 1.000 e 10.000 linhas e aborta a transação se não tiver. |
| Reprodutibilidade | `setseed(0.42)` e `max_parallel_workers_per_gather = 0` fazem cada execução sobre um schema novo gerar os mesmos dados. |

Do `seed.sql` foram copiadas só ideias e técnicas: as listas de moedas, países,
empresas e plataformas reais, e os padrões de sorteio com `random()`. O
`seed.sql` atual nem roda sobre o `ddl.sql` atual, porque ainda usa as colunas
anteriores às DEC-014, 015 e 017 (`nome_canal`, `titulo_video`, `dataH_video`).

## Diferenças de modelagem em relação ao seed anterior

- **Chaves artificiais (DEC-014, 015, 017):** `NivelCanal`, `Inscricao`,
  `Patrocinio` e `Video` referenciam `id_canal`. `Participa` e `Comentario`
  referenciam `id_video`. `Doacao` e as 4 formas de pagamento usam
  `(id_video, seq_comentario, seq_doacao)`.
- **`Usuario.telefone` único (DEC-011):** o telefone termina com o número do
  usuário em 4 dígitos, o que impede repetição sem depender de sorte.
- **`Inscricao.data_inscricao` (DEC-007):** informada explicitamente, entre a
  criação do canal e 2026-10-31. Não depende de `CURRENT_DATE`, então a carga
  não muda conforme o dia da execução.
- **`MecanismoPlat.seq_plataforma`:** usuário e plataforma da doação vêm de
  `Comentario` e `Canal`, já que `Doacao` não repete mais `nick_usuario`.
- **`NivelCanal.gif`:** o caminho inclui o `id_canal`, para não colidir entre
  canais de mesmo nome em plataformas diferentes.

## Evidência da execução

Ambiente: container Docker `postgres:17` (`steam-do-bedo-db`). Para não apagar
os dados do banco `steam-do-bedo-db`, o teste rodou num banco descartável
`seed_v2_teste`, criado no mesmo container e apagado no fim. Os comandos são os
mesmos, trocando o nome do banco.

### 1. Primeira execução, sobre o banco recém-criado pelo `ddl.sql`

O `seed.sql` nunca foi executado nesse banco. Saída do `psql` (código de saída
`0`):

Contagem antes da carga, emitida pela checagem inicial:

```
NOTICE:  seed_v2: conversao = 0 linha(s) antes da carga
NOTICE:  seed_v2: pais = 0 linha(s) antes da carga
NOTICE:  seed_v2: empresa = 0 linha(s) antes da carga
NOTICE:  seed_v2: empresapais = 0 linha(s) antes da carga
NOTICE:  seed_v2: plataforma = 0 linha(s) antes da carga
NOTICE:  seed_v2: usuario = 0 linha(s) antes da carga
NOTICE:  seed_v2: plataformausuario = 0 linha(s) antes da carga
NOTICE:  seed_v2: streamerpais = 0 linha(s) antes da carga
NOTICE:  seed_v2: canal = 0 linha(s) antes da carga
NOTICE:  seed_v2: nivelcanal = 0 linha(s) antes da carga
NOTICE:  seed_v2: inscricao = 0 linha(s) antes da carga
NOTICE:  seed_v2: patrocinio = 0 linha(s) antes da carga
NOTICE:  seed_v2: video = 0 linha(s) antes da carga
NOTICE:  seed_v2: participa = 0 linha(s) antes da carga
NOTICE:  seed_v2: comentario = 0 linha(s) antes da carga
NOTICE:  seed_v2: doacao = 0 linha(s) antes da carga
NOTICE:  seed_v2: bitcoin = 0 linha(s) antes da carga
NOTICE:  seed_v2: paypal = 0 linha(s) antes da carga
NOTICE:  seed_v2: cartaocredito = 0 linha(s) antes da carga
NOTICE:  seed_v2: mecanismoplat = 0 linha(s) antes da carga
```

Contagem final, emitida pela conferência ao fim do script:

```
      tabela       | tuplas | dentro_do_intervalo
-------------------+--------+---------------------
 Conversao         |   1000 | t
 Pais              |   1000 | t
 Empresa           |   1000 | t
 EmpresaPais       |   1196 | t
 Plataforma        |   1000 | t
 Usuario           |   4000 | t
 PlataformaUsuario |   7772 | t
 StreamerPais      |   1207 | t
 Canal             |   1239 | t
 NivelCanal        |   6195 | t
 Inscricao         |   2034 | t
 Patrocinio        |   1340 | t
 Video             |   5583 | t
 Participa         |   5230 | t
 Comentario        |   9500 | t
 Doacao            |   4750 | t
 BitCoin           |   1010 | t
 PayPal            |   1010 | t
 CartaoCredito     |   1030 | t
 MecanismoPlat     |   1700 | t
(20 rows)
```

As colunas de identidade partiram do 1: `Empresa.nro` 1..1000,
`Plataforma.nro` 1..1000, `Canal.id_canal` 1..1239, `Video.id_video` 1..5583.
Total: 65.716 tuplas, cerca de 9,4 MB (heap + índices).

### 2. Segunda execução, sem refazer o `ddl.sql`

Falhou na checagem inicial, com código de saída `3` (erro de script com
`ON_ERROR_STOP`), antes de qualquer `INSERT`:

```
ERROR:  seed_v2 abortado: o banco não está vazio. Tabelas com linhas: conversao (1000), pais (1000), empresa (1000), empresapais (1196), plataforma (1000), usuario (4000), plataformausuario (7772), streamerpais (1207), canal (1239), nivelcanal (6195), inscricao (2034), patrocinio (1340), video (5583), participa (5230), comentario (9500), doacao (4750), bitcoin (1010), paypal (1010), cartaocredito (1030), mecanismoplat (1700)
HINT:  Este seed só roda sobre um schema recém-criado. Rode o ddl.sql de novo e depois o seed_v2.sql. Nada foi inserido.
CONTEXT:  PL/pgSQL function inline_code_block line 28 at RAISE
```

Nada foi inserido.

### 3. Outras conferências

- **Reprodutibilidade:** duas execuções de `ddl.sql` + `seed_v2.sql` geraram o
  mesmo hash MD5 do conteúdo de `Comentario`, `Inscricao`, `Patrocinio`,
  `Doacao` e `PlataformaUsuario`.
- **Consistência:** 0 inscrições anteriores à criação do canal ou no próprio
  canal, 0 inscrições ou comentários de usuários sem conta na plataforma do
  canal, 0 streamers sem canal, 0 canais principais em plataforma fictícia.
- **Especializações de `Doacao`:** 0 doações sem forma de pagamento, 0 doações
  em mais de uma forma, 0 doações via mecanismo da plataforma em comentário
  offline.
- **Busca no arquivo:** `seed.sql` aparece só no comentário do cabeçalho, e não
  há `\i`, `DROP`, `TRUNCATE`, `CREATE TABLE`, `ALTER` nem `DELETE` fora de
  comentários.

## Realismo das proporções

O item 1 impõe a faixa de 1.000 a 10.000 tuplas por tabela. Dentro dela, o
seed tenta reproduzir as concentrações do mundo real. Medido na carga acima:

| Aspecto | Valor no seed | Como é gerado |
|---|---|---|
| Usuários por plataforma real | YouTube 1.717, Twitch 1.270, Kick 550 … Mixer 53 | Conta principal sorteada com peso pela participação de mercado |
| Contas por usuário | 1 conta: 1.025, 2 contas: 2.178, 3 contas: 797 | Segunda conta real em ~40% dos usuários, conta fictícia em ~60% |
| Visualizações | 10% dos canais somam 44% das visualizações; mediana por vídeo 24,7 mil e média 120 mil | Popularidade própria por canal × sorteio assimétrico por vídeo |
| Membros | 36% dos usuários; 1.006 membros de 1 canal, 289 de 2 e 150 de 3; 10% dos canais concentram 44% dos membros | Escolha ponderada pelas visualizações do canal |
| Patrocínio | 490 canais patrocinados (40%), 290 marcas; 10 marcas fazem 42% dos patrocínios; nenhuma dona de plataforma real patrocina | Cotas por faixa de visualizações e sorteio ponderado de marcas |
| Forma de pagamento | Mecanismo da plataforma 1.700 (36%), cartão 1.030, PayPal 1.010, BitCoin 1.010 | Faixas fixas de posição numa ordem determinística |
| Valor da doação (mediana) | Mecanismo da plataforma US$ 7, PayPal US$ 26, cartão US$ 37, BitCoin US$ 135; mediana geral US$ 24 | Distribuição própria por forma de pagamento |
| Doações em comentários online | 85% | Sorteio favorece comentários online |

Distorções que continuam e são impostas pelo item 1:

- **Tabelas de referência infladas:** `Conversao` (964 moedas fictícias),
  `Pais` (960 países fictícios) e `Plataforma` (990 plataformas fictícias)
  precisam de pelo menos 1.000 linhas, embora o mundo real tenha cerca de 180
  moedas, 195 países e algumas dezenas de plataformas de streaming.
- **50% dos comentários trazem doação** (no real, cerca de 1% a 5%). Como cada
  uma das 4 especializações precisa de pelo menos 1.000 linhas, `Doacao` tem no
  mínimo 4.000 linhas. Com `Comentario` limitado a 10.000, pelo menos 40% dos
  comentários precisam ter doação.
- **Pirâmide achatada:** no real, `Comentario` é ordens de grandeza maior que
  `Video`. Aqui o teto de 10.000 deixa cerca de 1,7 comentário por vídeo.
- **25% dos usuários são streamers:** `StreamerPais` e `Canal` precisam de pelo
  menos 1.000 linhas, e aumentar `Usuario` empurraria `PlataformaUsuario` para
  acima de 10.000.

## Pontos em aberto

- `procedures.sql` e `queries.sql` não foram testados sobre esta carga.
- `Plataforma` e `Canal` ocupam cerca do dobro do necessário em disco por causa
  dos `UPDATE` finais dos atributos derivados (tuplas mortas). Um
  `VACUUM FULL` depois da carga resolve; ele não pode rodar dentro da
  transação do seed.
- O Mixer foi encerrado em 2020, mas a data de criação dos canais é sorteada
  até 2024 em todas as plataformas, inclusive no Mixer. O peso dele é o menor
  (1% das contas principais), mas a inconsistência pode aparecer.
