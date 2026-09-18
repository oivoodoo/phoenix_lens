import Config

# Evaluated after compile. Used by Mix releases and `mix phoenix_lens.server`
# when PHX_SERVER / PHOENIX_LENS_SERVER is set in the environment.
# Source: https://hexdocs.pm/phoenix/deployment.html#runtime-configuration
if System.get_env("PHOENIX_LENS_SERVER") in ["1", "true"] do
  PhoenixLens.Standalone.configure!()
end
