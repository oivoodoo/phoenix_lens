exclude =
  if System.get_env("DATABASE_URL") in [nil, ""] do
    [:integration]
  else
    []
  end

exclude =
  if System.get_env("MYSQL_URL") in [nil, ""] do
    [:mysql | exclude]
  else
    exclude
  end

ExUnit.start(exclude: exclude)
