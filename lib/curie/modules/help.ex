defmodule Curie.Help do
  use Curie.Commands
  use GenServer

  alias Curie.Data.Help
  alias Curie.Data

  @check_typo ["curie", "currency", "help"]
  @self __MODULE__

  def start_link(_args) do
    GenServer.start_link(@self, [], name: @self)
  end

  def init(_args) do
    {:ok, get_commands()}
  end

  def handle_call(:get, _from, state), do: {:reply, state, state}

  def handle_cast(:reload, _state), do: {:noreply, get_commands()}

  def parse(content) when is_binary(content), do: String.replace(content, "<prefix>", @prefix)

  def parse(%{command: command, description: description, short: short} = _entry),
    do: {command, %{description: parse(description), short: short}}

  def get_commands do
    case Data.all(Help) do
      [] ->
        %{commands: [], full: %{}}

      entries ->
        Enum.map(entries, &parse(&1))
        |> Enum.into(%{})
        |> (&%{commands: Map.keys(&1), full: &1}).()
    end
  end

  def command({"curie", message, _args}) do
    ("Heya, my name is Curie! I am a Discord bot written in Elixir.\n" <>
       "My purpose here is to accompany members of Shadowmere, \n" <>
       "offering relevant information and playful distractions.\n" <>
       "My duties consist of fetching various content from the web,\n" <>
       "posting notifications, updates and hosting mini-games.\n" <>
       "I also help managing this guild with things like role management,\n" <>
       "tracking changes and mundane maintanace tasks.\n" <>
       "If you want to find out about all the things I can help you with,\n" <>
       "you can use one of my commands called **#{@prefix}help**.\n" <>
       "If you want to look at my source code, you can find it here:\n" <>
       "https://github.com/Andris0/CurieEx")
    |> (&Curie.embed(message, &1, 0x620589)).()
  end

  def command({"currency", message, _args}) do
    ("One of the things I manage here is the Currency System.\n" <>
       "It works like this, you can ask the server owner to\n" <>
       "whitelist your account and when approved, you will\n" <>
       "have a balance tied to your account in form of Tempests #{@tempest}.\n" <>
       "You can use these tempests to partake in my mini-games,\n" <>
       "collect rewards and have your name on the leaderboard.\n" <>
       "Current currency related mini-games are Pots and 21,\n" <>
       "purchasable rewards are guild name color roles.\n" <>
       "Both games need at least 2 players to reach a result.\n" <>
       "I can fill one of the player spots, if it is needed.\n" <>
       "(If I have any tempests myself to spend of course.)\n" <>
       "At the start your balance will be 0, you can obtain them\n" <>
       "from a passive gain by being online during full clock hours.\n" <>
       "Passive gain caps at 300, so you'll actaully have to play\n" <>
       "with some other folk if you want to have enough for a name color.\n" <>
       "Other than that, good luck and don't spend it all in one place!\n" <>
       "(Not like you can spend it anywhere else anyway.)")
    |> (&Curie.embed(message, &1, 0xFFD700)).()
  end

  def command({"help", @owner = message, [call]}) when call == "r" do
    GenServer.cast(@self, :reload)
    Curie.embed(message, "Help module state reloaded.", "green")
  end

  def command({"help", message, args}) when args == [] do
    state = GenServer.call(@self, :get)

    commands =
      state.commands
      |> Enum.filter(&(state.full[&1].short != nil))
      |> Enum.map(&"**#{@prefix <> &1}** - #{state.full[&1].short}")
      |> Enum.join("\n")

    content = "\n\nUse **#{@prefix}help command** for more info.\n"

    Curie.embed(message, "=> Curie's commands\n\n" <> commands <> content, "green")
  end

  def command({"help", message, [command | _rest]}) do
    state = GenServer.call(@self, :get)

    with match when match != nil <- Curie.check_typo(command, state.commands) do
      ("Command → **#{@prefix <> match}**\n\n" <> state.full[match].description)
      |> (&Curie.embed(message, &1, "green")).()
    else
      _no_match ->
        Curie.embed(message, "Command unrecognized.", "red")
    end
  end

  def command(call), do: check_typo(call, @check_typo, &command/1)
end
