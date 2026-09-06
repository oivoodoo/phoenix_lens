alias Dummy.Repo

{:ok, now} = DateTime.now("Etc/UTC")
now = DateTime.truncate(now, :second)

shift = fn days -> DateTime.add(now, -days * 86_400, :second) end

users = [
  %{
    email: "alice@example.com",
    first_name: "Alice",
    last_name: "Example",
    phone: "555-123-4567",
    inserted_at: now,
    updated_at: now
  }
]

users =
  users ++
    for i <- 1..24 do
      %{
        email: "user#{i}@example.com",
        first_name: "User",
        last_name: "#{i}",
        phone: "555-000-#{String.pad_leading(Integer.to_string(i), 4, "0")}",
        inserted_at: shift.(rem(i, 40)),
        updated_at: now
      }
    end

{25, _} = Repo.insert_all("users", users)

user_ids = Repo.query!("SELECT id FROM users ORDER BY id").rows |> List.flatten()
pick_user = fn i -> Enum.at(user_ids, rem(i, length(user_ids))) end

orders =
  for i <- 1..40 do
    %{
      user_id: pick_user.(i),
      total_cents: 500 + i * 25,
      status: Enum.at(["paid", "refunded", "pending"], rem(i, 3)),
      inserted_at: shift.(rem(i, 90)),
      updated_at: now
    }
  end

{40, _} = Repo.insert_all("orders", orders)

categories = ["engineering", "product", "design", "ops"]
statuses = ["published", "draft", "archived"]

posts =
  for i <- 1..30 do
    published? = rem(i, 5) != 0

    %{
      user_id: pick_user.(i),
      title: "Post #{i}",
      body: "Body for post #{i}. " <> String.duplicate("lorem ipsum ", 12),
      status: if(published?, do: "published", else: Enum.at(statuses, rem(i, 3))),
      category: Enum.at(categories, rem(i, 4)),
      published_at: if(published?, do: shift.(rem(i, 60))),
      inserted_at: shift.(rem(i, 80)),
      updated_at: now
    }
  end

{30, _} = Repo.insert_all("posts", posts)
post_ids = Repo.query!("SELECT id FROM posts ORDER BY id").rows |> List.flatten()
pick_post = fn i -> Enum.at(post_ids, rem(i, length(post_ids))) end

comments =
  for i <- 1..80 do
    user_id = pick_user.(i)

    %{
      post_id: pick_post.(i),
      user_id: user_id,
      body: "Comment #{i} on this post.",
      author_email: "user#{rem(i, 24) + 1}@example.com",
      inserted_at: shift.(rem(i, 50)),
      updated_at: now
    }
  end

{80, _} = Repo.insert_all("comments", comments)

events = ["page_view", "login", "signup", "checkout", "error"]
paths = ["/", "/pricing", "/blog", "/checkout", "/settings"]

logs =
  for i <- 1..120 do
    %{
      user_id: if(rem(i, 7) == 0, do: nil, else: pick_user.(i)),
      event: Enum.at(events, rem(i, 5)),
      path: Enum.at(paths, rem(i, 5)),
      ip: "203.0.113.#{rem(i, 250) + 1}",
      user_agent: "Mozilla/5.0 (Dummy/#{rem(i, 4)})",
      status_code: Enum.at([200, 200, 200, 301, 404, 500], rem(i, 6)),
      inserted_at: shift.(rem(i, 45))
    }
  end

{120, _} = Repo.insert_all("logs", logs)

plans = [
  {"free", 0},
  {"starter", 900},
  {"pro", 2900},
  {"business", 9900}
]

subscriptions =
  for {user_id, i} <- Enum.with_index(user_ids, 1) do
    {plan, amount} = Enum.at(plans, rem(i, 4))
    status = Enum.at(["active", "active", "active", "canceled", "past_due"], rem(i, 5))
    started = shift.(30 + rem(i, 200))

    %{
      user_id: user_id,
      plan: plan,
      status: status,
      amount_cents: amount,
      email: "user#{i}@example.com",
      started_at: started,
      canceled_at: if(status == "canceled", do: DateTime.add(started, 20 * 86_400, :second)),
      inserted_at: started,
      updated_at: now
    }
  end

{25, _} = Repo.insert_all("subscriptions", subscriptions)

IO.puts("""
Seeded:
  25 users (alice@example.com)
  40 orders
  30 posts
  80 comments
  120 logs
  25 subscriptions
""")
