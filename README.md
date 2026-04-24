# MiniDiscord — Compte-rendu de TP

## Arborescence du projet

```
mini_discord/
├── lib/
│   ├── salon.ex
│   ├── client_handler.ex
│   ├── mini_discord.ex
│   └── chat_server.ex
├── test/
├── mix.exs
└── README.md
```

---

## Phase 1 — GenServer : le module Salon


### Réponses aux questions — Phase 1

**Q1. Pourquoi utilise-t-on `Process.monitor/1` dans `handle_call({:rejoindre})` ?**

`Process.monitor/1` permet au salon (GenServer) de surveiller le processus client.
Si le client se déconnecte brutalement (crash réseau, fermeture du terminal…),
son processus se termine et Erlang/OTP envoie automatiquement au salon un message
`{:DOWN, ref, :process, pid, reason}`.
Sans ce mécanisme, le salon garderait indéfiniment un PID mort dans sa liste
`clients` et essaierait de lui envoyer des messages, ce qui causerait des erreurs silencieuses.

---

**Q2. Que se passe-t-il si on n'implémente pas `handle_info({:DOWN, ...})` ?**

Si on n'implémente pas ce callback, OTP envoie quand même le message `{:DOWN, ...}`
au GenServer, mais personne ne le traite : il reste dans la boîte aux lettres du processus
et génère un warning `handle_info/2 not handled`.
Plus grave, le PID du client mort reste dans `state.clients` pour toujours.
À chaque broadcast, le salon essaie d'envoyer un message à ce PID fantôme ;
`send/2` ne plante pas (c'est tolérant en Elixir), mais c'est une fuite mémoire
car la liste grandit sans jamais se nettoyer.

---

**Q3. Quelle est la différence entre `handle_call` et `handle_cast` ?
Pourquoi `broadcast` est un cast ?**

| | `handle_call` | `handle_cast` |
|---|---|---|
| Synchronisme | **Synchrone** — le processus appelant attend la réponse | **Asynchrone** — l'appelant n'attend rien |
| Réponse | Obligatoire (`{:reply, valeur, état}`) | Aucune (`{:noreply, état}`) |
| Blocage | Oui, pendant le traitement | Non |

`broadcast` est un `cast` parce que l'expéditeur du message n'a pas besoin
de savoir quand les abonnés ont reçu le message : il envoie et continue.
Utiliser un `call` bloquerait le client le temps que le salon distribue le message
à tous ses abonnés, ce qui serait inutile et moins performant.
En revanche, `rejoindre` et `quitter` sont des `call` car on a besoin de la confirmation
(`:ok`) avant de continuer le flux de connexion.

---

## Phase 2 — Supervision et robustesse

### Test — tuer le salon "general"

```elixir
# Dans iex -S mix :
pid = GenServer.whereis({:via, Registry, {MiniDiscord.Registry, "general"}})
Process.exit(pid, :kill)
```

### Réponses aux questions — Phase 2

**Q2-4. Le salon redémarre-t-il après le kill ? Pourquoi ?**

Oui, le salon redémarre automatiquement.
Il est supervisé par `MiniDiscord.SalonSupervisor` (un `DynamicSupervisor`
avec la stratégie `:one_for_one`).
Quand un processus enfant meurt, le superviseur reçoit le signal de fin et
en relance une nouvelle instance selon les paramètres définis dans `start_link`.
C'est le principe fondamental de la tolérance aux pannes OTP : *let it crash*,
le superviseur se charge de la résurrection.
Les clients connectés reçoivent toutefois un message d'erreur car leurs sockets
sont liées à l'ancien processus ; ils devront se reconnecter au salon.

---

**Q2-5. Quelle est la différence entre `:one_for_one` et `:one_for_all` ?**

- **`:one_for_one`** : si un enfant plante, **seul cet enfant** est redémarré.
  Les autres enfants continuent de fonctionner normalement.
  C'est la stratégie utilisée ici car les salons sont indépendants les uns des autres.

- **`:one_for_all`** : si un enfant plante, **tous les enfants** sont arrêtés
  puis redémarrés.
  On l'utilise quand les processus sont fortement couplés et ne peuvent pas
  fonctionner correctement sans les autres (ex : un processus de configuration
  dont tous les autres dépendent).

---

## Phase 3 — Sécurité et commandes

### 3.1 Pseudos uniques via ETS

Dans `mini_discord.ex`, la table ETS est créée au démarrage de l'application :
```elixir
:ets.new(:pseudos, [:named_table, :public, :set])
```

Dans `client_handler.ex` :
```elixir
defp pseudo_disponible?(pseudo), do: :ets.lookup(:pseudos, pseudo) == []
defp reserver_pseudo(pseudo),    do: :ets.insert(:pseudos, {pseudo, self()})
defp liberer_pseudo(pseudo),     do: :ets.delete(:pseudos, pseudo)
```

La fonction `choisir_pseudo/1` boucle récursivement jusqu'à obtenir un pseudo libre.

### 3.2 Commandes slash

| Commande | Effet |
|---|---|
| `/list` | Affiche les salons actifs |
| `/join <salon>` | Quitte le salon actuel et rejoint le nouveau |
| `/quit` | Déconnecte proprement le client |
| autre | "Commande inconnue" |


