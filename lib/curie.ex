defmodule Curie do
  use Application

  alias Nostrum.Stuct.{Channel, Guild, Message, User}
  alias Nostrum.Stuct.Guild.Member
  alias Nostrum.Cache.GuildCache
  alias Nostrum.Error.ApiError

  import Nostrum.Api, only: [bangify: 1]
  import Nostrum.Struct.Embed

  @colors Application.get_env(:curie, :colors)

  @type message_or_error :: {:ok, Message.t()} | {:error, ApiError.t()}
  @type destination :: Channel.id() | Message.t()
  @type options :: keyword | map

  @spec color(String.t()) :: non_neg_integer | nil
  def color(name), do: @colors[name]

  @spec time_now() :: String.t()
  def time_now, do: Timex.local() |> Timex.format!("%H:%M:%S %d-%m-%Y", :strftime)

  @spec avatar_url(User.t()) :: String.t()
  def avatar_url(user),
    do: "https://cdn.discordapp.com/avatars/#{user.id}/#{user.avatar}.webp?size=1024"

  @spec check_typo(String.t(), String.t() | [String.t()]) :: String.t() | nil
  def check_typo(call, commands) do
    {match, similarity} =
      if(is_binary(commands), do: List.wrap(commands), else: commands)
      |> Enum.map(&{&1, call |> String.downcase() |> String.jaro_distance(&1)})
      |> Enum.max_by(fn {_call, similarity} -> similarity end)

    if similarity >= 0.75, do: match
  end

  @spec embed!(destination, String.t(), String.t() | non_neg_integer) :: Message.t() | no_return
  def embed!(channel, description, color), do: embed(channel, description, color) |> bangify()

  @spec embed(destination, String.t(), String.t() | non_neg_integer) :: message_or_error
  def embed(channel, description, color) do
    channel = if is_map(channel), do: channel.channel_id, else: channel
    color = unless is_integer(color), do: color(color), else: color

    %Nostrum.Struct.Embed{}
    |> put_color(color)
    |> put_description(description)
    |> (&Curie.send(channel, embed: &1)).()
  end

  @spec send!(destination, options) :: Message.t() | no_return
  def send!(channel, options), do: Curie.send(channel, options) |> bangify()

  @spec send(destination, options, non_neg_integer) :: message_or_error
  def send(channel, options, retries \\ 0) do
    channel = if is_map(channel), do: channel.channel_id, else: channel

    case Nostrum.Api.create_message(channel, options) do
      {:ok, _message} = result ->
        result

      {:error, %{status_code: code, message: _response}} = error ->
        if code >= 500 and retries <= 10 do
          Process.sleep(2000)
          Curie.send(channel, options, retries + 1)
        else
          error
        end
    end
  end

  @spec edit!(Message.t(), options) :: Message.t() | no_return
  def edit!(message, options), do: edit(message, options) |> bangify()

  @spec edit!(Channel.id(), Message.id(), options) :: Message.t() | no_return
  def edit!(channel_id, message_id, options),
    do: edit(channel_id, message_id, options) |> bangify()

  @spec edit(Message.t(), options) :: message_or_error
  def edit(%{channel_id: channel_id, message_id: message_id} = _message, options),
    do: edit(channel_id, message_id, options)

  @spec edit(Channel.id(), Message.id(), options, non_neg_integer) :: message_or_error
  def edit(channel_id, message_id, options, retries \\ 0) do
    case Nostrum.Api.edit_message(channel_id, message_id, options) do
      {:ok, _message} = result ->
        result

      {:error, %{status_code: code, message: _response}} = error ->
        if code >= 500 and retries <= 10 do
          Process.sleep(250)
          edit(channel_id, message_id, options, retries + 1)
        else
          error
        end
    end
  end

  @spec get(String.t(), [{String.t(), String.t()}], non_neg_integer) ::
          {200, HTTPoison.Respose.t()} | {:failed, String.t()}
  def get(url, headers \\ [], retries \\ 0) when is_list(headers) do
    case HTTPoison.get(url, [{"Connection", "close"}] ++ headers, follow_redirect: true) do
      {:ok, response} ->
        case response.status_code do
          200 ->
            {200, response}

          code ->
            if code >= 500 and retries < 5 do
              Process.sleep(2000)
              get(url, headers, retries + 1)
            else
              {:failed, Integer.to_string(code)}
            end
        end

      {:error, error} ->
        if retries < 5 do
          Process.sleep(2000)
          get(url, headers, retries + 1)
        else
          {:failed, inspect(error.reason)}
        end
    end
  end

  @spec unix_to_amount(non_neg_integer) :: String.t()
  def unix_to_amount(timestamp) do
    amount = (Timex.local() |> Timex.to_unix()) - timestamp
    {minutes, seconds} = {div(amount, 60), rem(amount, 60)}
    {hours, minutes} = {div(minutes, 60), rem(minutes, 60)}
    {days, hours} = {div(hours, 24), rem(hours, 24)}

    [{"d", days}, {"h", hours}, {"m", minutes}, {"s", seconds}]
    |> Enum.filter(fn {_key, value} -> value != 0 end)
    |> Enum.map_join(", ", fn {key, value} -> to_string(value) <> key end)
  end

  @spec get_member(Guild.id(), atom, term, non_neg_integer) :: Member.t() | nil
  def get_member(guild, key, value, retries \\ 0) do
    case GuildCache.select(guild, & &1.members) do
      {:ok, list} when key != :tag ->
        Enum.find(list, &(Map.get(&1.user, key) == value))

      {:ok, list} when key == :tag ->
        [name, disc] = Regex.run(~r/^(.+)#(\d{4})$/, value, capture: :all_but_first)
        Enum.find(list, &(&1.user.username == name and &1.user.discriminator == disc))

      {:error, _reason} ->
        Process.sleep(200)
        if retries <= 5, do: get_member(guild, key, value, retries + 1)
    end
  end

  @spec get_member(
          %{guild_id: Guild.id(), content: Message.content(), mentions: [User.t()]},
          non_neg_integer
        ) :: Member.t() | nil
  def get_member(%{guild_id: guild, content: content, mentions: mentions} = _message, position) do
    full_name =
      content
      |> String.split()
      |> (&Enum.slice(&1, position..length(&1))).()
      |> Enum.join(" ")

    if guild != nil and full_name != "" do
      cond do
        mentions != [] ->
          mentions
          |> List.first()
          |> (&get_member(guild, :id, &1.id)).()

        full_name =~ ~r/^\d+$/ ->
          full_name
          |> String.to_integer()
          |> (&get_member(guild, :id, &1)).()

        full_name =~ ~r/#\d{4}$/ ->
          get_member(guild, :tag, full_name)

        true ->
          get_member(guild, :username, full_name)
      end
    end
  end

  @impl true
  def start(_type, _args) do
    IO.puts("  == Curie - Nostrum #{Application.spec(:nostrum, :vsn)} ==\n")
    Curie.Supervisor.start_link()
  end
end
