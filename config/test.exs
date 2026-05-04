import Config

config :shatter, Shatter.Store, table_type: :ram_copies
config :shatter, :dhcp_port, 0
config :shatter, :dhcp_handler_timeout, 1_000
config :shatter, :http_port, 0
