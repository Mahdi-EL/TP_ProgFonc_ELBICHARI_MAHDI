defmodule MiniDiscord.Client do

  @doc"""
  Point d'entrée principal du client.
  host : nom type 'xxxbore.pub'
  port : entier ex: 4040
  """
 def start(host, port) do
  connect_with_retry(host, port, 1)
end
defp connect_with_retry(host, port, attempt) do
  case :gen_tcp.connect(String.to_charlist(host), port,
         [:binary, packet: :line, active: false]) do

    {:ok, socket} ->
      IO.puts("✅ Connecté au serveur #{host}:#{port}")

      rencontre(socket)

      IO.puts("💬 Tu peux envoyer des messages :")

      receiver = Task.async(fn -> receive_loop(socket, host, port) end)
      sender   = Task.async(fn -> send_loop(socket) end)

      Task.await(receiver, :infinity)
      Task.await(sender, :infinity)

    {:error, reason} ->
      IO.puts("❌ Tentative #{attempt} échouée : #{inspect(reason)}")
      :timer.sleep(2000)
      connect_with_retry(host, port, attempt + 1)
  end
end

  # Échange initial : pseudo et salon
  defp rencontre(socket) do
  # Lire message de bienvenue
  recv_print(socket)

  # 👉 demander directement le pseudo
  pseudo = IO.gets("Pseudo: ") |> String.trim()
  :gen_tcp.send(socket, pseudo <> "\r\n")

  # Lire réponse serveur (liste salons)
  recv_print(socket)

  # Choisir salon
  salon = IO.gets("Salon: ") |> String.trim()
  :gen_tcp.send(socket, salon <> "\r\n")

  # Lire confirmation
  recv_print(socket)
end

  # Boucle de réception — affiche les messages du serveur
  defp receive_loop(socket, host, port) do
  case :gen_tcp.recv(socket, 0) do
    {:ok, msg} ->
      IO.write(msg)
      receive_loop(socket, host, port)

    {:error, reason} ->
      IO.puts("\n🔌 Connexion perdue (#{inspect(reason)}). Reconnexion...")
      :gen_tcp.close(socket)
      connect_with_retry(host, port, 1)
  end
end

  # Boucle d'envoi — lit le clavier et envoie au serveur
  defp send_loop(socket) do
  case IO.gets("> ") do
    nil ->
      IO.puts("Fin du client")
      :gen_tcp.close(socket)

    msg ->
      msg = String.trim(msg)

      if msg != "" do
        :gen_tcp.send(socket, msg <> "\r\n")
      end

      send_loop(socket)
  end
end

  # Helper — reçoit et affiche un message
  defp recv_print(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, msg} -> IO.write(msg)
      {:error, _} -> IO.puts("Erreur de réception")
    end
  end
  defp valider_message(msg) do
  cond do
    msg == "" ->
      {:error, "Message vide"}

    String.length(msg) > 500 ->
      {:error, "Message trop long (max 500 caractères)"}

    String.match?(msg, ~r/[<>\\]/) ->
      {:error, "Caractères interdits"}

    true ->
      {:ok, msg}
  end
end
end