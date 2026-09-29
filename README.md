# The Gamer Life

Simulador de vida **mobile** (Godot 4.3) em português e inglês, no gênero de "life sims" como BitLife — mas com identidade própria: **a sua vida inteira gira em torno de um Sistema de videogame**, inspirado em *The Gamer*, *Re:Monster*, *Tensei Shitara Slime* e isekai.

Você nasce, cresce, estuda, trabalha, ama, envelhece e morre — e o tempo todo uma janela azul só sua mostra **nível, EXP, atributos sem teto, habilidades, títulos e missões**. Estudar cria a skill *Leitura Rápida*, que evolui para *Mente Acelerada* e depois *Sábio Analítico*. Correr vira *Maratonista*. Aos 12–16 anos o céu se rasga, você descobre o mundo oculto dos Despertos e aprende a **criar Dungeons Instantâneas**. Monstros dão EXP, ouro, núcleos de mana (que valem dinheiro no mercado real do jogo), livros de skill e equipamentos. Com *Devorar* você rouba as habilidades do que derrota. No nível 25 você evolui de existência. Quando morre, o Sistema passa para um herdeiro — ou sua alma reencarna com bênçãos.

E tudo está ligado: INT sobe suas notas, FOR melhora o desempenho de pedreiro e policial, SOR curva todas as rolagens, CAR decide entrevistas e romances, VIT atrasa a velhice, e um empréstimo a um amigo aos 24 pode voltar aos 39.

## Rodando

1. Instale o [Godot 4.3](https://godotengine.org/download).
2. Abra a pasta do projeto no Godot e aperte **Play** (retrato 720×1280).

Linha de comando:

```bash
godot --headless --import                              # primeira vez
godot --headless -s res://tests/test_runner.gd         # testes
godot --headless -s res://tests/batch_sim.gd -- 500    # simula 500 vidas e imprime estatísticas
```

## Documentação

Arquitetura completa, modelo de dados, Event Engine, pipeline do ano, save/versionamento, navegação mobile, roadmap e pesquisa: **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**.

Mundo vivo (diálogos por contexto, pessoas com vida própria, cidade, governo, tecnologia, famosos, fofoca): **[docs/LIVING_WORLD.md](docs/LIVING_WORLD.md)**.

Comparação ponto a ponto com a profundidade do BitLife (o que existe, o que foi adicionado, o que ficou de fora): **[docs/BITLIFE_GAP_ANALYSIS.md](docs/BITLIFE_GAP_ANALYSIS.md)**.

## Estrutura

```
src/core      serviços (estado, RNG, probabilidade, condições, efeitos, dados, i18n, save)
src/systems   um sistema por responsabilidade (Gamer, Skills, Carreira, Finanças, Saúde, ...)
src/sim       orquestrador + pipeline anual
src/pixel     pixel art procedural (paletas com hue shifting, retratos, ícones)
src/ui        interface mobile (só apresentação)
data          todo o conteúdo em JSON (eventos, empregos, skills, monstros, ...)
locale        textos PT/EN
tests         testes, smoke test de UI e simulação em massa
```
