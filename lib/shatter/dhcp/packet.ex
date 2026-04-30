defmodule Shatter.DHCP.Packet do
  @moduledoc false

  alias Shatter.DHCP.Options

  @spec parse(binary()) :: {:ok, map()} | {:error, atom()}
  def parse(<<
        op,
        htype,
        hlen,
        hops,
        xid::32,
        secs::16,
        flags::16,
        ci1, ci2, ci3, ci4,
        yi1, yi2, yi3, yi4,
        si1, si2, si3, si4,
        gi1, gi2, gi3, gi4,
        chaddr::binary-16,
        sname_bin::binary-64,
        file_bin::binary-128,
        options_bin::binary
      >>) do
    with {:ok, options} <- Options.parse(options_bin) do
      {:ok,
       %{
         op: op,
         htype: htype,
         hlen: hlen,
         hops: hops,
         xid: xid,
         secs: secs,
         flags: flags,
         ciaddr: {ci1, ci2, ci3, ci4},
         yiaddr: {yi1, yi2, yi3, yi4},
         siaddr: {si1, si2, si3, si4},
         giaddr: {gi1, gi2, gi3, gi4},
         chaddr: chaddr,
         sname: trim_null(sname_bin),
         file: trim_null(file_bin),
         options: options
       }}
    end
  end

  def parse(_), do: {:error, :truncated}

  @spec serialize(map()) :: binary()
  def serialize(packet) do
    %{
      op: op,
      htype: htype,
      hlen: hlen,
      hops: hops,
      xid: xid,
      secs: secs,
      flags: flags,
      ciaddr: {ci1, ci2, ci3, ci4},
      yiaddr: {yi1, yi2, yi3, yi4},
      siaddr: {si1, si2, si3, si4},
      giaddr: {gi1, gi2, gi3, gi4},
      chaddr: chaddr,
      sname: sname,
      file: file,
      options: options
    } = packet

    chaddr_bin = pad_to(chaddr, 16)
    sname_bin = pad_to(sname, 64)
    file_bin = pad_to(file, 128)
    opts_bin = Options.serialize(options)

    <<
      op,
      htype,
      hlen,
      hops,
      xid::32,
      secs::16,
      flags::16,
      ci1, ci2, ci3, ci4,
      yi1, yi2, yi3, yi4,
      si1, si2, si3, si4,
      gi1, gi2, gi3, gi4,
      chaddr_bin::binary,
      sname_bin::binary,
      file_bin::binary,
      opts_bin::binary
    >>
  end

  defp trim_null(bin), do: hd(:binary.split(bin, <<0>>))

  defp pad_to(str, size) when byte_size(str) >= size, do: binary_part(str, 0, size)

  defp pad_to(str, size) do
    pad_bytes = size - byte_size(str)
    str <> <<0::size(pad_bytes * 8)>>
  end
end
