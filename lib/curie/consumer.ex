defmodule Curie.Consumer do
  use Nostrum.Consumer

  alias Nostrum.Struct.{Message, WSState}

  @self __MODULE__
  @handlers %{
    message: [
      &Curie.Generic.handler/1,
      &Curie.Help.handler/1,
      &Curie.Images.handler/1,
      &Curie.Storage.handler/1,
      &Curie.Currency.handler/1,
      &Curie.Colors.handler/1,
      &Curie.Weather.handler/1,
      &Curie.Pot.handler/1,
      &Curie.TwentyOne.handler/1,
      &Curie.Leaderboard.handler/1
    ],
    presence: [
      &Curie.Storage.store_details/1,
      &Curie.Storage.status_gather/1,
      &Curie.Announcements.stream/1
    ]
  }

  @spec start_link() :: Supervisor.on_start()
  def start_link do
    Consumer.start_link(@self, name: @self)
  end

  @spec call_handlers(Message.t() | map(), [function()]) :: no_return()
  def call_handlers(payload, handlers),
    do: Task.start(fn -> for handler <- handlers, do: handler.(payload) end)

  @spec add_heartbeat(Message.t(), WSState.t()) :: map()
  def add_heartbeat(message, ws) do
    {send, _} = ws.last_heartbeat_send.microsecond
    {ack, _} = ws.last_heartbeat_ack.microsecond
    Map.put(message, :heartbeat, %{send: send, ack: ack})
  end

  @impl true
  def handle_event({:READY, _payload, _ws_state}) do
    IO.puts("# Curie: Awake! #{Curie.time_now()}")
    Curie.Scheduler.set_status()
  end

  @impl true
  def handle_event({:MESSAGE_CREATE, {%{content: _content} = message}, ws_state}) do
    message |> add_heartbeat(ws_state) |> call_handlers(@handlers.message)
  end

  @impl true
  def handle_event({:MESSAGE_UPDATE, {%{content: _content} = updated}, ws_state}) do
    updated |> add_heartbeat(ws_state) |> call_handlers(@handlers.message)
  end

  @impl true
  def handle_event({:PRESENCE_UPDATE, {_guild, _old, new}, _ws_state}) do
    call_handlers(new, @handlers.presence)
  end

  @impl true
  def handle_event({:MESSAGE_DELETE, {message}, _ws_state}) do
    Curie.Announcements.delete_log(message)
  end

  @impl true
  def handle_event({:MESSAGE_REACTION_ADD, {reaction}, _ws_state}) do
    Curie.Leaderboard.handler(reaction)
  end

  @impl true
  def handle_event({:MESSAGE_REACTION_REMOVE, {reaction}, _ws_state}) do
    Curie.Leaderboard.handler(reaction)
  end

  @impl true
  def handle_event({:GUILD_MEMBER_ADD, {guild_id, member}, _ws_state}) do
    Curie.Announcements.join_log(guild_id, member)
  end

  @impl true
  def handle_event({:GUILD_MEMBER_REMOVE, {_guild_id, member}, _ws_state}) do
    Curie.Announcements.leave_log(member)
    Curie.Storage.remove(member.user.id)
  end

  @impl true
  def handle_event(_event), do: :ignored
end
