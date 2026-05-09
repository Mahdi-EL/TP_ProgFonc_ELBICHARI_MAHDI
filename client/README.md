# MiniDiscord — Client TP Programmation Fonctionnelle
**Étudiant :** ELBICHARI Mahdi  
**Langage :** Elixir / OTP  
**Dépôt :** https://github.com/Mahdi-EL/TP_ProgFonc_ELBICHARI_MAHDI

---

## Arborescence du projet

```
TP_ProgFonc_ELBICHARI_MAHDI/
├── server/                      ← Serveur MiniDiscord (TP partie 1)
│   ├── lib/
│   │   ├── chat_server.ex
│   │   ├── client_handler.ex
│   │   ├── mini_discord.ex
│   │   └── salon.ex
│   └── mix.exs
├── client/                      ← Client MiniDiscord (TP partie 2)
│   ├── lib/
│   │   └── client.ex
│   └── mix.exs
└── README.md
```

---

## Initialisation

### Renommer le projet serveur et créer le client

```bash
# Renommer l'ancien projet en server
mv mon_projet server

# Créer le projet client
mix new client
cd client
```

### Lancer le serveur

```bash
cd server
iex -S mix
```

### Lancer le client

```bash
cd client
iex -S mix
MiniDiscord.Client.start("localhost", 4040)
```

---

## Vérification des connexions

Avant d'implémenter le client complet, vérification manuelle dans iex :

```elixir
# Se connecter au serveur
{:ok, socket} = :gen_tcp.connect('localhost', 4040,
  [:binary, packet: :line, active: false])

# Lire le message de bienvenue
:gen_tcp.recv(socket, 0)
# => {:ok, "Bienvenue sur MiniDiscord!\r\n"}

# Envoyer un pseudo
:gen_tcp.send(socket, "alice\r\n")

# Lire la suite
:gen_tcp.recv(socket, 0)
# => {:ok, "📋 Salons disponibles : ..."}
```

> **Remarque :** chaque ligne envoyée doit se terminer par `"\r\n"`

---

## 1. Client — `client/lib/client.ex`

### Code complet

```elixir
defmodule MiniDiscord.Client do

  @cle "miniDiscordKey2025_SecretKey32!!"

  def start(host, port) do
    pseudo = IO.gets("Ton pseudo : ") |> String.trim()
    salon  = IO.gets("Salon à rejoindre : ") |> String.trim()
    connect_with_retry(host, port, pseudo, salon, 1)
  end

  defp connect_with_retry(host, port, pseudo, salon, attempt) do
    case :gen_tcp.connect(String.to_charlist(host), port,
           [:binary, packet: 0, active: false]) do
      {:ok, socket} ->
        IO.puts("✅ Connecté à #{host}:#{port}")
        handshake(socket, pseudo, salon)
        receiver = Task.async(fn -> receive_loop(socket, host, port, pseudo, salon) end)
        sender   = Task.async(fn -> send_loop(socket) end)
        Task.await(receiver, :infinity)
        Task.await(sender, :infinity)

      {:error, reason} ->
        IO.puts("⚠️ Tentative #{attempt} échouée : #{inspect(reason)}")
        :timer.sleep(2000)
        connect_with_retry(host, port, pseudo, salon, attempt + 1)
    end
  end

  defp handshake(socket, pseudo, salon) do
    :gen_tcp.recv(socket, 0, 500)
    :gen_tcp.send(socket, pseudo <> "\r\n")
    case :gen_tcp.recv(socket, 0, 500) do
      {:ok, msg} -> IO.write(msg)
      _ -> :ok
    end
    :gen_tcp.send(socket, salon <> "\r\n")
    attendre_entree(socket)
  end

  defp attendre_entree(socket) do
    case :gen_tcp.recv(socket, 0, 1000) do
      {:ok, msg} ->
        IO.write(msg)
        cond do
          String.contains?(msg, "oui/non") ->
            choix = IO.gets("") |> String.trim()
            :gen_tcp.send(socket, choix <> "\r\n")
            attendre_entree(socket)
          String.contains?(msg, "Choisis un mot de passe") ->
            mdp = IO.gets("") |> String.trim()
            :gen_tcp.send(socket, mdp <> "\r\n")
            attendre_entree(socket)
          String.contains?(msg, "protégé") ->
            mdp = IO.gets("") |> String.trim()
            :gen_tcp.send(socket, mdp <> "\r\n")
            attendre_entree(socket)
          String.contains?(msg, "Tu es dans") ->
            :ok
          true ->
            attendre_entree(socket)
        end
      {:error, _} -> :ok
    end
  end

  defp receive_loop(socket, host, port, pseudo, salon) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, msg} ->
        IO.write(msg)
        receive_loop(socket, host, port, pseudo, salon)
      {:error, reason} ->
        IO.puts("\n🔌 Connexion perdue (#{inspect(reason)}). Reconnexion...")
        :gen_tcp.close(socket)
        connect_with_retry(host, port, pseudo, salon, 1)
    end
  end

  defp send_loop(socket) do
    msg = IO.gets("") |> String.trim()
    case valider_message(msg) do
      {:ok, msg_valide} ->
        iv = :crypto.strong_rand_bytes(16)
        msg_c = :crypto.crypto_one_time(:aes_256_ctr, @cle, iv, msg_valide, true)
        encoded = Base.encode64(iv <> msg_c)
        :gen_tcp.send(socket, encoded <> "\r\n")
      {:error, raison} ->
        IO.puts("❌ #{raison}")
    end
    send_loop(socket)
  end

  defp valider_message(msg) do
    cond do
      String.length(msg) == 0 ->
        {:error, "Message vide"}
      String.length(msg) > 500 ->
        {:error, "Message trop long (max 500 chars)"}
      String.match?(msg, ~r/[\\?<>]/) ->
        {:error, "Message contient des caractères interdits (\\ ? < >)"}
      true ->
        {:ok, msg}
    end
  end

end
```

### Explication des fonctions

| Fonction | Rôle |
|---|---|
| `start/2` | Point d'entrée — demande pseudo/salon et lance la connexion |
| `connect_with_retry/5` | Connexion TCP avec retry automatique |
| `handshake/3` | Échange initial pseudo/salon avec le serveur |
| `attendre_entree/1` | Gère les messages du serveur pendant le setup |
| `receive_loop/5` | Reçoit et affiche les messages en continu |
| `send_loop/1` | Lit le clavier, valide et envoie les messages chiffrés |
| `valider_message/1` | Filtre les messages invalides |

---

## 2.1 Reconnexion automatique

En cas d'échec de connexion, le client retente automatiquement toutes les 2 secondes :

```elixir
defp connect_with_retry(host, port, pseudo, salon, attempt) do
  case :gen_tcp.connect(...) do
    {:ok, socket} -> ...
    {:error, reason} ->
      IO.puts("⚠️ Tentative #{attempt} échouée : #{inspect(reason)}")
      :timer.sleep(2000)
      connect_with_retry(host, port, pseudo, salon, attempt + 1)
  end
end
```

### Test

```elixir
# Dans iex du serveur — tuer le ChatServer
Process.whereis(MiniDiscord.ChatServer) |> Process.exit(:kill)
```

Le client affiche :
```
⚠️ Tentative 1 échouée : :econnrefused
⚠️ Tentative 2 échouée : :econnrefused
✅ Connecté à localhost:4040  ← reconnexion automatique !
```

---

## 2.2 Reconnexion depuis la réception de message

Quand la connexion est perdue pendant une session, `receive_loop` détecte l'erreur et relance la connexion :

```elixir
defp receive_loop(socket, host, port, pseudo, salon) do
  case :gen_tcp.recv(socket, 0) do
    {:ok, msg} ->
      IO.write(msg)
      receive_loop(socket, host, port, pseudo, salon)
    {:error, reason} ->
      IO.puts("\n🔌 Connexion perdue (#{inspect(reason)}). Reconnexion...")
      :gen_tcp.close(socket)
      connect_with_retry(host, port, pseudo, salon, 1)
  end
end
```

### Test

```elixir
# Tuer le ChatServer pendant qu'un client est connecté
Process.whereis(MiniDiscord.ChatServer) |> Process.exit(:kill)
```

Le client affiche :
```
🔌 Connexion perdue (:closed). Reconnexion...
✅ Connecté à localhost:4040
```

---

## 2.3 Robustesse OTP

**Question : Qu'apporterait la gestion du suivi de processus,
redémarrage automatique par rapport à votre code ?**

Actuellement, la reconnexion du client est gérée manuellement
via `connect_with_retry/5` qui retente la connexion de façon récursive.
Cette approche fonctionne mais reste limitée.

Si on utilisait OTP (GenServer + Supervisor) côté client :

- **Redémarrage automatique** : si le processus client plante pour
  n'importe quelle raison (pas seulement une déconnexion réseau),
  le Supervisor le relancerait automatiquement sans intervention manuelle.

- **Gestion d'état** : l'état du client (pseudo, salon, socket)
  serait maintenu proprement dans un GenServer plutôt que passé
  en paramètres de fonction en fonction.

- **Let it crash** : au lieu de gérer tous les cas d'erreur
  manuellement, on laisserait le processus planter et le
  superviseur s'occuperait de le relancer dans un état propre.

- **Tolérance aux pannes complète** : notre code actuel ne gère
  que la déconnexion réseau. Avec OTP, tout type de crash serait
  géré automatiquement.

---

## 2.4 Filtrage de message

La fonction `valider_message/1` filtre les messages non conformes :

```elixir
defp valider_message(msg) do
  cond do
    String.length(msg) == 0 ->
      {:error, "Message vide"}
    String.length(msg) > 500 ->
      {:error, "Message trop long (max 500 chars)"}
    String.match?(msg, ~r/[\\?<>]/) ->
      {:error, "Message contient des caractères interdits (\\ ? < >)"}
    true ->
      {:ok, msg}
  end
end
```

### Test

| Message envoyé | Résultat |
|---|---|
| *(vide)* | `❌ Message vide` |
| 501 caractères | `❌ Message trop long (max 500 chars)` |
| `bonjour<monde` | `❌ Message contient des caractères interdits` |
| `bonjour` | Envoyé normalement ✅ |

---

## 2.5 Cryptographie AES-256

### Principe

Le serveur et les clients partagent la même clé AES-256 :

```elixir
@cle "miniDiscordKey2025_SecretKey32!!"  # 32 bytes
```

### Chiffrement côté client (`send_loop`)

```elixir
iv = :crypto.strong_rand_bytes(16)
msg_c = :crypto.crypto_one_time(:aes_256_ctr, @cle, iv, msg_valide, true)
encoded = Base.encode64(iv <> msg_c)
:gen_tcp.send(socket, encoded <> "\r\n")
```

### Déchiffrement côté serveur (`client_handler.ex`)

```elixir
defp dechiffrer(data) do
  try do
    decoded = Base.decode64!(String.trim(data))
    <<iv::binary-size(16), msg_chiffre::binary>> = decoded
    :crypto.crypto_one_time(:aes_256_ctr, @cle, iv, msg_chiffre, false)
  rescue
    _ -> data
  end
end
```

### Flux de communication

```
Client tape "bonjour"
→ iv = :crypto.strong_rand_bytes(16)
→ msg_c = AES256_encrypt("bonjour", @cle, iv)
→ envoie Base64(iv <> msg_c) sur le réseau  ← chiffré ✅

Serveur reçoit Base64(iv <> msg_c)
→ décode Base64
→ extrait iv (16 premiers bytes)
→ msg = AES256_decrypt(msg_c, @cle, iv) = "bonjour" ✅
→ broadcast "[mahdi] bonjour" aux autres clients ✅
```

### Preuve du chiffrement — logs serveur

```
🔐 Reçu chiffré : YzAzdFNlTC9lN0pSUnIyQ3h2NUJ2Tjh4NEVrPQ0K
🔓 Déchiffré    : fjhg

🔐 Reçu chiffré : TDhlMDl6eVVPYTVwOUVKOUlGSGIwQlNzZU85LytnPT0NCg==
🔓 Déchiffré    : sdfjhk

🔐 Reçu chiffré : QVV4dXhMcUdFQUNwOFJubDNKVEs3enRwS1FvPQ0K
🔓 Déchiffré    : heee
```

### Intérêt de la cryptographie

Sans cryptographie, les messages voyagent en clair sur le réseau.
N'importe qui qui intercepte le tunnel `bore` peut lire les conversations.

Avec AES-256-CTR :
- Les messages sont **illisibles sur le réseau** ✅
- Seuls les participants avec la **clé partagée** peuvent déchiffrer ✅
- AES-256 est le **standard militaire** de chiffrement ✅

---

## Récapitulatif — Tout ce qui a été implémenté

| Fonctionnalité | Fichier | Statut |
|---|---|---|
| Connexion TCP | `client.ex` | ✅ |
| Handshake pseudo/salon | `client.ex` | ✅ |
| Receiver loop | `client.ex` | ✅ |
| Sender loop | `client.ex` | ✅ |
| Reconnexion automatique (2.1) | `client.ex` | ✅ |
| Reconnexion depuis réception (2.2) | `client.ex` | ✅ |
| Robustesse OTP (2.3) | README | ✅ |
| Filtrage de messages (2.4) | `client.ex` | ✅ |
| Cryptographie AES-256 (2.5) | `client.ex` + `client_handler.ex` | ✅ |
