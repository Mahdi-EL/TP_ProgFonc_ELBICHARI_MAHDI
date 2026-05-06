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
    # Vider les messages du serveur
    :gen_tcp.recv(socket, 0, 500)
    :gen_tcp.send(socket, pseudo <> "\r\n")
    :gen_tcp.recv(socket, 0, 500)
    :gen_tcp.send(socket, salon <> "\r\n")
    :gen_tcp.recv(socket, 0, 500)
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
    :gen_tcp.send(socket, msg <> "\r\n")
    send_loop(socket)
  end
end