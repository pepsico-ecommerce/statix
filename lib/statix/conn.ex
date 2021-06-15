defmodule Statix.Conn do
  @moduledoc false

  defmodule PortClosedError do
    @moduledoc "Raised when a port closure is detected."

    @message "Port closure detected."
    defexception [:message]

    @impl true
    def exception(_), do: %__MODULE__{message: @message}
  end

  defstruct [:sock, :header, :name]

  alias Statix.Packet

  require Logger

  def new(host, port) when is_binary(host) do
    new(String.to_charlist(host), port)
  end

  def new(host, port) when is_list(host) or is_tuple(host) do
    case :inet.getaddr(host, :inet) do
      {:ok, address} ->
        header = Packet.header(address, port)
        %__MODULE__{header: header}

      {:error, reason} ->
        raise(
          "cannot get the IP address for the provided host " <>
            "due to reason: #{:inet.format_error(reason)}"
        )
    end
  end

  def open(%__MODULE__{name: name}) do
    {:ok, sock} = :gen_udp.open(0, active: false)
    Process.register(sock, name)
  end

  def transmit(%__MODULE__{header: header, sock: sock} = conn, type, key, val, options)
      when is_binary(val) and is_list(options) do
    result =
      header
      |> Packet.build(type, key, val, options)
      |> transmit(conn)

    if result == {:error, :port_closed} do
      Logger.error(fn ->
        if(is_atom(sock), do: "", else: "Statix ") <>
          "#{inspect(sock)} #{type} metric \"#{key}\" lost value #{val}" <> " due to port closure"
      end)

      # open a new port for subsequent tranmissions
      # NOTE: this port will be linked to the process that
      # called `transmit`, so perhaps this should be handled
      # by sending a message to a GenServer instead?
      open(conn)
    end

    result
  end

  defp transmit(packet, %__MODULE__{sock: sock}) do
    try do
      Port.command(sock, packet)
    rescue
      ArgumentError ->
        {:error, :port_closed}
    else
      true ->
        receive do
          {:inet_reply, _port, status} -> status
        end
    end
  end
end
