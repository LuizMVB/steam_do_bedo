# Anotações Gerais

Destinado a anotações gerais sobre o projeto que eu realizei a partir da leitura do enunciado

## Conceitos

### Views 

- [ ] Visões Virtuais (Views): São apenas consultas SQL salvas. Elas não armazenam dados fisicamente; toda vez que alguém faz uma consulta na view, o banco de dados executa a query original em tempo real nas tabelas base.
- [ ] Visões Materializadas: Funcionam como uma tabela física (um snapshot ou cópia) que armazena previamente o resultado da consulta. Quando você consulta uma visão materializada, ela entrega o dado pronto de imediato, sem precisar recalcular os joins ou agregações a cada acesso

### Índices

#### Tipos de índices

O limite do enunciado é de até 5 índices de apoio, cada um justificado pelo overhead de inserção. No PostgreSQL, PK e UNIQUE criam um índice automaticamente (B-tree). FK **não** cria índice.

##### Chaves (definem a identidade da linha e geram índice)

- [ ] Chave natural: usa atributos que já existem no minimundo (ex.: `Usuario.nick`, `Canal(nome, nro_plataforma)`). Tem significado, mas pode ser larga e ser repetida em todas as tabelas filhas.
- [ ] Chave composta: PK com mais de uma coluna (ex.: `Video(nome_canal, nro_plataforma, titulo, dataH)`). O índice cresce com a largura, e cada FK filha repete as colunas.
- [ ] Chave artificial (surrogate): identificador sem significado no domínio, gerado pelo banco (`GENERATED ALWAYS AS IDENTITY`). Deixa PK, FK e JOIN mais estreitos. Se a identidade natural continuar valendo, precisa de um `UNIQUE` sobre ela, que cria outro índice. O enunciado sugere avaliar para `Video` e dependentes.
- [ ] Chave candidata / alternativa (`UNIQUE`): garante unicidade de atributos que não são a PK (ex.: `Usuario.email`, `BitCoin.TxID`). Cria índice B-tree e custa a cada INSERT.

##### Quando optar por cada tipo de chave

- [ ] **Chave natural simples** (um atributo do domínio): quando o atributo é curto, estável, nunca nulo e realmente identifica a entidade. Ex.: `Conversao.moeda` (código ISO de 3 letras) e `Pais.ddi`. Evita uma coluna sem significado e a tabela fica legível. Não serve se o valor pode mudar ou é longo e se repete em muitas FKs.
- [ ] **Chave natural composta**: quando a identidade do minimundo é, de fato, a combinação de atributos e a entidade é fraca (depende de outra). Ex.: `NivelCanal(canal, nivel)` e `Participa`, que são tabelas pequenas ou de associação com poucos referenciadores. Vira problema quando a chave é referenciada por muitas tabelas, porque a largura se repete em cada FK e índice (caso de `Video` → `Comentario` → `Doacao` → 4 tabelas de pagamento).
- [ ] **Chave artificial (surrogate)**: quando a tabela é referenciada por muitas outras, ou por tabelas grandes, e a chave natural é composta ou larga (`VARCHAR`, `TIMESTAMPTZ`). Ex.: `Video`, `Canal`. Também quando a identidade natural pode mudar (título corrigido, nome alterado), já que a surrogate não muda. Mantém-se a chave natural como `UNIQUE`. O custo é esse índice extra e um JOIN a mais para recuperar o nome.
- [ ] **Chave artificial parcial** (artificial só para parte da identidade, como o `seq` dependente do vídeo em `Comentario`): quando a entidade é fraca e o número só faz sentido dentro do pai. Mantém o vínculo com o pai e estreita a chave sem criar um identificador global.
- [ ] **Surrogate onde já existe**: `Empresa.nro` e `Plataforma.nro` já são identificadores sequenciais do enunciado. Aqui o que se decide é o tamanho do tipo (`SMALLINT`, `INTEGER`, `BIGINT`), conforme a quantidade possível de linhas.
- [ ] **Chave candidata (`UNIQUE`)**: quando um atributo ou combinação não é a PK mas não pode repetir segundo o negócio (`Usuario.email`, `BitCoin.TxID`, `Plataforma(nome, empresa_fund)`). Atenção: NULLs não colidem em `UNIQUE`, então a coluna precisa ser `NOT NULL` para a regra valer para todos. Cada `UNIQUE` custa um índice e overhead de INSERT, então nas tabelas grandes só se justifica por regra de negócio.
- [ ] **Sem `UNIQUE` redundante**: não criar `UNIQUE` sobre um superconjunto de uma chave que já é única (`UNIQUE (moeda, nome)` com `moeda` PK; `UNIQUE (nome, nome_fantasia)` com `nome` único). Não protege nada e cria índice à toa.
- [ ] **Tamanho do tipo da chave**: escolher pelo máximo realista de linhas, não pelo máximo teórico. `SMALLINT` até 32.767, `INTEGER` até ~2,15 × 10^9, `BIGINT` até ~9,22 × 10^18. Vale mais quando a coluna se repete em chaves e FKs de tabelas grandes.

##### Estruturas de índice no PostgreSQL

- [ ] B-tree (padrão): serve para igualdade, faixa (`<`, `>`, `BETWEEN`), `ORDER BY` e `LIMIT` (top-k). É o tipo de PK e UNIQUE e o mais relevante neste trabalho.
- [ ] Índice composto (multicoluna): a ordem das colunas importa. Atende filtros pelo prefixo à esquerda (ex.: `(nome_canal, nro_plataforma)` atende filtro só por `nome_canal`, mas não só por `nro_plataforma`).
- [ ] Índice parcial (`WHERE ...`): indexa só parte das linhas (ex.: só doações não recusadas). Fica menor e custa menos na inserção.
- [ ] Índice de expressão: indexa o resultado de uma função (ex.: `lower(email)` para unicidade sem diferenciar maiúsculas).
- [ ] Índice de cobertura (`INCLUDE`): guarda colunas extras na folha para permitir *index-only scan*, sem acessar a tabela.
- [ ] Hash: só igualdade. Raramente compensa frente ao B-tree.
- [ ] GIN, GiST, BRIN: voltados a texto completo, geometria e tabelas muito grandes ordenadas fisicamente. Provavelmente fora do escopo.

##### Conceitos para justificar a escolha

- [ ] Seletividade: índice só ajuda quando o filtro devolve poucas linhas. Se devolve grande parte da tabela, o planner prefere *Seq Scan*.
- [ ] Overhead de escrita: cada índice é atualizado em todo INSERT/UPDATE/DELETE e ocupa espaço. Por isso há o limite de 5.
- [ ] Índice em FK: o Postgres não cria. Ajuda JOIN e filtro pela coluna da FK, mas conta no orçamento.
- [ ] Como comprovar: `EXPLAIN (ANALYZE, BUFFERS)` antes e depois, e `pg_relation_size`/`pg_indexes_size` para o tamanho.

## Minimundo

- responder questões sobre
  - alcance do público,
  - quantidade de propagandas realizadas, 
  - arrecadação direta (doações), 
  - arrecadação indireta (membros inscritos), 
  - número de interações diretas (comentários online) e
  - número de interações (comentários online + offline)
- 