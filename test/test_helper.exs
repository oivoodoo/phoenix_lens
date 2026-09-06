exclude =
  if System.get_env("DATABASE_URL") in [nil, ""] do
    [:integration]
  else
    []
  end

ExUnit.start(exclude: exclude)
