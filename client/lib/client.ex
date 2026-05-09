defmodule MiniDiscord.Client do

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
      # Consommer bienvenue + prompt pseudo
      :gen_tcp.recv(socket, 0, 500)
      # Envoyer pseudo
      :gen_tcp.send(socket, pseudo <> "\r\n")
      # Consommer liste salons + prompt salon
      :gen_tcp.recv(socket, 0, 500)
      # Envoyer salon
      :gen_tcp.send(socket, salon <> "\r\n")
      # Gérer les messages jusqu'à "Tu es dans"
      attendre_entree(socket)
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

  @cle "miniDiscordKey2025_SecretKey32!!"

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
  defp attendre_entree(socket) do
  case :gen_tcp.recv(socket, 0, 1000) do
    {:ok, msg} ->
      IO.write(msg)
      cond do
        # Salon créé → répondre "non" au mot de passe
        String.contains?(msg, "mot de passe") ->
          :gen_tcp.send(socket, "non\r\n")
          attendre_entree(socket)
        # On est dans le salon → handshake terminé
        String.contains?(msg, "Tu es dans") ->
          :ok
        true ->
          attendre_entree(socket)
      end
    {:error, _} -> :ok
    end 
  end

end