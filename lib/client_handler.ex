defmodule MiniDiscord.ClientHandler do
  require Logger
 
  # ─────────────────────────────────────────────
  # Point d'entrée
  # ─────────────────────────────────────────────
 
  def start(socket) do
    :gen_tcp.send(socket, "Bienvenue sur MiniDiscord!\r\n")
    pseudo = choisir_pseudo(socket)
    choisir_et_rejoindre_salon(socket, pseudo)
  end
 
  # ─────────────────────────────────────────────
  # Choix du pseudo (unique via ETS)
  # ─────────────────────────────────────────────
 
  defp choisir_pseudo(socket) do
    :gen_tcp.send(socket, "Entre ton pseudo : ")
    case :gen_tcp.recv(socket, 0) do
      {:ok, raw} ->
        pseudo = String.trim(raw)
 
        # Ignorer les sondes HTTP automatiques de Codespaces
        if String.starts_with?(pseudo, "GET") or String.starts_with?(pseudo, "POST") do
          :gen_tcp.close(socket)
          exit(:normal)
        end
 
        if pseudo_disponible?(pseudo) do
          reserver_pseudo(pseudo)
          pseudo
        else
          :gen_tcp.send(socket, "❌ Le pseudo \"#{pseudo}\" est déjà pris, choisis-en un autre.\r\n")
          choisir_pseudo(socket)
        end
 
      {:error, _} ->
        :gen_tcp.close(socket)
        exit(:normal)
    end
  end
 
  defp pseudo_disponible?(pseudo), do: :ets.lookup(:pseudos, pseudo) == []
  defp reserver_pseudo(pseudo),    do: :ets.insert(:pseudos, {pseudo, self()})
  defp liberer_pseudo(pseudo),     do: :ets.delete(:pseudos, pseudo)
 
  # ─────────────────────────────────────────────
  # Choix et rejoindre un salon
  # ─────────────────────────────────────────────
 
  defp choisir_et_rejoindre_salon(socket, pseudo) do
    # Afficher la liste des salons existants (mise à jour en temps réel)
    afficher_salons(socket)
 
    :gen_tcp.send(socket, "Rejoins un salon existant ou tape un nouveau nom : ")
    {:ok, raw} = :gen_tcp.recv(socket, 0)
    salon = String.trim(raw)
 
    rejoindre_salon(socket, pseudo, salon)
  end
 
  defp afficher_salons(socket) do
    case MiniDiscord.Salon.lister() do
      [] ->
        :gen_tcp.send(socket, "📋 Aucun salon existant — tu seras le premier !\r\n")
      salons ->
        liste = salons
          |> Enum.map(fn s ->
            verrou = if MiniDiscord.Salon.a_password?(s), do: "🔒", else: "🔓"
            "#{verrou} #{s}"
          end)
          |> Enum.join("  |  ")
        :gen_tcp.send(socket, "📋 Salons disponibles : #{liste}\r\n")
    end
  end
 
  defp rejoindre_salon(socket, pseudo, salon) do
    # Créer le salon s'il n'existe pas encore
    salon_existait? = Registry.lookup(MiniDiscord.Registry, salon) != []
 
    unless salon_existait? do
      DynamicSupervisor.start_child(
        MiniDiscord.SalonSupervisor,
        {MiniDiscord.Salon, salon})
 
      # Proposer de protéger le nouveau salon par un mot de passe
      :gen_tcp.send(socket, "🆕 Nouveau salon créé ! Veux-tu y mettre un mot de passe ? (oui/non) : ")
      {:ok, reponse} = :gen_tcp.recv(socket, 0)
      if String.trim(reponse) == "oui" do
        :gen_tcp.send(socket, "Choisis un mot de passe pour ##{salon} : ")
        {:ok, mdp} = :gen_tcp.recv(socket, 0)
        MiniDiscord.Salon.definir_password(salon, String.trim(mdp))
        :gen_tcp.send(socket, "✅ Mot de passe défini pour ##{salon} !\r\n")
      end
    end
 
    # Tenter de rejoindre (avec mot de passe si nécessaire)
    tenter_rejoindre(socket, pseudo, salon)
  end
 
  defp tenter_rejoindre(socket, pseudo, salon) do
    if MiniDiscord.Salon.a_password?(salon) do
      :gen_tcp.send(socket, "🔒 Ce salon est protégé. Entre le mot de passe : ")
      {:ok, mdp} = :gen_tcp.recv(socket, 0)
      mdp = String.trim(mdp)
 
      case MiniDiscord.Salon.rejoindre(salon, self(), mdp) do
        :ok ->
          entrer_dans_salon(socket, pseudo, salon)
        {:error, :mauvais_password} ->
          :gen_tcp.send(socket, "❌ Mot de passe incorrect ! Réessaie.\r\n")
          tenter_rejoindre(socket, pseudo, salon)
      end
    else
      MiniDiscord.Salon.rejoindre(salon, self())
      entrer_dans_salon(socket, pseudo, salon)
    end
  end
 
  defp entrer_dans_salon(socket, pseudo, salon) do
    MiniDiscord.Salon.broadcast(salon, "📢 #{pseudo} a rejoint ##{salon}\r\n")
    :gen_tcp.send(socket, "Tu es dans ##{salon} — écris tes messages (/ pour les commandes) !\r\n")
    loop(socket, pseudo, salon)
  end
 
  # ─────────────────────────────────────────────
  # Boucle principale
  # ─────────────────────────────────────────────
 
  defp loop(socket, pseudo, salon) do
    receive do
      {:message, msg} -> :gen_tcp.send(socket, msg)
    after 0 -> :ok
    end
 
    case :gen_tcp.recv(socket, 0, 100) do
      {:ok, raw} ->
        msg = String.trim(raw)
        if String.starts_with?(msg, "/") do
          gerer_commande(socket, pseudo, salon, msg)
        else
          MiniDiscord.Salon.broadcast(salon, "[#{pseudo}] #{msg}\r\n")
          loop(socket, pseudo, salon)
        end
 
      {:error, :timeout} ->
        loop(socket, pseudo, salon)
 
      {:error, reason} ->
        Logger.info("Client déconnecté : #{inspect(reason)}")
        MiniDiscord.Salon.broadcast(salon, "👋 #{pseudo} a quitté ##{salon}\r\n")
        MiniDiscord.Salon.quitter(salon, self())
        liberer_pseudo(pseudo)
    end
  end
 
  # ─────────────────────────────────────────────
  # Commandes slash
  # ─────────────────────────────────────────────
 
  defp gerer_commande(socket, pseudo, salon, commande) do
    case commande do
      "/list" ->
        afficher_salons(socket)
        loop(socket, pseudo, salon)
 
      "/quit" ->
        MiniDiscord.Salon.broadcast(salon, "👋 #{pseudo} a quitté ##{salon}\r\n")
        MiniDiscord.Salon.quitter(salon, self())
        liberer_pseudo(pseudo)
        :gen_tcp.send(socket, "À bientôt !\r\n")
        :gen_tcp.close(socket)
 
      "/join " <> nouveau_salon ->
        nouveau_salon = String.trim(nouveau_salon)
        MiniDiscord.Salon.broadcast(salon, "👣 #{pseudo} a quitté ##{salon}\r\n")
        MiniDiscord.Salon.quitter(salon, self())
        rejoindre_salon(socket, pseudo, nouveau_salon)
 
      "/password " <> nouveau_mdp ->
        MiniDiscord.Salon.definir_password(salon, String.trim(nouveau_mdp))
        :gen_tcp.send(socket, "✅ Mot de passe mis à jour pour ##{salon} !\r\n")
        loop(socket, pseudo, salon)
 
      _ ->
        :gen_tcp.send(socket, "❓ Commandes : /list  /join <salon>  /password <mdp>  /quit\r\n")
        loop(socket, pseudo, salon)
    end
  end
end