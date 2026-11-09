"""Write the Archify candidate JSON for every diagram, in English and pt-BR.

One source of truth for both languages: edit TEXT, then run
    python3 docs/diagrams/src/build_candidates.py
and render with `just diagrams`.
"""
import json
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
PT_UI = ROOT / "vendor/archify/examples/locales/pt.json"

# (en, pt-BR) for every visible string
T = {
    # architecture
    "arch.title": ("Contextual bandit: model and decision layers", "Bandit contextual: camadas de modelo e de decisão"),
    "member": ("Member", "Assinante"), "member.sub": ("opens the homepage", "abre a página inicial"),
    "ctx": ("Context c", "Contexto c"), "ctx.sub": ("history, country", "histórico, país"),
    "model": ("RewardModel", "RewardModel"), "model.sub": ("belief b", "crença b"),
    "model.tag": ("probabilistic", "probabilístico"),
    "rule": ("DecisionRule", "DecisionRule"), "rule.sub": ("greedy, ε, UCB, TS", "gulosa, ε, UCB, TS"),
    "home": ("Homepage", "Página inicial"), "home.sub": ("shows arm a", "mostra o braço a"),
    "spec": ("Z3 spec", "Spec em Z3"), "spec.sub": ("proved invariants", "invariantes provadas"),
    "log": ("Event log", "Log de eventos"), "log.sub": ("(c, a, r, P(a))", "(c, a, r, P(a))"),
    "e.request": ("request", "requisição"), "e.estimate": ("estimate", "estimar"),
    "e.meanwidth": ("mean, width", "média, largura"), "e.arm": ("arm a", "braço a"),
    "e.proves": ("proves", "prova"), "e.log": ("log", "registra"), "e.reward": ("reward r → update", "recompensa r → atualizar"),
    "c.model": ("Model layer", "Camada de modelo"),
    "c.model.1": ("Keeps a belief b and updates it with (c, a, r)", "Guarda uma crença b e a atualiza com (c, a, r)"),
    "c.model.2": ("Reports a mean and an uncertainty width for each arm", "Informa uma média e uma largura de incerteza para cada braço"),
    "c.rule": ("Decision layer", "Camada de decisão"),
    "c.rule.1": ("Sees only the per-arm estimates, never the raw history", "Vê só as estimativas por braço, nunca o histórico bruto"),
    "c.rule.2": ("Returns a probability for every arm", "Devolve uma probabilidade para cada braço"),
    "c.spec": ("Z3 guarantees", "Garantias em Z3"),
    "c.spec.1": ("Every rule returns a valid distribution", "Toda regra devolve uma distribuição válida"),
    "c.spec.2": ("Calibrated model ⇒ UCB loses at most 2β·width", "Modelo calibrado ⇒ UCB perde no máximo 2β·largura"),
    # sequence
    "seq.title": ("One round of a contextual bandit", "Uma rodada de um bandit contextual"),
    "agent": ("Agent", "Agente"), "agent.sub": ("policy", "política"),
    "s.ctx": ("context c", "contexto c"), "s.est": ("estimate(b, c, a) for all a", "estimate(b, c, a) para todo a"),
    "s.estret": ("mean, width per arm", "média, largura por braço"), "s.rule": ("estimates", "estimativas"),
    "s.dist": ("P(arm)", "P(braço)"), "s.show": ("show arm a ~ P", "mostrar braço a ~ P"),
    "s.reward": ("reward r", "recompensa r"), "s.update": ("update(b, c, a, r)", "update(b, c, a, r)"),
    "s.log": ("log (c, a, r, P(a))", "registrar (c, a, r, P(a))"),
    "seg.decide": ("Decide", "Decidir"), "seg.act": ("Act", "Agir"), "seg.learn": ("Learn", "Aprender"),
    "c.seq.1t": ("Decide", "Decidir"),
    "c.seq.1a": ("The model turns the belief into estimates", "O modelo transforma a crença em estimativas"),
    "c.seq.1b": ("The rule turns estimates into P(arm)", "A regra transforma as estimativas em P(braço)"),
    "c.seq.2t": ("Learn", "Aprender"),
    "c.seq.2a": ("Only the chosen arm's reward is observed", "Só a recompensa do braço escolhido é observada"),
    "c.seq.2b": ("Logging P(a) enables offline replay and IPW", "Registrar P(a) permite replay e IPW offline"),
    # workflow
    "wf.title": ("A/B test as a special case of a bandit", "Teste A/B como caso particular de bandit"),
    "lane.ab": ("A/B/n test", "Teste A/B/n"), "lane.bandit": ("Contextual bandit", "Bandit contextual"),
    "ab.split": ("Split traffic", "Dividir tráfego"), "ab.split.sub": ("1/K per variant", "1/K por variante"),
    "ab.run": ("Run test", "Rodar o teste"), "ab.run.sub": ("fixed period", "período fixo"),
    "ab.analyze": ("Analyze", "Analisar"), "ab.analyze.sub": ("pick winner", "escolher vencedora"),
    "ab.ship": ("Ship winner", "Lançar vencedora"), "ab.ship.sub": ("100% traffic", "100% do tráfego"),
    "b.ctx": ("Observe context", "Observar contexto"), "b.ctx.sub": ("per request", "por requisição"),
    "b.est": ("Estimate arms", "Estimar braços"), "b.est.sub": ("mean + width", "média + largura"),
    "b.pick": ("Pick arm", "Escolher braço"), "b.pick.sub": ("explore / exploit", "explorar / aproveitar"),
    "b.reward": ("Get reward", "Receber recompensa"), "b.reward.sub": ("chosen arm only", "só do braço escolhido"),
    "b.update": ("Update model", "Atualizar modelo"), "b.update.sub": ("posterior", "posteriori"),
    "w.next": ("next round", "próxima rodada"),
    "c.wf.1t": ("Same thing at ε = 1", "Igual com ε = 1"),
    "c.wf.1a": ("ε-greedy with ε = 1 is the 1/K split (Z3: epsGreedy_one_is_ab_test)", "ε-gulosa com ε = 1 é a divisão 1/K (Z3: epsGreedy_one_is_ab_test)"),
    "c.wf.1b": ("Split, then ship = explore-then-commit", "Dividir e depois lançar = explorar e depois decidir"),
    "c.wf.2t": ("What the bandit adds", "O que o bandit acrescenta"),
    "c.wf.2a": ("Moves traffic to better arms during the test", "Move tráfego para os braços melhores durante o teste"),
    "c.wf.2b": ("Uses context: a winner per member, not one for all", "Usa contexto: uma vencedora por assinante, não uma para todos"),
    # timeline (video scene 1.2)
    "tl.title": ("Steal like an artist: the bandit, from 1952 to 2026", "Steal like an artist: o bandit, de 1952 a 2026"),
    "tl.sub": ("Video scene 1.2. Dates to the year or the month; the day is the first one.", "Cena 1.2 do vídeo. Datas no ano ou no mês; o dia é o primeiro."),
    "tl.theory": ("Theory", "Teoria"), "tl.industry": ("Industry", "Indústria"), "tl.ideas": ("Ideas", "Ideias"),
    "tl.robbins": ("1952 Robbins", "1952 Robbins"), "tl.robbins.d": ("States the multi-armed bandit problem", "Formula o problema do bandit de múltiplos braços"),
    "tl.linucb": ("2010 LinUCB", "2010 LinUCB"), "tl.linucb.d": ("Li, Chu, Langford, Schapire: context as a vector", "Li, Chu, Langford, Schapire: o contexto como vetor"),
    "tl.kleon": ("2012 Steal Like an Artist", "2012 Steal Like an Artist"), "tl.kleon.d": ("Austin Kleon: nothing is original", "Austin Kleon: nada é original"),
    "tl.hackday": ("2017 globo.com hackday", "2017 hackday da globo.com"), "tl.hackday.d": ("Bandit service in Scala (Tiago Motta)", "Serviço de bandit em Scala (Tiago Motta)"),
    "tl.netflix": ("2017-12 Netflix artwork", "2017-12 imagens da Netflix"), "tl.netflix.d": ("One image per title, per member", "Uma imagem por título, por assinante"),
    "tl.slides": ("2018 globo.com slides", "2018 slides da globo.com"), "tl.slides.d": ("Renan Moreira de Oliveira: MAB ML PARA AB RL", "Renan Moreira de Oliveira: MAB ML PARA AB RL"),
    "tl.motta": ("2024 Tiago Motta's post", "2024 post de Tiago Motta"), "tl.motta.d": ("The service is still in use", "O serviço ainda é usado"),
    "tl.rsi": ("2026 RSI", "2026 RSI"), "tl.rsi.d": ("The bandit inside the agent's self-improvement loop", "O bandit dentro do laço de automelhoria do agente"),
    "c.tl.t": ("Read it in the video", "Como entra no vídeo"),
    "c.tl.1": ("One event at a time, each with its source in small type", "Um marco por vez, cada um com a fonte em letra pequena"),
    "c.tl.2": ("The 58-year gap from Robbins to LinUCB is compressed", "O buraco de 58 anos entre Robbins e o LinUCB aparece comprimido"),
    # pi as a bandit (video scenes 1.3 and 1.4)
    "pi.title": ("π and you: one arm, then three", "π e você: um braço, depois três"),
    "pi.lane.agent": ("Agent", "Agente"), "pi.lane.you": ("You, the reward", "Você, a recompensa"),
    "pi.belief": ("Belief", "Crença"), "pi.belief.sub": ("mean grade per action", "nota média por ação"),
    "pi.pick": ("Exploit or explore", "Aproveitar ou explorar"), "pi.pick.sub": ("π(N), π(N+1), another lever", "π(N), π(N+1), outra alavanca"),
    "pi.show": ("Show π", "Mostrar π"), "pi.show.sub": ("one approximation", "uma aproximação"),
    "pi.grade": ("Is it good?", "Está bom?"), "pi.grade.sub": ("grade in [0, 1]", "nota em [0, 1]"),
    "pi.update": ("Update belief", "Atualizar crença"), "pi.update.sub": ("chosen action only", "só da ação escolhida"),
    "pi.next": ("next round", "próxima rodada"),
    "c.pi.1t": ("One arm: Leibniz (scene 1.3)", "Um braço: Leibniz (cena 1.3)"),
    "c.pi.1a": ("20 rounds: exploit 9 times (0.14), explore 11 times (0.76)", "20 rodadas: aproveitar 9 vezes (0,14), explorar 11 vezes (0,76)"),
    "c.pi.1b": ("Z3: step_exploit, step_explore_n, step_reward_bounded", "Z3: step_exploit, step_explore_n, step_reward_bounded"),
    "c.pi.2t": ("Three arms (scene 1.4)", "Três braços (cena 1.4)"),
    "c.pi.2a": ("Ramanujan 16 pulls, Gauss-Legendre 3, Leibniz 1", "Ramanujan 16 vezes, Gauss-Legendre 3, Leibniz 1"),
    "c.pi.2b": ("The agent never reads the formula; it hears you", "O agente não lê a fórmula; ele ouve você"),
    # RSI loop (video scenes 3.1 to 3.3)
    "rsi.title": ("Recursive self-improvement: a bandit that tunes a bandit", "Automelhoria recursiva: um bandit que ajusta um bandit"),
    "rsi.lane.outer": ("Outer agent", "Agente de fora"), "rsi.lane.inner": ("Inner agent", "Agente de dentro"),
    "rsi.pick": ("Select ε", "Escolher ε"), "rsi.pick.sub": ("arms 1, 0.5, 0.1, 0.01", "braços 1; 0,5; 0,1; 0,01"),
    "rsi.run": ("ε-greedy shop", "Sorveteria ε-gulosa"), "rsi.run.sub": ("500 customers", "500 clientes"),
    "rsi.gain": ("Mean gain", "Ganho médio"), "rsi.gain.sub": ("per customer", "por cliente"),
    "rsi.update": ("Update belief on ε", "Atualizar crença sobre ε"), "rsi.update.sub": ("no human in the loop", "sem pessoa no laço"),
    "rsi.next": ("next episode", "próximo episódio"),
    "c.rsi.1t": ("Result (scene 3.2)", "Resultado (cena 3.2)"),
    "c.rsi.1a": ("200 episodes: ε = 0.5 selected 168 times, gain 0.099", "200 episódios: ε = 0,5 escolhido 168 vezes, ganho 0,099"),
    "c.rsi.1b": ("ε = 0.01 selected 9 times, gain 0.057", "ε = 0,01 escolhido 9 vezes, ganho 0,057"),
    "c.rsi.2t": ("Same rule at both levels", "A mesma regra nos dois níveis"),
    "c.rsi.2a": ("Z3: rsi_valid, outer_explores (z3-scala Video.scala, R4)", "Z3: rsi_valid, outer_explores (z3-scala Video.scala, R4)"),
    "c.rsi.2b": ("In real systems the arms are edits to the agent itself", "Em sistemas reais, os braços são mudanças no próprio agente"),
}


def build(lang):
    i = 0 if lang == "en" else 1
    t = lambda k: T[k][i]
    out = f"docs/diagrams/{lang}"
    meta_extra = {"locale": "en"} if lang == "en" else {
        "locale": "pt-BR",
        "translations": json.loads(PT_UI.read_text(encoding="utf-8")),
    }

    def meta(title, name):
        return {"title": t(title), "output": f"{out}/{name}.html", "quality_profile": "showcase", **meta_extra}

    W, H = 130, 64
    arch = {
        "schema_version": 1,
        "diagram_type": "architecture",
        "meta": meta("arch.title", "bandit-architecture"),
        "components": [
            {"id": "member", "type": "external", "label": t("member"), "sublabel": t("member.sub"), "pos": [40, 200], "size": [W, H]},
            {"id": "context", "type": "frontend", "label": t("ctx"), "sublabel": t("ctx.sub"), "pos": [270, 200], "size": [W, H]},
            {"id": "model", "type": "database", "label": t("model"), "sublabel": t("model.sub"), "tag": t("model.tag"), "pos": [500, 200], "size": [W, H]},
            {"id": "rule", "type": "backend", "label": t("rule"), "sublabel": t("rule.sub"), "pos": [730, 200], "size": [W, H]},
            {"id": "home", "type": "frontend", "label": t("home"), "sublabel": t("home.sub"), "pos": [960, 200], "size": [W, H]},
            {"id": "spec", "type": "security", "label": t("spec"), "sublabel": t("spec.sub"), "pos": [730, 50], "size": [W, H]},
            {"id": "log", "type": "messagebus", "label": t("log"), "sublabel": t("log.sub"), "pos": [960, 50], "size": [W, H]},
        ],
        "connections": [
            {"id": "request", "from": "member", "to": "context", "label": t("e.request"), "variant": "emphasis"},
            {"id": "estimate", "from": "context", "to": "model", "label": t("e.estimate")},
            {"id": "estimates", "from": "model", "to": "rule", "label": t("e.meanwidth"), "variant": "emphasis"},
            {"id": "show", "from": "rule", "to": "home", "label": t("e.arm"), "variant": "emphasis"},
            {"id": "proves", "from": "spec", "to": "rule", "label": t("e.proves"), "variant": "security", "fromSide": "bottom", "toSide": "top"},
            {"id": "log", "from": "home", "to": "log", "label": t("e.log"), "variant": "dashed", "fromSide": "top", "toSide": "bottom"},
            {"id": "reward", "from": "home", "to": "model", "label": t("e.reward"), "fromSide": "bottom", "toSide": "bottom"},
        ],
        "cards": [
            {"dot": "cyan", "title": t("c.model"), "items": [t("c.model.1"), t("c.model.2")]},
            {"dot": "emerald", "title": t("c.rule"), "items": [t("c.rule.1"), t("c.rule.2")]},
            {"dot": "rose", "title": t("c.spec"), "items": [t("c.spec.1"), t("c.spec.2")]},
        ],
    }

    seq = {
        "schema_version": 1,
        "diagram_type": "sequence",
        "meta": meta("seq.title", "bandit-round"),
        "participants": [
            {"id": "home", "type": "external", "label": t("home"), "sublabel": t("member")},
            {"id": "agent", "type": "backend", "label": t("agent"), "sublabel": t("agent.sub")},
            {"id": "model", "type": "database", "label": t("model"), "sublabel": t("model.sub")},
            {"id": "rule", "type": "backend", "label": t("rule"), "sublabel": t("rule.sub")},
            {"id": "log", "type": "messagebus", "label": t("log"), "sublabel": t("log.sub")},
        ],
        "segments": [
            {"from": 150, "to": 295, "label": t("seg.decide")},
            {"from": 300, "to": 350, "label": t("seg.act")},
            {"from": 360, "to": 415, "label": t("seg.learn")},
        ],
        "messages": [
            {"id": "ctx", "from": "home", "to": "agent", "y": 165, "label": t("s.ctx"), "variant": "emphasis"},
            {"id": "est", "from": "agent", "to": "model", "y": 195, "label": t("s.est")},
            {"id": "estret", "from": "model", "to": "agent", "y": 225, "label": t("s.estret"), "variant": "return"},
            {"id": "rule", "from": "agent", "to": "rule", "y": 255, "label": t("s.rule")},
            {"id": "dist", "from": "rule", "to": "agent", "y": 283, "label": t("s.dist"), "variant": "return"},
            {"id": "show", "from": "agent", "to": "home", "y": 312, "label": t("s.show"), "variant": "emphasis"},
            {"id": "reward", "from": "home", "to": "agent", "y": 340, "label": t("s.reward"), "variant": "return"},
            {"id": "update", "from": "agent", "to": "model", "y": 372, "label": t("s.update")},
            {"id": "log", "from": "agent", "to": "log", "y": 402, "label": t("s.log"), "variant": "dashed"},
        ],
        "activations": [
            {"participant": "agent", "from": 165, "to": 408, "type": "backend"},
            {"participant": "model", "from": 190, "to": 231, "type": "database"},
            {"participant": "rule", "from": 250, "to": 289, "type": "backend"},
            {"participant": "model", "from": 367, "to": 380, "type": "database"},
        ],
        "cards": [
            {"dot": "emerald", "title": t("c.seq.1t"), "items": [t("c.seq.1a"), t("c.seq.1b")]},
            {"dot": "orange", "title": t("c.seq.2t"), "items": [t("c.seq.2a"), t("c.seq.2b")]},
        ],
    }

    wf = {
        "schema_version": 2,
        "diagram_type": "workflow",
        "meta": meta("wf.title", "ab-test-vs-bandit"),
        "lanes": [
            {"id": "ab", "label": t("lane.ab")},
            {"id": "bandit", "label": t("lane.bandit")},
        ],
        "mainPath": ["b_ctx", "b_est", "b_pick", "b_reward", "b_update"],
        "nodes": [
            {"id": "ab_split", "lane": "ab", "col": 0, "type": "frontend", "label": t("ab.split"), "sublabel": t("ab.split.sub")},
            {"id": "ab_run", "lane": "ab", "col": 1, "type": "backend", "label": t("ab.run"), "sublabel": t("ab.run.sub")},
            {"id": "ab_analyze", "lane": "ab", "col": 2, "type": "backend", "label": t("ab.analyze"), "sublabel": t("ab.analyze.sub")},
            {"id": "ab_ship", "lane": "ab", "col": 3, "type": "cloud", "label": t("ab.ship"), "sublabel": t("ab.ship.sub")},
            {"id": "b_ctx", "lane": "bandit", "col": 0, "type": "external", "label": t("b.ctx"), "sublabel": t("b.ctx.sub")},
            {"id": "b_est", "lane": "bandit", "col": 1, "type": "database", "label": t("b.est"), "sublabel": t("b.est.sub")},
            {"id": "b_pick", "lane": "bandit", "col": 2, "type": "backend", "label": t("b.pick"), "sublabel": t("b.pick.sub")},
            {"id": "b_reward", "lane": "bandit", "col": 3, "type": "frontend", "label": t("b.reward"), "sublabel": t("b.reward.sub")},
            {"id": "b_update", "lane": "bandit", "col": 4, "type": "database", "label": t("b.update"), "sublabel": t("b.update.sub")},
        ],
        "edges": [
            {"id": "ab1", "from": "ab_split", "to": "ab_run"},
            {"id": "ab2", "from": "ab_run", "to": "ab_analyze"},
            {"id": "ab3", "from": "ab_analyze", "to": "ab_ship", "variant": "emphasis"},
            {"id": "b1", "from": "b_ctx", "to": "b_est"},
            {"id": "b2", "from": "b_est", "to": "b_pick", "variant": "emphasis"},
            {"id": "b3", "from": "b_pick", "to": "b_reward"},
            {"id": "b4", "from": "b_reward", "to": "b_update"},
            {"id": "next", "from": "b_update", "to": "b_est", "label": t("w.next"), "variant": "dashed", "role": "return", "route": "bottom-channel"},
        ],
        "cards": [
            {"dot": "cyan", "title": t("c.wf.1t"), "items": [t("c.wf.1a"), t("c.wf.1b")]},
            {"dot": "emerald", "title": t("c.wf.2t"), "items": [t("c.wf.2a"), t("c.wf.2b")]},
        ],
    }

    timeline = {
        "schema_version": 1,
        "diagram_type": "timeline",
        "meta": {**meta("tl.title", "bandit-timeline"), "subtitle": t("tl.sub"), "evidence": "observed", "timezone": "UTC"},
        "layout": {"breaks": "auto"},
        "lanes": [
            {"id": "theory", "label": t("tl.theory")},
            {"id": "industry", "label": t("tl.industry")},
            {"id": "ideas", "label": t("tl.ideas")},
        ],
        "events": [
            {"id": "robbins", "at": "1952-01-01T00:00Z", "title": t("tl.robbins"), "detail": t("tl.robbins.d"), "lane": "theory", "kind": "change"},
            {"id": "linucb", "at": "2010-01-01T00:00Z", "title": t("tl.linucb"), "detail": t("tl.linucb.d"), "lane": "theory", "kind": "change"},
            {"id": "kleon", "at": "2012-01-01T00:00Z", "title": t("tl.kleon"), "detail": t("tl.kleon.d"), "lane": "ideas", "kind": "default"},
            {"id": "hackday", "at": "2017-01-01T00:00Z", "title": t("tl.hackday"), "detail": t("tl.hackday.d"), "lane": "industry", "kind": "action"},
            {"id": "netflix", "at": "2017-12-01T00:00Z", "title": t("tl.netflix"), "detail": t("tl.netflix.d"), "lane": "industry", "kind": "action"},
            {"id": "slides", "at": "2018-01-01T00:00Z", "title": t("tl.slides"), "detail": t("tl.slides.d"), "lane": "industry", "kind": "default"},
            {"id": "motta", "at": "2024-09-28T00:00Z", "title": t("tl.motta"), "detail": t("tl.motta.d"), "lane": "industry", "kind": "default"},
            {"id": "rsi", "at": "2026-01-01T00:00Z", "title": t("tl.rsi"), "detail": t("tl.rsi.d"), "lane": "ideas", "kind": "change"},
        ],
        "cards": [
            {"dot": "amber", "title": t("c.tl.t"), "items": [t("c.tl.1"), t("c.tl.2")]},
        ],
    }

    pi = {
        "schema_version": 2,
        "diagram_type": "workflow",
        "meta": meta("pi.title", "pi-arms"),
        "lanes": [
            {"id": "agent", "label": t("pi.lane.agent")},
            {"id": "you", "label": t("pi.lane.you")},
        ],
        "mainPath": ["pi_belief", "pi_pick", "pi_show", "pi_grade", "pi_update"],
        "nodes": [
            {"id": "pi_belief", "lane": "agent", "col": 0, "type": "database", "label": t("pi.belief"), "sublabel": t("pi.belief.sub")},
            {"id": "pi_pick", "lane": "agent", "col": 1, "type": "backend", "label": t("pi.pick"), "sublabel": t("pi.pick.sub")},
            {"id": "pi_show", "lane": "agent", "col": 2, "type": "frontend", "label": t("pi.show"), "sublabel": t("pi.show.sub")},
            {"id": "pi_grade", "lane": "you", "col": 3, "type": "external", "label": t("pi.grade"), "sublabel": t("pi.grade.sub")},
            {"id": "pi_update", "lane": "agent", "col": 4, "type": "database", "label": t("pi.update"), "sublabel": t("pi.update.sub")},
        ],
        "edges": [
            {"id": "p1", "from": "pi_belief", "to": "pi_pick", "variant": "emphasis"},
            {"id": "p2", "from": "pi_pick", "to": "pi_show"},
            {"id": "p3", "from": "pi_show", "to": "pi_grade"},
            {"id": "p4", "from": "pi_grade", "to": "pi_update", "variant": "emphasis"},
            {"id": "pnext", "from": "pi_update", "to": "pi_belief", "label": t("pi.next"), "variant": "dashed", "role": "return"},
        ],
        "cards": [
            {"dot": "cyan", "title": t("c.pi.1t"), "items": [t("c.pi.1a"), t("c.pi.1b")]},
            {"dot": "amber", "title": t("c.pi.2t"), "items": [t("c.pi.2a"), t("c.pi.2b")]},
        ],
    }

    rsi = {
        "schema_version": 2,
        "diagram_type": "workflow",
        "meta": meta("rsi.title", "rsi-loop"),
        "lanes": [
            {"id": "outer", "label": t("rsi.lane.outer")},
            {"id": "inner", "label": t("rsi.lane.inner")},
        ],
        "mainPath": ["rsi_pick", "rsi_run", "rsi_gain", "rsi_update"],
        "nodes": [
            {"id": "rsi_pick", "lane": "outer", "col": 0, "type": "backend", "label": t("rsi.pick"), "sublabel": t("rsi.pick.sub")},
            {"id": "rsi_run", "lane": "inner", "col": 1, "type": "backend", "label": t("rsi.run"), "sublabel": t("rsi.run.sub")},
            {"id": "rsi_gain", "lane": "inner", "col": 2, "type": "frontend", "label": t("rsi.gain"), "sublabel": t("rsi.gain.sub")},
            {"id": "rsi_update", "lane": "outer", "col": 3, "type": "database", "label": t("rsi.update"), "sublabel": t("rsi.update.sub")},
        ],
        "edges": [
            {"id": "r1", "from": "rsi_pick", "to": "rsi_run", "variant": "emphasis"},
            {"id": "r2", "from": "rsi_run", "to": "rsi_gain"},
            {"id": "r3", "from": "rsi_gain", "to": "rsi_update", "variant": "emphasis"},
            {"id": "rnext", "from": "rsi_update", "to": "rsi_pick", "label": t("rsi.next"), "variant": "dashed", "role": "return"},
        ],
        "cards": [
            {"dot": "emerald", "title": t("c.rsi.1t"), "items": [t("c.rsi.1a"), t("c.rsi.1b")]},
            {"dot": "violet", "title": t("c.rsi.2t"), "items": [t("c.rsi.2a"), t("c.rsi.2b")]},
        ],
    }

    d = HERE / lang
    d.mkdir(exist_ok=True)
    for name, obj in [("bandit-architecture.architecture", arch), ("bandit-round.sequence", seq), ("ab-test-vs-bandit.workflow", wf),
                      ("bandit-timeline.timeline", timeline), ("pi-arms.workflow", pi), ("rsi-loop.workflow", rsi)]:
        (d / f"{name}.json").write_text(json.dumps(obj, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    for lang in ("en", "pt-BR"):
        build(lang)
    print("wrote candidates to", HERE)
