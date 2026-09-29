# Mundo vivo — diálogos por contexto, pessoas com vida própria, sociedade

> Objetivo: cada vida é única, sem roteiro. O mundo muda **com você ou sem você**, e tudo o que as pessoas dizem depende de quem elas são, do que aconteceu com elas, do que aconteceu com você e do estado do mundo.

## Pesquisa que guiou o design

| Referência | O que aprendemos | Como virou mecânica aqui |
|---|---|---|
| **BitLife** | Relações por papel, barra de relação, interações positivas/negativas, NPCs que pedem dinheiro, morrem, casam | Mantido e aprofundado: agora cada NPC tem vida própria simulada e fala com personalidade |
| **AltLife** (Life Simulator) | Personalidade que afeta emoções e interações, crenças e aspirações, hobbies, gerações. Crítica comum dos jogadores: *"poucas consequências para as decisões"* | Persona com Big Five, crenças (política, fé), aspirações e manias; toda escolha deixa **marcas** que circulam por fofoca |
| **AlterLife** (Steam) | Vida "real" onde nada vem fácil, carreiras, casa, rotina | Cidade com lugares que abrem e fecham, economia e tecnologia que mudam empregos |
| **Valve — "AI-driven Dynamic Dialog" (GDC 2012, Elan Ruskin)** | Banco de regras + fatos; casa a regra **mais específica**; genéricas como fallback; memória escrita de volta | É exatamente o `DialogueSystem` |
| **Crusader Kings III** | Traços geram opinião, estresse e memórias; eventos julgados por valores | Marcas julgadas pelos valores de cada NPC (um devoto e um cruel reagem ao contrário) |

## 1. Persona (`src/systems/persona.gd`)
Todo personagem (NPCs e jogador) tem:
- **Big Five** (abertura, disciplina, extroversão, amabilidade, nervosismo) derivado de traços + atributos ocultos; filhos herdam 40% dos pais.
- **Voz**: doce, formal, gírias, direto, sarcástico, tímido, dramático, nerd, tranquilo, criança, das antigas. **Muda com a idade** (o adolescente de gírias pode virar um sessentão formal).
- **Interesses** (22 temas), **política** (−100 a +100), **fé**, **aspiração** (família, riqueza, carreira, fama, saber, aventura, paz, poder, fé, romance), **mania** (20, ex.: sempre atrasa, conversa com plantas, pão-duro) e um **bordão** pessoal fixo.

## 2. Motor de diálogo (`src/systems/dialogue_system.gd`)
1. **Fatos**: a cada fala monta ~150 fatos: sobre quem fala (papel, idade, humor, Big Five, voz, traços, interesses, política, fé, emprego, doenças, dinheiro, eventos de vida recentes, o que sabe de você, memórias de você), sobre você (idade, estudo e notas, emprego, dinheiro, prisão, vícios, casamento, filhos, fama, nível do Sistema), sobre o mundo (economia, eventos mundiais, partido no poder, eleição, lei das fendas, eras tecnológicas, manchetes do ano, criminalidade da cidade) e sobre a cena (lugar, clima, hora).
2. **Regras** (`data/dialogue/*.json`, **533 regras**, ~1.300 textos PT/EN): cada regra tem critérios; vence a **mais específica**; as genéricas são fallback.
3. **Anti-repetição**: falas ditas nos últimos 3 anos perdem prioridade; regras podem ter `cd` e `once`.
4. **Cena completa** ao conversar: ambiente (narração) → cumprimento na voz da pessoa → assunto (a vida dela, a sua, o mundo, as memórias) → às vezes o bordão → **suas respostas com a chance** calculada pela personalidade dela → reação.
5. **Respostas** (`data/dialogue_replies.json`, 30): ouvir, piada, consolar, ajudar com dinheiro, aconselhar, concordar/discordar, prometer, retrucar, pedir desculpas, emprestar, recusar, provocar, brincar, dar bronca... Cada uma muda relação, humor e **memória** (ex.: *te consolou*, *discutiu com você*, *te deve dinheiro*).
6. **Idade**: bebês ouvem "gugu-dadá"; nada de política ou dinheiro com crianças.
7. **Toda interação** (elogio, insulto, presente, pedir dinheiro...) ganha uma reação falada que depende de traços e voz.

## 3. Pessoas com vida própria (`src/systems/npc_system.gd`, `data/npc_life.json`)
- **Humor** que oscila conforme o nervosismo, a economia, a saúde e o desemprego.
- **Casamentos entre NPCs** com qualidade própria: seus pais podem se separar (afeta você), um pai solteiro pode casar de novo (**padrasto/madrasta**) e ter filhos (**meio-irmão**).
- **39 eventos de vida** escolhidos por personalidade e mundo: promoção, demissão (mais comum na recessão e na automação), largar tudo por um sonho, abrir negócio (vira um lugar real na cidade), falir, loteria, casar, divorciar, bebê, doença, cura, acidente, mudar de cidade, voltar, conversão, perder a fé, virar militante, viajar, adotar pet, **despertar poderes**, ser preso, burnout, dívidas, formatura, primeiro amor...
- **Ligam para você** (até 3 por ano) quando algo real aconteceu: demissão, bebê, divórcio, doença, pedido de dinheiro, saudade, cobrança de casamento, preocupação com seu vício, declaração de amor.

## 4. Sociedade (`src/systems/society_system.gd`)
- **Cidades** geradas por cultura, com prosperidade, criminalidade e poluição que tendem a um alvo definido pela economia, pelas políticas e **pelos seus atos** (seus crimes aumentam a criminalidade; seus negócios e doações, a prosperidade).
- **Lugares** (padaria, bar, academia, guilda, igreja...) abrem e fecham com a economia; NPCs donos; eras novas criam lugares novos (sala de VR, café de mana).
- **Governo**: 5 partidos com ideologia e políticas (impostos, assistência, policiamento, **lei das fendas**: livre, registro obrigatório ou proibição), aprovação, protestos, **eleições a cada 4 anos** e o seu voto. Se você chegar a presidente, o governo é seu.
- **Tecnologia**: 11 eras (redes sociais → smartphones → streaming → Era dos Caçadores → IA → automação → energia limpa → mundos virtuais → tecnologia de mana → terapia genética → longevidade) com efeitos reais em salários por setor e na saúde.
- **Famosos**: estreiam, ganham prêmios, casam, se envolvem em escândalos, são presos, se aposentam e morrem. **Liga esportiva** com campeão anual e torcedores.
- **Jornal anual** com tudo isso + os seus feitos quando você é famoso.
- **Marcas e fofoca**: o que você faz (prisão, divórcio, promoção, música de sucesso, eleição...) vira uma marca; as pessoas próximas descobrem por fofoca (depende de fama, proximidade e de quem gosta de fofoca) e **julgam pelos próprios valores**.

## 5. Eventos do mundo (`data/events/world_life.json`)
Assalto (só em cidade perigosa), dia de eleição, demissão por automação, protesto (pode dar ficha), encontro com famoso, fiscalização das fendas (quando proibidas), lugar favorito fechando, mundos virtuais e tratamento de longevidade.

## 6. Interface
- **Conversa**: retrato, humor, voz, narração, falas em balões e respostas com a chance mostrada pelo Sistema.
- **Ficha do NPC**: personalidade (quanto mais próximo ou quanto maior o nível de *Observar*, mais se revela: voz, mania, interesses, sonho, política, Big Five) e a **vida dele** ano a ano.
- **🌍 Mundo** (tela inicial): Jornal, Cidade, Governo (com voto), Tecnologia, Famosos e Liga.

## 7. Testes
`tests/test_living_world.gd` (18 testes): personas e herança, regra mais específica, variedade entre pessoas, chances por personalidade, respostas mudando relação, fofoca julgada por valores, vidas de NPC, recasamento, divórcio dos pais, sociedade sem o jogador, voto, automação, crimes aumentando a criminalidade, ligações, fala adequada à idade, textos completos PT/EN e **save/load determinístico** com o mundo inteiro.

Save v4: migração adiciona os contêineres; persona e sociedade são criadas sob demanda em saves antigos.
