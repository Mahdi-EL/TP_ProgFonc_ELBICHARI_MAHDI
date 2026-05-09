# MiniDiscord — TP Programmation Fonctionnelle
**Étudiant :** ELBICHARI Mahdi  
**Langage :** Elixir / OTP  
**Dépôt :** https://github.com/Mahdi-EL/TP_ProgFonc_ELBICHARI_MAHDI

---

## Présentation du projet

Ce projet est un mini serveur de chat (inspiré de Discord) développé en **Elixir** avec le framework **OTP**. Il est divisé en deux parties :

| Partie | Dossier | Description |
|---|---|---|
| **TP1 — Serveur** | [`server/`](./server) | Serveur TCP multi-clients avec supervision OTP |
| **TP2 — Client** | [`client/`](./client) | Client TCP avec reconnexion et cryptographie |

---

## TP1 — Serveur

Le serveur gère les connexions des utilisateurs, les salons de discussion et la diffusion des messages.

### Fonctionnalités principales
- **GenServer** — Chaque salon est un processus qui gère ses abonnés
- **Supervision OTP** — Redémarrage automatique en cas de crash
- **Pseudos uniques** — Gestion via table ETS
- **Historique** — Les 10 derniers messages conservés par salon
- **Commandes** — `/list`, `/join`, `/quit`, `/password`
- **Bonus** — Authentification par mot de passe hashé SHA-256

### Lancer le serveur
```bash
cd server
iex -S mix
```

➡️ **[Voir le README complet du serveur](./server/README.md)**

---

## TP2 — Client

Le client permet de se connecter au serveur MiniDiscord depuis n'importe quelle machine.

### Fonctionnalités principales
- **Connexion TCP** — Connexion au serveur avec handshake automatique
- **Reconnexion automatique** — Retry toutes les 2 secondes si connexion perdue
- **Filtrage** — Rejet des messages vides, trop longs ou avec caractères interdits
- **Cryptographie AES-256** — Messages chiffrés sur le réseau avec clé partagée

### Lancer le client
```bash
cd client
iex -S mix
```
```elixir
MiniDiscord.Client.start("localhost", 4040)
```

➡️ **[Voir le README complet du client](./client/README.md)**

---

## Architecture globale

```
Utilisateur A          Utilisateur B
(Client Elixir)        (Client nc/telnet)
      │                       │
      │  iv <> AES256(msg)    │  message texte
      ▼                       ▼
┌─────────────────────────────────────┐
│           Serveur TCP               │
│  ┌──────────────────────────────┐   │
│  │      Supervision OTP         │   │
│  │  ┌────────┐  ┌────────────┐  │   │
│  │  │ Salon  │  │ ChatServer │  │   │
│  │  │General │  │  (TCP)     │  │   │
│  │  └────────┘  └────────────┘  │   │
│  └──────────────────────────────┘   │
└─────────────────────────────────────┘
```

---

## Accès depuis l'extérieur — Tunnel bore

```bash
# Installer bore
curl -L https://github.com/ekzhang/bore/releases/download/v0.5.0/bore-v0.5.0-x86_64-unknown-linux-musl.tar.gz | tar xz

# Lancer le tunnel
./bore local 4040 --to bore.pub
# => listening at bore.pub:XXXXX

# Connexion depuis n'importe quelle machine
telnet bore.pub XXXXX
```

---

## Technologies utilisées

| Technologie | Usage |
|---|---|
| **Elixir** | Langage de programmation |
| **OTP** | Supervision et tolérance aux pannes |
| **GenServer** | Gestion des salons de discussion |
| **ETS** | Stockage des pseudos actifs |
| **AES-256-CTR** | Chiffrement des messages |
| **bore** | Tunnel pour accès externe |
