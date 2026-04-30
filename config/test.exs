import Config

config :shatter, Shatter.Store, table_type: :ram_copies
config :shatter, :dhcp_port, 6767
config :shatter, :dhcp_handler_timeout, 100
