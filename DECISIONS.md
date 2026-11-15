# Registro de Decisões de Projeto

## Objetivo

Documentar as decisões de projeto tomadas ao longo da evolução do mesmo

Cada decisão tem um identificador `DEC-NNN`, atribuído em ordem sequencial e
nunca reutilizado. Decisões que afetam o `ddl.sql` são referenciadas lá por um
comentário `-- DEC-NNN`.

A partir da DEC-005, cada decisão traz a linha **Aplicada no DDL: sim/não**.
`não` significa que o `ddl.sql` ainda não reflete a decisão; ela só passa a
`sim` quando o grupo pedir a alteração do DDL.

Números ausentes na sequência pertencem a decisões descartadas e não são reutilizados.

Uma decisão que substitui outra diz isso nos dois lados ("Substituída pela
DEC-0NN" na antiga, "Substitui a DEC-0NN" na nova). O texto das decisões
antigas não é apagado.

## Regra de alteração do modelo (critério de todas as decisões; DEC-019)

O trabalho **otimiza** um modelo relacional já mapeado (professor, consulta de
2026-11-11, 00:15).

- **Pode:** criar constraints (`UNIQUE`, `NOT NULL`, `CHECK`, FK), remodelar
  chaves (inclusive com surrogate), mudar tipos e criar índices, views,
  triggers e functions.
- **Não pode:** criar ou remover tabelas, mudar relacionamentos, criar colunas
  que não sejam de chave, nem remover atributos derivados (`qtd_users`,
  `qtd_visualizacoes`).

---

## DEC-001 · Procedure do item 6: gasto mensal por usuário em USD

`sp_obter_qtd_canais_e_gasto_mensal_por_usuario(p_nick_usuario)` retorna, por
usuário, em quantos canais ele é membro e quanto desembolsa por mês, em moeda
local e em dólares (USD).

### Como funciona

- Une `usuario`, `inscricao`, `nivelcanal`, `pais` e `conversao`.
- `NivelCanal` é o catálogo de níveis de assinatura de cada canal (nome do
  nível, `valor`, `gif`). `Inscricao` liga o usuário a um nível de um canal, e
  o `valor` mensal vem de `NivelCanal.valor`.
- Retorna `qtd_canais`, `moeda`, `vr_mensal_moeda_local` e `vr_mensal_usd`.
- A conversão é `valor * Conversao.fator_conver`, onde o fator é de moeda para USD.
- Ordena por `vr_mensal_usd` decrescente. O filtro por usuário é opcional.

### Premissas

1. **Moeda do valor (interpretação nossa, não explícita no minimundo):** o
   minimundo diz que o patrocínio tem valor "em dólares americanos", mas não
   informa a moeda do valor do nível de membro (nem da doação). Ele diz apenas
   que cada usuário tem um país de residência, que cada país tem uma moeda e que
   cada moeda tem um fator "para conversão do valor da moeda estrangeira para
   dólares americanos". Como o usuário é a única entidade da inscrição ligada a
   um país, interpretamos que `NivelCanal.valor` está na moeda do país de
   residência do usuário (`Usuario.pais_residencia` -> `Pais.moeda`) e o
   convertemos para USD. Leituras alternativas, que mudariam a conversão: o valor
   já estar em USD (como o patrocínio) ou estar na moeda do canal/streamer.
2. **Usuário sem país de residência (escolha nossa):** o minimundo não diz se o
   país de residência é obrigatório e a DDL aceita nulo. Nesse caso o usuário é
   tratado como USD (fator 1), para não sumir do resultado.
   **Substituída pela DEC-025:** `pais_residencia` passou a `NOT NULL`, então
   todo usuário tem moeda e o fator 1 deixou de ser necessário.
3. **Periodicidade (prevista no minimundo):** o minimundo diz que o membro
   contribui com um valor mensal conforme o nível e que o sistema não armazena
   o histórico de membros. Logo, "por mês" é o valor mensal atual das
   inscrições vigentes, e não um histórico mês a mês.

---

## DEC-002 · Procedure do item 9: top-k canais por aportes de membros em USD

`sp_obter_top_k_canais_por_aportes_de_membros(p_k)` retorna os `p_k` canais que
mais recebem aportes de membros, com a quantidade de membros e o valor total
mensal em dólares (USD).

### Como funciona

- Une `inscricao`, `nivelcanal`, `usuario`, `pais` e `conversao` e agrupa por
  canal (`nome_canal`, `nro_plataforma`).
- O aporte de cada membro é o `NivelCanal.valor` do nível em que está inscrito,
  convertido para USD por `Conversao.fator_conver`.
- Retorna `qtd_membros` e `vr_total_aportes` (já em USD), ordenados por
  `vr_total_aportes` decrescente, com desempate por `nome_canal`, limitados a
  `p_k` linhas.

### Premissas

1. **Reaproveita as premissas do item 6:** o valor do nível é tratado como
   mensal e na moeda do país de residência do membro, e membro sem país de
   residência é tratado como USD (fator 1). Veja a seção do item 6, que traz a
   justificativa e o que o minimundo diz ou não diz. Se a premissa de moeda
   mudar, os itens 6 e 9 devem mudar juntos.
2. **Conversão antes de somar (escolha nossa):** a conversão é feita por membro,
   antes da soma por canal. Sem ela, a soma misturaria moedas diferentes e o
   ranking entre canais não seria comparável.
3. **Vigência (prevista no minimundo):** o sistema não armazena o histórico de
   membros, então só as inscrições vigentes entram no cálculo.
4. **Valor de `p_k` (escolha nossa):** com `p_k` nulo o `LIMIT` do PostgreSQL não
   limita e a função devolve todos os canais.

---

## DEC-003 · Procedure do item 10: top-k canais por doações recebidas

`sp_obter_top_k_canais_por_doacoes_recebidas(p_k)` retorna os `p_k` canais que
mais receberam doações, somando todos os vídeos do canal.

### Premissas

1. **Doações recusadas ficam de fora (escolha nossa):** o minimundo define o status
   da doação como `recusado`, `recebido` ou `lido`. Doação recusada não foi
   recebida, então só entram `recebido` e `lido`. É o mesmo critério dos itens 4 e 7.
2. **Sem conversão de moeda:** o minimundo não informa a moeda do valor da doação,
   então o valor é somado como está. Se a doação for em moeda local, a soma mistura
   moedas (ponto em aberto, igual ao dos itens 4 e 7).
   **Fechado pela DEC-026:** a doação é gravada em USD no `INSERT` (trigger T11),
   então a soma já é em USD.
3. **Sem join com `video` e `comentario`:** `Doacao` já carrega a chave do canal e
   do vídeo, então agrupar por canal já cobre "todos os vídeos".
4. **Só canais com doação aparecem**, e `p_k` nulo devolve todos (comportamento do
   `LIMIT` do PostgreSQL).

---

## DEC-004 · Procedure do item 11: top-k canais por faturamento total

`sp_obter_top_k_canais_por_faturamento(p_k)` retorna os `p_k` canais que mais
faturam, com o valor de cada fonte (`vr_patrocinio`, `vr_membros`, `vr_doacoes`) e
o `vr_faturamento_total`, todos em USD.

### Premissas

1. **Fontes de receita:** patrocínio (já em USD segundo o minimundo), membros
   (valor do nível convertido para USD, mesma premissa dos itens 6 e 9) e doações
   recebidas (sem recusadas, mesma regra do item 10).
2. **Doação não é convertida (ponto em aberto):** como o minimundo não diz a moeda
   da doação, ela entra na soma como está. Se for em moeda local, o total do item
   11 mistura moedas.
   **Fechado pela DEC-026:** a doação é gravada em USD no `INSERT` (T11).
3. **Combinação por `UNION ALL`:** cada fonte é lida separadamente e só então
   somada por canal. Unir as três tabelas com `JOIN` multiplicaria as linhas de uma
   fonte pelas da outra e inflaria os valores.
4. **Canal sem nenhuma receita não aparece**, e `p_k` nulo devolve todos.
5. **Observação sobre os dados do seed:** o patrocínio domina o faturamento (na
   ordem de 10^5 USD por canal) e o valor de membros é pequeno (dezenas de USD),
   então o ranking é praticamente o do item 8.

---

## DEC-005 · Tipo de `Plataforma.nro` e de `nro_plataforma`: INTEGER

O enunciado diz que a plataforma é "identificada por um número sequencial
único". Escolhemos `INTEGER` (4 bytes) para `Plataforma.nro` e para todas as
colunas `nro_plataforma` que o referenciam, em vez de `BIGINT`.

### Cálculo da capacidade

- `BIGINT`: 2^63 − 1 = 9.223.372.036.854.775.807 (≈ 9,22 × 10^18).
- `INTEGER`: 2^31 − 1 = 2.147.483.647 (≈ 2,15 × 10^9).
- `SMALLINT`: 2^15 − 1 = 32.767.
- Uma coluna `GENERATED ALWAYS AS IDENTITY` começa em 1 e não dá a volta
  (sem `CYCLE`), então todos esses valores são utilizáveis.

### Por que INTEGER

1. **Demanda real é minúscula:** existem dezenas de plataformas de streaming no
   mundo, talvez poucas centenas. Mesmo a escala de 1.000 plataformas do seed v1
   usa ≈ 5 × 10^-5 % da capacidade de `INTEGER`. A população mundial (≈ 8 × 10^9)
   já passa do limite de `INTEGER`, e plataformas não chegam perto disso.
2. **BIGINT é desperdício:** serve para mais que ~10^18 registros. A 10^9
   inserções por segundo, esgotá-lo levaria ≈ 292 anos (9,22 × 10^18 / 10^9 /
   31.536.000 s). Folga desse tamanho não traz benefício aqui.
3. **O custo do tipo se multiplica:** `nro_plataforma` é parte da chave de
   `Canal`, `Video`, `Comentario`, `Doacao` e das 4 tabelas de pagamento, e se
   repete em todos os índices de PK e FK dessas tabelas. Cada linha dessas
   tabelas, e de cada índice, carrega 4 bytes a menos com `INTEGER`.
4. **Por que não SMALLINT:** 32.767 também cobre o mundo real, mas deixa pouca
   margem para uma escala sintética grande (seed v2 parametrizável) e a
   diferença de 2 bytes por coluna tende a ser absorvida pelo alinhamento das
   colunas vizinhas. `INTEGER` é o ponto de equilíbrio.

### Premissas e limites

- A escolha pressupõe que o número de plataformas nunca passa de 2,1 bilhões.
  Se isso deixar de valer, o tipo deve ser revisto.
- O ganho de espaço **não foi medido**; o argumento é por tamanho de tipo e
  repetição na chave. Medir é pendência para a evidência do relatório.
- `Empresa.nro` é tratado separadamente na DEC-008.
- **Efeito das DEC-014, 015 e 017:** com `id_canal` e `id_video`, as tabelas
  filhas deixam de repetir `nro_plataforma`. A coluna passa a existir só em
  `Plataforma.nro`, `Canal.nro_plataforma` e `PlataformaUsuario.nro_plataforma`.
  O argumento 3 acima (custo repetido nas tabelas grandes) vale então apenas para
  o modelo sem surrogates; com elas, o ganho do `INTEGER` é pequeno e a escolha
  vale por consistência de critério.

### Aplicada no DDL: sim
Onde: `Plataforma.nro`, `Canal.nro_plataforma` e `PlataformaUsuario.nro_plataforma` como `INTEGER` no `ddl.sql`.

O `ddl.sql` continua com `BIGINT`. Para aplicar, trocar para `INTEGER`:
`Plataforma.nro`, `Canal.nro_plataforma` e `PlataformaUsuario.nro_plataforma`.
As demais colunas `nro_plataforma` (`Patrocinio`, `NivelCanal`, `Inscricao`,
`Video`, `Participa`, `Comentario`, `Doacao`, `BitCoin`, `PayPal`,
`CartaoCredito`, `MecanismoPlat`) são removidas pela DEC-014, DEC-015 e DEC-017,
e não precisam de troca de tipo.
Uma versão com `ALTER TABLE ... TYPE INTEGER` nas 14 colunas, antes das
surrogates, foi testada em banco descartável (roda sem erro, 50 constraints
mantidas, sequência da identity também vira `integer`) e depois retirada do
arquivo.

---

## DEC-006 · Identidade da plataforma: `UNIQUE (nome, empresa_fund)`

(Revisada: a versão anterior pedia `UNIQUE (nome)`.)

O minimundo identifica a plataforma pelo número sequencial (`nro`, a PK) e não
diz que o nome é único. Decidimos que a **identidade de negócio** da plataforma é
o par **nome + empresa fundadora**: não pode haver duas plataformas com o mesmo
nome e a mesma fundadora.

### Por que `empresa_fund` e não `empresa_resp`

- A empresa fundadora é um fato histórico e não muda. A empresa responsável pode
  mudar (venda, fusão, reestruturação). Colocar `empresa_resp` na constraint
  faria uma troca de responsável parecer uma nova identidade.
- Ambas as colunas são `NOT NULL`, então a constraint não tem a brecha de
  múltiplos NULLs do `UNIQUE`.

### Por que faz sentido

1. Duas linhas com o mesmo nome e a mesma fundadora seriam o mesmo fato
   duplicado, o que o enunciado proíbe ("sem redundância").
2. Permite homônimos de fundadoras diferentes (nomes não são globalmente únicos
   no mundo real), o que `UNIQUE (nome)` proibiria.
3. Barato: `Plataforma` é pequena e estável; o índice B-tree da constraint pesa
   dezenas de kB. Como a coluna `nome` vem primeiro, o mesmo índice atende
   buscas só por nome.
4. Compatível com os dados: no seed v1, 1.000 plataformas, 0 pares
   `(nome, empresa_fund)` repetidos.

### Premissas e limites

- A constraint é **mais fraca** que `UNIQUE (nome)`: aceita duas plataformas com
  o mesmo nome se a fundadora for diferente. É a escolha do grupo.
- Depende da premissa de que `empresa_fund` realmente nunca muda. Se mudar, a
  identidade muda junto.
- `UNIQUE` diferencia maiúsculas de minúsculas (`Twitch` ≠ `twitch`).
- O índice da constraint não entra no limite de 5 índices de apoio, na leitura do
  grupo (PK e UNIQUE tratados como constraints). Ponto a confirmar com o professor.
- O seed v2 precisa gerar pares `(nome, empresa_fund)` distintos.

### Aplicada no DDL: sim
Onde: `Plataforma`, constraint `plataforma_nome_fund_key UNIQUE (nome, empresa_fund)`.

Hoje `Plataforma` não tem nenhuma constraint UNIQUE (conferido em
`pg_constraint`). Para aplicar: `UNIQUE (nome, empresa_fund)` na criação de
`Plataforma` ou `ALTER TABLE steam_do_bedo.Plataforma ADD CONSTRAINT
plataforma_nome_fund_key UNIQUE (nome, empresa_fund);`.

---

## DEC-007 · Data de inscrição do membro nas procedures de membros (itens 6, 9 e 11)

> **Substituída pela DEC-019.** A coluna `data_inscricao` era coluna comum fora de
> chave, o que a regra do professor não permite. Ela e o parâmetro `p_data_ref`
> foram removidos.

Trecho do minimundo: "Cada membro inscrito contribui com um valor mensal que
depende do seu nível de membro. Existem cinco níveis de membros e os nomes e os
valores de cada nível são definidos para cada canal."

### Validação (verificada no código)

As procedures **não consideram data de inscrição**, e hoje **não conseguem**:

- `Inscricao` tem só `nome_canal`, `nro_plataforma`, `nick_membro` e `nivel`.
  Não existe coluna de data (conferido no `ddl.sql`).
- Os itens 6 (`sp_obter_qtd_canais_e_gasto_mensal_por_usuario`) e 9
  (`sp_obter_top_k_canais_por_aportes_de_membros`) somam `NivelCanal.valor` de
  todas as inscrições existentes. O item 11 repete o mesmo cálculo de membros.
- O valor vem do nível, e o nível é resolvido pela chave
  `(nome_canal, nro_plataforma, nivel)`, o que respeita o trecho "valores de cada
  nível definidos para cada canal".

### Ponto de atenção

O trecho citado **não menciona data**. O texto só pede o valor mensal por nível
e diz que o sistema guarda apenas membros vigentes (sem histórico). Com isso, o
cálculo atual (somar o valor mensal de cada inscrição vigente) está coerente com
o minimundo. A data só passaria a ser exigência se o grupo decidir que ela muda
o resultado, por exemplo: ignorar inscrições com data futura, ou limitar a uma
data de referência.

### Correção proposta (se o grupo adotar)

1. **Esquema:** adicionar a `Inscricao` a coluna
   `data_inscricao DATE NOT NULL DEFAULT CURRENT_DATE`. Os dados do seed v1 e do
   v2 passam a precisar dessa coluna, com data posterior à data do canal
   (`Canal.data`).
2. **Procedures (itens 6, 9 e 11):** acrescentar o parâmetro opcional
   `p_data_ref DATE DEFAULT CURRENT_DATE` e o filtro
   `i.data_inscricao <= p_data_ref` na parte de membros. O valor continua sendo
   o mensal do nível, sem proporcionalizar por dias (não há histórico para isso).
3. **Consistência:** a regra "data da inscrição não anterior ao início do canal"
   envolve outra tabela e não cabe em `CHECK`; seria trigger. "Não maior que
   hoje" também não cabe em `CHECK` (expressão não imutável).
4. **Índices:** nenhum novo. O filtro por data é aplicado depois do JOIN pela
   chave de `Inscricao`, e o orçamento de 5 índices não deve ser gasto aqui sem
   EXPLAIN que mostre ganho.

### Aplicada no DDL: não (revertida pela DEC-019)
Onde estava: `Inscricao.data_inscricao DATE NOT NULL DEFAULT CURRENT_DATE`; `p_data_ref` nos itens 6, 9 e 11 do `procedures.sql`. Removidos.

---

## DEC-008 · Tipo de `Empresa.nro` e das colunas que o referenciam: INTEGER

Segue a lógica da DEC-005, mas com um argumento de capacidade diferente.

### Cálculo da capacidade

- `INTEGER`: 2^31 − 1 = 2.147.483.647 (≈ 2,15 × 10^9).
- `BIGINT`: 2^63 − 1 ≈ 9,22 × 10^18.
- `Empresa` guarda fundadoras, responsáveis e patrocinadoras. Mesmo que o banco
  tentasse catalogar todas as empresas do mundo, a ordem de grandeza é de
  centenas de milhões (estimativa nossa, não verificada em fonte), abaixo de
  2,15 × 10^9 com folga de cerca de uma ordem de grandeza. Para o escopo real
  (empresas ligadas a streamers de jogos), o uso é muito menor.

### Diferença para a DEC-005

- Para plataformas a demanda é de dezenas, e `INTEGER` sobra por muitos ordens
  de grandeza. Para empresas a folga é menor, mas `INTEGER` continua suficiente.
  Por isso **não** se escolhe `SMALLINT` aqui: 32.767 pode ser ultrapassado em
  uma escala sintética grande.
- O ganho de espaço é **menor** que o da DEC-005. `Empresa.nro` é referenciado
  só por `Plataforma` (`empresa_fund`, `empresa_resp`), `EmpresaPais`
  (`nro_empresa`) e `Patrocinio` (`nro_empresa`), todas tabelas pequenas ou
  médias, fora das chaves das tabelas grandes (`Comentario`, `Doacao`). A
  escolha vale mais por consistência de critério do que por economia medida.

### Premissas e limites

- Pressupõe menos de 2,1 bilhões de empresas. Se deixar de valer, rever o tipo.
- O ganho de espaço **não foi medido**.
- Se a DEC-005 mudar de tipo, avaliar esta junto.

### Aplicada no DDL: sim
Onde: `Empresa.nro`, `Plataforma.empresa_fund`/`empresa_resp`, `EmpresaPais.nro_empresa` e `Patrocinio.nro_empresa` como `INTEGER`.

O `ddl.sql` continua com `BIGINT`. Para aplicar, trocar para `INTEGER`:
`Empresa.nro`, `Plataforma.empresa_fund`, `Plataforma.empresa_resp`,
`EmpresaPais.nro_empresa` e `Patrocinio.nro_empresa`. Não foi testado em banco
descartável.

---

## DEC-009 · `Empresa`: não adicionar `UNIQUE (nome, nome_fantasia)`

### Validação

A proposta **não faz sentido como está**:

- `Empresa.nome` já é `UNIQUE`. Se `nome` é único sozinho, qualquer par
  `(nome, nome_fantasia)` também é, então a constraint composta não protege nada
  e só cria um índice a mais.
- `nome_fantasia` é nulável. Em `UNIQUE`, NULLs contam como distintos (a menos
  de `NULLS NOT DISTINCT`, PostgreSQL 15+), então o par com `nome_fantasia`
  nulo nunca violaria a regra.

### Decisão

Manter `UNIQUE (nome)` como está. Se o grupo quiser permitir razões sociais
repetidas com nomes fantasia diferentes, a alternativa é **remover** `UNIQUE
(nome)` e usar o par com `NULLS NOT DISTINCT`. Mas a identidade real da empresa é
o identificador nacional por país (`EmpresaPais`), e não o nome.

Dados do seed v1: 0 pares `(nome, nome_fantasia)` repetidos e 0 nulos em
`nome_fantasia`.

### Aplicada no DDL: não se aplica

Nada a alterar: `UNIQUE (nome)` já existe (`empresa_nome_key`).

---

## DEC-010 · `Conversao`: `nome` é UNIQUE e `moeda` continua como PK

### `UNIQUE (nome)`: sim

Duas moedas com o mesmo nome seriam duplicata. A tabela é pequena e o custo do
índice é desprezível.

### `UNIQUE (moeda, nome)`: não

Como `moeda` é a PK, qualquer conjunto de colunas que a contenha já é único. A
constraint composta nunca seria violada sozinha e cria um índice sem função. A
unicidade útil é `UNIQUE (nome)`, só no nome.

### `moeda` como PK: faz sentido

- É o código ISO 4217 de 3 letras (USD, BRL, EUR): curto, estável, imutável e
  já usado como identificador no mundo real.
- É referenciado por `Pais.moeda`. Uma chave natural de 3 caracteres é mais
  estreita e legível que uma surrogate, e a tabela é pequena (dezenas de linhas
  no mundo real), sem ganho em trocá-la.
- Vários países compartilham a mesma moeda (Euro), o que é uma relação 1:N
  correta: `Pais.moeda` não é único.
- Seed v1: todas as 1.000 moedas casam com `^[A-Z]{3}$` e os 1.000 nomes são
  distintos.

### Aplicada no DDL: sim
Onde: `Conversao`, constraint `conversao_nome_key UNIQUE (nome)`.

`Conversao` hoje só tem a PK em `moeda`. Para aplicar: `UNIQUE (nome)` na criação
ou `ALTER TABLE steam_do_bedo.Conversao ADD CONSTRAINT conversao_nome_key UNIQUE
(nome);`.

---

## DEC-011 · `Usuario`: `email` e `telefone` são UNIQUE (cada um sozinho)

### Decisão

Duas constraints separadas: `UNIQUE (email)` e `UNIQUE (telefone)`. Não é um
`UNIQUE (email, telefone)`, que só barraria o par idêntico e deixaria o mesmo
email com telefones diferentes.

### Validação

- **Email:** identifica a conta na prática. Faz sentido. `NOT NULL` já existe.
- **Telefone:** o minimundo diz que serve para "validação em duas vias". Um
  telefone amarrado a uma conta é coerente com essa finalidade, mas no mundo
  real telefones são compartilhados (família). É regra do grupo, não verdade do
  domínio.
- **Brecha de NULL:** `telefone` é nulável no DDL, e `UNIQUE` aceita vários
  NULLs. Para a regra valer para todos, `telefone` precisa ser `NOT NULL`, o
  que também decorre do texto ("um telefone"). Premissa a confirmar.
- **Maiúsculas e minúsculas:** `UNIQUE (email)` trata `A@x.com` e `a@x.com`
  como diferentes. A alternativa é um índice único sobre `lower(email)`.
- **Custo:** `Usuario` é uma das maiores tabelas no seed v2. São dois índices B-tree
  a mais, cada um atualizado em todo INSERT. Entram como constraints, fora dos 5
  índices de apoio, na leitura do grupo.
- Seed v1: 4.000 usuários, 0 emails repetidos, 0 telefones repetidos, 0 telefones
  nulos.

### Aplicada no DDL: sim
Onde: `Usuario`, constraints `usuario_email_key` e `usuario_telefone_key` (`telefone` segue nulável).

`Usuario` hoje não tem UNIQUE além da PK. Para aplicar: `UNIQUE (email)` e
`UNIQUE (telefone)` na criação, ou dois `ALTER TABLE ... ADD CONSTRAINT`, e
`telefone` como `NOT NULL` se a premissa for aceita.

---

## DEC-014 · `Canal`: surrogate `id_canal` com `UNIQUE (nome, nro_plataforma)`

### Avaliação da chave composta atual

A PK `(nome, nro_plataforma)` é **correta**, mas cara. `nome VARCHAR(255)` e
`nro_plataforma` aparecem em 11 tabelas (`Patrocinio`, `NivelCanal`, `Inscricao`,
`Video`, `Participa`, `Comentario`, `Doacao`, `BitCoin`, `PayPal`,
`CartaoCredito`, `MecanismoPlat`). Em todas elas fazem parte da PK e da FK, e
portanto de cada linha e de cada índice. Nas tabelas grandes (`Comentario`,
`Doacao`) isso pesa.

### Alternativas

1. **Manter a chave composta:** correto, sem mudança, custo de largura mantido.
2. **PK só em `nome`:** o enunciado diz "identificado por seu nome único", mas
   a mesma pessoa pode ter canais de mesmo nome em plataformas diferentes
   ("um ou mais canais associados a cada streamer em diferentes plataformas").
   Seria uma restrição que o domínio não garante. Os 1.287 nomes do seed v1 são
   todos distintos, mas isso é característica do gerador.
3. **Surrogate (escolhida):** `id_canal INTEGER GENERATED ALWAYS AS IDENTITY`
   como PK, e `UNIQUE (nome, nro_plataforma)` para preservar a identidade de
   negócio. As tabelas filhas passam a ter `id_canal` (4 bytes) no lugar de
   `nome_canal` + `nro_plataforma`.

### Por que a surrogate

- Reduz a largura de linha, de PK e de FK nas tabelas filhas.
- A identidade natural continua protegida pelo `UNIQUE`.
- `INTEGER`: coerente com DEC-005 e DEC-008. Estimativa nossa, não verificada:
  mesmo as maiores plataformas têm centenas de milhões de canais, abaixo de
  2,15 × 10^9. A folga é menor que a das plataformas; rever se a escala mudar.
  **Substituído pela DEC-023:** com vídeo curto no cenário (DEC-020), `id_canal`
  passou a `BIGINT`. A surrogate e o `UNIQUE` continuam como estão aqui.

### Custos e limites

- Um índice a mais em `Canal` (o do `UNIQUE`), pequeno frente aos ganhos nas
  filhas.
- As procedures que hoje devolvem `nome_canal` e `nro_plataforma` direto das
  tabelas filhas precisarão de `JOIN` com `Canal` para obter o nome. Esse custo
  precisa ser medido com `EXPLAIN (ANALYZE, BUFFERS)`.
- Exige reescrever o DDL, os seeds e as procedures. **Não foi medido** o ganho
  de espaço nem o custo do `JOIN` extra.
- Interage com a DEC-015 (surrogate em `Video`): o ganho em `Comentario` e
  `Doacao` é maior se as duas forem adotadas juntas. Medição na DEC-017.
- A leitura de "nome único" adotada: único **por plataforma** (como já está no
  DDL).

### Aplicada no DDL: sim
Onde: `Canal` com `canal_pkey (id_canal)` e `canal_nome_plataforma_key`; `Patrocinio`, `NivelCanal`, `Inscricao` e `Video` referenciam `id_canal`.

`Canal` hoje tem `PRIMARY KEY (nome, nro_plataforma)`, e as 11 tabelas filhas o
referenciam.

---

## DEC-015 · `Video`: surrogate `id_video` baseado em `id_canal`

### Validação

Faz sentido. `Video` é referenciado por `Participa`, `Comentario`, `Doacao` e
pelas 4 tabelas de pagamento, e hoje cada uma repete `nome_canal`,
`nro_plataforma`, `titulo` e `dataH` (4 colunas, duas delas largas) em PK e FK.
O enunciado também sugere avaliar identificador artificial para `Video` e
dependentes.

### Decisão

- `id_video BIGINT GENERATED ALWAYS AS IDENTITY` como PK.
- `id_canal` (DEC-014) substitui `nome_canal` + `nro_plataforma`; é FK para `Canal`.
- A identidade de negócio é preservada com `UNIQUE (id_canal, titulo, dataH)`.
  **Sim, faz sentido:** sem isso nada impediria dois vídeos com o mesmo título e
  data/hora no mesmo canal, o que o enunciado proíbe ("identificado por seu
  título e data/hora de postagem").
- `titulo` e `dataH` precisam ser declarados `NOT NULL`: deixam de ser PK, e só a
  PK os tornava obrigatórios.
- Filhas passam a referenciar só `id_video`. `Participa` fica com
  `PK (id_video, nick_streamer)`.
- Tipo `BIGINT` (e não `INTEGER` como em DEC-005, 008 e 014): vídeos são a
  entidade com mais crescimento. **Substituído pela DEC-021:** `id_video` passou
  a UUID v7 (geração distribuída no cenário com vídeo curto). Estimativa nossa, não verificada: só as grandes
  plataformas têm bilhões de vídeos, acima do limite de 2,15 × 10^9 do `INTEGER`.

### Custos e limites

- Um índice a mais em `Video` (o do `UNIQUE`). Como `id_canal` vem primeiro, ele
  atende também as buscas "vídeos de um canal" (itens 2 e 3), que hoje usam o
  prefixo da PK composta.
- Exige reescrever DDL, seeds e procedures. Procedures que hoje devolvem
  título ou data direto das filhas passam a precisar de `JOIN` com `Video`.
- Ganho medido em `Comentario`: ver DEC-017.

### Aplicada no DDL: sim
Onde: `Video` com `video_pkey (id_video)` e `video_canal_titulo_datah_key`; `Participa` com `participa_pkey (id_video, nick_streamer)`.

`Video` hoje tem `PRIMARY KEY (nome_canal, nro_plataforma, titulo, dataH)`.

---

## DEC-016 · Constraints `CHECK` para valores numéricos

### Validação

Faz sentido e é barato: `CHECK` não cria índice, então não consome os 5 índices
de apoio, e custa só a avaliação da expressão no INSERT/UPDATE. No seed v1,
nenhuma linha viola nenhuma das regras abaixo.

Uma ressalva: "maior que 0" **não vale para tudo**. Contadores podem ser zero
(canal novo sem visualizações, plataforma sem usuários), então esses recebem
`>= 0`.

### Decisão

| Coluna | Regra | Motivo |
|---|---|---|
| `Conversao.fator_conver` | `> 0` | fator zero ou negativo anula ou inverte a conversão |
| `Patrocinio.valor` | `> 0` | patrocínio vigente com valor zero não existe |
| `NivelCanal.valor` | `> 0` | nível pago |
| `Doacao.valor` | `> 0` | vale também para doação recusada |
| `Comentario.seq` | `> 0` | número sequencial a partir de 1 |
| `Doacao.seq_pg` | `> 0` | idem |
| `Doacao.seq_comentario` | `> 0` | idem |
| `MecanismoPlat.seq_plataforma` | `> 0` | idem |
| `Video.duracao` | `> INTERVAL '0'` | vídeo tem duração (nulo continua permitido) |
| `Plataforma.qtd_users` | `>= 0` | derivado, pode ser zero |
| `Canal.qtd_visualizacoes` | `>= 0` | derivado, pode ser zero |
| `Video.visu_simul`, `Video.visu_total` | `>= 0` | contadores |
| `Video` | `visu_simul <= visu_total` | o pico simultâneo não excede o total (acréscimo do grupo: confirmar) |

- Ids `IDENTITY` não precisam de `CHECK`: começam em 1.
- `CHECK` com coluna nula passa (resultado desconhecido), então as colunas
  nuláveis (`duracao`, `visu_*`) só são validadas quando preenchidas.

### Aplicada no DDL: sim
Onde: 13 `CHECK` nomeados `*_check` (`conversao`, `patrocinio`, `nivelcanal`, `doacao`, `comentario`, `mecanismoplat`, `video`, `plataforma`, `canal`); `visu_simul <= visu_total` não aplicada.

O `ddl.sql` hoje só tem `CHECK` em `Canal.tipo` e `Doacao.status`. Para aplicar:
`CHECK` na criação ou `ALTER TABLE ... ADD CONSTRAINT ... CHECK (...)`.

---

## DEC-017 · `Comentario` com Canal e Video com surrogate: aguenta o crescimento?

### Pergunta

Mesmo com `id_canal` e `id_video`, `Comentario` é a maior tabela e tende a
crescer muito. A chave resultante aguenta?

### Evidência (teste real, banco descartável, apagado depois)

1.000.000 de comentários (50.000 vídeos × 20), inserção em ordem aleatória, mesmos
dados nas 4 variantes, depois `VACUUM ANALYZE`. `nick` ~13 caracteres, título ~36,
nome de canal ~18.

| Variante | PK | Tabela | Índices | Total | Tempo de INSERT |
|---|---|---|---|---|---|
| A (atual) | `(nome_canal, nro_plataforma, titulo, dataH, nick, seq)` | 195 MB | 156 MB | 352 MB | 11,2 s |
| B | `(id_video, nick, seq)` | 135 MB | 62 MB | 196 MB | 7,2 s |
| C | `(id_video, seq)` | 135 MB | 38 MB | 173 MB | 5,3 s |
| D | `id_comentario` identity + `UNIQUE (id_video, seq)` | 142 MB | 59 MB | 201 MB | 6,3 s |

Resultado: a variante C reduz o índice em 76% (156 → 38 MB), o total em 51% e o
tempo de INSERT em 52% frente à atual. B (manter `nick` na PK) perde a maior
parte do ganho. D (id próprio) fica entre B e C, porque o `UNIQUE` recria um
índice.

### Decisão

1. A surrogate em `Canal` e `Video` **resolve a maior parte** do problema, mas
   o ganho completo só aparece **retirando `nick_usuario` da PK**: como `seq` já é
   único por vídeo, `PK (id_video, seq)` identifica o comentário.
   `nick_usuario` fica `NOT NULL` com FK para `Usuario`.
2. `seq` como `INTEGER` (comentários por vídeo cabem com folga em 2,15 × 10^9);
   `id_video` segue `BIGINT` (DEC-015).
3. `Doacao` referencia `(id_video, seq_comentario)` e não repete `nick_usuario`,
   que é determinado pelo comentário. Isso também reduz redundância. As 4
   tabelas de pagamento ficam com chave `(id_video, seq_comentario, seq_doacao)`.
   Logo, `Doacao` fica com `PK (id_video, seq_comentario, seq_pg)` e FK para
   `Comentario (id_video, seq)`.
4. **Se o volume ultrapassar o que um índice B-tree único comporta bem**
   (centenas de milhões de linhas), o passo seguinte é particionar
   `Comentario` por `HASH (id_video)`. A PK `(id_video, seq)` já contém a chave de
   partição, o que o PostgreSQL exige para PK em tabela particionada. Não
   recomendado agora: com 1.000 a 10.000 linhas por tabela não há ganho.
5. O que sobra pesando na linha é `nick_usuario` (texto) e `texto` (vai para TOAST
   quando grande). Surrogate em `Usuario` reduziria o primeiro; não foi medido nem
   decidido. **Decidido e medido na DEC-022** (`id_usuario BIGINT`).

### Consequência a resolver depois

`seq` é "um número sequencial que depende do vídeo". Gerar `max(seq)+1` por vídeo
tem risco de concorrência: duas inserções simultâneas no mesmo vídeo podem
calcular o mesmo número, e a segunda falha pela PK. Uma `SEQUENCE` global não
serve, porque numera todos os vídeos juntos. A estratégia de geração **não está
decidida**; precisa ser definida antes da etapa de triggers, e até lá o seed
informa `seq` explicitamente.

**Resolvido pela DEC-027 (trigger T3):** se o `INSERT` não informar `seq`, o
trigger trava a linha do vídeo (`SELECT ... FOR UPDATE`) e usa `max(seq) + 1`.

### Limites da medição

- Dados sintéticos, uma única execução, tabela isolada sem FKs (as FKs
  acrescentam custo a todas as variantes) e sem concorrência.
- Os tempos são relativos entre as variantes; os valores absolutos dependem da
  máquina.
- O ganho em consultas não foi medido (as procedures ainda não foram reescritas).

### Aplicada no DDL: sim
Onde: `comentario_pkey (id_video, seq)`, `doacao_pkey (id_video, seq_comentario, seq_pg)` e PK `(id_video, seq_comentario, seq_doacao)` em `BitCoin`, `PayPal`, `CartaoCredito` e `MecanismoPlat`.

`Comentario` hoje tem PK de 6 colunas
`(nome_canal, nro_plataforma, titulo_video, dataH_video, nick_usuario, seq)`.

---

## DEC-018 · Índices de apoio (item 4): `Inscricao(nick_membro)` e `Canal(nro_plataforma)`

> **Substituída pela DEC-034.** As medições abaixo foram feitas com cache quente,
> dados uniformes e as chaves antigas (`nick` como PK). Os índices saíram do
> `ddl.sql` e foram refeitos em `indices.sql`, medidos a frio sobre o seed v3.

### Contexto

O item mandatório 4 pede até 5 índices de apoio, com justificativa individual e
consideração do overhead de inserção. Índice de apoio aqui é o índice secundário
criado por decisão do grupo (`CREATE INDEX`), **além** dos 27 que o PostgreSQL
cria sozinho para `PRIMARY KEY` e `UNIQUE`. Esses não contam no teto. Antes desta
decisão havia **zero** índices explícitos. `CHECK` (DEC-016) não cria índice.

Cada candidato foi levantado a partir dos `WHERE`, `JOIN`, `GROUP BY` e
`ORDER BY` das 11 functions de `procedures.sql` (a 12 ainda não existe). O
PostgreSQL não indexa FKs automaticamente, e um índice composto só serve a um
filtro pela coluna **líder**.

### Decisão: 2 índices (teto de 5 respeitado; 3 vagas livres)

```sql
CREATE INDEX idx_inscricao_nick_membro ON steam_do_bedo.Inscricao (nick_membro);
CREATE INDEX idx_canal_nro_plataforma  ON steam_do_bedo.Canal (nro_plataforma);
```

Os outros 6 candidatos medidos não se sustentaram (ver "Candidatos
descartados"). Não forçamos índices só para preencher o teto.

### Como foi medido

- O `steam_do_bedo` estava vazio (0 linhas). As medições foram feitas no schema
  descartável `bench_idx`, criado com o próprio `ddl.sql` e o `procedures.sql`
  (só o nome do schema trocado) e apagado ao final.
- Volume sintético de ~100× o seed v1, gerado com `setseed`: Usuario 400.000,
  Canal 125.079, NivelCanal 625.395, Inscricao 799.999, Patrocinio 176.176,
  Video 500.316, Comentario 900.000, Doacao 499.641. Plataformas 1 a 10 com ~10 mil
  canais cada (8% de `Canal`) e 990 plataformas com ~25 canais cada. Doacao com
  10% `recusado`, 45% `recebido` e 45% `lido`; Comentario com 65% online.
- As functions são `LANGUAGE sql STABLE` e o planejador as expande (*inline*):
  o `EXPLAIN` mostra os nós internos, e `p IS NULL OR col = p` vira `col = p`
  quando o parâmetro é constante. Por isso um índice pode atender o filtro opcional.
- Tempo: `EXPLAIN (ANALYZE, BUFFERS)` da chamada real da function, 1 execução de
  aquecimento + 5 medidas, **mediana**. Buffers = `shared hit + read` da raiz.
- Overhead de escrita: `INSERT ... SELECT` da tabela inteira (ordem física) numa
  cópia com as mesmas PK/UNIQUE/CHECK, com e sem o índice. Duas variantes:
  (a) sem FKs, tabela inteira, 3 rodadas; (b) **com as FKs reais**, lote de 200 mil
  linhas (Canal inteiro: 125 mil), 5 rodadas intercaladas e `CHECKPOINT` antes de
  cada uma. Valor reportado: mediana.

### Índice 1 · `idx_inscricao_nick_membro`

- **Definição:** `CREATE INDEX idx_inscricao_nick_membro ON steam_do_bedo.Inscricao (nick_membro);`
- **Consulta atendida:** item 6, `sp_obter_qtd_canais_e_gasto_mensal_por_usuario(p_nick_usuario)`,
  no `JOIN inscricao i ON i.nick_membro = u.nick` com `u.nick = p_nick_usuario`.
- **Por que as chaves não bastam:** `inscricao_pkey` é `(id_canal, nick_membro)`.
  Com `id_canal` na frente, ela não serve para buscar as inscrições de um membro,
  e o plano fazia `Seq Scan` em toda a tabela.
- **Evidência (item 6 com usuário):**

  | | Plano em `Inscricao` | Mediana | Buffers |
  |---|---|---|---|
  | Sem índice | `Seq Scan`, 799.997 linhas descartadas pelo filtro | 68,5 ms | 5.905 |
  | Com índice | `Index Scan using idx_inscricao_nick_membro` | 0,051 ms | 23 |

  A seletividade é altíssima: 2 linhas de 800 mil por usuário. O item 6 sem filtro
  e os itens 9 e 11 leem a tabela inteira e não usam o índice (sem ganho nem perda).
- **Custo:** 19 MB criado sobre a tabela pronta (24 MB quando preenchido pela carga),
  contra 46 MB de heap. Carga sem FKs: 4.384 → 11.313 ms (+158%). Carga com FKs:
  5.376 → 8.960 ms (**+67%**, ~18 µs por linha). É o mais caro dos dois, porque a
  chave é texto (`en_US.utf8`) inserido em ordem aleatória na árvore.
- **Por que vale:** inscrição é escrita rara (o usuário assina um canal de vez em
  quando), e a busca "inscrições do usuário" é leitura frequente. 68 ms poupados
  por consulta pagam ~3.800 inscrições. O índice também evita a varredura de
  `Inscricao` na verificação da FK `inscricao_nick_membro_fkey` ao remover ou
  alterar um `Usuario` (não medido).
- **Tipo e colunas:** B-tree simples, só igualdade. Não foi incluída
  `data_inscricao` (DEC-007): o filtro `data_inscricao <= p_data_ref` casa com
  100% das linhas no padrão (`CURRENT_DATE`) e com 45,7% no corte de 2020, então
  não é seletivo. `INCLUDE (nivel, id_canal)` também não compensa: com 2 linhas
  por usuário, o acesso ao heap custa poucos buffers.

### Índice 2 · `idx_canal_nro_plataforma`

- **Definição:** `CREATE INDEX idx_canal_nro_plataforma ON steam_do_bedo.Canal (nro_plataforma);`
- **Consultas atendidas:** item 1, `sp_obter_streamers_com_maior_qtd_videos_publicados(p_plataforma)`,
  e item 4, `sp_obter_canais_pela_media_doacoes_por_comentario(p_nro_plataforma)`,
  ambos com `WHERE c.nro_plataforma = p`.
- **Por que as chaves não bastam:** `canal_nome_plataforma_key` (DEC-014) é
  `(nome, nro_plataforma)`. Com `nome` na frente, ela não serve para filtrar só por
  plataforma.
- **Evidência:**

  | Consulta | Sem índice | Com índice | Buffers |
  |---|---|---|---|
  | Item 1, plataforma com 26 canais | `Seq Scan canal` (125.053 descartadas), 7,84 ms | `Bitmap Index Scan idx_canal_nro_plataforma`, 0,255 ms (31×) | 2.018 → 210 |
  | Item 4, plataforma com 26 canais | `Seq Scan canal`, 7,91 ms | `Bitmap Index Scan`, 0,572 ms (14×) | 2.430 → 622 |
  | Item 1, plataforma 1 (8% dos canais) | 130,7 ms | 132,1 ms (sem ganho) | iguais |
  | Item 4, plataforma 2 (8% dos canais) | 359 e 365 ms | 362 e 393 ms (ruído) | iguais |

  Depois do filtro, os vídeos de cada canal já são achados por
  `video_canal_titulo_datah_key` (DEC-015, `id_canal` na frente). Nas plataformas
  grandes, o acesso a `Canal` cai de ~8 para ~4 ms, mas a varredura de `Video`
  domina e o tempo total não muda. O ganho está nas plataformas pequenas, que são
  a maioria (990 de 1.000 no volume de teste).
- **Custo:** 0,9 MB (o menor de todos). Carga sem FKs: 1.466 → 1.560 ms (+6%).
  Carga com FKs: 3.252 → 3.706 ms (**+14%**, ~3,6 µs por linha). `Canal` é tabela
  de escrita rara.
- **Extra:** atende a FK `canal_nro_plataforma_fkey` (remoção de `Plataforma`) e
  deve servir ao item 12 (agrupamento e filtro por plataforma), que ainda não foi
  implementado. **Não medido.**
- **Tipo e colunas:** B-tree simples. Uma composta `(nro_plataforma, nick_streamer)`
  só ajudaria o `GROUP BY` do item 1, que é dominado pela leitura de `Video`; não
  justifica o tamanho extra.

### Ganho x custo (resumo)

| Índice | Melhor ganho medido | Tamanho | Overhead de carga (com FKs) |
|---|---|---|---|
| `idx_inscricao_nick_membro` | item 6: 68,5 → 0,051 ms | 19 MB | +67% (~18 µs/linha) |
| `idx_canal_nro_plataforma` | itens 1 e 4: 7,9 → 0,26 / 0,57 ms | 0,9 MB | +14% (~3,6 µs/linha) |

Com os dois índices juntos, as 20 chamadas de teste foram medidas de novo. As que
não usam os índices novos ficaram dentro do ruído do ambiente (±20%): nenhum plano
dessas consultas mudou, e os buffers ficaram idênticos.

### Candidatos descartados

| Candidato | Consultas testadas | Resultado | Custo | Motivo |
|---|---|---|---|---|
| `Canal (nick_streamer)` | item 3 com streamer; itens 1 e 3 sem filtro | 543 → 617 ms (sem ganho) | 3,6 MB; carga +53% | O índice é usado para achar o canal, mas a function agrega **todo** `Comentario` (`Index Only Scan comentario_pkey`, 900 mil linhas) antes do `JOIN`. É isso que domina o tempo |
| `Comentario (id_video, coment_on)` | item 2 sem/com canal; item 3 | item 2 com canal 853 → 511 ms (−40%); sem filtro 5.738 → 5.158 ms (−10%); item 3 sem ganho | 23 MB; carga +64% sem FKs, +15% com FKs (~3,8 µs/linha) | Limítrofe. Ver abaixo |
| `Doacao (status) WHERE status <> 'recusado'` | itens 4, 7, 10 e 11 | **não usado** (`Seq Scan doacao` em todos) | 3,1 MB; carga +37% | O predicado casa com 90% das linhas, e varrer a tabela vence |
| `Doacao (id_video) INCLUDE (valor) WHERE status <> 'recusado'` | itens 4, 7, 10 e 11 | **não usado**; 3.218 → 3.107 ms, 1.134 → 1.150 ms, 2.634 → 2.540 ms (ruído) | 14 MB; carga +53% | Leitura integral e agregação. O tempo vai na ordenação por `cn.nome` (texto) |
| `Patrocinio (id_canal)` | itens 5, 8 e 11 | **não usado** | 3,6 MB; carga +90% | Os itens 8 e 11 agregam a tabela toda. O item 5 com empresa já leva 0,43 ms via `empresa_nome_key` + `patrocinio_pkey` (`nro_empresa` na frente) |

Sobre `Comentario (id_video, coment_on)`: o ganho existe, mas atende só o item 2 e
depende de *index-only scan*, que exige páginas marcadas como visíveis no
*visibility map*. Numa tabela com inserção contínua de comentários, isso tende a
cair (não medido). Além disso, o índice é cobrado na tabela de maior volume e maior
taxa de escrita (DEC-017). A causa da lentidão do item 2 filtrado é a forma da
consulta: ela agrega todos os comentários antes de filtrar o canal. Reescrevê-la
para agregar depois do `JOIN` deixaria `comentario_pkey (id_video, seq)` atender o
caso filtrado sem índice novo (não feito nem medido). É o primeiro candidato a
reavaliar se a function não for reescrita.

Hipóteses descartadas sem medição de consulta, porque nenhuma function as usa:

- `Participa (nick_streamer)`: nenhuma function lê `Participa`.
- `Comentario (nick_usuario)` e colunas de data em `Comentario`: nenhuma function
  filtra comentários por usuário ou data.
- `Video (id_canal)`: redundante. `video_canal_titulo_datah_key` (DEC-015) já tem
  `id_canal` na frente, e os planos dos itens 1, 2, 4 e 7 já usam esse índice.
- Ordenação por visualizações em `Video`: nenhuma function ordena linhas por
  `visu_total`; só há `SUM`.

Consultas já bem atendidas pelas chaves, sem índice novo: itens 2 e 7 por nome de
canal (`canal_nome_plataforma_key`; item 7 filtrado em 0,04 ms) e item 5 por
empresa. Os itens sem filtro e os top-k (8 a 11) agregam tabelas inteiras e
ordenam por um valor agregado, o que nenhum B-tree atende.

### Premissas e limitações

- Dados sintéticos com distribuição uniforme (exceto a concentração de canais nas
  plataformas 1 a 10), não os do seed. O `seed.sql` atual ainda usa as colunas
  antigas (`nome_canal`, `nro_plataforma` em `NivelCanal`, `Inscricao` etc.) e não
  roda contra este DDL. Não existe `seed_v2`.
- PostgreSQL 17.11 em Docker (aarch64), `shared_buffers` 128 MB, `work_mem` 4 MB,
  collation `en_US.utf8`. Sessão de medição com `jit = off` e
  `max_parallel_workers_per_gather = 0`. Cache quente.
- Ruído do ambiente de ±10 a 20% entre rodadas (a mesma consulta, sem nenhum
  índice envolvido, variou de 543 para 650 ms). Só diferenças muito acima disso
  foram tratadas como ganho. Na carga em lote houve picos isolados de até 74 s,
  absorvidos pela mediana.
- O tempo de carga não inclui o `COMMIT`/fsync. Não foram medidos: a latência de
  `INSERT` de uma linha, a concorrência, o efeito do *visibility map* e o ganho nas
  verificações de FK.
- Os números absolutos dependem da máquina. O que importa é a relação antes/depois.
- `ddl.sql` validado do zero em schema descartável (mesmo arquivo, nome do schema
  trocado): executou duas vezes seguidas sem erro e criou 29 índices (27 de
  PK/UNIQUE + 2 explícitos).

### Referências cruzadas

- DEC-014: `canal_nome_plataforma_key (nome, nro_plataforma)` atende o filtro por
  nome, mas não por plataforma.
- DEC-015: `video_canal_titulo_datah_key (id_canal, ...)` torna `Video (id_canal)`
  redundante.
- DEC-017: `comentario_pkey (id_video, seq)` e `doacao_pkey (id_video, ...)` já
  atendem o acesso por vídeo; o volume de `Comentario` pesa contra o índice C4.
- DEC-007: o filtro de `data_inscricao` não é seletivo.
- DEC-016: `CHECK` não consome o orçamento de índices.

### Aplicada no DDL: não (substituída pela DEC-034)
Onde estava: bloco "Índices de apoio" no fim do `ddl.sql`, com `idx_inscricao_nick_membro` e `idx_canal_nro_plataforma`. O bloco foi removido; os índices de apoio estão em `indices.sql` (DEC-034).

O `ddl.sql` não tinha nenhum índice explícito antes desta decisão (só os 27 de PK e UNIQUE).

---

## DEC-019 · Regra de alteração do modelo e remoção de `Inscricao.data_inscricao`

Substitui a DEC-007.

### Contexto

Na consulta de 2026-11-11 (00:15–00:32), o professor fixou o que pode mudar no
modelo relacional dado: "não pode criar coluna, não pode excluir coluna [...], não
pode tirar atributo derivado". A regra está no topo deste arquivo e vale como
critério para todas as decisões.

### Revisão das DECs contra a regra

| DEC | O que faz | Situação |
|---|---|---|
| 005, 008 | Tipo `INTEGER` em chaves | Mudança de tipo: pode |
| 006, 009, 010, 011, 016 | `UNIQUE`, `NOT NULL`, `CHECK` | Constraints: pode |
| 014, 015, 017, 021, 022, 023 | Surrogates `id_canal`, `id_video`, `id_usuario` e chaves dependentes | Remodelagem de chave: pode (o professor sugeriu `id_usuario`, 06:12) |
| **007** | `Inscricao.data_inscricao` | **Coluna comum fora de chave: não pode** |

### Decisão

Remover `Inscricao.data_inscricao` e o parâmetro `p_data_ref` dos itens 6, 9 e 11.
O minimundo já diz que "apenas os membros vigentes devem aparecer no sistema", então
a soma do valor mensal das inscrições existentes responde às consultas sem data.

As colunas novas que existem no DDL são todas de chave: `Usuario.id_usuario`,
`Canal.id_canal`, `Video.id_video` e as que os referenciam (`id_streamer`,
`id_membro`, `id_usuario`). Elas substituem as colunas de chave natural que se
propagavam (`nick`, `nome_canal` + `nro_plataforma`, `titulo` + `dataH`).

### Premissas e limitações

- Uma consulta "membros desde a data X" deixa de ser possível. O enunciado não pede.
- A data/hora do pagamento com cartão, que o minimundo cita, também não existe no
  modelo relacional dado; não foi criada pelo mesmo motivo (comentário no `ddl.sql`).

### Aplicada no DDL: sim
Onde: `Inscricao` sem `data_inscricao` no `ddl.sql`; functions 6, 9 e 11 sem `p_data_ref` no `procedures.sql`.

---

## DEC-020 · Cenário de volumetria: streaming de jogos com vídeo longo e curto

### Pergunta

O professor (02:06–03:57) deixou o grupo definir o tipo de vídeo e o volume, desde
que o mesmo cenário justifique tudo: tipos de chave, seed, índices e PDF. Ele
sugeriu a conta: "se você ficar filmando 24 horas todos os streamers [...] fazendo
um vídeo a cada 10 minutos, você não vai conseguir estourar"; "agora, se o cara
fica mandando um short de 10 em 10 segundos e replicando isso para 60
plataformas, aí não vai ter como".

### Decisão

O cenário de referência **inclui vídeo curto** (shorts, TikTok, Reels, Kwai) além
das lives e VODs de jogos, em dezenas de plataformas, com horizonte de 10 anos.

### Conta de capacidade (base de cada tipo de chave)

Números de referência (fontes secundárias, 2025):
[ITU, Facts and Figures 2025](https://www.itu.int/itu-d/reports/statistics/2025/10/15/ff25-internet-use):
6,0 bilhões de pessoas usam a internet (74% da população);
[ONU, World Population Prospects 2024](https://www.un.org/sustainabledevelopment/blog/2024/07/press-release-wpp2024/):
pico de cerca de 10,3 bilhões de pessoas por volta de 2084;
YouTube ~2,5 a 2,7 bilhões de usuários e TikTok ~1,6 a 1,9 bilhão
([Statista](https://www.statista.com/statistics/272014/number-of-us-social-network-users),
[Market.us](https://market.us/statistics/youtube)); YouTube Shorts com cerca de
12 milhões de uploads por dia (estimativa de blogs de estatística, sem fonte
oficial).

| Entidade | Cenário | Máximo em 10 anos | `INTEGER` (2,15 × 10^9) | `BIGINT` (9,22 × 10^18) | Tipo |
|---|---|---|---|---|---|
| Plataforma | dezenas a centenas | ~10^3 | sobra | — | `INTEGER` (DEC-005) |
| Empresa | todas as empresas do mundo | ~10^8 | sobra | — | `INTEGER` (DEC-008) |
| Usuario | pessoas na internet hoje (6,0 × 10^9); pico populacional 100% conectado (1,03 × 10^10); pior caso: cada pessoa com conta em 60 plataformas e 10 gerações de contas apagadas (id nunca reaproveitado) | 6,2 × 10^12 | **estoura já hoje** | 7 × 10^-7 do limite | `BIGINT` (DEC-022) |
| Canal | todo criador de vídeo curto tem canal; só o TikTok tem ~1,6–1,9 × 10^9 usuários; somando dezenas de plataformas | > 2,15 × 10^9 | estoura | sobra | `BIGINT` (DEC-023) |
| Video | ~10^8 vídeos por dia somando as plataformas (o Shorts sozinho tem ~1,2 × 10^7) → 3,7 × 10^11; pior caso do professor: 10^6 criadores, 1 short a cada 10 s, replicado em 60 plataformas → 1,9 × 10^15 | 1,9 × 10^15 | estoura | 0,02% do limite | `UUID v7` (DEC-021) |
| Comentario por vídeo | cauda longa; recorde de live na ordem de 10^7 mensagens | ~10^7 | sobra | — | `seq INTEGER` (DEC-024) |
| Doação por comentário | 1 a poucas | ~10 | sobra | — | `INTEGER` (DEC-024) |

### Consequências

1. `BIGINT` aguenta até o pior caso do professor. O que muda com o vídeo curto não
   é a capacidade, é a **forma de gerar o id**: nesse volume (exabytes) o banco
   não cabe num servidor só e passa a ser alimentado por coletores e partições que
   geram o id sem consultar uma sequence central. Isso leva ao UUID v7 em `Video`
   (DEC-021).
2. `Usuario` e `Canal` passam de 2,15 × 10^9 no cenário: `BIGINT`.
3. O seed v3 usa o mesmo cenário em escala reduzida (DEC-031): plataformas de vídeo
   curto têm mais vídeos por canal, vídeos curtos têm só comentários offline e
   menos comentários por visualização.

### Premissas e limitações

- Os números de usuários e uploads são de fontes secundárias e variam entre
  fontes; servem como ordem de grandeza, que é o que decide o tipo.
- O cenário não é estatística da UFF nem do grupo; é a hipótese que torna as
  decisões coerentes entre si.

### Aplicada no DDL: sim
Onde: tipos de `Usuario.id_usuario`, `Canal.id_canal`, `Video.id_video` e das colunas que os referenciam (DEC-021 a 024).

---

## DEC-021 · Chave de `Video`: UUID v7

Substitui a parte de tipo da DEC-015 (`BIGINT IDENTITY`). A surrogate e o
`UNIQUE (id_canal, titulo, dataH)` continuam.

### Pergunta

Com várias plataformas, o professor sugeriu avaliar outro identificador para o
vídeo, talvez UUID (01:42–03:57).

### Medição (banco descartável, 1 milhão de linhas, apagado depois)

| Variante | `Video` (tabela + PK) | `INSERT` de 1 mi | Índice da PK de `Comentario` (1 mi) |
|---|---|---|---|
| `BIGINT IDENTITY` | 64 MB | 2,8 s | 39 MB |
| UUID v4 (`gen_random_uuid()`) | 88 MB | 6,2 s | 50 MB |
| UUID v7 (function própria) | 88 MB | 5,7 s | 51 MB |

### Decisão e trade-off

`id_video UUID DEFAULT steam_do_bedo.uuid_v7()`, propagado para `Participa`,
`Comentario`, `Doacao` e as 4 formas de pagamento.

- **Por que UUID:** no cenário com vídeo curto (DEC-020) o id é gerado de forma
  distribuída. Cada coletor ou partição cria o vídeo sem consultar a sequence
  central, sem colisão e sem coordenação; dá para juntar dados de partições
  diferentes sem renumerar; e o id não é enumerável.
- **Por que v7 e não v4:** o v7 começa pelo instante em milissegundos, então ids
  novos caem no fim do B-tree, como uma sequence. O v4 é aleatório e espalha as
  inserções pelo índice inteiro (mais páginas sujas e *page splits* por inserção).
- **Custo aceito:** +37% de espaço em `Video`, +28% no índice da PK de
  `Comentario`, `INSERT` cerca de 2× mais lento, 16 bytes repetidos em 7 tabelas.
  Com `BIGINT` a capacidade também bastaria; o grupo paga esse custo pela geração
  distribuída.
- **Implementação:** o PostgreSQL 17 não tem `uuidv7()` (só o 18). O `ddl.sql`
  cria `uuid_v7(p_ts)`: 48 bits de timestamp + bits aleatórios do v4, com o
  nibble de versão trocado para 7 (RFC 9562). O seed gera o v7 a partir do
  `dataH` do vídeo, com bits derivados de uma semente, para ser reprodutível.

### Premissas e limitações

- Na medição acima o v7 ficou do mesmo tamanho que o v4: dentro do mesmo
  milissegundo a ordem é aleatória (sem contador), e a inserção em lote gera
  milhares de ids por milissegundo. Na inserção real (um vídeo por vez) a
  localidade é por milissegundo. No seed, os vídeos são inseridos em ordem de id.
- Migrar para o PostgreSQL 18 permitiria trocar a function por `uuidv7()` nativa.

### Aplicada no DDL: sim
Onde: function `steam_do_bedo.uuid_v7()`; `Video.id_video UUID`; `UUID` em `Participa`, `Comentario`, `Doacao`, `BitCoin`, `PayPal`, `CartaoCredito` e `MecanismoPlat`.

---

## DEC-022 · Surrogate em `Usuario`: `id_usuario BIGINT` com `UNIQUE (nick)`

Resolve o item 5 da DEC-017.

### Pergunta

O professor perguntou por que `Comentario` referencia `nick_usuario` e não um
`id_usuario` (06:01–06:23). O `nick VARCHAR(255)` era PK e se repetia em
`PlataformaUsuario`, `StreamerPais`, `Canal`, `Inscricao`, `Participa` e
`Comentario`.

### Medição (banco descartável, apagado depois)

| Tabela (volume) | `nick` (~13 caracteres) | `id_usuario BIGINT` |
|---|---|---|
| `Comentario` (1 mi) | 104 MB + 39 MB de índice | 104 MB + 39 MB |
| `Inscricao` (600 mil) | 34 MB + 36 MB | 30 MB (−12%) + 36 MB |

Em `Comentario` o tamanho não muda: o `BIGINT` ocupa o espaço que o alinhamento do
`dataH` (8 bytes) já desperdiçava. Com nicks mais longos, o texto ocuparia mais.

### Decisão

`id_usuario BIGINT GENERATED ALWAYS AS IDENTITY` como PK, `nick` com
`UNIQUE NOT NULL`, e as 6 FKs trocadas (`id_usuario`, `id_streamer`, `id_membro`).

### Justificativa

1. **Estabilidade:** o nick pode mudar (as plataformas permitem renomear). Com o
   nick como PK, renomear um usuário teria de atualizar milhões de comentários.
2. **Join por inteiro:** comparar `BIGINT` é mais barato que comparar texto com
   collation (`en_US.utf8`).
3. **`BIGINT` e não `INTEGER`:** a internet já tem 6,0 bilhões de pessoas e o pico
   populacional da ONU é de 10,3 bilhões, acima dos 2,15 × 10^9 do `INTEGER`
   (DEC-020). O `BIGINT` só deixaria de atender acima de ~9 × 10^8 contas por
   habitante. E não custa espaço em `Comentario`, pelo alinhamento.

### Custos e limitações

- Um índice a mais em `Usuario` (o `UNIQUE (nick)`). As consultas que filtram por
  nick (itens 3 e 6) passam por ele e depois seguem por id.
- Consultas que devolvem o nick precisam de `JOIN` com `Usuario`; as functions
  agregam por id e só juntam o nick no fim.

### Aplicada no DDL: sim
Onde: `usuario_pkey (id_usuario)`, `usuario_nick_key`; FKs `plataformausuario_id_usuario_fkey`, `streamerpais_id_streamer_fkey`, `canal_id_streamer_fkey`, `inscricao_id_membro_fkey`, `participa_id_streamer_fkey`, `comentario_id_usuario_fkey`.

---

## DEC-023 · `Canal.id_canal` passa a `BIGINT`

Substitui a parte de tipo da DEC-014 (`INTEGER`).

### Decisão

`id_canal BIGINT`, propagado para `Patrocinio`, `NivelCanal`, `Inscricao` e `Video`.

### Justificativa

No cenário com vídeo curto (DEC-020), todo criador de shorts tem canal. Só o
TikTok tem cerca de 1,6 a 1,9 bilhão de usuários; somando dezenas de plataformas e
10 anos, os canais passam de 2,15 × 10^9.

### Custo

+4 bytes por linha em `NivelCanal`, `Inscricao`, `Patrocinio` e `Video` e nos
índices que começam por `id_canal`. `Comentario` e `Doacao` não têm `id_canal`
(chegam ao canal pelo vídeo), então as maiores tabelas não pagam.

### Aplicada no DDL: sim
Onde: `Canal.id_canal BIGINT` e `id_canal BIGINT` em `Patrocinio`, `NivelCanal`, `Inscricao` e `Video`.

---

## DEC-024 · Chaves dependentes: `seq`, `seq_pg`, `seq_doacao` e `seq_plataforma` `INTEGER`

### Decisão

- `Comentario.seq INTEGER` (confirmado): o máximo do cenário, ~10^7 comentários
  num vídeo (DEC-020), cabe com folga. Comentário não tem chave própria; fica
  dependente do vídeo, `(id_video, seq)`, como o professor confirmou (03:07, 05:49).
- `Doacao.seq_pg`, `seq_doacao` (nas 4 formas) e `MecanismoPlat.seq_plataforma`:
  de `BIGINT` para `INTEGER`. São contadores por comentário ou por (usuário,
  plataforma), de poucas unidades.

### Justificativa

Com `UUID` (16 bytes) + `INTEGER` + `INTEGER`, a chave de `Doacao` e das formas
fecha em 24 bytes sem preenchimento de alinhamento; com `BIGINT` seriam 32.

### Aplicada no DDL: sim
Onde: tipos de `seq_pg`, `seq_doacao` e `seq_plataforma` no `ddl.sql`; geração por T3, T4 e T5 (DEC-027).

---

## DEC-025 · Constraints revisadas (item mandatório 2)

### Contexto

Depois das trocas de chave (DEC-021 a 024), toda chave natural que deixou de ser PK
precisa de `UNIQUE` + `NOT NULL`, e o plano pedia avaliar `UNIQUE` em `TxID` e
`IdPayPal`.

### Decisão

| Constraint | Regra de negócio | Custo |
|---|---|---|
| `usuario_nick_key UNIQUE (nick)`, `nick NOT NULL` | o nick identifica o usuário no minimundo | índice em `Usuario` (DEC-022) |
| `plataformausuario_nro_usuario_key UNIQUE (nro_plataforma, nro_usuario)` | o número de usuário identifica a conta dentro da plataforma | índice numa tabela de ~10^6 linhas, escrita rara |
| `streamerpais_passaporte_key UNIQUE (ddi_pais, nro_passaporte)` | o número do passaporte é único no país emissor | tabela pequena |
| `empresapais_id_nacional_key UNIQUE (ddi_pais, id_nacional)`, `id_nacional NOT NULL` | CNPJ, EIN etc. são únicos no país; é a identidade real da empresa (DEC-009) | tabela pequena |
| `pais_nome_key UNIQUE (nome)` | dois países com o mesmo nome seriam duplicata | tabela pequena |
| `bitcoin_txid_key UNIQUE (TxID)` | o TxID é o hash da transação na blockchain; não se repete | índice na menor forma de pagamento |
| `paypal_idpaypal_key UNIQUE (IdPayPal)` | o IdPayPal identifica um pagamento | índice em `PayPal` |
| `Usuario.pais_residencia NOT NULL` | o minimundo dá "um país de residência" a todo usuário; a conversão da doação (T11) depende dele | nenhum; substitui a premissa 2 da DEC-001 |
| `Plataforma.data_fund NOT NULL` | "uma data de fundação"; usada pelo T7 | nenhum |
| `Canal.data NOT NULL` | "data de início"; usada pelo T7 | nenhum |
| `NivelCanal.gif NOT NULL` | "para cada nível existe um arquivo .gif" | nenhum |
| `video_visu_simul_total_check CHECK (visu_simul <= visu_total)` | o pico simultâneo não passa do total (estava proposto na DEC-016) | nenhum |
| `canal_tipo_check`, `doacao_status_check` | os `CHECK` do enunciado, agora com nome explícito | nenhum |

Esses índices são de `UNIQUE` e não contam no teto de 5 índices de apoio (o teto
vale para os índices criados para desempenho, DEC-034).

### Premissas e limitações

- `Usuario.telefone` continua nulável (DEC-011): o `UNIQUE` aceita vários nulos.
- `UNIQUE (TxID)` e `UNIQUE (IdPayPal)` custam um índice cada em tabelas que
  crescem com as doações (1% a 5% dos comentários). Aceito por ser regra de negócio
  real: um pagamento duplicado é um erro que o banco deve barrar.
- O DDI do mundo real não é único (+1, +7); o seed usa o prefixo que distingue o
  país (DEC-031).

### Aplicada no DDL: sim
Onde: as constraints nomeadas da tabela acima, no `ddl.sql`.

---

## DEC-026 · Moeda: patrocínio em USD e doação gravada em USD no `INSERT`

Fecha os pontos em aberto das DEC-003 e 004.

### Contexto

O professor (12:09–15:14): o patrocínio "bota sempre em dólar", porque vem de um
contrato externo; a doação é convertida pelo país de residência do usuário, e
"as duas [formas] estão certas": converter no `INSERT` (valor **histórico**, quanto
o streamer recebeu no dia) ou na consulta (valor **corrigido**, quanto vale hoje).

### Decisão

- **Patrocínio:** `Patrocinio.valor` em USD, sem conversão.
- **Doação:** o `INSERT` informa o valor na moeda do país de residência de quem
  comentou (`Comentario.id_usuario` → `Usuario.pais_residencia` → `Pais.moeda` →
  `Conversao.fator_conver`). O trigger **T11** multiplica pelo fator e grava em USD
  com 2 casas. As consultas somam direto, sem conversão.
- **Membros:** continuam convertidos na consulta (DEC-001), pela view V2.

### Justificativa

- O grupo escolheu o valor histórico: é o que o canal efetivamente recebeu, e a
  maioria dos grupos também grava (segundo o professor). As consultas 4, 7, 10 e
  11 ficam mais simples e baratas (sem join com `Usuario`, `Pais` e `Conversao` nas
  doações).

### Premissas e limitações

- O valor em moeda local se perde: não se pode criar coluna (DEC-019), e
  `Conversao` não guarda histórico de câmbio para reconstruí-lo.
- Doação e membros ficam em critérios diferentes (histórico x corrigido). Para o
  propósito do sistema (escolher que canal patrocinar), os dois são comparáveis em
  USD; a diferença é o câmbio do dia.
- Doação que vira menos de US$ 0,01 é rejeitada pelo T11.
- O seed grava as doações já em USD (T11 não existe na carga), convertendo um valor
  em moeda local como o trigger faria.

### Aplicada no DDL: sim
Onde: comentários de `Patrocinio.valor` e `Doacao.valor` no `ddl.sql`; trigger `trg_t11_doacao_usd` em `triggers.sql`; views V1 e V4.

---

## DEC-027 · Triggers T1 a T11 (item mandatório 5)

### Contexto

O enunciado pede "triggers para manter a consistência do BD (todas as necessárias
via requisitos)". O professor separa os triggers num arquivo executado **depois** da
carga, "para não ter problema na hora de fazer inserção" (11:30), e confirmou que
`qtd_visualizacoes` é a soma bruta de `visu_total` e que `qtd_users` segue o mesmo
raciocínio (16:20–17:53).

### Decisão

| ID | Regra (origem) | Tabela e evento | Comportamento |
|---|---|---|---|
| T1 | `Canal.qtd_visualizacoes` = soma de `visu_total` (derivado) | `Video`: `AFTER INSERT/UPDATE/DELETE`, **por comando** com tabelas de transição | Soma o delta por canal; troca de canal subtrai do antigo e soma no novo |
| T2 | `Plataforma.qtd_users` = contas em `PlataformaUsuario` (derivado) | `PlataformaUsuario`: idem, por comando | +1/−1 por conta, por plataforma |
| T3 | `seq` "depende do vídeo" | `Comentario`: `BEFORE INSERT` | Se `seq` vier nulo: trava o vídeo (`FOR UPDATE`) e usa `max(seq) + 1` |
| T4 | `seq_pg` "depende do vídeo, do usuário e do comentário" | `Doacao`: `BEFORE INSERT` | Se nulo: trava o comentário e usa `max(seq_pg) + 1` |
| T5 | `seq_plataforma` "depende do usuário, do comentário e da plataforma" | `MecanismoPlat`: `BEFORE INSERT` | Se nulo: sequência por (usuário, plataforma), travando a conta; exige conta na plataforma |
| T6 | Especialização disjunta ("d" no ER) e total ("pode ser feita de quatro formas") | 4 formas: `BEFORE INSERT/UPDATE`; `Doacao` e formas: *constraint trigger* adiado | Rejeita a segunda forma; no `COMMIT`, rejeita doação sem forma |
| T7 | Coerência temporal (escolha do grupo) | `Comentario`, `Video`, `Canal`, `Plataforma` | Fundação ≤ canal ≤ vídeo ≤ comentário, nos dois sentidos |
| T8 | "Existem cinco níveis de membros" | `NivelCanal`: `BEFORE INSERT/UPDATE OF id_canal` | Rejeita o sexto nível |
| T9 | Dono do canal e participante do vídeo são streamers (ER: especialização com passaporte) | `Canal`, `Participa`, `StreamerPais` | Exige passaporte; rejeita apagar o último passaporte de quem tem canal |
| T10 | "Tem conta" do ER | `Canal`, `PlataformaUsuario` | Exige conta do dono na plataforma do canal; rejeita apagar essa conta |
| T11 | Doação em USD (DEC-026) | `Doacao`: `BEFORE INSERT` | Converte o valor pela moeda do país de residência |

O minimundo diz que não há histórico de patrocínios e membros: isso se resolve com
`DELETE` e não precisa de trigger.

### Justificativas de implementação

- **T1 e T2 por comando** (`REFERENCING NEW/OLD TABLE`): um `INSERT` de milhares de
  vídeos do mesmo canal faz um `UPDATE` no canal, e não milhares. O PostgreSQL não
  aceita tabela de transição com mais de um evento nem com `UPDATE OF`, então são
  três triggers por tabela. Os canais são atualizados em ordem de id, para que
  comandos concorrentes travem na mesma ordem e não entrem em deadlock.
- **T3, T4 e T5 com `SELECT ... FOR UPDATE`** na linha "pai" antes do `max + 1`:
  sem a trava, duas inserções simultâneas calculariam o mesmo número e a segunda
  falharia pela PK. Custo: inserções no mesmo vídeo (ou comentário, ou conta)
  ficam em fila; em pais diferentes, não se bloqueiam. O `max` usa o prefixo da PK.
- **T8 e T9 com `FOR NO KEY UPDATE` / `FOR KEY SHARE`**, para não bloquear as
  verificações de FK de outras transações.
- **T10 como trigger e não FK:** daria para declarar FK de `Canal` para
  `PlataformaUsuario`, mas isso mudaria os relacionamentos do modelo dado (DEC-019).
- **T10 não vale para `Comentario` e `Inscricao`:** conferir a conta a cada
  comentário custaria uma busca a mais na maior tabela.
- **T5 sem índice próprio:** o `max` percorre `MecanismoPlat` e confere usuário e
  plataforma pela PK de `Comentario` e de `Video`. Escrita rara; não vale gastar uma
  das 5 vagas de índice (DEC-034).

### Consequência para o seed

Como os triggers só existem depois da carga, o `seed_v3.sql` obedece às mesmas
regras e calcula os derivados no próprio `INSERT`, e uma conferência no fim aborta
a carga se alguma regra falhar (DEC-031).

### Evidência

`testes_triggers.sql`: para cada trigger, um caso aceito e um rejeitado, mais a
conferência dos derivados depois de `INSERT`, `UPDATE` e `DELETE`, numa transação
desfeita com `ROLLBACK`. Resultado em `seed_v3_RELATORIO.md`.

### Premissas e limitações

- A concorrência não foi testada (exigiria duas sessões simultâneas).
- T7 não sabe da data de encerramento de uma plataforma (o Mixer acabou em 2020): o
  modelo não tem essa coluna.
- O "atualização periódica" do `qtd_users` permitiria um recálculo agendado; o
  trigger mantém o valor sempre exato.

### Aplicada no DDL: sim (em arquivo separado)
Onde: `triggers.sql`, functions `fn_t01_*` a `fn_t11_*` e triggers `trg_t01_*` a `trg_t11_*`.

---

## DEC-028 · Views: 2 virtuais e 2 materializadas (item mandatório 3)

### Decisão

| ID | Nome | Tipo | Conteúdo | Atende | Por quê |
|---|---|---|---|---|---|
| V1 | `vw_doacao_recebida` | Virtual | Doações não recusadas, em USD, com canal e plataforma | Itens 4, 7 e a V4 | Centraliza a regra de status (DEC-003) e o caminho doação → vídeo → canal. Virtual para que os filtros (canal, plataforma) desçam até os índices das tabelas base |
| V2 | `vw_inscricao_usd` | Virtual | Inscrições com o valor do nível em moeda local e em USD | Item 6 e a V4 | Centraliza a conversão dos membros (DEC-001) |
| V3 | `mv_interacoes_video` | Materializada | Comentários online, offline e total por vídeo | Itens 2 e 3 | `Comentario` é a maior tabela (5 mi); contá-la domina o tempo. Contagem de comentários tolera atraso |
| V4 | `mv_faturamento_canal` | Materializada | Patrocínio, membros, doações e total em USD por canal | Itens 8 a 11 | Top-k ordenado por um agregado, que nenhum índice nas tabelas base atende. Para escolher que canal patrocinar, um atraso de horas é aceitável |

A V5 (streamers e canais por plataforma, item 12) não foi criada: o item 12 lê
`Canal` (~36 mil linhas) e fica em milissegundos sem view.

### Refresh

Periódico, por um agendador externo (cron ou pg_cron), com
`CALL steam_do_bedo.sp_refresh_views()`, que faz `REFRESH MATERIALIZED VIEW
CONCURRENTLY` nas duas (não bloqueia leituras). Não é disparado por trigger:
recontar a cada comentário custaria mais que a consulta. O custo do refresh foi
medido (DEC-034).

### Índices das materializadas e o teto de 5 (P09)

O grupo decidiu que **o índice de view materializada conta no teto de 5 índices de
apoio**, para não deixar dúvida na avaliação. Cada materializada tem um índice
`UNIQUE`, exigido pelo `REFRESH ... CONCURRENTLY`:

- `ux_mv_interacoes_video (id_canal, id_video)`: com `id_canal` na frente, também
  atende os itens 2 e 3 filtrados (vídeos de um canal);
- `ux_mv_faturamento_canal (id_canal)`.

Sobram 3 vagas para as tabelas base (DEC-034).

### Premissas e limitações

- Os itens 2, 3 e 8 a 11 refletem o último refresh; os demais são exatos.
- A comparação consulta direta × view virtual × materializada está na DEC-033.

### Aplicada no DDL: sim (em arquivo separado)
Onde: `views.sql`.

---

## DEC-029 · Functions ajustadas ao modelo final e item 12

### Decisão

- Todas as functions foram ajustadas às chaves novas (DEC-021 a 023): agregam por
  id e juntam nome e nick no fim. Consultas que listam canais devolvem nome **e**
  plataforma, porque o nome só é único por plataforma (o item 5 agrupava por nome e
  juntava canais homônimos de plataformas diferentes; corrigido).
- Itens 6, 9 e 11 sem `p_data_ref` (DEC-019).
- Doações em USD sem conversão na consulta (DEC-026); membros pela V2.
- **Item 12 (desafio):** `sp_obter_top_k_plataformas_por_streamers_e_canais(p_k,
  p_plataforma DEFAULT NULL)`. **Substituído pela DEC-035** (interpretação revista,
  posição global, empates, bordas, medição e validação). Conta, por plataforma, os streamers distintos com
  canal nela e os canais, ordena por streamers e desempata por canais (o "E" do
  enunciado, nessa ordem). Devolve também `qtd_users` como contexto.
- Todas continuam `LANGUAGE sql STABLE`, para o planejador expandir a function e
  transformar `p IS NULL OR col = p` em `col = p` quando o parâmetro é constante.

### Premissas e limitações

- "Streamer da plataforma" = streamer com canal nela; ter só conta não basta.
- O `queries.sql` usa valores reais do seed v3, obtidos por consulta.

### Aplicada no DDL: sim (em arquivo separado)
Onde: `procedures.sql` e `queries.sql`.

---

## DEC-030 · Ordem de execução dos arquivos

### Decisão

```
ddl.sql -> seed_v3.sql -> views.sql -> procedures.sql -> triggers.sql -> indices.sql -> queries.sql
                                                             (testes_triggers.sql depois de triggers.sql)
```

### Justificativa

- **Triggers depois da carga:** orientação do professor (11:30). Os triggers por
  linha (T3 a T11) pesariam milhões de vezes na carga, e o seed já obedece às regras.
- **Views antes das procedures:** as functions dependem delas; e as materializadas
  são preenchidas na criação, então precisam dos dados.
- **Índices de apoio depois da carga:** criar o índice sobre a tabela pronta é mais
  rápido que mantê-lo linha a linha durante a carga. Por isso os índices da DEC-018
  saíram do `ddl.sql` e estão em `indices.sql` (DEC-034). O `ddl.sql` só tem os
  índices de PK e `UNIQUE`.

### Aplicada no DDL: sim
Onde: cabeçalho de cada arquivo e do `ddl.sql`.

---

## DEC-031 · Seed v3: volume e distribuições autorizados pelo professor

Substitui o critério de volume do seed v2 (1.000 a 10.000 linhas por tabela).

### Contexto

O item mandatório 1 pede "entre 1000 e 10.000 tuplas por tabela". O professor
(04:09–05:31) disse que esse número é "só de referência", que não espera 10 mil
países, e pediu para "povoar o máximo que você conseguir, idealmente com centenas
de milhares de tuplas", com "distribuição desbalanceada": canais com muito mais
vídeos que outros e vídeos com muito mais comentários que outros.

### Decisão

- **Tabelas de referência no tamanho real**, abaixo de 1.000 linhas (autorizado):
  154 moedas ISO 4217, 199 países, 28 plataformas reais de vídeo longo e curto e
  3.000 empresas (cerca de 80 reais). Acabam as ~960 linhas fictícias do seed v2.
- **Tabelas grandes no máximo viável** no Docker local (5,8 GB de memória), na
  proporção do cenário da DEC-020, com escala ajustável (`-v escala=`). Na escala 1:

  | Tabela | Linhas | Tabela | Linhas |
  |---|---|---|---|
  | Usuario | 500.000 | Video | 1.247.319 |
  | PlataformaUsuario | 856.263 | Participa | 94.415 |
  | StreamerPais | 26.081 | Comentario | 5.000.143 |
  | Canal | 35.906 | Doacao | 99.510 |
  | NivelCanal | 98.855 | BitCoin | 9.669 |
  | Inscricao | 598.075 | PayPal | 21.494 |
  | Patrocinio | 18.785 | CartaoCredito | 23.719 |
  | EmpresaPais | 3.471 | MecanismoPlat | 44.628 |

- **Distribuições desbalanceadas e correlacionadas** (detalhes no
  `seed_v3_RELATORIO.md`): popularidade lognormal por canal (σ = 2,2) que comanda
  visualizações, número de vídeos, membros e patrocínio; comentários por vídeo
  proporcionais a `visu_total^0,85` com ruído (cauda longa); autores de comentário
  e membros sorteados por lei de potência (poucos usuários muito ativos); países
  e plataformas com pesos de mercado; 5% dos usuários são streamers (eram 25% no
  v2); 1,9% dos comentários com doação (eram 50%).
- **Obedece às regras dos triggers** (DEC-027) e calcula os derivados no próprio
  `INSERT`, a partir de tabelas temporárias de preparação (sem `UPDATE` final e sem
  tuplas mortas). Uma conferência no fim aborta a transação se qualquer regra
  falhar.
- **Doação em USD** (DEC-026): o valor é sorteado em moeda local e convertido como o
  T11 faria.

### Cuidados descobertos na validação

- O autovacuum nunca analisa tabela temporária. Sem `ANALYZE` nelas, o planejador
  escolhia nested loop com varredura completa nos JOINs de sorteio e a carga
  travava; cada tabela temporária recebe `ANALYZE` logo após a criação.
- `enable_memoize = off` na carga: o *Memoize* guardava o resultado de subconsultas
  `LATERAL` com `random()` pela chave de entrada e repetia o mesmo sorteio (só 0,39%
  dos comentários ficavam com doação e todos os vídeos tinham o mesmo convidado).
- O DDI do mundo real não é único (+1, +7): países do Caribe no +1 usam 1 + código
  de área, o Canadá usa 1613, o Cazaquistão 77 e o Vaticano 379.
- O sorteio do autor do comentário e do membro usa `LATERAL` pela chave única da
  tabela de contas: com `JOIN` comum, numa das cargas o planejador escolheu um plano
  que levou mais de 14 minutos só em `Comentario`.

### Premissas e limitações

- Conteúdo artificial (o professor aceitou, 05:02). Pesos e taxas são do grupo,
  inspirados em ordens de grandeza reais, não em estatística oficial.
- A carga completa leva cerca de 9 minutos e ocupa cerca de 2 GB; para entregar,
  o arquivo é pequeno (os dados são gerados), e a escala 0,1 roda em menos de 1 min.

### Aplicada no DDL: sim (no seed)
Onde: `seed_v3.sql` e `seed_v3_RELATORIO.md`.

---

## DEC-032 · Protocolo de medição a frio

### Contexto

O professor (08:46–10:33) alertou que "o SGBD tem cache": repetir a consulta faz ela
vir da memória, e com poucos dados a árvore do índice cabe numa página, então o
índice não faz diferença. A DEC-018 tinha medido com cache quente e dados
uniformes.

### Decisão

`bench/medir.sh` faz, antes de **cada** medida a frio:

1. `docker stop` do container de aferição: o processo do Postgres morre e o
   `shared_buffers` é esvaziado;
2. `echo 3 > /proc/sys/vm/drop_caches` num container privilegiado: esvazia o cache
   de páginas da VM Linux do Docker Desktop, que sobrevive ao restart do container;
3. `docker start` e espera o banco aceitar conexão;
4. **uma** consulta com `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)`.

Cada célula da matriz tem 5 repetições a frio e 5 a quente (depois de 1 execução de
aquecimento), e o valor usado é a **mediana**. A medida a frio é comprovada pelos
buffers da raiz do plano: `shared read` > 0 (páginas vindas do disco). A quente é um
cenário separado, para mostrar quanto o cache esconde.

### Configuração fixa

- PostgreSQL 17.11 (Docker `postgres:17`, aarch64), `shared_buffers` 128 MB,
  `work_mem` 4 MB (padrão), em `bench/configuracao.txt`.
- Na sessão de medida: `jit = off` (a compilação JIT soma tempo variável) e
  `max_parallel_workers_per_gather = 0` (um processo só, tempos comparáveis).
- Container separado (`stream-bench`), autorizado pelo usuário, para não reiniciar
  o banco do projeto.

### Limitações

- O planejamento a frio inclui carregar o catálogo; por isso tempo de planejamento
  e de execução são registrados separados, e os gráficos usam o de execução.
- O disco é o da VM do Docker no Mac (SSD): os tempos absolutos dependem da máquina;
  o que importa é a relação entre cenários.

### Aplicada no DDL: não se aplica
Onde: `bench/medir.sh` e `bench/aferir.py`.

---

## DEC-033 · Reescrita das consultas antes dos índices

### Contexto

O professor (08:25–08:39) orientou deixar as consultas "o melhor que você conseguir"
antes de criar índices. A DEC-018 já apontava que os itens 2 e 3 agregavam
`Comentario` inteira antes de filtrar o canal ou o streamer.

### Medição (a frio, mediana de 5, sem índices de apoio; `bench/resultados.csv`)

| Consulta | Original (agrega tudo, depois filtra) | Reescrita direta (filtra antes, 1 passada) | Final (view materializada V3) |
|---|---|---|---|
| Item 2, sem filtro | 7.951 ms | 14.642 ms | 10.247 ms |
| Item 2, filtro por canal | 3.730 ms | 828 ms | 326 ms |
| Item 3, sem filtro | 5.964 ms | 29.955 ms | 853 ms |
| Item 3, filtro por streamer | 6.799 ms | 979 ms | 175 ms |

| Consulta (top-k) | Direta nas tabelas | Sobre as views virtuais V1/V2 | View materializada V4 |
|---|---|---|---|
| Item 10, k = 10 | 2.409 ms | 1.569 ms | 26 ms |
| Item 11, k = 10 | 4.022 ms | 3.312 ms | 52 ms |

### Decisão

1. **Filtrar antes de agregar** nas consultas com filtro: a reescrita direta já reduz o
   item 2 filtrado em 4,5× e o item 3 filtrado em 7×, porque os comentários passam a
   ser lidos só dos vídeos do canal, pela PK `(id_video, seq)`.
2. **Sem filtro, a reescrita direta piora** (agrupar 5 mi de linhas por vídeo com
   chaves largas estoura o `work_mem` de 4 MB e ordena em disco). Por isso os itens 2
   e 3 leem a **view materializada V3** (DEC-028), que já tem a contagem por vídeo:
   item 3 sem filtro 5.964 → 853 ms (7×), item 3 filtrado 6.799 → 175 ms (39×),
   item 2 filtrado 3.730 → 326 ms (11×).
3. **Item 2 sem filtro continua caro** (~10 s) com qualquer forma: ele devolve e
   ordena 1,25 milhão de vídeos. O custo é a ordenação externa da saída, não a
   leitura. Na prática a consulta é usada com `LIMIT` (no `queries.sql`, as 10
   primeiras linhas), e o planejador faz *top-N heapsort* em memória.
4. **Item 3 em dois ramos excludentes** (`UNION ALL` com `p IS NULL` e `u.nick = p`):
   com o parâmetro constante, o planejador elimina o ramo que não serve, então o caso
   sem filtro agrega a V3 numa passada (3,0 → 1,5 s a quente) e o caso com filtro usa
   o índice.
5. **Views virtuais não aceleram por si**: V1/V2 ficam no mesmo patamar da consulta
   direta (o planejador as expande). A diferença de 2,4 s para 1,6 s no item 10 vem do
   plano (a V1 já junta o canal antes de agrupar), não da view. A materializada V4 é a
   que muda a ordem de grandeza (60 a 90×).
6. Todas continuam `LANGUAGE sql STABLE`, para o planejador expandir a function e
   usar índice no filtro opcional.

### Premissas e limitações

- As versões originais e alternativas estão em `bench/consultas_alternativas.sql`
  (schema `bench`, só para aferição).
- O ganho da V3 e da V4 vale para o dado do último refresh (DEC-028); o refresh da V3
  custa 8 s (comum) a 19–24 s (concorrente).

### Aplicada no DDL: sim (em arquivo separado)
Onde: `procedures.sql` (itens 2, 3 e 8 a 11 sobre V3/V4; item 3 em dois ramos).

---

## DEC-034 · Índices de apoio revisados (item mandatório 4)

Substitui a DEC-018.

### Contexto

A DEC-018 escolheu `Inscricao (nick_membro)` e `Canal (nro_plataforma)` medindo com
cache quente, dados uniformes e as chaves antigas. O professor pediu para escolher
pelos predicados e pela distribuição (07:03–08:16), considerar hash quando o predicado
é só de igualdade, e medir a frio (DEC-032).

### Método

1. Inventário dos predicados das 12 functions e das views, com a distribuição de cada
   coluna em `pg_stats` (`bench/predicados.md`, `bench/estatisticas.txt`).
2. Linha de base de todas as functions, com e sem filtro, só com PK, `UNIQUE` e os
   `UNIQUE` das materializadas, a frio e a quente (`bench/aferir.py`, fase `base`).
3. Mesmas consultas com os candidatos em B-tree (fase `indices`) e com hash nos de
   igualdade pura (fase `hash`); conjunto final (fase `final`).
4. Overhead de `INSERT` em lote (300 mil linhas em ordem aleatória numa cópia da
   tabela, com e sem o índice; mediana de 3) e tamanho (`bench/escrita.csv`,
   `bench/tamanhos.csv`).

### Decisão: os 5 índices (o teto conta os das views materializadas, DEC-028)

| # | Índice | Tipo | Consulta atendida | Ganho medido (mediana de 5) | Custo |
|---|---|---|---|---|---|
| 1 | `ux_mv_interacoes_video (id_canal, id_video)` | B-tree `UNIQUE` | itens 2 e 3 (V3); exigido pelo `REFRESH CONCURRENTLY` | item 3 filtrado lê 1.554 → 892 páginas com o índice 4 junto | 48 MB |
| 2 | `ux_mv_faturamento_canal (id_canal)` | B-tree `UNIQUE` | itens 8 a 11 (V4); exigido pelo `REFRESH CONCURRENTLY` | — (obrigatório) | 0,5 MB |
| 3 | `idx_inscricao_id_membro` | B-tree | item 6 com usuário; FK ao remover usuário | a frio 160 → 7 ms (22×); páginas 4.040 → 54; a quente 91 → 1,4 ms | 10 MB; `INSERT` +59% |
| 4 | `idx_canal_id_streamer` | B-tree | item 3 com streamer; T9 e T10 ("tem canal?"); FK | páginas 1.554 → 892; a quente 9 → 1,3 ms; a frio ~150 ms nos dois (ruído) | 0,7 MB; `INSERT` +17% |
| 5 | `idx_video_id_canal_cobertura (id_canal) INCLUDE (visu_total)` | B-tree de cobertura | item 1 com plataforma | Kick: a frio 587 → 341 ms, a quente 257 → 22 ms; páginas 25.526 → 9.530 | 38 MB; `INSERT` +9% |

### Justificativa de cada escolha

- **3 e 4 (igualdade seletiva):** a PK de `Inscricao` começa por `id_canal` e `Canal`
  não tinha índice em `id_streamer`; os planos varriam a tabela. Um membro tem ~1,9
  inscrições e um streamer ~1,4 canal: o filtro devolve 0,0025% e 0,014% da tabela.
- **5 (cobertura):** o item 1 conta vídeos e soma `visu_total` por canal. Os vídeos de
  um canal estão espalhados na tabela (correlação física 0,01, porque a ordem física
  segue o UUID v7, isto é, o tempo), então ler pela tabela custa uma página por vídeo.
  Com `visu_total` no `INCLUDE`, o plano vira *Index Only Scan*.
- **Hash x B-tree (igualdade pura, itens 3 e 6):** o hash leu as mesmas páginas e teve
  o mesmo tempo a quente (item 6: 0,6 contra 1,4 ms; item 3: 1,4 contra 1,3 ms), ficou
  **maior** (10,6 MB contra 8,7 MB no lote de `Inscricao`; 1,35 contra 1,08 MB em
  `Canal`) e não inseriu mais rápido (diferença dentro do ruído). Ficou o B-tree, que
  também entrega em ordem e é o que a verificação de FK usa com a mesma eficiência.

### Candidatos descartados

| Candidato | Resultado | Motivo |
|---|---|---|
| `Canal (nro_plataforma)` (DEC-018) | sem ganho: item 12 com Kick lê 672 → 588 páginas e fica em 14 ms sem e 69 ms com (ruído a frio); itens 1 e 4 com Kick continuaram varrendo `Video` | `Canal` tem 951 páginas e é lida em milissegundos; o custo estava em `Video` (resolvido pelo índice 5) |
| Hash em `Inscricao (id_membro)` e `Canal (id_streamer)` | mesmas páginas, índice maior | ver acima |
| `Doacao (status)` parcial | não medido de novo | `<> 'recusado'` devolve 89,9% de `Doacao` (predicado concentrado) |
| Índice para o top-k da V4 (`vr_* DESC`) | não criado | ordenar ~23 mil linhas custa milissegundos (itens 8 a 11 em 26 a 52 ms a frio); seriam 4 índices, um por coluna |
| `Comentario (id_usuario)` | não criado | nenhuma function filtra comentários por usuário; custaria um índice na maior tabela |

### Consultas que não mudam com índice (predicados concentrados ou leitura integral)

Os itens sem filtro (1, 4, 6, 7) e o item 1 com o YouTube (28% dos canais) leem a
maior parte das tabelas: o planejador mantém a varredura, com e sem índice (é o caso
"todos americanos" do professor). Os gráficos 01 e 02 mostram tempo e páginas iguais
nesses itens.

### Overhead de escrita das views materializadas

`REFRESH` da V3: 8 s comum e 19–24 s concorrente (1,25 mi de linhas); da V4: 1,1 a
2,1 s. Por isso o refresh é periódico e não por trigger (DEC-028).

### Premissas e limitações

- A frio, consultas de poucos milissegundos variam dezenas de ms entre repetições
  (latência do primeiro acesso ao disco e ao catálogo); por isso, para elas, as
  páginas lidas são a métrica principal, e a quente é complementar.
- O item 2 sem filtro variou de 10 s para 15 s entre fases sem nenhuma mudança de
  plano ou de páginas lidas: é a ordenação externa da saída, sensível ao disco da VM.
- O *index-only scan* do índice 5 depende do *visibility map*: em produção, com
  inserção contínua em `Video`, o `VACUUM` precisa estar em dia.
- Números absolutos dependem da máquina (Docker no Mac, SSD); vale a relação.

### Gráficos (`bench/graficos/`)

`01_tempo_indices_frio.png`, `02_buffers_indices.png`, `03_reescrita.png`,
`04_views.png`, `05_ganho_overhead.png`, `06_frio_quente.png`, `07_hash_btree.png`.

### Aplicada no DDL: sim (em arquivo separado)
Onde: `indices.sql` (índices 3 a 5) e `views.sql` (índices 1 e 2); o bloco de índices
do `ddl.sql` foi removido.

---

## DEC-035 · Item 12 (desafio): top-k plataformas por streamers E canais

Substitui a parte do item 12 da DEC-029.

### Enunciado

"Listar as top-k plataformas pela quantidade de streamers **E** canais. Dar a opção
de filtrar por plataforma como parâmetro opcional na forma de uma stored procedure."
O minimundo existe para "responder questões sobre o alcance de público" (e o
professor lembrou que o sistema serve para escolher o que patrocinar, 14:50).

### Interpretação (decidida antes do código)

**1. Quem é "streamer da plataforma".** Medido no seed v3 (escala 1):

| Interpretação | YouTube | Twitch | Kick | Efeito |
|---|---|---|---|---|
| **Dono de ao menos um canal na plataforma (escolhida)** | 10.092 | 3.036 | 1.252 | conta quem publica ali |
| Streamer com conta (`PlataformaUsuario` ∩ `StreamerPais`) | 11.900 | 3.669 | 1.539 | conta também quem só tem conta e nunca publicou; o ranking quase não muda (troca Kuaishou e Snapchat) |
| Dono ou convidado (`Participa`) | 21.120 | 13.869 | 6.929 | dobra ou quintuplica as plataformas de live: o convidado de uma colaboração aparece no canal de outro e pode nem ter conta na plataforma |

Escolhida a primeira. Ter conta não gera público (o canal é que publica), e o
convidado já está no alcance do canal de quem publicou; contá-lo infla as plataformas
de live com a mesma audiência. Contagem com `COUNT(DISTINCT id_streamer)`: quem tem
dois canais na mesma plataforma conta uma vez como streamer e duas como canal.

**2. O "E" sublinhado: ordenação lexicográfica (streamers, depois canais).**

| Alternativa | Por que não |
|---|---|
| Critério combinado (streamers + canais, ou ponderado) | conta o mesmo criador duas vezes (todo streamer tem ≥ 1 canal); o peso seria arbitrário |
| Exigir os dois (dominância de Pareto) | não dá ordem total: duas plataformas em que uma ganha em streamers e a outra em canais ficam incomparáveis, e não há top-k |
| **Lexicográfica (escolhida)** | cada streamer distinto é uma audiência própria (alcance de público); canais a mais do mesmo streamer ampliam pouco e só desempatam |

As duas quantidades são devolvidas, e as duas entram no critério: o "E" vale para a
listagem e para a ordem. `canais_por_streamer` aparece como métrica auxiliar.

**3. Empates no corte de k: entram todos (equivale a `FETCH FIRST k ROWS WITH
TIES`).** A posição é `rank()` sobre (streamers, canais): plataformas iguais dividem
a posição, e o corte é `posicao <= k`. Cortar no meio de um empate escolheria uma
plataforma por um critério que o enunciado não dá (o nome). Dentro do empate, a ordem
de saída é pelo nome, para ser determinística.

**4. Posição global, mesmo com filtro.** O `rank()` é calculado sobre todas as
plataformas e só depois a plataforma pedida é selecionada: o filtro mostra a posição
real (o Kick é o 6º, o Rooter o 28º), e não "1º de 1", como na versão anterior. Com
filtro, a plataforma volta mesmo fora do top-k, com `no_top_k = false`.

**5. Bordas.**

- Plataforma sem canal: `LEFT JOIN`, 0 streamers e 0 canais, no fim do ranking.
- `p_k` nulo: todas as plataformas (como nos itens 8 a 11, DEC-002); `p_k < 1`: erro
  `22023` com mensagem clara (um top-0 não é pergunta válida).
- Plataforma inexistente no filtro: erro `22023`, para não confundir com "plataforma
  sem canais" (que devolve uma linha com zeros).
- `qtd_users` (derivado, T2) conta CONTAS, de streamers ou não; é devolvido só como
  contexto, com outro nome de coluna, e não entra no critério.
- Métrica auxiliar de alcance: `qtd_visualizacoes`, soma do derivado
  `Canal.qtd_visualizacoes` dos canais da plataforma.

### Implementação

`steam_do_bedo.sp_obter_top_k_plataformas_por_streamers_e_canais(p_k INT DEFAULT
NULL, p_nro_plataforma INTEGER DEFAULT NULL)` em `procedures.sql`, devolvendo
`posicao`, `nro_plataforma`, `nome_plataforma`, `qtd_streamers`, `qtd_canais`,
`canais_por_streamer`, `qtd_visualizacoes`, `qtd_users` e `no_top_k`.

É a única function em plpgsql: a posição global obriga a agregar todas as plataformas
antes do filtro (o planejador não pode empurrar o filtro para baixo da window
function), então a expansão inline das functions SQL não traria ganho; e o plpgsql
valida os parâmetros com mensagem clara.

### Desempenho (protocolo a frio, DEC-032; mediana de 5)

Fase `item12` do `bench/aferir.py` (`bench/resultados.csv`, gráfico
`bench/graficos/08_item12.png`). Tempo de execução, a frio e a quente; páginas lidas
entre parênteses.

| Forma | Sem filtro (k = 10) | Filtro Kick | Filtro YouTube |
|---|---|---|---|
| Anterior (DEC-029, sem posição global) | 57 / 91 ms (675) | 56 / 5 ms (672) | 31 / 13 ms (672) |
| **Final, sem índices de apoio** | 139 / 67 ms (1.438) | 99 / 47 ms (1.435) | 67 / 62 ms (1.435) |
| **Final, com os índices finais (DEC-034)** | 64 / 67 ms (1.450) | 67 / 43 ms (1.447) | 62 / 42 ms (1.447) |
| Final + `Canal (nro_plataforma, id_streamer) INCLUDE (qtd_visualizacoes)` | 66 / 49 ms (1.468) | 65 / 73 ms (1.465) | 67 / 44 ms (1.465) |
| Sobre a V5 virtual (agregado por plataforma como view) | 73 / 46 ms (1.382) | 63 / 41 ms (1.378) | — |
| Sobre a V5 materializada (28 linhas, sem índice) | 10 / 1,2 ms (302) | 8 / 1,3 ms (303) | — |

Leitura:

- O custo é ler `Canal` inteira (~670 páginas) e ordenar os ~36 mil canais para o
  `COUNT(DISTINCT)`; a posição global obriga a fazer isso com ou sem filtro. As
  páginas a mais da versão final (~1.440 contra ~670) são de catálogo: é a primeira
  chamada de uma function plpgsql depois do restart (compila a function e valida a
  plataforma). Com filtro, a versão anterior era mais barata porque lia só uma
  plataforma, mas respondia errado ("1º de 1").
- **Índice de cobertura em `Canal`: descartado.** O planejador continua com
  `Seq Scan` + ordenação (plano conferido), as páginas não caem e o tempo fica no
  ruído. Além disso, seria o 6º índice.
- **V5 materializada: medida e não adotada.** Ela cai para 8 a 10 ms, mas o ganho
  absoluto é de ~50 ms numa resposta de 28 linhas consultada raramente; em troca, o
  item 12 deixaria de ser exato (um canal novo só apareceria depois do refresh) e
  seria mais um refresh agendado. Para a escolha de patrocínio o atraso seria
  aceitável, mas aqui não compensa. A V5 virtual não acelera nada (o planejador a
  expande), como as V1 e V2 (DEC-033). As views continuam 4 de 5.
- Nenhum índice de apoio foi trocado por causa do item 12: o teto de 5 (DEC-034) fica
  como está.

### Validação (`queries.sql`, bloco do item 12)

| Caso | Resultado |
|---|---|
| Sem filtro, k = 10 | 10 linhas, YouTube 1º (10.092 streamers), Kuaishou 10º |
| Filtro, plataforma grande (YouTube) | 1 linha, posição 1, `no_top_k` verdadeiro |
| Filtro, plataforma pequena dentro do top-10 (Kick) | posição 6 (global), não "1º de 1" |
| Filtro, plataforma fora do top-10 (Rooter) | posição 28, `no_top_k` falso |
| k = 100 (maior que o total) | as 28 plataformas, sem erro |
| Desempate e empate (montados com `ROLLBACK`) | A (1 streamer, 2 canais) fica à frente de B (1 streamer, 1 canal); C e D (sem canal) empatam na 31ª posição e k = 31 devolve 32 linhas |
| k = 0 e plataforma −1 | erro `22023` com mensagem clara |
| Contagem independente (subconsultas correlacionadas + posição recalculada como 1 + plataformas estritamente à frente) | 28 plataformas, **0 divergências**; soma dos canais = `count(*)` de `Canal` |

### Premissas e limitações

- **No seed v3 cada streamer tem no máximo um canal por plataforma** (os canais são
  criados a partir das contas), então na carga canais = streamers e
  `canais_por_streamer` = 1,00 em todas as plataformas: o desempate por canais não
  aparece nos dados carregados, só no caso montado da validação. Gerar canais
  secundários no seed (por exemplo, um canal de cortes) exigiria refazer a carga e
  toda a aferição; ficou como melhoria futura.
- O critério lexicográfico assume que audiência vem de criadores distintos. Uma
  leitura por visualizações (alcance bruto) daria outra ordem (o TikTok passaria o
  YouTube); por isso `qtd_visualizacoes` é devolvido ao lado.

### Aplicada no DDL: sim (em arquivo separado)
Onde: `procedures.sql` (item 12), `queries.sql` (validação), `bench/consultas_alternativas.sql` (alternativas medidas).
