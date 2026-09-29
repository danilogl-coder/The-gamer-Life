# The Gamer Life — Arquitetura

Simulador de vida mobile (Godot 4.3, GDScript) em que **toda a vida gira em torno de um "Sistema" de videogame** inspirado em *The Gamer*, com camadas de *Re:Monster* (devorar / absorver habilidades, evolução por rank), *Tensei Shitara Slime* (tiers de habilidade, evolução e fusão de skills) e *isekai* (reencarnação com bênçãos compradas com Pontos de Alma).

> Princípio: **Fácil de jogar. Difícil de prever. Impossível viver duas vidas iguais.**
> A UI só MOSTRA e SOLICITA. Regras vivem nos sistemas. Conteúdo vive em dados.

---

## 0. Auditoria do projeto

O repositório continha apenas um `README.md`. Não havia código nem assets a preservar, então a arquitetura foi desenhada do zero, seguindo o prompt:
DATA / SIMULATION / UI / PERSISTENCE separados, conteúdo data-driven, RNG determinístico e testes headless.

```
project.godot            Godot 4.3, retrato 720×1280, stretch canvas_items/expand, renderer mobile/compat
src/app.gd               Autoload "App": composição (dados, localização, bus, simulação, save/meta)
src/core/                Serviços puros (sem regras de gameplay)
src/sim/                 Orquestrador + pipeline anual
src/systems/             Um sistema = uma responsabilidade
src/pixel/               Pixel art procedural (paletas, rasterizador, retratos, ícones)
src/ui/                  Tema, widgets, telas e popups (só apresentação)
data/                    Todo o conteúdo (JSON)
data/events/             Eventos por tema (1 arquivo por tema)
locale/pt|en/            Textos (merge de todos os *.json da pasta)
tests/                   Testes unitários, smoke test de UI, simulação em massa
docs/                    Este documento
```

---

## A — Mapa de arquitetura

### Serviços do núcleo (`src/core`)

| Serviço | Responsabilidade |
|---|---|
| `GameState` | Estado central **apenas dados** (Dictionary serializável). Helpers de id, flags, contadores, timeline, acesso por caminho. |
| `RngService` | RNG determinístico por vida (seed + estado salvos no save). Nada usa `randf()` global. |
| `ProbabilityService` | Toda chance importante: `base + mods` (via caminhos de dados) + curva de **Sorte (LUK)**. Clamps configuráveis. |
| `ConditionEvaluator` | Condições em dados (`all/any/not`, `path op value`, comparação entre caminhos). |
| `EffectExecutor` | Verbos de efeito em dados (≈45 tipos). Conteúdo novo não precisa de código novo. |
| `DataRegistry` | Carrega e indexa todas as tabelas + `balance.json`. |
| `Localization` | Chaves → texto (PT/EN), params `{name}`; params `@chave` são traduzidos na hora de exibir (a timeline se re-traduz ao trocar idioma). |
| `SaveSystem` | JSON atômico, versionamento + migrations, normalização de números, meta-perfil. |
| `EventBus` | Sinais desacoplados (`year_advanced`, `level_up`, `skill_learned`, `character_died`, …). |

### Sistemas (`src/systems`)

| Sistema | Responsabilidade | Lê de | Escreve em |
|---|---|---|---|
| `GamerSystem` | Nível, EXP, stats (FOR/VIT/DES/INT/SAB/SOR/CAR), pontos, HP/MP, títulos, inventário, equipamento, ranks de evolução e **o pool global de modificadores** | skills, títulos, itens, traços, doenças, eventos mundiais, perks | stats, HP/MP |
| `SkillSystem` | Skills por repetição, XP de uso, tiers, **evolução no nível máx.**, **fusão**, Observar | contadores, talentos ocultos | skills |
| `ActivitySystem` | Orçamento anual de **tempo livre**, execução de atividades, contadores (→ skills/missões) | tempo, dinheiro, MP | tudo via efeitos |
| `EducationSystem` | Escola automática, faculdade/pós, notas (INT!), mensalidade, bolsa, reprovação, evasão | INT, disciplina, estresse, estudo do ano | educação, pais |
| `CareerSystem` | Vagas, entrevista, desempenho pelo **stat-chave do emprego**, promoção, demissão, aposentadoria, facções | stats, chefe, economia | carreira, estresse, EXP |
| `FinanceSystem` | Salário→impostos→custo de vida→moradia→filhos→empréstimos→juros; crédito; imóveis; investimentos | carreira, mundo, país | dinheiro, dívida |
| `HealthSystem` | Envelhecimento (mitigado por VIT), estresse (SAB), hábitos/vícios, doenças, lesões, morte | stats, hábitos, ocultos | saúde, morte |
| `RelationshipSystem` | Vínculos por papel, score, **memórias com decaimento por personalidade**, interações (dados), romance, casamento, divórcio, fertilidade, adoção | CAR, compatibilidade, traços | vínculos, memórias |
| `NpcSystem` | Simulação **abstrata anual só de NPCs relevantes**, mortes, heranças, netos, poda | vínculos | NPCs |
| `CharacterFactory` | Geração coerente de pessoas (idade↔cargo↔educação↔riqueza), genética dos filhos | países, nomes, traços | NPCs |
| `EventEngine` | Sorteio por peso×raridade, cooldown, once, atores, escolhas com chance visível, cadeias, agendados | condições | efeitos |
| `QuestSystem` | Missões do Sistema (contadores desde o início, condições, prazos, recompensas/penalidades) | contadores | efeitos |
| `DungeonSystem` | Dungeons Instantâneas: combate automático determinístico, drops, **Devorar**, derrota real | stats, skills, mods | EXP, ouro, itens, saúde |
| `CrimeSystem` | Crime → calor/evidência → investigação agendada → julgamento → prisão (estado próprio) | DES, furtividade, reputação | ficha, prisão |
| `WorldSystem` | Ciclo econômico, inflação, desemprego, imóveis, mercados, **atividade de fendas**, eventos mundiais | — | mundo, mods globais |
| `AchievementSystem` | Conquistas por condição (por vida + meta global) | estado | conquistas |
| `LegacySystem` | Morte, retrospectiva, herança/testamento, **herdeiro herda o Sistema**, Pontos de Alma e perks | tudo | nova geração |
| `SpecialCareerSystem` | Registro de **carreiras-minijogo modulares** (`SpecialCareer`): Música, Atleta, Empresa, Criador de conteúdo. Nova carreira = novo script + 1 linha em `special_careers.json` | stats, skills, mundo, fama | dinheiro, fama, EXP, saúde |
| `PetSystem` | Pets (envelhecem, dão felicidade) e **familiares**: monstros domados (skill Domar) que lutam, sobem de nível e, ao serem **nomeados** (gasta 80% do MP), evoluem para espécies nomeadas com bônus | dungeon, MP, CAR | combate, mods, felicidade |
| `YearPipeline` | Ordem exata do "+1 ANO" | — | — |
| `LifeSimulation` | Orquestrador + API pública (`advance_year`, `do_activity`, `interact`, `choose`, `allocate_stat`, `command`) + `resolve(path)` | — | — |

### Dependências (sem ciclos de compilação)
Sistemas recebem a referência do orquestrador (`_sim`) e se comunicam por **API explícita** ou **EventBus**. O `GameState` não contém lógica. A UI depende só de `App.sim` (API pública) e de dados para exibição.

### Matriz de interação (o "nada solto")

```
                ┌──────────── MODIFICADORES GLOBAIS (GamerSystem.mod) ────────────┐
 skills/títulos/itens/traços/doenças/eventos mundiais/perks/rank → todos os sistemas
                └──────────────────────────────────────────────────────────────────┘
 INT ─► notas ─► faculdade ─► empregos ─► salário ─► moradia/estilo ─► felicidade
 FOR ─► desempenho (construção, polícia, lutador) ─► promoção ─► skill Liderança
 VIT ─► HP ─► dungeons ─► EXP ─► pontos ─► VIT ... ; VIT ─► envelhecimento/longevidade
 SAB ─► estresse ─► saúde/burnout/depressão ─► desempenho/notas
 SOR ─► TODA rolagem (ProbabilityService) ─► drops, crimes, entrevistas, eventos
 CAR ─► entrevistas, romance, compatibilidade, julgamentos, fama
 Dungeon ─► Núcleos de Mana ─► mercado "mana_cores" ◄─ fendas do mundo (WorldSystem)
 Faltar aula ─► faltas ─► notas ↓ ─► pais ↓ ─► expulsão ─► "companhia duvidosa" ─► crime
 Crime ─► calor ─► investigação ANOS depois ─► prisão ─► perde emprego/escola ─► estudar na prisão
 Empréstimo a amigo ─► cobra/perdoa ─► (5–15 anos) amigo te salva
 Viagem com parceiro(a) ─► traição (flag) ─► 1–3 anos ─► parceiro(a) descobre ─► divórcio ─► metade dos bens
 Pais morrem ─► herança (se o vínculo for bom) ─► patrimônio
 Morte ─► herdeiro ganha % dos stats + uma skill + título ─► dinastia com mundo persistente
```

---

## B — Modelo de dados

Todos os personagens (jogador e NPCs) compartilham o mesmo schema; o jogador ganha campos extras (`CharacterFactory._add_player_fields`).

```jsonc
Character {
  id, first_name, last_name, sex, age, alive, is_player, country, wealth,
  look: {skin, hair, style, eyes, bg},            // genoma do retrato pixel
  attrs:  {health, happiness, stress, looks, discipline, reputation}, // 0..100
  hidden: {fertility, talent_music, talent_sport, talent_art, academic, aggression,
           impulsivity, courage, empathy, ambition, loyalty, greed, addiction_resist,
           disease_risk, stress_tolerance, longevity, mana_affinity},  // 0..100, descobertos com Observar
  traits: ["kind", "vengeful", ...],
  gamer: { level, exp, stat_points, rank, awakened, hp, mp,
           stats: {str, vit, dex, int, wis, luk, cha},   // SEM teto (escala OP)
           stat_xp: {}, skills: {id: {lv, xp}}, titles: [], title,
           inventory: {item: qty}, equipment: {weapon, armor, accessory} },
  education: {stage, years, grades, completed[], major, absences, scholarship},
  career:    {job, level, years, performance, salary, pension, history[]},
  finance:   {cash, debt, credit, loans[], properties[], investments{}, lifestyle, last_report},
  health:    {conditions: {id: {years, severity}}, fitness, habits: {alcohol, ...}},
  family:    {mother, father, spouse, children[], siblings[]},
  memory:    [{m: "insult", sev: 30, age: 22}],          // NPC lembra do jogador
  // só jogador:
  rels: {npc_id: {role, score, since, yr}}, quests: {active, done, failed},
  discovered: [], criminal: {record[], heat, prison{}}, fame, faction: {id, rank, rep},
  time: {slots, used}, year_counters: {}, recent_actions[], favorites[]
}
WorldState { cycle_phase, economy(-1..1), inflation, price_index, unemployment, housing, rift,
             markets: {asset: {price, last}}, events: {id: years_left}, history[] }
GameState  { save_version, seed, rng_state, world_year, generation, next_id, player_id,
             npcs{}, world{}, flags{}, counters{}, scheduled[], pending_events[],
             timeline[], event_history{}, achievements{}, legacy{}, dead, death{} }
```

Tabelas de conteúdo (`data/*.json`, indexadas por `id`): `activities`, `jobs`, `education`, `skills`, `titles`, `quests`, `monsters`, `dungeons`, `diseases`, `countries`, `traits`, `items` (inclui skill books, equipamentos e **perks de reencarnação**), `achievements`, `interactions`, `world_events`, `properties`, `crimes`, `factions`, `stats`, `names`, `balance`, `events/*`.

---

## C — Event Engine

```jsonc
{
  "id": "rival_awakened", "tags": [], "rarity": "uncommon", "weight": 8,
  "cooldown": 5, "once": false, "min_age": 14, "max_age": 999, "special": false,
  "conditions": [{"path": "flag.world_revealed", "op": "==", "value": true},
                 {"path": "calc.level", "op": ">=", "value": 10}],
  "actor": {"new": {"role": "rival", "age_rel": 0, "awakened": true}},   // ou {"role": ["friend","sibling"]}
  "actor_conditions": [...],                                           // filtro por candidato
  "effects": [...],                                                    // aplicados ao aparecer
  "choices": [{
    "id": "duel",
    "conditions": [...],                      // visibilidade da escolha
    "chance": {"base": 0.5, "mods": [{"path": "calc.actor_level_gap", "per": -0.04}]},
    "effects": [...],                         // sempre
    "success": {"effects": [... {"type": "SCHEDULE_EVENT", "event": "rival_rematch", "min": 2, "max": 5}]},
    "fail":    {"effects": [...]}
  }]
}
```

* **Textos** nunca estão no JSON: chaves derivadas `ev.<id>.title|desc|<choice>|<choice>.ok|fail|res`.
* **Sorteio anual**: 0–3 eventos; peso × multiplicador de raridade (`common … legendary` em `balance.json`), respeitando idade, cooldown, `once`, prisão (tag `prison`) e condições.
* **Chance visível**: a janela do Sistema mostra a % de cada escolha (é *The Gamer*: você vê os números).
* **Cadeias**: `TRIGGER_EVENT` (agora) e `SCHEDULE_EVENT` (daqui a N anos, mantendo o ator). Eventos agendados são revalidados quando vencem (se o ator morreu, a cadeia morre).
* **Flags** (`SET_FLAG`, `CLEAR_FLAG`, `flag.x`) permitem histórias longas sem código. Flags com prefixo `dyn_` sobrevivem à morte (segredos de família).
* **Condição por caminho**: `player.*`, `actor.*`, `world.*`, `flag.*`, `counter.*`, `yc.*` (contador do ano), `stat.*` (stat efetivo), `skill.*`, `mod.*`, `rel.<papel|actor>`, `calc.*` (net_worth, employed, level, compat, …).
* **Verbos de efeito**: `CHANGE_STAT, CHANGE_VALUE (mult/min/max), CHANGE_MONEY (scale_income), CHANGE_RELATIONSHIP, ADD_MEMORY, START/END_RELATIONSHIP, SET_ROLE, ADD/REMOVE_DISEASE, ADD/REMOVE_ITEM, START_JOB, LOSE_JOB, ADD_CRIMINAL_RECORD, TRIGGER_EVENT, SCHEDULE_EVENT, SET/CLEAR_FLAG, COUNTER, GAIN_EXP (scale_level), STAT_XP, GIVE_STAT_POINTS, SKILL_XP, LEARN_SKILL, GRANT_TITLE, START_QUEST, FACTION_REP, JOIN_FACTION, CHANGE_FAME, CHANGE_HABIT, DISCOVER_HIDDEN, CHANGE_HIDDEN, ADD/REMOVE_TRAIT, SPAWN_NPC, GO_TO_PRISON, TRIAL, KILL, HEAL, LOG, NOTIFY, CHANCE (ramos), WORLD_EVENT, MARRY (prenup), DIVORCE, CONCEIVE, OBSERVE, CHANGE_ACTOR`. Qualquer efeito aceita `"if": [condições]`.

---

## D — Pipeline do ano (`YearPipeline.advance`)

```
FECHA O ANO QUE PASSOU (usa as ações/contadores deste ano)
 1. Finance       salário, impostos, custo de vida, moradia, filhos, empréstimos, juros, crédito
 2. Career        desempenho (stat-chave), promoção/demissão/layoff, EXP e estresse do trabalho
    Special       ticks das carreiras especiais (streaming, patrocínio, lucro da empresa, seguidores)
 3. Education     notas, mensalidade (pais podem pagar), formatura / repetência
 4. Crime         calor decai, pena da prisão diminui
 5. Gamer         Corpo do Jogador (HP/MP cheios), crescimento natural / declínio da velhice
 6. Health        envelhecimento, estresse, hábitos, doenças, CHECK DE MORTE  ─► se morreu: fim
 7. Relations     decaimento, memórias esmaecem (personalidade), traição/divórcio
    Pets          idade, vínculo, morte de pets, familiares
 8. NPCs          NPCs relevantes envelhecem, trabalham, casam, têm filhos, morrem (herança), poda
ABRE O ANO NOVO
 9. Calendário    idade+1, ano+1, marcos (maioridade, décadas)
10. World         ciclo econômico, inflação, mercados, fendas, eventos mundiais
11. Quests        prazos/falhas, novas ofertas do Sistema
12. Scheduled     consequências atrasadas que venceram
13. Eventos       sorteio anual
14. Títulos, conquistas, fusões de skills
15. Orçamento     tempo livre do ano, matrícula automática, novas missões
```

Performance: nada roda por frame. A simulação só acontece quando o jogador age, avança o ano ou abre uma tela. NPCs irrelevantes são podados; o cache de modificadores é invalidado só quando a fonte muda.

---

## E — Save / persistência

* `user://saves/slot_1.json` — a vida/dinastia (o `GameState.data` inteiro). Autosave a cada ano e na morte.
* `user://meta.json` — perfil entre vidas: idioma, Pontos de Alma, conquistas globais, histórico de vidas.
* Escrita **atômica** (arquivo `.tmp` → rename).
* `save_version` + `SaveSystem.MIGRATIONS[v] = func(data)` aplicadas em sequência até a versão atual. Exemplo real: v1→v2 adiciona `special`, `pets`, `possessions`, `challenge` e `settings` a saves antigos (coberto por teste).
* JSON devolve números como float: `SaveSystem.normalize` converte floats inteiros em int. O estado do RNG (64 bits) é salvo como **string**.
* Teste garante: salvar → carregar → continuar produz **exatamente** a mesma vida (determinismo).

---

## F — Navegação mobile

```
┌──────────────────────────────┐
│ [retrato] Nome · Idade · Ocup│  ← janela do Sistema (Lv, rank, título, HP/MP)
│ $ dinheiro  ⏱ tempo livre    │
│ Saúde  Felicidade  Estresse …│
├──────────────────────────────┤
│  TIMELINE da vida (rolagem)  │
├──────────────────────────────┤
│ [ação recente][fav][fav]     │  ← 1 toque para repetir
│ [        +1 ANO   ⏱3/7     ] │  ← botão gigante
├────┬────┬────┬────┬────┬─────┤
│VIDA│SIST│RELA│AÇÕES│CARR│BENS│  ← abas (≥104 px)
└────┴────┴────┴────┴────┴─────┘
```

* **SISTEMA**: Status (alocar pontos, +1/+5/Auto), Skills (tier, nível, XP, bônus, evolução), Missões, Títulos (equipar), Itens (usar/equipar/vender), Conquistas.
* **RELAÇÕES**: agrupadas (família, amor, amigos, escola/trabalho, outros) → ficha com janela **Observar** (quanto maior o nível da skill, mais se revela), memórias e ações com % de chance.
* **AÇÕES**: categorias → ação (2 toques). Estrela = favorito. Ações bloqueadas aparecem com o motivo.
* **CARREIRA**: educação (matrícula com requisitos claros) e vagas (motivo do bloqueio).
* **BENS**: relatório financeiro, estilo de vida, dívidas, imóveis, mercado.
* Popups: janela azul do Sistema para eventos; bottom-sheets para listas; notificações empilhadas acima da barra.
* Safe areas (notch) via `DisplayServer.get_display_safe_area`, `stretch=canvas_items/expand` (16:9, 19.5:9, 20:9, tablets). Alvos de toque ≥ 84 px (viewport 720).
* **Debug**: segure o dedo 1,2 s sobre a linha de idade → painel DEV (dinheiro, EXP, +10 anos, forçar evento/doença/emprego, spawn NPC, matar, flags, agendados).

---

## G — Roadmap

| Fase | Conteúdo | Estado |
|---|---|---|
| 1 Core | GameState, RNG, Probabilidade, Condições, Efeitos, Dados, Localização, Save, Bus | ✅ |
| 2 Vida básica | Nascimento, família, infância, escola, faculdade, emprego, saúde, morte | ✅ |
| 2b **Sistema** | Nível/EXP, 7 stats sem teto, pontos, títulos, skills por repetição, evolução, fusão, Observar, missões, dungeons, devorar, ranks | ✅ |
| 3 Economia | Dinheiro, impostos, dívida, crédito, empréstimos, imóveis, veículos, colecionáveis, mercado (inclui Núcleos de Mana) | ✅ |
| 4 Sociedade | Amizades, romance, casamento, divórcio, filhos, netos, memórias, reputação | ✅ (redes sociais profundas: próximo) |
| 5 Vida alternativa | Crime, investigação, julgamento, prisão (estado próprio), fuga, recurso | ✅ |
| 6 Carreiras especiais | Módulos `SpecialCareer`: Música (compor, gravar, turnê, gravadora), Atleta (ligas, temporadas, títulos, patrocínio, doping), Empresa (setor, preço, contratações, marketing, P&D, concorrência, venda/falência), Influenciador (plataformas fictícias, viral, cancelamento, publis). Próximos: Político, Ator, Astronauta | ✅ (4) |
| 7 Meta | Conquistas, legado, dinastias, Pontos de Alma, perks, **desafios** ("De Professor a Milionário"…) com recompensa em Pontos de Alma | ✅ |
| 8 Pets/Familiares | Pets comuns; domar monstros (Re:Monster); **nomear** familiares (Tensura) gasta MP e os faz evoluir; lutam e dividem EXP | ✅ |
| 8b Patrimônio | Veículos (depreciação, clássicos valorizam, pane/acidente/blitz) e colecionáveis (random walk) | ✅ |
| 8c Classificação | Tag `mature` em atividades/eventos + opção na tela inicial | ✅ |
| 9 Conteúdo | Escalar para 1000+ eventos, 300 empregos, 100 doenças… (só dados) | ⏳ |

---

## Pesquisa e inspirações

* **The Gamer** — janela de Status (Nome, Classe, HP/MP, Nível, atributos, título, dinheiro, pontos); *Gamer's Mind* (imune a efeitos mentais, controla emoções fortes) → `gamer_mind` reduz 50% do ganho de estresse; *Gamer's Body* (dormir numa cama restaura HP/MP e remove estados negativos) → `gamer_body` + atividade "Dormir numa cama" + recuperação anual; *Observe* (ver nome/nível/atributos) → janela Observar por nível; ações do dia a dia viram skills; objetos são itens; ID Create/ID Escape; mundo oculto de usuários de habilidades e guildas.
* **Re:Monster** — habilidade de absorção: força ao consumir o que derrota → skill `devour` absorve skills de monstros (`absorb` em `monsters.json`); evolução de existência por rank (goblin → hobgoblin → ogro …) → ranks Humano → Desperto → Transcendente → Semideus → Soberano (níveis 25/60/120/250) com escolha de caminho.
* **Tensei Shitara Slime** — tiers Comum/Extra/Única/Suprema (`tier`), skills evoluem ao passar do limite (`evolves_to`), fusões (`fusion`, ex.: Controle de Chi + Controle de Mana → Harmonia Yin-Yang; Liderança + Melodia da Alma → Aura Soberana).
* **Isekai / reencarnação** — ao morrer: continuar como herdeiro (o Sistema troca de hospedeiro) ou reencarnar gastando Pontos de Alma em bênçãos.

### Pixel art em código
* **Rampas com hue shifting**: sombras deslizam para azul/violeta e ganham saturação; luzes deslizam para amarelo e perdem saturação (`PixelPalette.ramp`).
* **Luz direcional** (topo-esquerda) em elipses com normal aproximada — evita *pillow shading* (`PixelCanvas.shaded_ellipse`).
* **Contorno seletivo (sel-out)**: o contorno é uma versão escura e fria da cor vizinha, não preto chapado.
* **Dithering ordenado (Bayer 4×4)** nos degradês de fundo.
* **Escala inteira + filtro nearest** em tudo (retratos 32×32 ×2/×3/×4, ícones 12×12 ×3, molduras 7×7 ×3).
* Retratos gerados do genoma (pele, cabelo, estilo, olhos, fundo) + sexo + fase da vida + humor; filhos herdam genes dos pais.

---

## Testes e ferramentas

```bash
godot --headless --import                                     # 1ª vez (cache de classes)
godot --headless -s res://tests/test_runner.gd                # testes unitários/integrados
godot --headless -s res://tests/batch_sim.gd -- 1000          # 1000 vidas "casuais"
godot --headless -s res://tests/batch_sim.gd -- 300 grinder   # 300 vidas focadas em dungeon
xvfb-run godot --rendering-driver opengl3 --resolution 720x1280 -s res://tests/ui_smoke.gd -- /tmp/shots
```

Os testes cobrem: determinismo do RNG, condições, probabilidade, save/load determinístico, migrations, **integridade referencial de todos os dados** (skills, itens, eventos, empregos, missões, títulos, facções), chaves de localização, passagem de ano, bloqueio por evento pendente, progressão escolar, requisitos de emprego, economia de adulto/menor, fertilidade por idade, morte + herdeiro + herança, eventos agendados, skill por repetição, level up/pontos, dungeon, prisão e vidas completas até a morte.

### Resultado da simulação em massa (referência de balanceamento)

| Métrica | Casual (40 vidas) | Grinder de dungeons (30 vidas) |
|---|---|---|
| Idade média de morte | 70 | 110 |
| Patrimônio (média / mediana) | 1,1M / 0,21M | 41M / 27M |
| Casados | 55% | 17% |
| Nível aos 18 / 40 / morte | 8 / 12 / 16 | 20 / 75 / 332 |
| Evoluiu de rank (1 / 2) | 0% / 0% | 97% / 93% |
| Mortes em dungeon | 0% | 3% |
| Eventos por vida | ~123 | ~182 |

Correções que a simulação encontrou: seguidores/fãs cresciam sem limite com atributos OP (agora crescimento logístico até o teto da população do mundo); lesões graves se acumulavam até matar (agora o *Corpo do Jogador* fecha ferimentos ao dormir, como no manhwa, e a saúde se recupera naturalmente).

A diferença entre as colunas é o objetivo: quem abraça o Sistema vira uma força absurda (escala OP), mas paga com tempo (menos casamentos e filhos) e risco real de morte.

## Como adicionar conteúdo (sem código)

1. **Evento**: acrescente um objeto em `data/events/<tema>.json` e as chaves `ev.<id>.*` em `locale/pt|en/events.json`.
2. **Emprego/atividade/skill/item/doença/título/missão/conquista**: acrescente em `data/<tabela>.json` + nome em `locale/*/content.json`.
3. Rode `tests/test_runner.gd` — o teste de integridade acusa referências quebradas e textos faltando.
4. Balanceamento global em `data/balance.json` (salários, EXP, chances, juros, fertilidade, mortalidade, raridade…).

## Exportação mobile
No preset de exportação (Android/iOS), inclua `*.json` em *Filters to export non-resource files*. O projeto usa o renderizador Compatibility (GLES3) para rodar bem em celulares modestos.
