defmodule MiniDiscord.Salon do
  use GenServer
 
  # ─────────────────────────────────────────────
  # API publique
  # ─────────────────────────────────────────────
 
  def start_link(name) do
    GenServer.start_link(__MODULE__,
      %{name: name, clients: [], historique: [], password: nil},
      name: via(name))
  end
 
  def rejoindre(salon, pid, password \\ nil),
    do: GenServer.call(via(salon), {:rejoindre, pid, password})
 
  def quitter(salon, pid),
    do: GenServer.call(via(salon), {:quitter, pid})
 
  def broadcast(salon, msg),
    do: GenServer.cast(via(salon), {:broadcast, msg})
 
  def definir_password(salon, password),
    do: GenServer.call(via(salon), {:set_password, password})
 
  def a_password?(salon),
    do: GenServer.call(via(salon), :a_password?)
 
  def lister do
    Registry.select(MiniDiscord.Registry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end
 
  # ─────────────────────────────────────────────
  # Callbacks GenServer
  # ─────────────────────────────────────────────
 
  def init(state), do: {:ok, state}
 
  def handle_call({:set_password, password}, _from, state) do
    hashed = :crypto.hash(:sha256, password)
    {:reply, :ok, %{state | password: hashed}}
  end
 
  def handle_call(:a_password?, _from, state) do
    {:reply, state.password != nil, state}
  end
 
  def handle_call({:rejoindre, pid, password}, _from, state) do
    cond do
      state.password == nil ->
        {:reply, :ok, ajouter_client(pid, state)}
 
      password != nil and :crypto.hash(:sha256, password) == state.password ->
        {:reply, :ok, ajouter_client(pid, state)}
 
      true ->
        {:reply, {:error, :mauvais_password}, state}
    end
  end
 
  def handle_call({:quitter, pid}, _from, state) do
    nouveaux_clients = List.delete(state.clients, pid)
    {:reply, :ok, %{state | clients: nouveaux_clients}}
  end
 
  def handle_cast({:broadcast, msg}, state) do
    Enum.each(state.clients, fn pid -> send(pid, {:message, msg}) end)
    nouvel_historique = Enum.take([msg | state.historique], 10)
    {:noreply, %{state | historique: nouvel_historique}}
  end
 
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    nouveaux_clients = List.delete(state.clients, pid)
    {:noreply, %{state | clients: nouveaux_clients}}
  end
 
  # ─────────────────────────────────────────────
  # Helpers privés
  # ─────────────────────────────────────────────
 
  defp ajouter_client(pid, state) do
    Process.monitor(pid)
    Enum.each(Enum.reverse(state.historique), fn msg ->
      send(pid, {:message, "[historique] #{msg}"})
    end)
    %{state | clients: [pid | state.clients]}
  end
 
  defp via(name), do: {:via, Registry, {MiniDiscord.Registry, name}}
end