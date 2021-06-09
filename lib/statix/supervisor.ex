defmodule Statix.Supervisor do
  @moduledoc """
  # TODO: write moduledoc
  """

  use GenServer

  # consider a connection reestablished after 15s
  @reconnect_timeout 15 * 1_000

  # by default, give up on reconnecting after 10 failed attempts
  @default_max_reconnect_attempts 10

  defmodule State do
    @moduledoc false

    @enforce_keys [:mod]
    defstruct mod: nil,
              alive: true,
              reconnect_timeout: nil,
              reconnect_attempts: 0,
              max_reconnect_attempts: -1
  end

  def start_link(opts) do
    name = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl GenServer
  def init(opts) do
    # if a port closure is detected, we'll attempt to open a new connection
    Process.flag(:trap_exit, true)

    statix_mod =
      case Keyword.fetch(opts, :statix_mod) do
        {:ok, mod} -> mod
        :error -> raise "must provide `:statix_mod` when starting `Statix.Supervisor`"
      end

    max_reconnect_attempts =
      Keyword.get(opts, :max_reconnect_attempts, @default_max_reconnect_attempts)

    # open a managed connection to the server
    :ok = statix_mod.connect(managed: true)

    {:ok, %State{mod: statix_mod, max_reconnect_attempts: max_reconnect_attempts}}
  end

  @impl GenServer
  def handle_info({:EXIT, _port, %Statix.Conn.PortClosedError{} = _reason}, state) do
    # cancel previous timeout, if any
    if state.reconnect_timeout, do: :timer.cancel(state.reconnect_timeout)

    if state.reconnect_attempts >= state.max_reconnect_attempts do
      {:exit, {:shutdown, "too many reconnect attempts"},
       %{state | reconnect_attempts: state.reconnect_attempts + 1}}
    else
      # open a new managed connection
      :ok = state.mod.connect(managed: true)

      # reset reconnect attempts after timeout
      timeout = :timer.send_after(@reconnect_timeout, :reconnected)

      {:noreply,
       %{state | reconnect_timeout: timeout, reconnect_attempts: state.reconnect_attempts + 1}}
    end
  end

  def handle_info({:EXIT, _port, reason}, state) do
    # pass abnormal exits up to the supervisor
    {:stop, {:shutdown, reason}, state}
  end

  def handle_info(:reconnected, state) do
    {:noreply, %{state | reconnect_timeout: nil, reconnect_attempts: 0}}
  end
end
