defmodule MiniDiscordTest do
  use ExUnit.Case
  doctest MiniDiscord

  test "greets the world" do
    assert MiniDiscord.hello() == :world
  end
end
